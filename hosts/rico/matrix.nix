{
  config,
  lib,
  pkgs,
  ...
}:
let
  matrixDomain = "matrix.outworld66.ru";
  elementDomain = "chat.outworld66.ru";
  rtcDomain = "matrix-rtc.outworld66.ru";
  elementWeb = pkgs.element-web.override {
    conf = {
      default_server_name = matrixDomain;
      default_server_config = {
        "m.homeserver" = {
          base_url = "https://${matrixDomain}";
        };
        "m.identity_server" = {
          base_url = "";
        };
      };
      disable_custom_urls = true;
      disable_guests = true;
      element_call.use_exclusively = true;
      features.feature_element_call_video_rooms = true;
    };
  };
in
lib.mkIf (config.server.secrets.enable or false) {
  services.postgresql = {
    enable = true;
    initialScript = pkgs.writeText "matrix-database.sql" ''
      SELECT $$CREATE DATABASE matrix-synapse TEMPLATE template0 LC_COLLATE 'C' LC_CTYPE 'C'$$
      WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'matrix-synapse')
      \gexec
    '';
    ensureDatabases = [ "matrix-synapse" ];
    ensureUsers = [
      {
        name = "matrix-synapse";
        ensureDBOwnership = true;
      }
    ];
  };

  services.matrix-synapse = {
    enable = true;
    dataDir = "/var/lib/matrix-synapse";
    extraConfigFiles = [ "/var/lib/matrix-synapse/secrets.yaml" ];
    settings = {
      server_name = matrixDomain;
      public_baseurl = "https://${matrixDomain}/";
      enable_registration = false;
      federation_enabled = false;
      password_config.enabled = false;
      database = {
        name = "psycopg2";
        args = {
          database = "matrix-synapse";
          host = "/run/postgresql";
          user = "matrix-synapse";
        };
      };
      listeners = [
        {
          port = 8008;
          bind_addresses = [ "127.0.0.1" ];
          type = "http";
          tls = false;
          x_forwarded = true;
          resources = [
            {
              names = [
                "client"
                "openid"
              ];
              compress = false;
            }
          ];
        }
      ];
      oidc_providers = [
        {
          idp_id = "pocket-id";
          idp_name = "Pocket ID";
          issuer = "https://id.outworld66.ru";
          client_id = "matrix";
          client_secret_path = "/var/lib/matrix-synapse/oidc-client-secret";
          scopes = [
            "openid"
            "profile"
            "email"
          ];
          enable_registration = true;
          allow_existing_users = true;
          user_mapping_provider.config = {
            localpart_template = "{{ user.preferred_username }}";
            display_name_template = "{{ user.name }}";
            email_template = "{{ user.email }}";
          };
        }
      ];
      experimental_features = {
        msc3266_enabled = true;
        msc4143_enabled = true;
        msc4222_enabled = true;
      };
      max_event_delay_duration = "24h";
      rc_message = {
        per_second = 0.5;
        burst_count = 30;
      };
      rc_delayed_event_mgmt = {
        per_second = 1;
        burst_count = 20;
      };
      matrix_rtc.transports = [
        {
          type = "livekit";
          livekit_service_url = "https://${rtcDomain}/livekit/jwt";
        }
      ];
    };
  };

  services.pocket-id = {
    managedGroups = [
      "matrix-admin"
      "matrix-user"
    ];
    userGroupMappings = [
      {
        email = "outworld66@gmail.com";
        groups = [ "matrix-admin" ];
      }
    ];
  };

  systemd.services.matrix-synapse = {
    requires = [
      "matrix-synapse-secret.service"
      "pocket-id-oidc-provision.service"
      "postgresql.service"
    ];
    after = [
      "matrix-synapse-secret.service"
      "pocket-id-oidc-provision.service"
      "postgresql.service"
    ];
  };

  systemd.services.matrix-synapse-secret = {
    description = "Create persistent Synapse secret configuration";
    wantedBy = [ "multi-user.target" ];
    before = [ "matrix-synapse.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "matrix-synapse-secret" ''
        install -d -m 0750 -o matrix-synapse -g matrix-synapse /var/lib/matrix-synapse
        if [ ! -s /var/lib/matrix-synapse/secrets.yaml ]; then
          umask 077
          printf "macaroon_secret_key: '%s'\\nregistration_shared_secret: '%s'\\n" \
            "$(${pkgs.openssl}/bin/openssl rand -hex 32)" \
            "$(${pkgs.openssl}/bin/openssl rand -hex 32)" \
            > /var/lib/matrix-synapse/secrets.yaml
        fi
        if ! grep -q '^registration_shared_secret:' /var/lib/matrix-synapse/secrets.yaml; then
          umask 077
          printf "registration_shared_secret: '%s'\\n" "$(${pkgs.openssl}/bin/openssl rand -hex 32)" \
            >> /var/lib/matrix-synapse/secrets.yaml
        fi
        chown matrix-synapse:matrix-synapse /var/lib/matrix-synapse/secrets.yaml
        chmod 0400 /var/lib/matrix-synapse/secrets.yaml
      '';
    };
  };

  systemd.services.matrix-admin-bootstrap = {
    description = "Bootstrap the Matrix server administrator";
    wantedBy = [ "multi-user.target" ];
    requires = [
      "matrix-synapse.service"
      "pocket-id-oidc-provision.service"
    ];
    after = [
      "matrix-synapse.service"
      "pocket-id-oidc-provision.service"
    ];
    path = [
      pkgs.coreutils
      pkgs.openssl
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "matrix-admin-bootstrap" ''
        set -eu
        password_file=$(mktemp)
        trap 'rm -f "$password_file"' EXIT
        chmod 0600 "$password_file"
        openssl rand -base64 48 > "$password_file"
        ${config.services.matrix-synapse.package}/bin/register_new_matrix_user \
          --admin \
          --exists-ok \
          --user outworld66 \
          --password-file "$password_file" \
          -c ${config.services.matrix-synapse.configFile} \
          -c /var/lib/matrix-synapse/secrets.yaml \
          http://127.0.0.1:8008/
      '';
    };
  };

  systemd.services.livekit-secret = {
    description = "Create persistent LiveKit credentials for MatrixRTC";
    wantedBy = [ "multi-user.target" ];
    before = [
      "livekit.service"
      "lk-jwt-service.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "livekit-secret" ''
        install -d -m 0700 /var/lib/livekit
        if [ ! -s /var/lib/livekit/keys ]; then
          umask 077
          printf 'matrixrtc: %s\n' "$(${pkgs.coreutils}/bin/head -c 32 /dev/urandom | ${pkgs.coreutils}/bin/base64 -w0)" > /var/lib/livekit/keys
        fi
        chmod 0400 /var/lib/livekit/keys
      '';
    };
  };

  services.livekit = {
    enable = true;
    keyFile = "/var/lib/livekit/keys";
    settings = {
      port = 7880;
      rtc = {
        tcp_port = 7881;
        udp_port = 7882;
        use_external_ip = true;
      };
    };
  };
  systemd.services.livekit = {
    requires = [ "livekit-secret.service" ];
    after = [ "livekit-secret.service" ];
  };

  services.lk-jwt-service = {
    enable = true;
    livekitUrl = "wss://${rtcDomain}/livekit/sfu";
    keyFile = "/var/lib/livekit/keys";
    port = 8088;
  };
  systemd.services.lk-jwt-service = {
    requires = [ "livekit-secret.service" ];
    after = [ "livekit-secret.service" ];
  };

  networking.firewall = {
    allowedTCPPorts = [ 7881 ];
    allowedUDPPorts = [ 7882 ];
  };

  services.homepage-dashboard.services = lib.mkAfter [
    {
      Social = [
        {
          "Element" = {
            href = "https://${elementDomain}";
            icon = "element.png";
            description = "Private Rico Matrix chat and group calls";
          };
        }
      ];
    }
  ];

  services.caddy.virtualHosts = {
    ${matrixDomain}.extraConfig = ''
      @matrixWellKnown path /.well-known/matrix/client
      handle @matrixWellKnown {
        header Content-Type application/json
        header Access-Control-Allow-Origin *
        respond '{"m.homeserver":{"base_url":"https://${matrixDomain}"}}' 200
      }
      handle {
        reverse_proxy 127.0.0.1:8008
      }
    '';

    ${elementDomain}.extraConfig = ''
      root * ${elementWeb}
      try_files {path} /index.html
      file_server
    '';

    ${rtcDomain}.extraConfig = ''
      @jwtService path /livekit/jwt/sfu/get /livekit/jwt/healthz
      handle @jwtService {
        uri strip_prefix /livekit/jwt
        reverse_proxy 127.0.0.1:8088
      }
      @livekit path /livekit/sfu /livekit/sfu/*
      handle @livekit {
        uri strip_prefix /livekit/sfu
        reverse_proxy 127.0.0.1:7880
      }
      respond 404
    '';
  };
}
