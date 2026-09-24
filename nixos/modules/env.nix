{ lib, pkgs, ... }:

{
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocales = [ "ru_RU.UTF-8/UTF-8" ];

  environment.sessionVariables = rec {
    TERMINAL = "alacritty";
    EDITOR = "nvim";
    XDG_BIN_HOME = "$HOME/.local/bin";
    GIO_EXTRA_MODULES = lib.mkForce [
      "${pkgs.dconf.lib}/lib/gio/modules"
      "${pkgs.gvfs}/lib/gio/modules"
    ];
    PATH = [
      "${XDG_BIN_HOME}"
    ];
  };
}
