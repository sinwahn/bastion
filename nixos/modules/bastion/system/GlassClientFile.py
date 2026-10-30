import os


class GlassClientFile:
    """One looking-glass client file, read and written by the client's own rules."""

    # The client's rules (common/src/option.c 437-476, 507-686, 909): a line
    # that begins with ";" is a comment, a line that begins with "[" opens
    # the section named up to "]", an option's line is name=value with the
    # spaces around both left out, names match in any case, and the last
    # line of an option wins.

    def __init__(self, files, path, log):
        self.files = files
        self.path = path
        self.log = log

    def options(self):
        """{section: {option: value}}, both names in lower case; nothing when the file is not there."""
        found = {}
        if not self.files.exists(self.path):
            self.log.note(f"{self.path} is not there: it sets no option")
            return found
        section = self.kOutside
        for line in self.files.read_text_latin1(self.path).split("\n"):
            if line.startswith(";"):
                continue
            if self._opens_section(line):
                section = line[1:line.index("]")].lower()
            elif section is not self.kOutside and "=" in line:
                name, value = line.split("=", 1)
                found.setdefault(section, {})[name.strip().lower()] = value.strip()
        return found

    def write_option(self, section, option, value):
        """The option's line replaced where it stands, else added after its section's last line, else at the end."""
        # The line replaced is the last one, which the client reads; every
        # other line is kept as it is. The folder is made with mode 0700 when
        # it is not there, as the client makes it
        # (common/src/platform/linux/paths.c 78).
        lines = self._lines()
        line = f"{option}={value}"
        here = self._option_line(lines, section, option)
        end = self._section_end(lines, section)
        if here >= 0:
            lines[here] = line
        elif end >= 0:
            lines.insert(end, line)
        else:
            lines.extend(([""] if lines else []) + [f"[{section}]", line])
        self.files.make_private_folders(os.path.dirname(self.path))
        self.files.write_whole_latin1_keeping_mode(self.path, "\n".join(lines) + "\n")

    def _lines(self):
        text_now = ""
        if self.files.exists(self.path):
            text_now = self.files.read_text_latin1_exact(self.path)
        lines = text_now.split("\n")
        if lines[-1] == "":
            lines.pop()
        return lines

    def _option_line(self, lines, section, option):
        here = -1
        for index, old in self._section_lines(lines, section):
            if not old.startswith(";") and "=" in old and old.split("=", 1)[0].strip().lower() == option.lower():
                here = index
        return here

    def _section_end(self, lines, section):
        ends = [index + 1 for index, old in enumerate(lines)
                if self._opens_section(old) and old[1:old.index("]")].lower() == section.lower()]
        ends += [index + 1 for index, _ in self._section_lines(lines, section)]
        return max(ends, default=-1)

    def _section_lines(self, lines, section):
        inside = []
        section_now = self.kOutside
        for index, old in enumerate(lines):
            if self._opens_section(old):
                section_now = old[1:old.index("]")].lower()
            elif section_now == section.lower() and old.strip():
                inside.append((index, old))
        return inside

    def _opens_section(self, line):
        return line.startswith("[") and "]" in line

    files = None
    path = ""
    log = None
    kOutside = object()
