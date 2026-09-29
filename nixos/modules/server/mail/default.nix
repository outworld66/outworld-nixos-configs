{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.server.mail;
  credentialDir = "/run/credentials/stalwart.service";
  provisionScript = pkgs.writeShellScriptBin "stalwart-provision-pocket-users" ''
    set -eu

    : "''${POCKET_ID_API_KEY_FILE:?set POCKET_ID_API_KEY_FILE}"
    : "''${STALWART_URL:?set STALWART_URL}"
    : "''${STALWART_USER:?set STALWART_USER}"
    if [ -n "''${STALWART_PASSWORD_FILE:-}" ]; then
      STALWART_PASSWORD=$(cat "$STALWART_PASSWORD_FILE")
      export STALWART_PASSWORD
    fi
    : "''${STALWART_PASSWORD:?set STALWART_PASSWORD or STALWART_PASSWORD_FILE}"

    api_key=$(cat "$POCKET_ID_API_KEY_FILE")
    api="$STALWART_URL/api"
    pocket_api="''${POCKET_ID_URL:-http://127.0.0.1:1411}/api"
    allowed_groups="''${STALWART_ALLOWED_GROUPS:-mail-admin,mail-user}"

    curl_api() {
      ${pkgs.curl}/bin/curl --fail --silent --show-error "$@"
    }

    domains=$(curl_api \
      --user "$STALWART_USER:$STALWART_PASSWORD" \
      "$api/principal?type=domain&fields=name&limit=1000")
    if ! printf '%s' "$domains" | ${pkgs.jq}/bin/jq -e --arg domain "${cfg.primaryDomain}" \
      '.data.items[] | select(.name == $domain)' >/dev/null; then
      curl_api \
        --user "$STALWART_USER:$STALWART_PASSWORD" \
        -H 'Content-Type: application/json' \
        --data-binary "$(printf '%s' '${cfg.primaryDomain}' | ${pkgs.jq}/bin/jq -Rs '{type:"domain",name:(rtrimstr("\\n"))}')" \
        "$api/principal" >/dev/null
    fi

    tmp_dir=$(${pkgs.coreutils}/bin/mktemp -d)
    trap '${pkgs.coreutils}/bin/rm -rf "$tmp_dir"' EXIT
    : > "$tmp_dir/desired"
    curl_api -H "X-API-KEY: $api_key" \
      "$pocket_api/users?pagination%5Blimit%5D=1000" \
      | ${pkgs.jq}/bin/jq -c \
        '.data[] | select(.emailVerified == true) | {email, id}' \
      | while IFS= read -r user; do
        email=$(printf '%s' "$user" | ${pkgs.jq}/bin/jq -er .email)
        user_id=$(printf '%s' "$user" | ${pkgs.jq}/bin/jq -er .id)
        groups=$(curl_api -H "X-API-KEY: $api_key" "$pocket_api/users/$user_id/groups")
        if printf '%s' "$groups" | ${pkgs.jq}/bin/jq -e --arg allowed "$allowed_groups" \
          '($allowed | split(",")) as $names | any(.[]; .name as $name | $names | index($name))' >/dev/null; then
          printf '%s\n' "$email" >> "$tmp_dir/desired"
        fi
      done

    accounts=$(curl_api \
      --user "$STALWART_USER:$STALWART_PASSWORD" \
      "$api/principal?type=individual&fields=name&limit=1000" \
      | ${pkgs.jq}/bin/jq -c '.data.items[]')
    while IFS= read -r email; do
      [ -n "$email" ] || continue
      account=$(printf '%s\n' "$accounts" | ${pkgs.jq}/bin/jq -c --arg email "$email" \
        'select(.name == $email)' | head -n1)
      if [ -z "$account" ]; then
        curl_api \
          --user "$STALWART_USER:$STALWART_PASSWORD" \
          -H 'Content-Type: application/json' \
          --data-binary "$(printf '%s' "$email" | ${pkgs.jq}/bin/jq -Rs '{type:"individual",name:(rtrimstr("\\n")),emails:[(rtrimstr("\\n"))],roles:["user"]}')" \
          "$api/principal" >/dev/null
      else
        principal_url=$(printf '%s' "$email" | ${pkgs.jq}/bin/jq -sRr @uri)
        curl_api \
          --user "$STALWART_USER:$STALWART_PASSWORD" \
          -X PATCH \
          -H 'Content-Type: application/json' \
          --data-binary '[{"action":"removeItem","field":"disabledPermissions","value":"authenticate"}]' \
          "$api/principal/$principal_url" >/dev/null
      fi
    done < "$tmp_dir/desired"

    printf '%s\n' "$accounts" | ${pkgs.jq}/bin/jq -r '.name' \
      | while IFS= read -r email; do
        [ "$email" = "pocket-id@${cfg.primaryDomain}" ] && continue
        if ! ${pkgs.coreutils}/bin/grep -Fqx "$email" "$tmp_dir/desired"; then
          principal_url=$(printf '%s' "$email" | ${pkgs.jq}/bin/jq -sRr @uri)
          curl_api \
            --user "$STALWART_USER:$STALWART_PASSWORD" \
            -X PATCH \
            -H 'Content-Type: application/json' \
            --data-binary '[{"action":"addItem","field":"disabledPermissions","value":"authenticate"}]' \
            "$api/principal/$principal_url" >/dev/null
        fi
      done
  '';
in
{
  options.server.mail = {
    enable = lib.mkEnableOption "Stalwart mail server";
    hostname = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = "Fully qualified hostname used by Stalwart.";
    };
    primaryDomain = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = "Primary mail domain served by Stalwart.";
    };
    adminPasswordFile = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/stalwart/admin-password";
      description = "File containing the Stalwart administrator password.";
    };
    accounts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.passwordFile = lib.mkOption {
            type = lib.types.path;
            description = "File containing the account password.";
          };
        }
      );
      default = { };
      description = "Local Stalwart accounts and their password files.";
    };
    certificateSource = lib.mkOption {
      type = lib.types.path;
      description = "Certificate source copied from the existing certificate manager.";
    };
    keySource = lib.mkOption {
      type = lib.types.path;
      description = "Private key source copied from the existing certificate manager.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.stalwart = {
      enable = true;
      stateVersion = "26.05";
      credentials = {
        "cert.pem" = "/var/lib/stalwart/tls/cert.pem";
        "key.pem" = "/var/lib/stalwart/tls/key.pem";
      };
      settings = {
        config.local-keys = [
          "authentication.fallback-admin.*"
          "certificate.*"
          "directory.*"
          "server.*"
        ];
        server.hostname = cfg.hostname;
        server.listener = {
          smtp = {
            bind = [ "[::]:25" ];
            protocol = "smtp";
          };
          submission = {
            bind = [ "[::]:587" ];
            protocol = "smtp";
          };
          submissions = {
            bind = [ "[::]:465" ];
            protocol = "smtp";
            tls.implicit = true;
          };
          imaptls = {
            bind = [ "[::]:993" ];
            protocol = "imap";
            tls.implicit = true;
          };
          http = {
            bind = [ "127.0.0.1:8080" ];
            protocol = "http";
          };
        };
        certificate.default = {
          cert = "%{file:${credentialDir}/cert.pem}%";
          private-key = "%{file:${credentialDir}/key.pem}%";
          default = true;
        };
        authentication.fallback-admin = {
          user = "admin";
          secret = "%{file:" + (toString cfg.adminPasswordFile) + "}%";
        };
      };
    };

    networking.firewall.allowedTCPPorts = [
      25
      465
      587
      993
    ];

    environment.systemPackages = [ provisionScript ];

    systemd.services.stalwart-provision-pocket-users = {
      description = "Provision verified Pocket ID users in Stalwart";
      after = [
        "stalwart.service"
        "pocket-id.service"
      ];
      requires = [
        "stalwart.service"
        "pocket-id.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        Environment = [
          "POCKET_ID_API_KEY_FILE=/var/lib/pocket-id/static-api-key"
          "STALWART_URL=http://127.0.0.1:8080"
          "STALWART_USER=admin"
          "STALWART_PASSWORD_FILE=${cfg.adminPasswordFile}"
        ];
        ExecStart = "${provisionScript}/bin/stalwart-provision-pocket-users";
      };
    };

    systemd.timers.stalwart-provision-pocket-users = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "5min";
        Persistent = true;
      };
    };

    systemd.services.stalwart-certs = {
      description = "Install the Stalwart TLS certificate";
      wantedBy = [ "stalwart.service" ];
      before = [ "stalwart.service" ];
      after = [ "caddy.service" ];
      wants = [ "caddy.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "stalwart-certs" ''
          set -eu
          until [ -r ${lib.escapeShellArg cfg.certificateSource} ] && [ -r ${lib.escapeShellArg cfg.keySource} ]; do
            sleep 1
          done
          install -d -m 0750 -o stalwart -g stalwart /var/lib/stalwart/tls
          install -m 0640 -o stalwart -g stalwart ${lib.escapeShellArg cfg.certificateSource} /var/lib/stalwart/tls/cert.pem
          install -m 0640 -o stalwart -g stalwart ${lib.escapeShellArg cfg.keySource} /var/lib/stalwart/tls/key.pem
        '';
      };
    };

    systemd.services.stalwart = {
      after = [
        "stalwart-certs.service"
      ];
      requires = [
        "stalwart-certs.service"
      ];
    };

    systemd.services.stalwart-ensure-accounts = {
      description = "Ensure declarative Stalwart mail accounts";
      wantedBy = [ "multi-user.target" ];
      after = [ "stalwart.service" ];
      requires = [ "stalwart.service" ];
      path = with pkgs; [
        coreutils
        jq
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "stalwart-ensure-accounts" ''
          set -eu
          while :; do
            http_code=$(${pkgs.curl}/bin/curl --retry 30 --retry-connrefused --retry-delay 1 --max-time 2 \
              --silent --output /dev/null --write-out '%{http_code}' \
              --user "admin:$(cat ${lib.escapeShellArg cfg.adminPasswordFile})" \
              'http://127.0.0.1:8080/api/principal?type=domain')
            case "$http_code" in
              000|404) sleep 1 ;;
              *) break ;;
            esac
          done
          api=http://127.0.0.1:8080/api
          curl_api() {
            ${pkgs.curl}/bin/curl --fail --silent --show-error \
              --user "admin:$(cat ${lib.escapeShellArg cfg.adminPasswordFile})" "$@"
          }
          domains=$(curl_api "$api/principal?type=domain&fields=name&limit=1000")
          if ! printf '%s' "$domains" | jq -e --arg domain ${lib.escapeShellArg cfg.primaryDomain} \
            '.data.items[] | select(.name == $domain)' >/dev/null; then
            curl_api \
              -H 'Content-Type: application/json' \
              --data-binary '{"type":"domain","name":'"$(printf '%s' ${lib.escapeShellArg cfg.primaryDomain} | jq -Rs .)"'}' \
              "$api/principal" >/dev/null
          fi
          accounts=$(curl_api "$api/principal?type=individual&fields=name&limit=1000" | jq -c '.data.items[]')
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (email: account: ''
              if ! printf '%s\n' "$accounts" | jq -e --arg email ${lib.escapeShellArg email} 'select(.name == $email)' >/dev/null; then
                jq -n \
                  --arg name ${lib.escapeShellArg email} \
                  --arg secret "$(cat ${lib.escapeShellArg account.passwordFile})" \
                  '{type:"individual",name:$name,emails:[$name],secrets:[$secret],roles:["user"]}' \
                  | curl_api -H 'Content-Type: application/json' --data-binary @- "$api/principal" >/dev/null
              fi
            '') cfg.accounts
          )}
        '';
      };
    };
  };
}
