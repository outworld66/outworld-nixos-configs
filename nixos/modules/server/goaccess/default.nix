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
    unitConfig.ConditionPathExists = "/var/log/caddy/access.log";
    serviceConfig = {
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.goaccess}/bin/goaccess"
        "/var/log/caddy/access.log"
        "--log-format=CADDY"
        "--output=/srv/goaccess/index.html"
        "--real-time-html"
        "--addr=0.0.0.0"
        "--port=7890"
        "--ws-url=ws://192.168.0.3:7890"
        "--fifo-out=/srv/goaccess/goaccess.fifo"
      ];
      ExecStartPre = "${pkgs.coreutils}/bin/rm -f /srv/goaccess/goaccess.fifo";
      WorkingDirectory = "/srv/goaccess";
      Restart = "on-failure";
      ProtectSystem = "full";
      ReadOnlyPaths = [ "/var/log/caddy/access.log" ];
      ReadWritePaths = [ "/srv/goaccess" ];
    };
  };
}
