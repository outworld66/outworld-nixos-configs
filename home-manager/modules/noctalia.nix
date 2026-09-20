{ inputs, pkgs, ... }:

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
      };
    };

    # Noctalia writes this TOML through Home Manager and validates it while
    # evaluating the configuration. The clock widget opens the calendar.
    settings = {
      theme = {
        mode = "dark";
        source = "custom";
        custom_palette = "agterm-grey";
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
          "session"
          "settings"
          "network"
          "volume"
          "keyboard_layout"
          "tray"
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
    };
  };
}
