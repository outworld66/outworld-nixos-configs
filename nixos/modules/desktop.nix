{
  pkgs,
  ...
}:
{
  programs.niri.enable = true;

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

  # ReGreet greeter: greetd + cage, sessions (incl. niri) are picked up from
  # the display-manager session registry. Keeps the greetd PAM stack, so
  # fingerprint unlock at the greeter continues to work. Newer nixpkgs
  # renames this option to services.displayManager.regreet.
  programs.regreet = {
    enable = true;
    settings.GTK.application_prefer_dark_theme = true;
    theme = {
      package = pkgs.adw-gtk3;
      name = "adw-gtk3-dark";
    };
  };

  # The iNiR keyboard-layout indicator resolves layout names to codes via
  # /usr/share/X11/xkb/rules/base.lst, which does not exist on NixOS.
  systemd.tmpfiles.rules = [
    "L+ /usr/share/X11/xkb/rules/base.lst - - - - ${pkgs.xkeyboardconfig}/share/X11/xkb/rules/base.lst"
  ];
}
