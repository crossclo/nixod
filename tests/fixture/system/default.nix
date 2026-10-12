# Every starter system file (an instance has copies).
let
  starter = ../../../starter/system;
in
{
  imports = map (f: starter + "/${f}.nix") [
    "shell"
    "fonts"
    "desktop"
  ];
}
