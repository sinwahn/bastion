# Not a module: one function asserts that a name fits a network device's
# name; the message is built from the name's length and the longest length.
{ lib }:

let
  # IFNAMSIZ (16) less its end byte: the longest network device name the
  # kernel takes.
  kNameMax = 15;
in
name: message: {
  assertion = lib.stringLength name <= kNameMax;
  message = message (toString (lib.stringLength name)) (toString kNameMax);
}
