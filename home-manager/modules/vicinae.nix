{
  inputs,
  pkgs,
  configDirectory,
  ...
}:

{
  home.file.".local/share/vicinae/scripts/open-nixos-config.sh" = {
    executable = true;
    text = ''
      #!${pkgs.bash}/bin/bash
      # @vicinae.schemaVersion 1
      # @vicinae.title Открыть NixOS конфигурацию
      # @vicinae.mode silent
      # @vicinae.icon ❄️
      # @vicinae.packageName Разработка
      # @vicinae.description Открыть NixOS конфигурацию в Neovim

      ${pkgs.zed-editor}/bin/zeditor \
        --working-directory "${configDirectory}" \
        -e . >/dev/null 2>&1 &
    '';
  };

  programs.vicinae = {
    enable = true;
    systemd.enable = true;

    settings = {
      close_on_focus_loss = true;
      consider_preedit = true;
      pop_to_root_on_close = true;
      favicon_service = "twenty";
      search_files_in_root = true;

      theme = {
        light = {
          name = "vicinae-light";
          icon_theme = "default";
        };
        dark = {
          name = "vicinae-dark";
          icon_theme = "default";
        };
      };

      launcher_window.opacity = 0.96;
    };

    extensions = with inputs.vicinae-extensions.packages.${pkgs.stdenv.hostPlatform.system}; [
      nix
      power-profile
      process-manager
      wifi-commander
    ];
  };

  # Vicinae only indexes desktop entries at startup
  # (https://github.com/vicinaehq/vicinae/issues/1241). Restart the server
  # whenever the user nix profile changes, so newly installed or removed
  # applications show up without a manual restart.
  systemd.user.paths.vicinae-app-rescan = {
    Unit.Description = "Watch user nix profile for desktop entry changes";
    Path.Modified = [ "/nix/var/nix/profiles/per-user/%u/" ];
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.vicinae-app-rescan = {
    Unit = {
      Description = "Restart Vicinae to pick up new desktop entries";
      # avoid restart loops: restarting Vicinae does not touch the profile
      After = [ "vicinae.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl --user restart vicinae.service";
    };
  };
}
