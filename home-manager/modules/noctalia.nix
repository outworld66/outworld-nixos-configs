{
  hostname,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  batterySuspend = pkgs.writeShellScript "noctalia-battery-suspend" ''
    for online in /sys/class/power_supply/*/online; do
      [ -r "$online" ] && [ "$(<"$online")" = 1 ] && exit 0
    done
    ${pkgs.systemd}/bin/systemctl suspend
  '';
in

{
  imports = [ inputs.noctalia.homeModules.default ];

  programs.noctalia = {
    enable = true;
    package = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
    systemd.enable = true;

    customPalettes.agterm-grey = {
      dark = {
        mPrimary = "#b8bcc2";
        mOnPrimary = "#1a1b1e";
        mSecondary = "#92979f";
        mOnSecondary = "#17181b";
        mTertiary = "#c6c9ce";
        mOnTertiary = "#1a1b1e";
        mError = "#c58f98";
        mOnError = "#24171a";
        mSurface = "#1a1b1e";
        mOnSurface = "#d7d9dc";
        mSurfaceVariant = "#27292d";
        mOnSurfaceVariant = "#aeb2b8";
        mOutline = "#4c5158";
        mShadow = "#101113";
        mHover = "#35383e";
        mOnHover = "#e1e3e6";
        terminal = {
          background = "#1a1b1e";
          foreground = "#d7d9dc";
          cursor = "#d7d9dc";
          cursorText = "#1a1b1e";
          selectionBg = "#4c566a";
          selectionFg = "#e1e3e6";
          normal = {
            black = "#1a1b1e";
            red = "#c58f98";
            green = "#aeb8a3";
            yellow = "#c1b79a";
            blue = "#9baec2";
            magenta = "#b0a3ba";
            cyan = "#9fb8b8";
            white = "#d7d9dc";
          };
          bright = {
            black = "#4c5158";
            red = "#d5a0a8";
            green = "#bdc9b1";
            yellow = "#d2c8aa";
            blue = "#b5c8dc";
            magenta = "#c5b7d0";
            cyan = "#b9d2d2";
            white = "#f0f1f2";
          };
        };
      };
    };

    # Noctalia writes this TOML through Home Manager and validates it while
    # evaluating the configuration. The clock widget opens the calendar.
    settings = {
      theme = {
        mode = "dark";
        source = "custom";
        custom_palette = "agterm-grey";

        templates = {
          enable_builtin_templates = true;
          builtin_ids = [
            "gtk3"
            "gtk4"
            "qt"
            "ghostty"
          ];
        };
      };

      bar.order = [ "main" ];
      bar.main = {
        position = "top";
        enabled = true;
        reserve_space = true;
        thickness = 32;
        margin_ends = 0;
        padding = 8;
        widget_spacing = 6;
        capsule = true;
        capsule_fill = "surface_variant";
        capsule_foreground = "on_surface";
        capsule_padding = 6;
        capsule_radius = 6;
        capsule_opacity = 0.92;
        capsule_border = "outline";
        start = [ "media" ];
        center = [
          "calendar"
          "time"
          "notifications"
        ];
        end = [
          "tray"
          "keyboard_layout"
          "volume"
          "network"
          "settings"
          "session"
        ];
      };

      widget.calendar = {
        type = "clock";
        format = "{:%a %d %b}";
      };
      widget.time = {
        type = "clock";
        format = "{:%H:%M}";
      };

      widget.keyboard_layout = {
        type = "keyboard_layout";
      };
    }
    // lib.optionalAttrs (hostname == "tpx13") {
      idle.behavior.lock = {
        timeout = 300;
        action = "lock";
        enabled = true;
      };
      idle.behavior."battery-suspend" = {
        timeout = 1800;
        action = "command";
        command = "${batterySuspend}";
      };
    };
  };
}
