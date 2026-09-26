{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.server.cloudreve;
  cloudreve = pkgs.stdenvNoCC.mkDerivation {
    pname = "cloudreve";
    version = "4.19.1";
    src = pkgs.fetchurl {
      url = "https://github.com/cloudreve/Cloudreve/releases/download/4.19.1/cloudreve_4.19.1_linux_amd64.tar.gz";
      hash = "sha256-KHofWa2xJJrxXNVQsZHS+nETK/0SX+rYV48gFSxLmd4=";
    };
    sourceRoot = ".";
    dontBuild = true;
    installPhase = "install -Dm755 cloudreve $out/bin/cloudreve";
  };
in
{
  options.server.cloudreve.enable = lib.mkEnableOption "cloudreve service";
  config = lib.mkIf cfg.enable {
    users.users.cloudreve = {
      isSystemUser = true;
      group = "cloudreve";
      home = "/var/lib/cloudreve";
    };
    users.groups.cloudreve = { };
    systemd.tmpfiles.rules = [ "d /var/lib/cloudreve 0750 cloudreve cloudreve -" ];

    systemd.services.cloudreve = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        ExecStartPre = "${pkgs.coreutils}/bin/install -Dm755 ${cloudreve}/bin/cloudreve /var/lib/cloudreve/cloudreve";
        ExecStart = "/var/lib/cloudreve/cloudreve -c /var/lib/cloudreve/conf.ini";
        User = "cloudreve";
        Group = "cloudreve";
        WorkingDirectory = "/var/lib/cloudreve";
        Restart = "on-failure";
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/cloudreve" ];
      };
    };
  };
}
