from model.enums import ThreadKind


class FastFirst:
    """A VM that takes the fast cores first and shares them with other fast-first VMs."""

    def order(self, fast, dense, is_free):
        return ([group for group in fast if is_free(group)] + [group for group in fast if not is_free(group)]
                + [group for group in dense if is_free(group)] + [group for group in dense if not is_free(group)])

    def shares_fast_only(self, pins, taken, kinds):
        return all(kinds.get(thread) == ThreadKind.kFast.value for thread in pins if taken.get(thread))

    def word(self):
        return ThreadKind.kFast.value
