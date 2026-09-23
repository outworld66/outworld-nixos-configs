{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.server.gobackup;
  gobackup = pkgs.stdenvNoCC.mkDerivation {
    pname = "gobackup";
    version = "3.1.1";

    src = pkgs.fetchurl {
      url = "https://github.com/gobackup/gobackup/releases/download/v3.1.1/gobackup-linux-amd64.tar.gz";
      hash = "sha256-1OwmTC8mZ0KqNw6QoWZlNZF94CB72Qh4aCNBX85JJMY=";
    };

    dontUnpack = true;

    installPhase = ''
      tar -xzf "$src"
      install -Dm755 gobackup $out/bin/gobackup
    '';
  };
in
{
  options.server.gobackup.configFile = lib.mkOption {
    type = lib.types.path;
    default = "/etc/gobackup/gobackup.yml";
    description = "GoBackup configuration file.";
  };

  config = {
    environment.systemPackages = [ gobackup ];

    systemd.tmpfiles.rules = [
      "d /etc/gobackup 0750 root root -"
      "d /var/lib/gobackup 0750 root root -"
    ];

    systemd.services.gobackup = {
      description = "GoBackup backup job";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        ConditionPathExists = cfg.configFile;
        Type = "oneshot";
        ExecStart = "${gobackup}/bin/gobackup perform --config ${cfg.configFile}";
        ProtectSystem = "strict";
        ReadWritePaths = [ "/var/lib/gobackup" ];
      };
    };

    systemd.timers.gobackup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };
  };
}
