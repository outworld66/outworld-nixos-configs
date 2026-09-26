{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.server.ente;
in
{
  options.server.ente.enable = lib.mkEnableOption "ente service";
  config = lib.mkIf cfg.enable {
    services.garage = {
      enable = true;
      package = pkgs.garage;
      settings = {
        replication_factor = 1;
        consistency_mode = "consistent";
        rpc_bind_addr = "127.0.0.1:3901";
        rpc_public_addr = "127.0.0.1:3901";
        rpc_secret = builtins.hashString "sha256" "ente-local-garage";
        s3_api = {
          s3_region = "us-east-1";
          api_bind_addr = "127.0.0.1:3900";
        };
      };
    };

    services.ente = {
      api = {
        enable = true;
        enableLocalDB = true;
        domain = "ente-api.private.outworld66.ru";
        nginx.enable = true;
        settings = {
          s3 = {
            use_path_style_urls = true;
            b2-eu-cen = {
              endpoint = "http://127.0.0.1:3900";
              region = "us-east-1";
              bucket = "ente";
              key._secret = "/var/lib/ente/s3-access-key";
              secret._secret = "/var/lib/ente/s3-secret-key";
            };
          };
          key = {
            encryption._secret = "/var/lib/ente/encryption-key";
            hash._secret = "/var/lib/ente/hash-key";
          };
          jwt.secret._secret = "/var/lib/ente/jwt-secret";
        };
      };
      web = {
        enable = true;
        domains = {
          api = "ente-api.private.outworld66.ru";
          accounts = "ente-accounts.private.outworld66.ru";
          cast = "ente-cast.private.outworld66.ru";
          albums = "ente-albums.private.outworld66.ru";
          photos = "ente-photos.private.outworld66.ru";
        };
      };
    };

    services.nginx.defaultListen = [
      {
        addr = "127.0.0.1";
        port = 8081;
      }
    ];
    services.nginx.virtualHosts =
      lib.genAttrs
        [
          "ente-api.private.outworld66.ru"
          "ente-accounts.private.outworld66.ru"
          "ente-cast.private.outworld66.ru"
          "ente-albums.private.outworld66.ru"
          "ente-photos.private.outworld66.ru"
        ]
        (_: {
          forceSSL = false;
        });

    systemd.services.ente-secrets = {
      description = "Generate Ente local secrets";
      before = [
        "ente.service"
        "garage.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "ente-secrets" ''
          install -d -m 0750 -o ente -g ente /var/lib/ente
          if [ ! -s /var/lib/ente/encryption-key ]; then
            printf 'GK%s\n' "$(${pkgs.coreutils}/bin/head -c 12 /dev/urandom | ${pkgs.coreutils}/bin/od -An -tx1 | ${pkgs.coreutils}/bin/tr -d ' \n')" > /var/lib/ente/s3-access-key
            ${pkgs.coreutils}/bin/head -c 32 /dev/urandom | ${pkgs.coreutils}/bin/od -An -tx1 | ${pkgs.coreutils}/bin/tr -d ' \n' > /var/lib/ente/s3-secret-key
            ${pkgs.coreutils}/bin/head -c 32 /dev/urandom | ${pkgs.coreutils}/bin/base64 -w0 > /var/lib/ente/encryption-key
            ${pkgs.coreutils}/bin/head -c 64 /dev/urandom | ${pkgs.coreutils}/bin/base64 -w0 > /var/lib/ente/hash-key
            ${pkgs.coreutils}/bin/head -c 32 /dev/urandom | ${pkgs.coreutils}/bin/base64 -w0 > /var/lib/ente/jwt-secret
          elif ! ${pkgs.gnugrep}/bin/grep -Eq '^GK[[:xdigit:]]{24}$' /var/lib/ente/s3-access-key 2>/dev/null \
            || ! ${pkgs.gnugrep}/bin/grep -Eq '^[[:xdigit:]]{64}$' /var/lib/ente/s3-secret-key 2>/dev/null; then
            printf 'GK%s\n' "$(${pkgs.coreutils}/bin/head -c 12 /dev/urandom | ${pkgs.coreutils}/bin/od -An -tx1 | ${pkgs.coreutils}/bin/tr -d ' \n')" > /var/lib/ente/s3-access-key
            ${pkgs.coreutils}/bin/head -c 32 /dev/urandom | ${pkgs.coreutils}/bin/od -An -tx1 | ${pkgs.coreutils}/bin/tr -d ' \n' > /var/lib/ente/s3-secret-key
          fi
          ${pkgs.coreutils}/bin/chmod 0400 /var/lib/ente/*-key /var/lib/ente/jwt-secret
          ${pkgs.coreutils}/bin/chown ente:ente /var/lib/ente/*-key /var/lib/ente/jwt-secret
        '';
      };
    };

    systemd.services.garage = {
      after = [ "ente-secrets.service" ];
      requires = [ "ente-secrets.service" ];
    };
    systemd.services.ente-garage = {
      description = "Configure Ente Garage storage";
      wantedBy = [ "multi-user.target" ];
      after = [
        "garage.service"
        "ente-secrets.service"
      ];
      requires = [
        "garage.service"
        "ente-secrets.service"
      ];
      path = [
        pkgs.garage
        pkgs.coreutils
        pkgs.gnugrep
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "ente-garage" ''
          set -e
          node_id=$(garage node id -q | ${pkgs.coreutils}/bin/cut -d@ -f1)
          garage layout show | grep -q "$node_id" || garage layout assign -c 1G -z ente "$node_id"
          if garage layout show | grep -q 'Staged role changes'; then
            version=$(garage layout show | ${pkgs.coreutils}/bin/sed -n 's/^Current cluster layout version: //p')
            garage layout apply --version "$((version + 1))"
          fi
          if ! ${pkgs.gnugrep}/bin/grep -Eq '^[[:xdigit:]]{64}$' /var/lib/ente/s3-secret-key; then
            ${pkgs.coreutils}/bin/head -c 32 /dev/urandom | ${pkgs.coreutils}/bin/od -An -tx1 | ${pkgs.coreutils}/bin/tr -d ' \n' > /var/lib/ente/s3-secret-key
            ${pkgs.coreutils}/bin/chmod 0400 /var/lib/ente/s3-secret-key
            ${pkgs.coreutils}/bin/chown ente:ente /var/lib/ente/s3-secret-key
          fi
          access_key=$(${pkgs.coreutils}/bin/cat /var/lib/ente/s3-access-key)
          secret_key=$(${pkgs.coreutils}/bin/cat /var/lib/ente/s3-secret-key)
          garage key info "$access_key" >/dev/null 2>&1 || garage key import "$access_key" "$secret_key" --yes
          garage bucket info ente >/dev/null 2>&1 || garage bucket create ente
          garage bucket allow --read --write ente --key "$access_key"
        '';
        RemainAfterExit = true;
      };
    };
    systemd.services.ente = {
      after = [ "ente-garage.service" ];
      requires = [ "ente-garage.service" ];
    };
  };
}
