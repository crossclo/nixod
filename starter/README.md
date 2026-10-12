# starter

Plain config files, ready to copy into a nixod instance: an i3 desktop, zsh,
Neovim, kitty, rofi, dunst, a GTK theme, a palette, fonts.

Nothing in nixod imports them. At setup, the agent ports the user's own
dotfiles first, then copies from here whatever they don't have:

```sh
nixod starter                         # list
nixod starter copy home/i3.nix        # + what it needs (its `# needs:` line)
nixod starter diff                    # the instance's copies vs this version
```

`home/*` goes to the instance's `home/` (Home Manager), `system/*` to its
`system/` (NixOS, every host). Once copied, a file is the user's own: nixod
never changes it, and fixes made here later only reach it through
`nixod starter diff`, by hand.

The desktop files act only on hosts with `nixod.profiles.x11` on, so the same
`home/` works on a machine without a desktop.
