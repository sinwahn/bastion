class FirstStart:
    """A VM's first start: its cable's link down for that start, and its window the console, as no looking-glass host runs in Windows yet."""

    def word(self):
        return "first"

    def plan_lines(self):
        return ["This is its first start: its cable's link stays down, so it has no network this time."]

    def change(self, root, cables):
        cables.link_down(root)

    def shows_glass(self):
        return False

    def remember(self, first_starts, name):
        first_starts.add(name)
