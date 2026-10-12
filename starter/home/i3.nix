# i3 (X11): i3bar with a powerline status, picom, a themed i3lock.
#
# Bar = native i3bar (reliable, built-in workspaces, tray on the
# primary output), with a powerline status from a small script (i3bar JSON
# protocol). Compositor: picom.
#
# Keybindings: stock i3 (the Home Manager module's defaults). On an AZERTY
# layout (settings.keyboard.xkb = "fr"), workspaces use the real keysyms of
# the top row (& é " ' ( - è _ ç à), as i3's config wizard would.
#
# Started by nixod.profiles.x11 (greetd → startx → ~/.xsession).
# needs: home/colors.nix system/desktop.nix system/fonts.nix home/rofi.nix home/terminal.nix home/notifications.nix
{
  lib,
  pkgs,
  osConfig,
  ...
}:

let
  c = import ./colors.nix;

  isAzerty = osConfig.nixod.settings.keyboard.xkb == "fr";

  # Wallpaper: a file named "wallpaper" or "wallpaper.<ext>" in the user's
  # Pictures directory. Without one, a flat background from the palette.
  set-wallpaper = pkgs.writeShellScriptBin "set-wallpaper" ''
    pics=$(${pkgs.xdg-user-dirs}/bin/xdg-user-dir PICTURES 2>/dev/null)
    for f in "''${pics:-$HOME/Pictures}/wallpaper" "''${pics:-$HOME/Pictures}/wallpaper".*; do
      if [ -f "$f" ]; then
        exec ${pkgs.feh}/bin/feh --no-fehbg --bg-fill "$f"
      fi
    done
    exec ${pkgs.hsetroot}/bin/hsetroot -solid "#${c.bg}"
  '';

  # Power menu (rofi). No keybinding (stock bindings): run it from a
  # terminal or rofi (run mode). "Log out" goes back to tuigreet.
  powermenu-i3 = pkgs.writeShellScriptBin "powermenu-i3" ''
    choice=$(printf '󰌾  Lock\n󰍃  Log out\n󰜉  Reboot\n󰐥  Power off' \
      | rofi -dmenu -i -p "Session")
    case "$choice" in
      *Lock*)      loginctl lock-session ;;
      *"Log out"*) ${pkgs.i3}/bin/i3-msg exit ;;
      *Reboot*)    systemctl reboot ;;
      *"Power off"*) systemctl poweroff ;;
    esac
  '';

  # i3lock-color in the palette's colors: cream background, honey ring,
  # red on error. Called by xss-lock (lock session / suspend).
  i3lock-themed = pkgs.writeShellScriptBin "i3lock-themed" ''
    ${pkgs.i3lock-color}/bin/i3lock \
      --color=${c.bg} \
      --ignore-empty-password \
      --clock \
      --indicator \
      --radius=90 \
      --ring-width=8 \
      --inside-color=${c.bg-dark}ee \
      --ring-color=${c.yellow}ff \
      --line-uses-inside \
      --keyhl-color=${c.orange}ff \
      --bshl-color=${c.red}ff \
      --separator-color=${c.bg}00 \
      --insidever-color=${c.bg-hl}ee \
      --ringver-color=${c.amber}ff \
      --insidewrong-color=${c.bg-hl}ee \
      --ringwrong-color=${c.red}ff \
      --verif-color=${c.fg}ff \
      --wrong-color=${c.red}ff \
      --time-color=${c.fg}ff \
      --date-color=${c.fg-dark}ff \
      --layout-color=${c.fg-dark}ff
  '';

  # i3bar status (JSON protocol), powerline style: each item is a colored
  # segment, preceded by a chevron (U+E0B2, written as UTF-8 bytes so the
  # source doesn't depend on an invisible glyph) that colors the transition
  # from the previous segment.
  # Chain: CPU ❮ RAM ❮ volume ❮ network ❮ battery (if any) ❮ clock.
  i3bar-status = pkgs.writeShellScriptBin "i3bar-status" ''
    chev=$(printf '\xee\x82\xb2')

    printf '{"version":1}\n[\n[]\n'

    prev_total=0
    prev_idle=0

    while :; do
      # ---- CPU: /proc/stat delta between two loop turns ----
      read -r _ u n s idl w irq sirq st _ < /proc/stat
      total=$((u + n + s + idl + w + irq + sirq + st))
      idle=$((idl + w))
      dt=$((total - prev_total))
      di=$((idle - prev_idle))
      prev_total=$total
      prev_idle=$idle
      if [ "$dt" -gt 0 ]; then cpu=$(( (100 * (dt - di)) / dt )); else cpu=0; fi

      # ---- RAM ----
      mem=$(${pkgs.procps}/bin/free | ${pkgs.gawk}/bin/awk '/^Mem/ {printf "%d", $3 / $2 * 100}')

      # ---- Volume (pipewire) ----
      volraw=$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
      case "$volraw" in
        *MUTED*) vol="󰝟 muted" ;;
        "")      vol="󰝟 —" ;;
        *)       vol="󰕾 $(printf '%s' "$volraw" | ${pkgs.gawk}/bin/awk '{printf "%d%%", $2 * 100}')" ;;
      esac

      # ---- Network: default route's interface, SSID on Wi-Fi ----
      iface=$(${pkgs.iproute2}/bin/ip route get 1.1.1.1 2>/dev/null \
              | ${pkgs.gnugrep}/bin/grep -oP 'dev \K\S+' | ${pkgs.coreutils}/bin/head -1)
      if [ -z "$iface" ]; then
        net="󰖪 offline"
      elif [ -d "/sys/class/net/$iface/wireless" ]; then
        ssid=$(${pkgs.iw}/bin/iw dev "$iface" link 2>/dev/null \
               | ${pkgs.gnused}/bin/sed -n 's/^\s*SSID: //p')
        net="󰤨 ''${ssid:-$iface}"
      else
        net="󰈀 $iface"
      fi

      # ---- Battery (only if the machine has one) ----
      batdir=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | ${pkgs.coreutils}/bin/head -1)
      if [ -n "$batdir" ]; then
        bat=$(cat "$batdir/capacity" 2>/dev/null || echo "?")
        case "$(cat "$batdir/status" 2>/dev/null)" in
          Charging) baticon="󰂄" ;;
          Full)     baticon="󰁹" ;;
          *)        baticon="󰁾" ;;
        esac
      fi

      # ---- Clock ----
      clock=$(${pkgs.coreutils}/bin/date '+%a %d %b  %H:%M')

      # ---- Powerline assembly ----
      line=""
      prev=""
      add() {
        if [ -z "$prev" ]; then
          line="$line{\"full_text\":\"$chev\",\"color\":\"#$1\",\"separator\":false,\"separator_block_width\":0},"
        else
          line="$line{\"full_text\":\"$chev\",\"color\":\"#$1\",\"background\":\"#$prev\",\"separator\":false,\"separator_block_width\":0},"
        fi
        line="$line{\"full_text\":\" $3 \",\"color\":\"#$2\",\"background\":\"#$1\",\"separator\":false,\"separator_block_width\":0},"
        prev=$1
      }

      add "${c.orange}" "${c.black}" " $cpu%"
      add "${c.purple}" "${c.black}" " $mem%"
      add "${c.cyan}"   "${c.black}" "$vol"
      add "${c.blue}"   "${c.black}" "$net"
      [ -n "$batdir" ] && add "${c.pink}" "${c.black}" "$baticon $bat%"
      add "${c.amber}"  "${c.black}" " $clock"

      printf ',[%s]\n' "''${line%,}"
      sleep 3
    done
  '';
in
{
  # Desktop hosts only (nixod.profiles.x11).
  config = lib.mkIf osConfig.nixod.profiles.x11.enable (
    lib.mkMerge [
      {
        home.packages = with pkgs; [
          set-wallpaper
          powermenu-i3
          i3lock-themed
          # X11 clipboard
          xclip
          # Screenshots
          flameshot
          maim
          # Hardware controls
          brightnessctl
          playerctl
          pavucontrol
          networkmanagerapplet
        ];

        xsession.windowManager.i3.config = {
          floating.criteria = [
            { class = "Pavucontrol"; }
            { class = "Nm-connection-editor"; }
            { class = "Blueman-manager"; }
            { class = "Imv"; }
            { class = "mpv"; }
            { title = "Confirmation"; }
          ];

          startup = [
            {
              command = "set-wallpaper";
              notification = false;
              always = true;
            }
            # Turns off screen blanking on idle (DPMS + X11 default blanking,
            # ~10 min). Manual lock and suspend stay handled by xss-lock below.
            {
              command = "${pkgs.xset}/bin/xset s off -dpms";
              notification = false;
              always = true;
            }
            # No nm-applet on purpose: the network is shown in the bar.
            {
              command = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
              notification = false;
            }
            # Locks on `loginctl lock-session` and on suspend.
            {
              command = "${pkgs.xss-lock}/bin/xss-lock --transfer-sleep-lock -- i3lock-themed --nofork";
              notification = false;
            }
          ];
        };
      }

      {
        # Generates ~/.xsession (started by startx from nixod's x11 system
        # profile): imports the environment into systemd --user, starts
        # hm-graphical-session.target (→ graphical-session.target → picom/dunst),
        # runs i3, and stops everything cleanly on logout.
        xsession.enable = true;

        xsession.windowManager.i3 = {
          enable = true;
          # Home Manager needs a package for its onChange command (`i3-msg reload`).
          # Same package as the system one, Nix deduplicates.
          package = pkgs.i3;

          config = {
            modifier = "Mod4"; # SUPER
            terminal = "kitty";
            menu = "rofi -show drun"; # used by the stock Mod4+d binding

            fonts = {
              names = [ "JetBrainsMono Nerd Font" ];
              size = 10.0;
            };

            gaps = {
              inner = 12;
              outer = 6;
              smartBorders = "on";
            };

            window = {
              border = 2;
              titlebar = false;
            };

            floating = {
              border = 2;
              titlebar = false;
            };

            # Focused window in honey yellow, the rest in discreet cream chrome,
            # urgent in red.
            colors = {
              focused = {
                border = "#${c.yellow}";
                background = "#${c.yellow}";
                text = "#${c.black}";
                indicator = "#${c.orange}";
                childBorder = "#${c.yellow}";
              };
              focusedInactive = {
                border = "#${c.gray}";
                background = "#${c.bg-hl}";
                text = "#${c.fg-dark}";
                indicator = "#${c.gray}";
                childBorder = "#${c.gray}";
              };
              unfocused = {
                border = "#${c.gray}";
                background = "#${c.bg-dark}";
                text = "#${c.comment}";
                indicator = "#${c.gray}";
                childBorder = "#${c.gray}";
              };
              urgent = {
                border = "#${c.red}";
                background = "#${c.red}";
                text = "#${c.bg}";
                indicator = "#${c.red}";
                childBorder = "#${c.red}";
              };
            };

            # ---- Bar: native i3bar ----
            # Built-in workspaces (always right), tray on the primary output,
            # powerline status from i3bar-status. One bar per output, managed by
            # i3 itself: no external service.
            bars = [
              {
                position = "top";
                trayOutput = "primary";
                statusCommand = "${i3bar-status}/bin/i3bar-status";
                fonts = {
                  names = [ "JetBrainsMono Nerd Font" ];
                  size = 11.0;
                };
                colors = {
                  background = "#${c.bg-dark}";
                  statusline = "#${c.fg}";
                  separator = "#${c.gray}";
                  focusedWorkspace = {
                    border = "#${c.yellow}";
                    background = "#${c.yellow}";
                    text = "#${c.black}";
                  };
                  activeWorkspace = {
                    border = "#${c.bg-hl}";
                    background = "#${c.bg-hl}";
                    text = "#${c.fg-dark}";
                  };
                  inactiveWorkspace = {
                    border = "#${c.bg-dark}";
                    background = "#${c.bg-dark}";
                    text = "#${c.comment}";
                  };
                  urgentWorkspace = {
                    border = "#${c.red}";
                    background = "#${c.red}";
                    text = "#${c.bg}";
                  };
                  bindingMode = {
                    border = "#${c.orange}";
                    background = "#${c.orange}";
                    text = "#${c.black}";
                  };
                };
              }
            ];

            keybindings =
              let
                # AZERTY: digits need Shift, so the default Mod4+1..0 bindings
                # can't be reached AND grab the same keys as Mod4+Shift+1..0
                # (keysym "1" = Shift+"&"). They are removed (null) and the real
                # top-row keysyms are bound instead. The stock Mod4+Shift+1..0
                # moves work as they are.
                frKeys = [
                  "ampersand"
                  "eacute"
                  "quotedbl"
                  "apostrophe"
                  "parenleft"
                  "minus"
                  "egrave"
                  "underscore"
                  "ccedilla"
                  "agrave"
                ];
                azerty =
                  lib.listToAttrs (
                    lib.imap1 (i: k: {
                      name = "Mod4+${k}";
                      value = "workspace number ${toString i}";
                    }) frKeys
                  )
                  // lib.listToAttrs (
                    map (n: {
                      name = "Mod4+${toString n}";
                      value = null;
                    }) (lib.range 0 9)
                  )
                  // {
                    # Scratchpad removed: on AZERTY "-" IS the workspace 6 key
                    # (duplicate keybinding at startup).
                    "Mod4+Shift+minus" = null;
                  };

                # Media (Fn) keys. Without these, the keyboard sends the
                # XF86Audio*/XF86MonBrightness* keysyms but nothing handles them.
                # Volume through wireplumber (what the bar reads), playback
                # through playerctl.
                wpctl = "${pkgs.wireplumber}/bin/wpctl";
                playerctl = "${pkgs.playerctl}/bin/playerctl";
                media = {
                  "XF86AudioRaiseVolume" = "exec --no-startup-id ${wpctl} set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+";
                  "XF86AudioLowerVolume" = "exec --no-startup-id ${wpctl} set-volume @DEFAULT_AUDIO_SINK@ 5%-";
                  "XF86AudioMute" = "exec --no-startup-id ${wpctl} set-mute @DEFAULT_AUDIO_SINK@ toggle";
                  "XF86AudioMicMute" = "exec --no-startup-id ${wpctl} set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
                  "XF86AudioPlay" = "exec --no-startup-id ${playerctl} play-pause";
                  "XF86AudioPause" = "exec --no-startup-id ${playerctl} play-pause";
                  "XF86AudioNext" = "exec --no-startup-id ${playerctl} next";
                  "XF86AudioPrev" = "exec --no-startup-id ${playerctl} previous";
                };

                # Built-in screens (does nothing where there is none).
                brightness = {
                  "XF86MonBrightnessUp" = "exec --no-startup-id ${pkgs.brightnessctl}/bin/brightnessctl set +5%";
                  "XF86MonBrightnessDown" = "exec --no-startup-id ${pkgs.brightnessctl}/bin/brightnessctl set 5%-";
                };
              in
              lib.mkOptionDefault ((lib.optionalAttrs isAzerty azerty) // media // brightness);
          };
        };

        # Compositor: clean gaps, shadows, rounded corners.
        services.picom = {
          enable = true;
          backend = "glx";
          vSync = true;
          fade = true;
          fadeDelta = 4;
          shadow = true;
          shadowOffsets = [
            (-8)
            (-8)
          ];
          shadowOpacity = 0.35;
          settings = {
            shadow-radius = 16;
            corner-radius = 10;
            rounded-corners-exclude = [
              "window_type = 'dock'"
              "window_type = 'desktop'"
              "class_g = 'i3bar'"
            ];
            shadow-exclude = [
              "class_g = 'i3bar'"
              "class_g = 'i3-frame'"
            ];
            blur-method = "dual_kawase";
            blur-strength = 4;
            blur-background-exclude = [
              "window_type = 'dock'"
              "window_type = 'desktop'"
            ];
          };
        };
      }
    ]
  );
}
