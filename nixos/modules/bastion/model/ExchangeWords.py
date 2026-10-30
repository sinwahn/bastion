import dataclasses


@dataclasses.dataclass
class ExchangeWords:
    """host-networks.nix's exchange: the broker section's words, the commands, the step and its lines."""
    section: str = ""
    section_key: str = ""
    sends_to: str = ""
    sends_to_label: str = ""
    nothing_listed: str = ""
    retired_mark: str = ""
    send: str = ""
    send_action: str = ""
    transfers: str = ""
    clean: str = ""
    clean_action: str = ""
    outbox_folder: str = ""
    usage_verb: str = ""
    usage_line: str = ""
    step: str = ""
    key: str = ""
    module: str = ""
    exchange_files: str = ""
    module_words: dict = dataclasses.field(default_factory=dict)
