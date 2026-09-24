{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.server.webdav;
in
{
  options.server.webdav.environmentFile = lib.mkOption {
    type = lib.types.path;
    default = "/etc/webdav/environment";
    description = "EnvironmentFile containing WEBDAV_USERNAME and WEBDAV_PASSWORD.";
  };

  config = {
    environment.systemPackages = [ pkgs.webdav ];

    systemd.tmpfiles.rules = [
      "d /srv/webdav 0750 webdav users -"
      "d /etc/webdav 0755 root root -"
    ];

    users.users.webdav = {
      isSystemUser = true;
      group = "webdav";
      home = "/srv/webdav";
    };
    users.groups.webdav = { };

    environment.etc."webdav/config.yml".text = builtins.toJSON {
      address = "127.0.0.1";
      port = 6065;
      prefix = "/webdav";
      directory = "/srv/webdav";
      permissions = "CRUD";
      users = [
        {
          username = "{env}WEBDAV_USERNAME";
          password = "{env}WEBDAV_PASSWORD";
        }
      ];
    };

    systemd.services.webdav = {
      description = "WebDAV server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig.ConditionPathExists = cfg.environmentFile;
      serviceConfig = {
        ExecStart = "${pkgs.webdav}/bin/webdav -c /etc/webdav/config.yml";
        EnvironmentFile = cfg.environmentFile;
        User = "webdav";
        Group = "webdav";
        WorkingDirectory = "/srv/webdav";
        Restart = "on-failure";
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/srv/webdav" ];
      };
    };
  };
}
