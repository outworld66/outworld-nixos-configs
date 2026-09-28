{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.server.donetick;
  donetick = pkgs.stdenvNoCC.mkDerivation {
    pname = "donetick";
    version = "0.1.79";
    src = pkgs.fetchurl {
      url = "https://github.com/donetick/donetick/releases/download/v0.1.79/donetick_Linux_x86_64.tar.gz";
      hash = "sha256-6b9k0vsgqUZyzkxHn3q32XGzwwIDE/2y50GssQA2LFE=";
    };
    sourceRoot = ".";
    dontBuild = true;
    installPhase = "install -Dm755 donetick $out/bin/donetick";
  };
in
{
  options.server.donetick.enable = lib.mkEnableOption "donetick service";
  config = lib.mkIf cfg.enable {
    users.users.donetick = {
      isSystemUser = true;
      group = "donetick";
      home = "/var/lib/donetick";
    };
    users.groups.donetick = { };

    environment.etc."donetick/selfhosted.yaml".text = builtins.readFile ./selfhosted.yaml;
    systemd.tmpfiles.rules = [ "d /var/lib/donetick 0750 donetick donetick -" ];

    systemd.services.donetick-secret = {
      description = "Generate Donetick JWT secret";
      before = [ "donetick.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "donetick-secret" ''
          install -d -m 0750 -o donetick -g donetick /var/lib/donetick
          if [ ! -s /var/lib/donetick/environment ]; then
            umask 077
            printf 'DT_JWT_SECRET=%s\n' "$(head -c 32 /dev/urandom | base64 -w0)" > /var/lib/donetick/environment
            chown donetick:donetick /var/lib/donetick/environment
          fi
        '';
      };
    };

    systemd.services.donetick = {
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "donetick-secret.service"
        "pocket-id-oidc-provision.service"
      ];
      wants = [ "network-online.target" ];
      requires = [
        "donetick-secret.service"
        "pocket-id-oidc-provision.service"
      ];
      serviceConfig = {
        ExecStartPre = "${pkgs.coreutils}/bin/install -Dm640 -o donetick -g donetick /etc/donetick/selfhosted.yaml /var/lib/donetick/config/selfhosted.yaml";
        ExecStart = "${donetick}/bin/donetick";
        Environment = [
          "DT_ENV=selfhosted"
          "DT_SQLITE_PATH=/var/lib/donetick/donetick.db"
          "DT_SERVER_PUBLIC_HOST=https://donetick.outworld66.ru"
          "DT_SERVER_CORS_ALLOW_ORIGINS=https://localhost, http://localhost, capacitor://localhost"
        ];
        EnvironmentFile = [
          "/var/lib/donetick/environment"
          "/var/lib/donetick/oidc.env"
        ];
        User = "donetick";
        Group = "donetick";
        WorkingDirectory = "/var/lib/donetick";
        Restart = "on-failure";
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/donetick" ];
      };
    };

  };
}
