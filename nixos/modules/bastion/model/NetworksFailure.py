import dataclasses


@dataclasses.dataclass
class NetworksFailure:
    """Why the live data file cannot be read; failed is False while it can."""
    failed: bool = False
    refused: bool = False
    reason: str = ""
