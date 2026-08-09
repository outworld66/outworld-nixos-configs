{ pkgs, ... }:
{
  home.packages = with pkgs; [
    nwg-look
    adw-gtk3
    qt6Packages.qt6ct
    papirus-icon-theme
  ];
  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
  };
}
