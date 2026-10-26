{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  domain = "stoat.outworld66.ru";
  stateDir = "/var/lib/stoat";
  oidcEnvironment = "${stateDir}/oidc.env";
  oidcIssuer = "https://id.outworld66.ru";
  oidcReady = pkgs.writeShellScript "stoat-pocket-id-ready" ''
    for attempt in $(${pkgs.coreutils}/bin/seq 1 120); do
      if ${pkgs.curl}/bin/curl --fail --silent ${lib.escapeShellArg "${oidcIssuer}.well-known/openid-configuration"} \
        | ${pkgs.jq}/bin/jq -e --arg issuer ${lib.escapeShellArg oidcIssuer} \
          '.issuer == $issuer and (.id_token_signing_alg_values_supported | index("RS256") != null)' >/dev/null; then
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 2
    done
    echo "Pocket ID Stoat OIDC provider is not ready" >&2
    exit 1
  '';
  baseConfig = builtins.readFile "${inputs.stoat-backend}/crates/core/config/Revolt.toml";
  configFile = pkgs.writeText "stoat-Revolt.toml" (
    builtins.replaceStrings
      [
        "production = false"
        "environment = \"dev\""
        "app = \"http://local.revolt.chat\""
        "api = \"http://local.revolt.chat/api\""
        "events = \"ws://local.revolt.chat/ws\""
        "autumn = \"http://local.revolt.chat/autumn\""
        "january = \"http://local.revolt.chat/january\""
        "password = \"rabbitpass\""
        "issuer = \"\"\nclient_id = \"\"\nclient_secret = \"\""
        "private_key = \"LS0tLS1CRUdJTiBFQyBQUklWQVRFIEtFWS0tLS0tCk1IY0NBUUVFSUJSUWpyTWxLRnBiVWhsUHpUbERvcEliYk1yeVNrNXpKYzVYVzIxSjJDS3hvQW9HQ0NxR1NNNDkKQXdFSG9VUURRZ0FFWnkrQkg2TGJQZ2hEa3pEempXOG0rUXVPM3pCajRXT1phdkR6ZU00c0pqbmFwd1psTFE0WAp1ZDh2TzVodU94QWhMQlU3WWRldVovWHlBdFpWZmNyQi9BPT0KLS0tLS1FTkQgRUMgUFJJVkFURSBLRVktLS0tLQo\""
        "public_key = \"BGcvgR-i2z4IQ5Mw841vJvkLjt8wY-FjmWrw83jOLCY52qcGZS0OF7nfLzuYbjsQISwVO2HXrmf18gLWVX3Kwfw=\""
        "encryption_key = \"qcuMA+ssxhMyKaNAKBGFfryfFtUH8NDlamQyDwGW6fU=\""
        "access_key_id = \"minioautumn\""
        "secret_access_key = \"minioautumn\""
        "[hosts.livekit]\n\n[rabbit]"
        "[api.livekit.nodes]\n"
      ]
      [
        "production = true"
        "environment = \"prod\""
        "app = \"https://${domain}\""
        "api = \"https://${domain}/api\""
        "events = \"wss://${domain}/ws\""
        "autumn = \"https://${domain}/autumn\""
        "january = \"https://${domain}/january\""
        "password = \"\""
        "issuer = \"${oidcIssuer}\"\nclient_id = \"stoat\"\nclient_secret = \"\""
        "private_key = \"\""
        "public_key = \"\""
        "encryption_key = \"\""
        "access_key_id = \"stoat\""
        "secret_access_key = \"\""
        "[hosts.livekit]\nworldwide = \"wss://stoat.outworld66.ru/livekit\"\n\n[rabbit]"
        "[api.livekit.nodes.worldwide]\nurl = \"http://livekit:7880\"\nlat = 0.0\nlon = 0.0\nkey = \"stoat\"\nsecret = \"\"\n"
      ]
      baseConfig
  );
  composeFile = ./stoat/compose.yml;
  secretFile = "${stateDir}/secrets.env";
in
lib.mkIf (config.server.secrets.enable or false) {
  systemd.services.stoat-secrets = {
    description = "Create persistent Stoat secrets and configuration";
    wantedBy = [ "multi-user.target" ];
    before = [ "stoat.service" ];
    path = [
      pkgs.openssl
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "stoat-secrets" ''
        install -d -m 0750 ${stateDir} /var/lib/stoat/database /var/lib/stoat/rabbit /srv/stoat/files
        install -m 0444 ${configFile} ${stateDir}/Revolt.toml
        umask 077
        printf 'REVOLT__API__OIDC__CLIENT_SECRET=%s\n' "$(cat /var/lib/stoat/oidc-client-secret)" > ${oidcEnvironment}.new
        chmod 0400 ${oidcEnvironment}.new
        if ! cmp -s ${oidcEnvironment}.new ${oidcEnvironment}; then
          mv ${oidcEnvironment}.new ${oidcEnvironment}
        else
          rm ${oidcEnvironment}.new
        fi
        if [ ! -s ${secretFile} ]; then
          umask 077
          rabbit_password=$(openssl rand -hex 32)
          s3_password=$(openssl rand -hex 32)
          files_key=$(openssl rand -base64 32)
          openssl ecparam -name prime256v1 -genkey -noout -out ${stateDir}/vapid.pem
          vapid_private=$(base64 -w0 ${stateDir}/vapid.pem | tr -d '=')
          vapid_public=$(openssl ec -in ${stateDir}/vapid.pem -outform DER 2>/dev/null | tail -c 65 | base64 | tr '/+' '_-' | tr -d '=\n')
          cat > ${secretFile} <<EOF
        RABBITMQ_DEFAULT_USER=rabbituser
        RABBITMQ_DEFAULT_PASS=$rabbit_password
        MINIO_ROOT_USER=stoat
        MINIO_ROOT_PASSWORD=$s3_password
        REVOLT__RABBIT__PASSWORD=$rabbit_password
        REVOLT__FILES__ENCRYPTION_KEY=$files_key
        REVOLT__FILES__S3__SECRET_ACCESS_KEY=$s3_password
        REVOLT__PUSHD__VAPID__PRIVATE_KEY=$vapid_private
        REVOLT__PUSHD__VAPID__PUBLIC_KEY=$vapid_public
        EOF
          chmod 0400 ${secretFile} ${stateDir}/vapid.pem
        fi
        if ! grep -q '^REVOLT__API__LIVEKIT__NODES__WORLDWIDE__SECRET=' ${secretFile}; then
          printf 'REVOLT__API__LIVEKIT__NODES__WORLDWIDE__SECRET=%s\n' "$(openssl rand -hex 32)" >> ${secretFile}
          chmod 0400 ${secretFile}
        fi
        livekit_secret=$(sed -n 's/^REVOLT__API__LIVEKIT__NODES__WORLDWIDE__SECRET=//p' ${secretFile})
        cat > ${stateDir}/livekit.yml <<EOF
        rtc:
          use_external_ip: true
          port_range_start: 50000
          port_range_end: 50100
          tcp_port: 7881
        redis:
          address: redis:6379
        turn:
          enabled: false
        keys:
          stoat: $livekit_secret
        webhook:
          api_key: stoat
          urls:
            - http://voice-ingress:8500/worldwide
        EOF
        chmod 0400 ${stateDir}/livekit.yml
      '';
    };
    requires = [ "pocket-id-oidc-provision.service" ];
    after = [ "pocket-id-oidc-provision.service" ];
  };

  virtualisation.docker.enable = true;

  systemd.services.stoat = {
    description = "Stoat self-hosted service stack";
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [
      configFile
      composeFile
    ];
    requires = [
      "docker.service"
      "stoat-secrets.service"
      "pocket-id.service"
      "pocket-id-oidc-provision.service"
    ];
    after = [
      "docker.service"
      "stoat-secrets.service"
      "pocket-id.service"
      "pocket-id-oidc-provision.service"
    ];
    path = [ pkgs.docker-compose ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = stateDir;
      ExecStartPre = oidcReady;
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose --project-directory ${stateDir} -f ${composeFile} up --detach --remove-orphans";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose --project-directory ${stateDir} -f ${composeFile} down";
      TimeoutStartSec = 0;
    };
  };

  networking.firewall = {
    allowedTCPPorts = [ 7881 ];
    allowedUDPPortRanges = [
      {
        from = 50000;
        to = 50100;
      }
    ];
  };

  services.caddy.extraConfig = lib.mkAfter ''
    http://127.0.0.1:15000 {
      @accountCredentialChanges path /api/auth/account/change/email /api/auth/account/change/password
      respond @accountCredentialChanges "Account credentials are managed by Pocket ID." 403
      route /.well-known/stoat {
        header Content-Type application/json
        header Access-Control-Allow-Origin *
        respond `{"api":"https://${domain}/api"}` 200
      }
      route /api* {
        uri strip_prefix /api
        reverse_proxy 127.0.0.1:14702 {
          header_down Location "^/" "/api/"
        }
      }
      route /ws* {
        uri strip_prefix /ws
        reverse_proxy 127.0.0.1:14703 {
          header_down Location "^/" "/ws/"
        }
      }
      route /autumn* {
        uri strip_prefix /autumn
        reverse_proxy 127.0.0.1:14704 {
          header_down Location "^/" "/autumn/"
        }
      }
      route /january* {
        uri strip_prefix /january
        reverse_proxy 127.0.0.1:14705 {
          header_down Location "^/" "/january/"
        }
      }
      route /gifbox* {
        uri strip_prefix /gifbox
        reverse_proxy 127.0.0.1:14706 {
          header_down Location "^/" "/gifbox/"
        }
      }
      route /livekit* {
        uri strip_prefix /livekit
        reverse_proxy 127.0.0.1:14710
      }
      reverse_proxy 127.0.0.1:15080
    }
  '';

  services.caddy.virtualHosts.${domain}.extraConfig = ''
    reverse_proxy 127.0.0.1:15000 {
      header_up Host 127.0.0.1
    }
  '';

  services.homepage-dashboard.settings.layout.Social = {
    style = "row";
    columns = 3;
  };
  services.homepage-dashboard.services = lib.mkAfter [
    {
      Social = [
        {
          Stoat = {
            href = "https://${domain}";
            icon = "si-discord";
            description = "Private chat with Pocket ID sign-in";
          };
        }
      ];
    }
  ];
}
