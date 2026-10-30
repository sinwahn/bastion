import json
import subprocess

from system.errors import ShellCommandFailed


class ShellCommands:
    """Every program the tool runs on the host, and the window and the sleep hold it keeps running."""

    def __init__(self, log):
        self.log = log

    def read(self, command, seconds):
        """The finished run of command within seconds, its output and errors kept apart."""
        try:
            return subprocess.run(command, capture_output=True, text=True, timeout=seconds)
        except (OSError, subprocess.SubprocessError) as error:
            self.log.note(f"{command[0]} did not run: {error}")
            raise ShellCommandFailed(str(error)) from error

    def read_json(self, command, seconds):
        """The JSON command prints."""
        answer = self.read(command, seconds)
        try:
            if answer.returncode == 0:
                return json.loads(answer.stdout)
        except ValueError as error:
            self.log.note(f"{command[0]} printed no JSON: {error}; nothing is read")
            raise ShellCommandFailed(str(error)) from error
        self.log.note(f"{command[0]} ended with {answer.returncode}; nothing is read")
        raise ShellCommandFailed(answer.stderr.strip())

    def read_lines_within(self, command, sent, seconds):
        """The lines command prints within seconds, those printed before the time ran out kept."""
        try:
            return subprocess.run(command, input=sent, capture_output=True, text=True,
                                  timeout=seconds).stdout.splitlines()
        except subprocess.TimeoutExpired as expired:
            self.log.note(f"{command[0]} did not end within {seconds} seconds; its lines so far are kept")
            return self._printed_lines(expired)
        except (OSError, subprocess.SubprocessError) as error:
            self.log.note(f"{command[0]} did not run: {error}; no line is read")
            return []

    def start_detached(self, command):
        subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)

    def start_window(self, command):
        self.window = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                       stderr=subprocess.DEVNULL)

    def stop_window(self):
        self.window.terminate()

    def start_hold(self, command):
        self.hold = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL)

    def release_hold(self):
        self.hold.stdin.close()
        self.hold.wait()

    def run_attached(self, command):
        self.finished = subprocess.run(command, text=True)

    def run_attached_feeding(self, command, sent):
        self.finished = subprocess.run(command, input=sent, text=True)

    def run_captured(self, command):
        self.finished = subprocess.run(command, text=True, capture_output=True)

    def run_captured_feeding(self, command, sent):
        self.finished = subprocess.run(command, input=sent, text=True, capture_output=True)

    def finished_run(self):
        """The last run of run_attached, run_captured and their feeding forms."""
        return self.finished

    def _printed_lines(self, expired):
        printed = expired.stdout or b""
        if isinstance(printed, bytes):
            return printed.decode(errors="replace").splitlines()
        return printed.splitlines()

    log = None
    finished = None
    window = None
    hold = None
