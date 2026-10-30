# Not a module: one function builds every udev rule line, each match
# [ KEY VALUE ] as KEY=="VALUE" and then each assignment as KEY="VALUE", in
# the order given.
{ lib }:

matches: assignments:
  lib.concatStringsSep ", " (map (m: "${lib.head m}==\"${lib.last m}\"") matches
    ++ map (a: "${lib.head a}=\"${lib.last a}\"") assignments) + "\n"
