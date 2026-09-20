{ inputs, pkgs, ... }:

{
  imports = [ inputs.noctalia.homeModules.default ];

  programs.noctalia = {
    enable = true;
    package = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
    systemd.enable = true;

    # Noctalia writes this TOML through Home Manager and validates it while
    # evaluating the configuration. The clock widget opens the calendar.
    settings = {
      bar.order = [ "main" ];
      bar.main = {
        position = "top";
        enabled = true;
        reserve_space = true;
        thickness = 32;
        margin_ends = 0;
        padding = 8;
        widget_spacing = 4;
        capsule = false;
        start = [ "media" ];
        center = [
          "calendar"
          "notifications"
        ];
        end = [
          "tray"
          "network"
          "bluetooth"
          "volume"
          "settings"
          "time"
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
    };
  };
}
