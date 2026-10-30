from model.enums import ThreadKind


class DenseFirst:
    """A VM that takes free dense cores first, then free fast cores, and shares a core only when none is free."""

    def order(self, fast, dense, is_free):
        return ([group for group in dense if is_free(group)] + [group for group in fast if is_free(group)]
                + [group for group in dense if not is_free(group)] + [group for group in fast if not is_free(group)])

    def shares_fast_only(self, pins, taken, kinds):
        return False

    def word(self):
        return ThreadKind.kDense.value
