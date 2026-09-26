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
          if [ ! -s /var/lib/ente/s3-access-key ]; then
            printf 'ente-local-access\n' > /var/lib/ente/s3-access-key
            head -c 24 /dev/urandom | base64 -w0 > /var/lib/ente/s3-secret-key
            head -c 32 /dev/urandom | base64 -w0 > /var/lib/ente/encryption-key
            head -c 64 /dev/urandom | base64 -w0 > /var/lib/ente/hash-key
            head -c 32 /dev/urandom | base64 -w0 > /var/lib/ente/jwt-secret
            chmod 0400 /var/lib/ente/*-key /var/lib/ente/jwt-secret
            chown ente:ente /var/lib/ente/*-key /var/lib/ente/jwt-secret
          fi
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
      path = [ pkgs.garage ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "ente-garage" ''
          node_id=$(garage status | tail -n1 | awk '{ print $1 }')
          garage layout show | grep -q "$node_id" || garage layout assign -c 1G -z ente "$node_id"
          garage layout apply --version 1 || true
          if ! garage key info "$(cat /var/lib/ente/s3-access-key)" >/dev/null 2>&1; then
            garage key import "$(cat /var/lib/ente/s3-access-key)" "$(cat /var/lib/ente/s3-secret-key)" --yes
            garage bucket create ente
            garage bucket allow --read --write ente --key "$(cat /var/lib/ente/s3-access-key)"
          fi
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
