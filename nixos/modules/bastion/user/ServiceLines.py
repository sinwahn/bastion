class ServiceLines:
    """A service VM's words on the screens."""

    def wrong(self, service):
        """Its WRONG line while its unit is not active, as the status screen and the broker section show it."""
        return f"{service.name} is not running: {service.meaning}. Do: sudo systemctl start {service.unit}"
