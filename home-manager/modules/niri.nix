{
  hostname,
  inputs,
  pkgs,
  ...
}:

let
  outputConfig =
    if hostname == "tpx13" then
      ''
        output "eDP-1" {
            mode "1920x1080"
            scale 1.25
            transform "normal"
            position x=952 y=1440
        }

        output "Xiaomi Corporation Mi Monitor 0000000000000" {
            mode "3440x1440"
            scale 1
            transform "normal"
            position x=0 y=0
        }
      ''
    else
      ''
        output "eDP-1" {
            mode "1920x1080@120.030"
            scale 1.25
            transform "normal"
            position x=0 y=0
        }
      '';
in
{
  imports = [ inputs.niri.homeModules.niri ];

  home.packages = with pkgs; [
    xwayland-satellite
  ];

  # Output geometry is host-specific and should not be overwritten by DMS.
  xdg.configFile."niri-host/outputs.kdl".text = outputConfig;

  programs.niri = { };
}
