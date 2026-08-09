{ inputs, pkgs, ... }:
{
  imports = [ inputs.niri.homeModules.niri ];
  home.packages = with pkgs; [
    xwayland-satellite
  ];
  programs.niri = { };
}
