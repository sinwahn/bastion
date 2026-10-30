import dataclasses


@dataclasses.dataclass
class AnswerPlace:
    """An answer point's VM by its vsock number, and the port its socket listens on."""
    cid: int = 0
    port: int = 0
