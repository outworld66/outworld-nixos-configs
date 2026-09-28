{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.pocket-id;
in
{
  options.services.pocket-id.userGroupMappings = lib.mkOption {
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          email = lib.mkOption { type = lib.types.str; };
          groups = lib.mkOption { type = lib.types.listOf lib.types.str; };
        };
      }
    );
    default = [ ];
    description = "Verified Pocket ID email addresses and groups to assign automatically.";
  };

  config = {
    services.pocket-id = {
      enable = true;
      environmentFile = "/var/lib/pocket-id/environment";
      credentials = {
        ENCRYPTION_KEY = "/var/lib/pocket-id/encryption-key";
        STATIC_API_KEY = "/var/lib/pocket-id/static-api-key";
      };
      package = pkgs.pocket-id.overrideAttrs (old: {
        src = pkgs.runCommand "pocket-id-source" { } ''
          cp -r ${inputs.pocket-id} "$out"
        '';
        version = "2.16.0-global-logout";
        goModules = old.goModules.overrideAttrs (_: {
          outputHash = "sha256-12YSxG2dqa/Bik+DefyEGpGtlJBpqArbhzi9rmiy1cs=";
          preBuild = "";
        });
        frontend = old.frontend.overrideAttrs (_frontendOld: {
          src = pkgs.runCommand "pocket-id-frontend-source" { } ''
            cp -r ${inputs.pocket-id} "$out"
          '';
          version = "2.16.0-global-logout";
          pnpmDeps = pkgs.fetchPnpmDeps {
            pname = "pocket-id-frontend";
            version = "2.16.0-global-logout";
            src = pkgs.runCommand "pocket-id-frontend-source" { } ''
              cp -r ${inputs.pocket-id} "$out"
            '';
            pnpm = pkgs.pnpm_10;
            fetcherVersion = 4;
            hash = "sha256-UmQDpQywsr1e6G/qF2WYbjd4u0ZLhI4vIKuaGPNk+ZE=";
          };
        });
        preBuild = (old.preBuild or "") + ''
          webauthn_login=$(find ./vendor -path '*/github.com/go-webauthn/webauthn/webauthn/login.go' -print -quit)
          if [ -z "$webauthn_login" ]; then
            echo "go-webauthn login source not found" >&2
            exit 1
          fi
          chmod -R u+w "$(dirname "$(dirname "$webauthn_login")")"
          sed -i '/Check if the BackupEligible flag has changed\./,+4d' "$webauthn_login"
        '';
      });
      settings = {
        APP_URL = "https://id.outworld66.ru";
        TRUST_PROXY = true;
        ANALYTICS_DISABLED = true;
        WEBAUTHN_ALLOW_SYNCED_PASSKEYS = true;
      };
    };

    systemd.services.pocket-id-secret = {
      description = "Generate Pocket ID encryption key";
      before = [ "pocket-id.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "pocket-id-secret" ''
          install -d -m 0750 -o pocket-id -g pocket-id /var/lib/pocket-id
          if [ ! -s /var/lib/pocket-id/encryption-key ]; then
            umask 077
            head -c 32 /dev/urandom | base64 -w0 > /var/lib/pocket-id/encryption-key
            chown pocket-id:pocket-id /var/lib/pocket-id/encryption-key
          fi
          if [ ! -s /var/lib/pocket-id/static-api-key ]; then
            umask 077
            head -c 32 /dev/urandom | base64 -w0 > /var/lib/pocket-id/static-api-key
            chown pocket-id:pocket-id /var/lib/pocket-id/static-api-key
          fi
          if [ ! -s /var/lib/pocket-id/environment ]; then
            cat > /var/lib/pocket-id/environment <<EOF
          UI_CONFIG_DISABLED=true
          ALLOW_USER_SIGNUPS=open
          SIGNUP_DEFAULT_USER_GROUP_IDS=[]
          EOF
            chmod 0400 /var/lib/pocket-id/environment
            chown pocket-id:pocket-id /var/lib/pocket-id/environment
          fi
        '';
      };
    };

    systemd.services.pocket-id = {
      after = [ "pocket-id-secret.service" ];
      requires = [ "pocket-id-secret.service" ];
    };

    systemd.services.pocket-id-oidc-provision = {
      description = "Provision Pocket ID OIDC clients";
      wantedBy = [ "multi-user.target" ];
      after = [ "pocket-id.service" ];
      requires = [ "pocket-id.service" ];
      path = with pkgs; [
        curl
        jq
        coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "pocket-id-oidc-provision" ''
          set -eu
          api_key=$(cat /var/lib/pocket-id/static-api-key)
          api="http://127.0.0.1:1411/api"
          curl_api() {
            curl --fail --silent --show-error --retry 30 --retry-connrefused --retry-delay 1 "$@"
          }

          media_group_id=$(curl_api \
            -H "X-API-KEY: $api_key" \
            "$api/user-groups?pagination%5Blimit%5D=100" \
            | jq -r '.data[] | select(.name == "media") | .id' | head -n1)
          if [ -z "$media_group_id" ]; then
            curl_api \
              -H "X-API-KEY: $api_key" \
              -H 'Content-Type: application/json' \
              -d '{"friendlyName":"Media","name":"media"}' \
              "$api/user-groups" >/dev/null
          fi

          group_id=$(curl_api \
            -H "X-API-KEY: $api_key" \
            "$api/user-groups?pagination%5Blimit%5D=100" \
            | jq -r '.data[] | select(.name == "nogroup") | .id' | head -n1)
          if [ -z "$group_id" ]; then
            group_id=$(curl_api \
              -H "X-API-KEY: $api_key" \
              -H 'Content-Type: application/json' \
              -d '{"friendlyName":"No access","name":"nogroup"}' \
              "$api/user-groups" | jq -er .id)
          fi
          default_groups=$(jq -cn --arg id "$group_id" '[ $id ]')
          if ! grep -qxF "SIGNUP_DEFAULT_USER_GROUP_IDS=$default_groups" /var/lib/pocket-id/environment; then
            sed '/^SIGNUP_DEFAULT_USER_GROUP_IDS=/d' /var/lib/pocket-id/environment > /var/lib/pocket-id/environment.new
            printf 'SIGNUP_DEFAULT_USER_GROUP_IDS=%s\n' "$default_groups" >> /var/lib/pocket-id/environment.new
            chown pocket-id:pocket-id /var/lib/pocket-id/environment.new
            chmod 0400 /var/lib/pocket-id/environment.new
            mv /var/lib/pocket-id/environment.new /var/lib/pocket-id/environment
            systemctl restart pocket-id.service
          fi

          ensure_group() {
            group_name=$1
            group_id=$(curl_api \
              -H "X-API-KEY: $api_key" \
              "$api/user-groups?pagination%5Blimit%5D=100" \
              | jq -r --arg name "$group_name" '.data[] | select(.name == $name) | .id' | head -n1)
            if [ -z "$group_id" ]; then
              group_id=$(curl_api \
                -H "X-API-KEY: $api_key" \
                -H 'Content-Type: application/json' \
                -d "{\"friendlyName\":\"$group_name\",\"name\":\"$group_name\"}" \
                "$api/user-groups" | jq -er .id)
            fi
            printf '%s' "$group_id"
          }

          apply_user_group_mapping() {
            mapping=$1
            email=$(printf '%s' "$mapping" | jq -er .email)
            target_group_ids=$(printf '%s' "$mapping" | jq -r '.groups[]' \
              | while IFS= read -r group_name; do
                  ensure_group "$group_name"
                  printf '\n'
                done | jq -Rsc 'split("\n") | map(select(length > 0))')
            user_id=$(curl_api \
              -H "X-API-KEY: $api_key" \
              "$api/users?pagination%5Blimit%5D=100" \
              | jq -r --arg email "$email" \
                '.data[] | select(.emailVerified == true and (.email | ascii_downcase) == ($email | ascii_downcase)) | .id' \
              | head -n1)
            if [ -n "$user_id" ]; then
              user=$(curl_api \
                -H "X-API-KEY: $api_key" \
                "$api/users/$user_id")
              user_groups=$(curl_api \
                -H "X-API-KEY: $api_key" \
                "$api/users/$user_id/groups" | jq -c 'map(.id)')
              updated_groups=$(jq -cn \
                --argjson target_group_ids "$target_group_ids" \
                --argjson user_groups "$user_groups" \
                '$user_groups + $target_group_ids | unique')
              curl_api \
                -H "X-API-KEY: $api_key" \
                -H 'Content-Type: application/json' \
                -X PUT \
                -d "{\"userGroupIds\":$updated_groups}" \
                "$api/users/$user_id/user-groups" >/dev/null
              is_admin=$(printf '%s' "$mapping" | jq -r '(.groups // []) | any(. == "admins")')
              printf '%s' "$user" | jq -c \
                --argjson isAdmin "$is_admin" \
                --argjson userGroupIds "$updated_groups" \
                '. + {isAdmin: $isAdmin, userGroupIds: $userGroupIds}' \
                | curl_api \
                    -H "X-API-KEY: $api_key" \
                    -H 'Content-Type: application/json' \
                    -X PUT \
                    --data-binary @- \
                    "$api/users/$user_id" >/dev/null
            fi
          }

          mappings='${builtins.toJSON cfg.userGroupMappings}'
          printf '%s' "$mappings" | jq -c '.[]' | while IFS= read -r mapping; do
            apply_user_group_mapping "$mapping"
          done

          provision_client() {
            client_id=$1
            name=$2
            callbacks=$3
            client_secret_file=$4
            frontchannel_logout_url=''${5:-}
            backchannel_logout_url=''${6:-}
            payload=$(jq -cn \
              --arg id "$client_id" \
              --arg name "$name" \
              --arg frontchannel_logout_url "$frontchannel_logout_url" \
              --arg backchannel_logout_url "$backchannel_logout_url" \
              --argjson callbacks "$callbacks" \
              '{id: $id, name: $name, description: $name, callbackURLs: $callbacks, logoutCallbackURLs: [], frontchannelLogoutURL: $frontchannel_logout_url, backchannelLogoutURL: $backchannel_logout_url, isPublic: false, pkceEnabled: true, skipConsent: true}')

            mkdir -p "$(dirname "$client_secret_file")"
            chmod 0750 "$(dirname "$client_secret_file")"
            if curl_api \
              -H "X-API-KEY: $api_key" \
              "$api/oidc/clients/$client_id" >/dev/null; then
              curl_api \
                -H "X-API-KEY: $api_key" \
                -H 'Content-Type: application/json' \
                -X PUT \
                -d "$payload" \
                "$api/oidc/clients/$client_id" >/dev/null
            else
              curl_api \
                -H "X-API-KEY: $api_key" \
                -H 'Content-Type: application/json' \
                -d "$payload" \
                "$api/oidc/clients" >/dev/null
            fi

            if [ -s "$client_secret_file" ]; then
              tr -d '\r\n' < "$client_secret_file" > "$client_secret_file.new"
              chmod 0400 "$client_secret_file.new"
              mv "$client_secret_file.new" "$client_secret_file"
            else
              curl_api \
                -H "X-API-KEY: $api_key" \
                -H 'Content-Type: application/json' \
                -d '{}' \
                "$api/oidc/clients/$client_id/secrets" \
                | jq -er .secret | tr -d '\r\n' > "$client_secret_file"
              chmod 0400 "$client_secret_file"
            fi
          }

          provision_client gotify Gotify \
            '["https://gotify.outworld66.ru/auth/oidc/callback","gotify://oidc/callback"]' \
            /var/lib/gotify/oidc-client-secret
          provision_client immich Immich \
            '["https://immich.outworld66.ru/auth/login","https://immich.outworld66.ru/user-settings","https://immich.outworld66.ru/api/oauth/mobile-redirect","app.immich:///oauth-callback"]' \
            /var/lib/immich/oidc-client-secret \
            "" \
            https://immich.outworld66.ru/api/oauth/backchannel-logout
          provision_client pomerium Pomerium \
            '["https://auth.outworld66.ru/oauth2/callback"]' \
            /var/lib/pomerium/client-secret \
            https://auth.outworld66.ru/.pomerium/sign_out

          install -d -m 0750 /var/lib/pomerium
          if [ ! -s /var/lib/pomerium/cookie-secret ] || [ "$(wc -c < /var/lib/pomerium/cookie-secret)" -ne 32 ]; then
            umask 077
            head -c 32 /dev/urandom > /var/lib/pomerium/cookie-secret
          fi
          if [ ! -s /var/lib/pomerium/shared-secret ] || [ "$(wc -c < /var/lib/pomerium/shared-secret)" -ne 32 ]; then
            umask 077
            head -c 32 /dev/urandom > /var/lib/pomerium/shared-secret
          fi
          chmod 0400 /var/lib/pomerium/cookie-secret /var/lib/pomerium/shared-secret
          umask 077
          printf '%s\n' \
            "IDP_CLIENT_SECRET=$(cat /var/lib/pomerium/client-secret)" \
            "COOKIE_SECRET=$(cat /var/lib/pomerium/cookie-secret)" \
            "SHARED_SECRET=$(cat /var/lib/pomerium/shared-secret)" \
            > /var/lib/pomerium/environment
          chmod 0400 /var/lib/pomerium/environment

          umask 077
          printf '%s\n' \
            GOTIFY_OIDC_ENABLED=true \
            GOTIFY_OIDC_ISSUER=https://id.outworld66.ru \
            GOTIFY_OIDC_CLIENTID=gotify \
            "GOTIFY_OIDC_CLIENTSECRET=$(cat /var/lib/gotify/oidc-client-secret)" \
            GOTIFY_OIDC_REDIRECTURL=https://gotify.outworld66.ru/auth/oidc/callback \
            GOTIFY_OIDC_AUTOREGISTER=true \
            GOTIFY_OIDC_USERNAMECLAIM=preferred_username \
            GOTIFY_OIDC_SCOPES=openid,profile,email,groups \
            GOTIFY_OIDC_GROUPS_CLAIM=groups \
            GOTIFY_OIDC_GROUPS_USER=admins \
            GOTIFY_OIDC_GROUPS_ADMIN=admins \
            > /var/lib/gotify/oidc.env
          chmod 0400 /var/lib/gotify/oidc.env
        '';
      };
    };

    systemd.timers.pocket-id-oidc-provision = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "5min";
        Persistent = true;
      };
    };

    systemd.services.pomerium = {
      after = [ "pocket-id-oidc-provision.service" ];
      requires = [ "pocket-id-oidc-provision.service" ];
    };
  };
}
