{ pkgs, ... }:
{
  services.pocket-id = {
    enable = true;
    environmentFile = "/var/lib/pocket-id/environment";
    credentials = {
      ENCRYPTION_KEY = "/var/lib/pocket-id/encryption-key";
      STATIC_API_KEY = "/var/lib/pocket-id/static-api-key";
    };
    settings = {
      APP_URL = "https://id.outworld66.ru";
      TRUST_PROXY = true;
      ANALYTICS_DISABLED = true;
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

        provision_client() {
          client_id=$1
          name=$2
          callbacks=$3
          client_secret_file=$4
          payload=$(printf '{"id":"%s","name":"%s","description":"%s","callbackURLs":%s,"logoutCallbackURLs":[],"isPublic":false,"pkceEnabled":true,"skipConsent":true}' \
            "$client_id" "$name" "$name" "$callbacks")

          mkdir -p "$(dirname "$client_secret_file")"
          chmod 0750 "$(dirname "$client_secret_file")"
          if ! curl_api \
            -H "X-API-KEY: $api_key" \
            "$api/oidc/clients/$client_id" >/dev/null; then
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
          '["https://immich.outworld66.ru/auth/login","https://immich.outworld66.ru/user-settings","app.immich:///oauth-callback"]' \
          /var/lib/immich/oidc-client-secret
        provision_client oauth2-proxy 'OAuth2 Proxy' \
          '["https://auth.outworld66.ru/oauth2/callback"]' \
          /var/lib/oauth2-proxy/client-secret

        umask 077
        cat > /var/lib/gotify/oidc.env <<EOF
        GOTIFY_OIDC_ENABLED=true
        GOTIFY_OIDC_ISSUER=https://id.outworld66.ru
        GOTIFY_OIDC_CLIENTID=gotify
        GOTIFY_OIDC_CLIENTSECRET=$(cat /var/lib/gotify/oidc-client-secret)
        GOTIFY_OIDC_REDIRECTURL=https://gotify.outworld66.ru/auth/oidc/callback
        GOTIFY_OIDC_AUTOREGISTER=true
        GOTIFY_OIDC_USERNAMECLAIM=preferred_username
        GOTIFY_OIDC_SCOPES=openid,profile,email,groups
        GOTIFY_OIDC_GROUPS_CLAIM=groups
        GOTIFY_OIDC_GROUPS_USER=media
        GOTIFY_OIDC_GROUPS_ADMIN=admins
        EOF
        chmod 0400 /var/lib/gotify/oidc.env
      '';
    };
  };
}
