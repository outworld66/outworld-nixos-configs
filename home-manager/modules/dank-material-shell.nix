{
  config,
  inputs,
  pkgs,
  configDirectory,
  ...
}:

let
  settingsDirectory = "${configDirectory}/home-manager/dotfiles/dank-material-shell";
  linkSetting = name: config.lib.file.mkOutOfStoreSymlink "${settingsDirectory}/${name}";
in
{
  imports = [ inputs.dms.homeModules.dank-material-shell ];

  programs.dank-material-shell = {
    enable = true;

    systemd = {
      enable = true;
      restartIfChanged = true;
    };

    # Install every optional dependency exposed by the DMS module.
    enableSystemMonitoring = true;
    dgop.package = inputs.dgop.packages.${pkgs.stdenv.hostPlatform.system}.default;
    enableVPN = true;
    enableDynamicTheming = true;
    enableAudioWavelength = true;
    enableCalendarEvents = true;
    enableClipboardPaste = true;
  };

  # Keep GUI-managed DMS settings writable while tracking them in this repo.
  xdg.configFile = {
    "DankMaterialShell/settings.json".source = linkSetting "settings.json";
    "DankMaterialShell/clsettings.json".source = linkSetting "clsettings.json";
    "DankMaterialShell/plugin_settings.json".source = linkSetting "plugin_settings.json";
  };
}
