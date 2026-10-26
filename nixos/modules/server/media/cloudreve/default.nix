{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.server.cloudreve;
  cloudreve = pkgs.buildGoModule {
    pname = "cloudreve";
    version = "4.19.1-oidc";
    src = pkgs.fetchFromGitHub {
      owner = "outworld66";
      repo = "cloudreve";
      rev = "b5899c5";
      hash = "sha256-3o1aNNN4ddEryKBVrzAeBV7/6sTmWuG/TlNyc0iWZSI=";
      fetchSubmodules = true;
    };
    vendorHash = "sha256-TGsXy6VZ2pB/bsEGTYy1uIH8zg9mwT1O4zvQpoqc7jU=";
    doCheck = false;
    buildPhase = ''
      runHook preBuild
      go build -o cloudreve .
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm755 cloudreve $out/bin/cloudreve-server
      runHook postInstall
    '';
  };
in
{
  options.server.cloudreve.enable = lib.mkEnableOption "Cloudreve service";

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /srv/cloudreve 0750 cloudreve cloudreve -"
      "d /srv/cloudreve/data 0750 cloudreve cloudreve -"
    ];

    users.groups.cloudreve = { };
    users.users.cloudreve = {
      isSystemUser = true;
      group = "cloudreve";
      home = "/var/lib/cloudreve";
      createHome = true;
    };

    systemd.services.cloudreve-oidc-env = {
      description = "Prepare Cloudreve Pocket ID credentials";
      wantedBy = [ "multi-user.target" ];
      after = [ "pocket-id-oidc-provision.service" ];
      requires = [ "pocket-id-oidc-provision.service" ];
      before = [ "cloudreve.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        install -d -m 0750 -o cloudreve -g cloudreve /var/lib/cloudreve
        umask 077
        printf '%s\n' \
          CR_OIDC_ISSUER=https://id.outworld66.ru \
          CR_OIDC_CLIENT_ID=cloudreve \
          CR_OIDC_REDIRECT_URL=https://cloudreve.outworld66.ru/api/v4/session/oidc/callback \
          CR_SETTING_DEFAULT_siteURL=https://cloudreve.outworld66.ru \
          CR_USERPASS_ENABLED=false \
          CR_PASSKEY_ENABLED=false \
          "CR_OIDC_CLIENT_SECRET=$(cat /var/lib/cloudreve/oidc-client-secret)" \
          > /var/lib/cloudreve/oidc.env
        chown cloudreve:cloudreve /var/lib/cloudreve/oidc.env
        chmod 0400 /var/lib/cloudreve/oidc.env
      '';
    };

    systemd.services.cloudreve = {
      description = "Cloudreve file storage";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "cloudreve-oidc-env.service"
      ];
      requires = [ "cloudreve-oidc-env.service" ];
      serviceConfig = {
        ExecStart = "${cloudreve}/bin/cloudreve-server -w -c /var/lib/cloudreve/conf.ini";
        ExecStartPre = pkgs.writeShellScript "cloudreve-config" ''
          if ! grep -q '^\[Database\]' /var/lib/cloudreve/conf.ini; then
            cat >> /var/lib/cloudreve/conf.ini <<'EOF'
          [Database]
          Type = sqlite
          DBFile = /var/lib/cloudreve/cloudreve.db
          EOF
          fi
          if [ -f /var/lib/cloudreve/cloudreve.db ]; then
            ${pkgs.sqlite}/bin/sqlite3 /var/lib/cloudreve/cloudreve.db \
              "UPDATE settings SET value = 'https://cloudreve.outworld66.ru' WHERE name = 'siteURL';"
          fi
        '';
        EnvironmentFile = "/var/lib/cloudreve/oidc.env";
        User = "cloudreve";
        Group = "cloudreve";
        WorkingDirectory = "/srv/cloudreve";
        Restart = "on-failure";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [
          "/var/lib/cloudreve"
          "/srv/cloudreve"
        ];
      };
    };
  };
}
