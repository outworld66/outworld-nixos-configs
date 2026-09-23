{ lib, pkgs, ... }:
{
  environment.systemPackages = [ pkgs.goaccess ];

  systemd.tmpfiles.rules = [
    "d /srv/goaccess 0755 root root -"
  ];

  systemd.services.goaccess = {
    description = "GoAccess real-time report";
    wantedBy = [ "multi-user.target" ];
    after = [ "caddy.service" ];
    wants = [ "caddy.service" ];
    serviceConfig = {
      ConditionPathExists = "/var/log/caddy/access.log";
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.goaccess}/bin/goaccess"
        "/var/log/caddy/access.log"
        "--log-format=CADDY"
        "--output=/srv/goaccess/index.html"
        "--real-time-html"
        "--addr=127.0.0.1"
      ];
      Restart = "on-failure";
      ProtectSystem = "strict";
      ReadOnlyPaths = [ "/var/log/caddy/access.log" ];
      ReadWritePaths = [ "/srv/goaccess" ];
    };
  };
}
