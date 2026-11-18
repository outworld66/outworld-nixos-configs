{
  hostname,
  lib,
  pkgs,
  user,
  ...
}:

let
  enabled = builtins.elem hostname [
    "majesty"
    "tpx13"
  ];
in
{
  config = lib.mkIf enabled {
    users.groups.sota-connect = { };
    users.users.${user}.extraGroups = [ "sota-connect" ];

    systemd.packages = [ pkgs.sota-connect ];
    systemd.services.sota-connect.enable = true;
  };
}
