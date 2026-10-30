class AnswerPoint:
    """An answer point inside a service VM, reached over vsock with socat."""

    def __init__(self, shell, socat, place):
        self.shell = shell
        self.socat = socat
        self.place = place

    def lines(self, seconds):
        return self.lines_answering("", seconds)

    def lines_answering(self, sent, seconds):
        """The lines the point prints within seconds after sent; what it printed before the seconds ran out is kept."""
        command = [self.socat, "-t", str(seconds), "-", f"VSOCK-CONNECT:{self.place.cid}:{self.place.port}"]
        return self.shell.read_lines_within(command, sent, seconds)

    shell = None
    socat = ""
    place = None
