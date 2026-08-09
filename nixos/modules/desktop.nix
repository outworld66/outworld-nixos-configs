{
  user,
  ...
}:
{
  programs.niri.enable = true;

  # The GNOME file chooser uses libadwaita's portal color preference instead
  # of the GTK theme configured in Home Manager. Use the GTK backend for file
  # dialogs so VSCodium, Zed, and other portal clients consistently get the
  # configured dark theme.
  xdg.portal.config.niri."org.freedesktop.impl.portal.FileChooser" = "gtk";

  # Never start the user's session without authentication.  In particular,
  # switching away from a locked session must only expose the greeter, not
  # create a new authenticated session on another VT.
  services.displayManager.autoLogin.enable = false;

  services.displayManager.dms-greeter = {
    enable = true;
    compositor.name = "niri";
    configHome = "/home/${user}";
  };
}
