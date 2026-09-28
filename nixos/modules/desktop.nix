{
  hostname,
  inputs,
  lib,
  pkgs,
  user,
  ...
}:
{
  imports = [
    inputs.noctalia-greeter.nixosModules.default
    inputs.umbriel.nixosModules.default
  ];

  programs.niri.enable = true;
  programs.umbriel.enable = true;

  boot.extraModprobeConfig = lib.mkIf (hostname == "tpx13") ''
    options thinkpad_acpi fan_control=1
  '';

  users.groups.fan_ctl = lib.mkIf (hostname == "tpx13") { };
  users.users.${user}.extraGroups = lib.mkIf (hostname == "tpx13") [ "fan_ctl" ];

  services.udev.extraRules = lib.mkIf (hostname == "tpx13") ''
    ACTION=="add|bind", SUBSYSTEM=="platform", DRIVER=="thinkpad_acpi", RUN+="${pkgs.coreutils}/bin/chgrp fan_ctl /proc/acpi/ibm/fan", RUN+="${pkgs.coreutils}/bin/chmod 0664 /proc/acpi/ibm/fan"
  '';

  # Keep the keyboard layout consistent in the greeter and desktop session.
  # Niri repeats these settings in its user configuration because it owns
  # the Wayland input seat after the session starts.
  services.xserver.xkb = {
    layout = "us,ru";
    options = "grp:lalt_lshift_toggle,compose:ralt,ctrl:nocaps";
  };

  # The GNOME file chooser uses libadwaita's portal color preference instead
  # of the GTK theme configured in Home Manager. Use the GTK backend for file
  # dialogs so VSCodium, Zed, and other portal clients consistently get the
  # configured dark theme.
  xdg.portal.config.niri."org.freedesktop.impl.portal.FileChooser" = "gtk";

  # Never start the user's session without authentication.  In particular,
  # switching away from a locked session must only expose the greeter, not
  # create a new authenticated session on another VT.
  services.displayManager.autoLogin.enable = false;

  services.displayManager.noctalia-greeter = {
    enable = true;
    settings = {
      session.default = "niri";
      appearance.theme_mode = "dark";
      keyboard = {
        layout = "us,ru";
        options = "grp:lalt_lshift_toggle,compose:ralt,ctrl:nocaps";
      };
    };
  };

  # The shell keyboard-layout indicator resolves layout names to codes via
  # /usr/share/X11/xkb/rules/base.lst, which does not exist on NixOS.
  systemd.tmpfiles.rules = [
    "L+ /usr/share/X11/xkb/rules/base.lst - - - - ${pkgs.xkeyboardconfig}/share/X11/xkb/rules/base.lst"
  ];
}
