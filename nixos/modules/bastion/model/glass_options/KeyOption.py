class KeyOption:
    """The looking-glass window's release key, input:escapeKey, default KEY_SCROLLLOCK (client/src/config.c 352-363)."""

    def section(self):
        return "input"

    def option(self):
        return "escapeKey"

    def default(self):
        return "KEY_SCROLLLOCK"

    def offered(self):
        return self.kKeys

    def shown(self, value):
        """A key name as the offered one it names in any case (client/src/config.c 958-979)."""
        return next((key for key in self.kKeys if key.lower() == value.lower()), value)

    # The key names the client accepts for its release key, its table
    # linux_to_str (client/src/kb.c 192-358), in the table's order.
    # KEY_RESERVED, index 0, is left out: no key sends it, so the capture would
    # have no release key.
    kKeys = (
        "KEY_ESC", "KEY_1", "KEY_2", "KEY_3", "KEY_4", "KEY_5", "KEY_6", "KEY_7", "KEY_8", "KEY_9",
        "KEY_0", "KEY_MINUS", "KEY_EQUAL", "KEY_BACKSPACE", "KEY_TAB", "KEY_Q", "KEY_W", "KEY_E",
        "KEY_R", "KEY_T", "KEY_Y", "KEY_U", "KEY_I", "KEY_O", "KEY_P", "KEY_LEFTBRACE",
        "KEY_RIGHTBRACE", "KEY_ENTER", "KEY_LEFTCTRL", "KEY_A", "KEY_S", "KEY_D", "KEY_F", "KEY_G",
        "KEY_H", "KEY_J", "KEY_K", "KEY_L", "KEY_SEMICOLON", "KEY_APOSTROPHE", "KEY_GRAVE",
        "KEY_LEFTSHIFT", "KEY_BACKSLASH", "KEY_Z", "KEY_X", "KEY_C", "KEY_V", "KEY_B", "KEY_N", "KEY_M",
        "KEY_COMMA", "KEY_DOT", "KEY_SLASH", "KEY_RIGHTSHIFT", "KEY_KPASTERISK", "KEY_LEFTALT",
        "KEY_SPACE", "KEY_CAPSLOCK", "KEY_F1", "KEY_F2", "KEY_F3", "KEY_F4", "KEY_F5", "KEY_F6",
        "KEY_F7", "KEY_F8", "KEY_F9", "KEY_F10", "KEY_NUMLOCK", "KEY_SCROLLLOCK", "KEY_KP7", "KEY_KP8",
        "KEY_KP9", "KEY_KPMINUS", "KEY_KP4", "KEY_KP5", "KEY_KP6", "KEY_KPPLUS", "KEY_KP1", "KEY_KP2",
        "KEY_KP3", "KEY_KP0", "KEY_KPDOT", "KEY_102ND", "KEY_F11", "KEY_F12", "KEY_RO", "KEY_HENKAN",
        "KEY_KATAKANAHIRAGANA", "KEY_MUHENKAN", "KEY_KPENTER", "KEY_RIGHTCTRL", "KEY_KPSLASH",
        "KEY_SYSRQ", "KEY_RIGHTALT", "KEY_HOME", "KEY_UP", "KEY_PAGEUP", "KEY_LEFT", "KEY_RIGHT",
        "KEY_END", "KEY_DOWN", "KEY_PAGEDOWN", "KEY_INSERT", "KEY_DELETE", "KEY_KPEQUAL", "KEY_PAUSE",
        "KEY_KPCOMMA", "KEY_HANGEUL", "KEY_HANJA", "KEY_YEN", "KEY_LEFTMETA", "KEY_RIGHTMETA",
        "KEY_COMPOSE", "KEY_POWER", "KEY_F13", "KEY_F14", "KEY_F15", "KEY_F16", "KEY_F17", "KEY_F18",
        "KEY_F19", "KEY_F20", "KEY_F21", "KEY_F22", "KEY_F23", "KEY_F24", "KEY_OPEN", "KEY_HELP",
        "KEY_MENU", "KEY_FRONT", "KEY_AGAIN", "KEY_UNDO", "KEY_CUT", "KEY_COPY", "KEY_PASTE",
        "KEY_KPJPCOMMA", "KEY_KATAKANA", "KEY_HIRAGANA", "KEY_ZENKAKUHANKAKU", "KEY_KPLEFTPAREN",
        "KEY_KPRIGHTPAREN", "KEY_PRINT", "KEY_MUTE", "KEY_VOLUMEUP", "KEY_VOLUMEDOWN", "KEY_NEXTSONG",
        "KEY_PLAYPAUSE", "KEY_PREVIOUSSONG", "KEY_STOPCD", "KEY_EJECTCD", "KEY_WWW", "KEY_BACK",
        "KEY_FORWARD", "KEY_STOP", "KEY_FIND", "KEY_SCROLLUP", "KEY_SCROLLDOWN", "KEY_EDIT",
        "KEY_SLEEP", "KEY_SCREENLOCK", "KEY_REFRESH", "KEY_CALC",
    )
