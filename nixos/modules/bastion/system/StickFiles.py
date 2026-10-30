import json
import os


class StickFiles:
    """The folders presets/attach.sh puts onto the stick, copied from the store."""

    def __init__(self, files):
        self.files = files

    def copy_store_folder(self, store, destination):
        """store copied whole, file by file without the store's read-only modes, so the copy can be removed."""
        self.files.copy_tree(store, destination)

    def copy_file(self, source, folder):
        self.files.copy_file(source, os.path.join(folder, os.path.basename(source)))

    def write_words(self, path, words):
        self.files.write_ascii(path, json.dumps(words, indent=2) + "\n")

    files = None
