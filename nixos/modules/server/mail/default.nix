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
    : "''${STALWART_PASSWORD:?set STALWART_PASSWORD}"

    api_key=$(cat "$POCKET_ID_API_KEY_FILE")
    api="$STALWART_URL/api"
    domain="''${STALWART_DOMAIN:-${cfg.primaryDomain}}"
    allowed_groups="''${STALWART_ALLOWED_GROUPS:-admins,media}"

    curl_api() {
      ${pkgs.curl}/bin/curl --fail --silent --show-error "$@"
    }

    jmap() {
      curl_api \
        --user "$STALWART_USER:$STALWART_PASSWORD" \
        -H 'Content-Type: application/json' \
        --data-binary "$1" \
        "$STALWART_URL/api"
    }

    accounts_response() {
      jmap '{"using":["urn:ietf:params:jmap:core","urn:stalwart:jmap"],"methodCalls":[["x:Account/query",{"filter":{}},"q"],["x:Account/get",{"ids":{"#ids":{"resultOf":"q","name":"x:Account/query","path":"/ids"}}},"g"]]}'
    }

    domain_id=$(jmap "$(printf '%s' "$domain" | ${pkgs.jq}/bin/jq -Rs '{using:["urn:ietf:params:jmap:core","urn:stalwart:jmap"],methodCalls:[["x:Domain/query",{filter:{name:(rtrimstr("\\n"))}},"q"]]}')" \
      | ${pkgs.jq}/bin/jq -er '.methodResponses[] | select(.[0] | endswith("Domain/query")) | .[1].ids[0]')

    tmp_dir=$(${pkgs.coreutils}/bin/mktemp -d)
    trap '${pkgs.coreutils}/bin/rm -rf "$tmp_dir"' EXIT
    : > "$tmp_dir/desired"
    curl_api -H "X-API-KEY: $api_key" \
      "$api/users?pagination%5Blimit%5D=1000" \
      | ${pkgs.jq}/bin/jq -c --arg domain "$domain" \
        '.data[] | select(.emailVerified == true and (.email | endswith("@" + $domain))) | {email, id}' \
      | while IFS= read -r user; do
        email=$(printf '%s' "$user" | ${pkgs.jq}/bin/jq -er .email)
        user_id=$(printf '%s' "$user" | ${pkgs.jq}/bin/jq -er .id)
        groups=$(curl_api -H "X-API-KEY: $api_key" "$api/users/$user_id/groups")
        if printf '%s' "$groups" | ${pkgs.jq}/bin/jq -e --arg allowed "$allowed_groups" \
          '($allowed | split(",")) as $names | any(.[]; .name as $name | $names | index($name))' >/dev/null; then
          printf '%s\n' "$email" >> "$tmp_dir/desired"
        fi
      done

    accounts=$(accounts_response | ${pkgs.jq}/bin/jq -c '.methodResponses[] | select(.[0] | endswith("Account/get")) | .[1].list[]')
    while IFS= read -r email; do
      [ -n "$email" ] || continue
      account=$(printf '%s\n' "$accounts" | ${pkgs.jq}/bin/jq -c --arg email "$email" \
        'select(.emailAddress == $email)' | head -n1)
      if [ -z "$account" ]; then
        local_part=''${email%@*}
        jmap "$(jq -n --arg name "$local_part" --arg domain_id "$domain_id" \
          '{using:["urn:ietf:params:jmap:core","urn:stalwart:jmap"],methodCalls:[["x:Account/set",{create:{new:{"@type":"User",name:$name,domainId:$domain_id,credentials:{},memberGroupIds:{},roles:{"@type":"User"},permissions:{"@type":"Inherit"},quotas:{},aliases:{},encryptionAtRest:{"@type":"Disabled"}}}},"c"]]}')" >/dev/null
      else
        account_id=$(printf '%s' "$account" | ${pkgs.jq}/bin/jq -er .id)
        jmap "$(jq -n --arg id "$account_id" \
          '{using:["urn:ietf:params:jmap:core","urn:stalwart:jmap"],methodCalls:[["x:Account/set",{update:{($id):{permissions:{"@type":"Inherit"}}}},"c"]]}')" >/dev/null
      fi
    done < "$tmp_dir/desired"

    printf '%s\n' "$accounts" | ${pkgs.jq}/bin/jq -r --arg domain "$domain" \
      'select(.emailAddress | endswith("@" + $domain)) | [.id, .emailAddress] | @tsv' \
      | while IFS=$'\t' read -r account_id email; do
        [ "$email" = "pocket-id@$domain" ] && continue
        if ! ${pkgs.coreutils}/bin/grep -Fqx "$email" "$tmp_dir/desired"; then
          jmap "$(jq -n --arg id "$account_id" \
            '{using:["urn:ietf:params:jmap:core","urn:stalwart:jmap"],methodCalls:[["x:Account/set",{update:{($id):{permissions:{"@type":"Replace",disabledPermissions:["authenticate"]}}}},"c"]]}')" >/dev/null
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
          until ${pkgs.curl}/bin/curl --silent --fail http://127.0.0.1:8080/api/discover/${cfg.primaryDomain} >/dev/null; do
            sleep 1
          done
          jmap() {
            ${pkgs.curl}/bin/curl --fail --silent --show-error \
              --user "admin:$(cat ${lib.escapeShellArg cfg.adminPasswordFile})" \
              -H 'Content-Type: application/json' \
              --data-binary "$1" \
              http://127.0.0.1:8080/api
          }
          domain_id=$(jmap "$(jq -n --arg domain ${lib.escapeShellArg cfg.primaryDomain} \
            '{using:["urn:ietf:params:jmap:core","urn:stalwart:jmap"],methodCalls:[["x:Domain/query",{filter:{name:$domain}},"q"]]}')" \
            | jq -er '.methodResponses[] | select(.[0] | endswith("Domain/query")) | .[1].ids[0]' || true)
          if [ -z "$domain_id" ]; then
            jmap "$(jq -n --arg domain ${lib.escapeShellArg cfg.primaryDomain} \
              '{using:["urn:ietf:params:jmap:core","urn:stalwart:jmap"],methodCalls:[["x:Domain/set",{create:{new:{name:$domain,isEnabled:true}}},"c"]]}')" >/dev/null
            domain_id=$(jmap "$(jq -n --arg domain ${lib.escapeShellArg cfg.primaryDomain} \
              '{using:["urn:ietf:params:jmap:core","urn:stalwart:jmap"],methodCalls:[["x:Domain/query",{filter:{name:$domain}},"q"]]}')" \
              | jq -er '.methodResponses[] | select(.[0] | endswith("Domain/query")) | .[1].ids[0]')
          fi
          accounts=$(jmap '{using:["urn:ietf:params:jmap:core","urn:stalwart:jmap"],methodCalls:[["x:Account/query",{filter:{}},"q"],["x:Account/get",{ids:{"#ids":{resultOf:"q",name:"x:Account/query",path:"/ids"}}},"g"]]}' \
            | jq -c '.methodResponses[] | select(.[0] | endswith("Account/get")) | .[1].list[]')
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              email: account:
              let
                localPart = lib.removeSuffix "@${cfg.primaryDomain}" email;
              in
              ''
                if ! printf '%s\n' "$accounts" | jq -e --arg email ${lib.escapeShellArg email} 'select(.emailAddress == $email)' >/dev/null; then
                  jq -n \
                    --arg name ${lib.escapeShellArg localPart} \
                    --arg domainId "$domain_id" \
                    --arg secret "$(cat ${lib.escapeShellArg account.passwordFile})" \
                    '{using:["urn:ietf:params:jmap:core","urn:stalwart:jmap"],methodCalls:[["x:Account/set",{create:{new:{"@type":"User",name:$name,domainId:$domainId,credentials:{"0":{"@type":"Password",secret:$secret}},memberGroupIds:{},roles:{"@type":"User"},permissions:{"@type":"Inherit"},quotas:{},aliases:{},encryptionAtRest:{"@type":"Disabled"}}}},"c"]]}' \
                    | { read -r payload; jmap "$payload"; } >/dev/null
                fi
              ''
            ) cfg.accounts
          )}
        '';
      };
    };
  };
}
