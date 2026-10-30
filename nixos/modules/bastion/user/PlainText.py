from rich.text import Text


class PlainText:
    """Plain text for a widget: no markup is read from data."""

    @staticmethod
    def of(value):
        return Text(str(value))
