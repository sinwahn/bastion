import contextlib
import glob
import json
import os
import shutil
import tempfile
import xml.etree.ElementTree as ET

from system.errors import FileFailed


class HostFiles:
    """Every file and folder the tool reads or writes on the host."""

    def __init__(self, log):
        self.log = log

    def read_json(self, path):
        with self._failures(path), open(path) as file:
            return json.load(file)

    def read_json_utf8(self, path):
        with self._failures(path), open(path, encoding="utf-8") as file:
            return json.load(file)

    def read_text_utf8(self, path):
        with self._failures(path), open(path, encoding="utf-8") as file:
            return file.read()

    def read_text_latin1(self, path):
        with self._failures(path), open(path, encoding="latin-1") as file:
            return file.read()

    def read_text_latin1_exact(self, path):
        with self._failures(path), open(path, encoding="latin-1", newline="") as file:
            return file.read()

    def write_whole_utf8(self, path, body):
        """path written whole beside itself and moved into place."""
        with self._failures(path):
            beside = self._write_beside(path, body, "utf-8")
            self._move_into_place(beside, path)

    def write_whole_latin1_keeping_mode(self, path, body):
        """path written whole beside itself with its mode kept, and moved into place."""
        with self._failures(path):
            beside = self._write_beside(path, body, "latin-1")
            self._keep_mode(path, beside)
            self._move_into_place(beside, path)

    def write_ascii(self, path, text):
        with self._failures(path), open(path, "w", encoding="ascii", newline="\n") as file:
            file.write(text)

    def exists(self, path):
        return os.path.exists(path)

    def is_file(self, path):
        return os.path.isfile(path)

    def is_folder(self, path):
        return os.path.isdir(path)

    def list_folder(self, path):
        with self._failures(path):
            return os.listdir(path)

    def make_folders(self, path):
        with self._failures(path):
            os.makedirs(path, exist_ok=True)

    def make_private_folders(self, path):
        with self._failures(path):
            os.makedirs(path, mode=0o700, exist_ok=True)

    def make_new_folders(self, path):
        with self._failures(path):
            os.makedirs(path)

    def remove(self, path):
        with self._failures(path):
            os.remove(path)

    def matching(self, pattern):
        return sorted(glob.glob(pattern))

    def free_bytes(self, path):
        with self._failures(path):
            figures = os.statvfs(path)
        return figures.f_bavail * figures.f_frsize

    def allocated_kib(self, path):
        # A file's size as du -k counts it: the blocks allocated, in 512-byte
        # units (CPython 3.13 Doc/library/os.rst 3189-3191; coreutils 9.11
        # src/du.c 638-640 with gnulib's lib/stat-size.h 79, 83-86), shown in
        # KiB rounded up (du.c 854-856, gnulib's lib/human.h 53).
        with self._failures(path):
            return -(-os.stat(path).st_blocks * 512 // 1024)

    def copy_tree(self, source, destination):
        """source copied file by file into the new folder destination, without the source's modes."""
        with self._failures(destination):
            os.makedirs(destination)
            for top, _, files in os.walk(source):
                here = os.path.join(destination, os.path.relpath(top, source))
                os.makedirs(here, exist_ok=True)
                for name in files:
                    shutil.copyfile(os.path.join(top, name), os.path.join(here, name))

    def copy_file(self, source, destination):
        with self._failures(destination):
            shutil.copyfile(source, destination)

    def device_answer(self, path, request):
        """The answer of the ioctl request on the device path, opened for reading and writing."""
        import fcntl
        with self._failures(path):
            device = os.open(path, os.O_RDWR)
            try:
                return fcntl.ioctl(device, request)
            finally:
                os.close(device)

    def xml_root(self, path):
        with self._failures(path):
            return ET.parse(path).getroot()

    def _write_beside(self, path, body, encoding):
        descriptor, beside = tempfile.mkstemp(dir=os.path.dirname(path), prefix=os.path.basename(path) + ".")
        try:
            with os.fdopen(descriptor, "w", encoding=encoding, newline="") as file:
                file.write(body)
        except BaseException:
            os.unlink(beside)
            raise
        return beside

    def _keep_mode(self, path, beside):
        try:
            if os.path.exists(path):
                shutil.copymode(path, beside)
        except BaseException:
            os.unlink(beside)
            raise

    def _move_into_place(self, beside, path):
        try:
            os.replace(beside, path)
        except BaseException:
            os.unlink(beside)
            raise

    @contextlib.contextmanager
    def _failures(self, path):
        try:
            yield
        except (OSError, ValueError, ET.ParseError) as error:
            self.log.note(f"{path}: {error}")
            raise FileFailed(str(error)) from error

    log = None
