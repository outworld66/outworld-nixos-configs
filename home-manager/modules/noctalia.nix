{
  hostname,
  inputs,
  lib,
  pkgs,
  user,
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

    # Noctalia writes this TOML through Home Manager and validates it while
    # evaluating the configuration. The clock widget opens the calendar.
    settings = {
      theme = {
        mode = "dark";
        source = "wallpaper";
        wallpaper_scheme = "m3-monochrome";

        templates = {
          enable_builtin_templates = true;
          builtin_ids = [
            "gtk3"
            "gtk4"
            "qt"
          ];
        };
      };

      wallpaper.directory = "/home/${user}/Syncthing/pictures/wallpapers";

      shell.greeter_sync.auto_sync = true;

      location = {
        auto_locate = false;
        address = "Saint Petersburg, Russia";
      };

      shell.panel = {
        control_center_placement = "attached";
        open_near_click_control_center = true;
      };

      plugins.enabled = [
        "raycursive/niri-displays"
        "noctalia/screen_recorder"
        "tordex/nvtop"
        "fel/ocr"
        "rylos/syncthing"
        "setyvii/niri-rules-studio"
      ]
      ++ lib.optional (hostname == "tpx13") "piero-93/thinkpad-fan";

      plugin_settings."rylos/syncthing" = {
        url = "http://127.0.0.1:8384/";
        config_path = "/home/${user}/.syncthing/.config/syncthing/config.xml";
        panel_placement = "attached";
        panel_open_near_click = true;
        poll_interval = 10;
        notify_events = true;
        show_pending = true;
      };

      widget.media.actions.left = "panel-toggle control-center media";

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
          "noctalia/screen_recorder:recorder"
          "fel/ocr:ocr"
          "rylos/syncthing:bar"
          "system_cpu"
          "gpu_nvtop"
        ]
        ++ lib.optional (hostname == "tpx13") "piero-93/thinkpad-fan:widget"
        ++ [
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

      widget.gpu_nvtop = {
        type = "sysmon";
        stat = "gpu_usage";
        actions.left = "panel-toggle tordex/nvtop:panel gpu";
      };

      widget.system_cpu = {
        type = "sysmon";
        stat = "cpu_usage";
        actions.left = "panel-toggle control-center system";
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
