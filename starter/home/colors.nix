# The palette of the themed files: "Summer Heat" (yellow), light and warm.
# Not a module: the files that use it import it themselves.
#
# Pale yellow cream (never pure white), warm ink, pastel accents from the
# Summer-Heat theme (Jfeatherstone/i3-themes), with honey yellow as the
# main accent.
# Single source of truth for the UI colors: kitty, i3, rofi, dunst,
# starship, fzf... (`import ./colors.nix` in each of those files). Values
# WITHOUT "#": each consumer adds its own prefix. Change one here and every
# file follows.
{
  bg = "faf3e1"; # main background, pale yellow cream
  bg-dark = "f2e6c9"; # panels, bars
  bg-hl = "eddfb8"; # highlighted background
  fg = "33302a"; # main text, warm ink
  fg-dark = "5c5648"; # secondary text
  comment = "8f8672"; # dimmed text
  black = "26231d";
  gray = "d8cdaf"; # inactive borders, chrome
  yellow = "e3a51a"; # honey yellow, MAIN accent
  amber = "edb83f"; # amber, bar segments
  orange = "e57c46";
  red = "e24c49"; # urgent / errors
  pink = "ec6798";
  magenta = "ec6798"; # alias of pink
  purple = "be78d1";
  blue = "75a4cd";
  cyan = "00c7df";
  teal = "00b19f";
  green = "61c766"; # semantic only (success)
}
