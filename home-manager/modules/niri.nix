{
  hostname,
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

        output "Lenovo Group Limited LEN T24h-20 V308A2D4" {
            mode "2560x1440"
            scale 1
            transform "normal"
            position x=440 y=0
        }

        output "Lenovo Group Limited LEN T24h-20 V308A2KA" {
            mode "2560x1440"
            scale 1
            transform "normal"
            position x=440 y=0
        }
      ''
    else
      # Majesty is a desktop profile and has no guaranteed eDP-1 output.
      # Leave its outputs to niri's automatic discovery instead of forcing
      # the laptop panel configuration used by tpx13.
      ''
        output "Xiaomi Corporation Mi Monitor Unknown" {
            mode "3440x1440@144.000"
            scale 1
            transform "normal"
            position x=0 y=0
        }
      '';
in
{
  home.packages = with pkgs; [
    xwayland-satellite
  ];

  # Output geometry is host-specific and should not be overwritten by the shell.
  xdg.configFile."niri-host/outputs.kdl".text = outputConfig;
}
