import enum


class ThreadKind(enum.Enum):
    kFast = "fast"
    kDense = "dense"


class InternetRule(enum.Enum):
    kOpen = "open"
    kListed = "listed"
    kNone = "none"
