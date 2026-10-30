import dataclasses


@dataclasses.dataclass
class PathPiece:
    line: str = ""
    wrong: str = ""


class PathPieces:
    """The path check's pieces in the order its traffic goes, each ending yes or no, a no with the WRONG line it gives."""

    def __init__(self):
        self.pieces = []

    def add(self, subject, fact, wrong):
        piece = PathPiece()
        piece.line = f"{subject}: {fact + ': ' if fact else ''}{'no' if wrong else 'yes'}"
        piece.wrong = wrong
        self.pieces.append(piece)

    def add_yes(self, subject, fact):
        self.add(subject, fact, "")

    def text(self, tail):
        wrong = next((piece.wrong for piece in self.pieces if piece.wrong), "")
        head = [f"WRONG: {wrong}", ""] if wrong else ["Nothing is wrong.", ""]
        return "\n".join(head + [piece.line for piece in self.pieces] + tail)

    pieces = ()
