{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  domain = "identity.outworld66.ru";
  smtpEnvironment = config.sops.templates."authentik/smtp-environment".path;
  ldapEnabled = config.server.authentik.ldap.enable;
  ldapBootstrap = pkgs.writeShellScript "authentik-ldap-bootstrap" ''
    set -eu
    if [ ! -s /var/lib/authentik/ldap-search-password ]; then
      umask 077
      ${pkgs.openssl}/bin/openssl rand -hex 32 > /var/lib/authentik/ldap-search-password
      chmod 0400 /var/lib/authentik/ldap-search-password
    fi
    export LDAP_SEARCH_PASSWORD="$(${pkgs.coreutils}/bin/cat /var/lib/authentik/ldap-search-password)"
    for _ in $(${pkgs.coreutils}/bin/seq 1 60); do
      if token="$(${authentikComponents.manage}/bin/manage.py shell -c 'from os import environ; from authentik.core.models import Group, User, UserTypes; from authentik.outposts.models import Outpost; group = Group.objects.get(name="ldap-directory-reader"); user, _ = User.objects.get_or_create(username="stalwart-ldap", defaults={"name": "Stalwart LDAP reader", "type": UserTypes.INTERNAL, "path": "users/ldap"}); user.type = UserTypes.INTERNAL; user.path = "users/ldap"; user.groups.add(group); user.set_password(environ["LDAP_SEARCH_PASSWORD"]); user.save(); outpost = Outpost.objects.get(name="Outworld LDAP"); outpost.token.delete(); print(outpost.token.key)' 2>/dev/null | ${pkgs.coreutils}/bin/tail -n1)"; then
        if [ -n "$token" ]; then break; fi
      fi
      ${pkgs.coreutils}/bin/sleep 2
    done
    if [ -z "''${token:-}" ]; then
      echo "Authentik LDAP outpost was not provisioned by its blueprint" >&2
      exit 1
    fi
    umask 077
    printf 'AUTHENTIK_TOKEN=%s\nAUTHENTIK_HOST=https://${domain}\nLDAP_SEARCH_PASSWORD=%s\n' \
      "$token" "$LDAP_SEARCH_PASSWORD" > /run/authentik-ldap-bootstrap/environment
    chmod 0400 /run/authentik-ldap-bootstrap/environment
  '';
  inherit
    (
      ((inputs.authentik-nix.lib.mkAuthentikScope { inherit pkgs; }).overrideScope (
        _final: prev: {
          authentikComponents = prev.authentikComponents // {
            # shortcut: Authentik 2026.8.3 has a stale docs dependency hash, refresh when upstream fixes it.
            docs = prev.authentikComponents.docs.overrideAttrs (old: {
              pnpmDeps = old.pnpmDeps.overrideAttrs (_: {
                outputHash = "sha256-b5MqbE9orSDjzdgJzfZ4KOgcw0KHwYLCFhawcQmYlxQ=";
              });
            });
          };
        }
      ))
    )
    authentikComponents
    ;
  blueprints = pkgs.symlinkJoin {
    name = "authentik-blueprints";
    paths = [ config.services.authentik.authentikComponents.staticWorkdirDeps ];
    postBuild = ''
      rm $out/blueprints
      mkdir $out/blueprints
      cp -rL ${config.services.authentik.authentikComponents.staticWorkdirDeps}/blueprints/. $out/blueprints/
      cp ${./blueprints/outworld.yaml} $out/blueprints/outworld.yaml
    '';
  };
in
{
  options.server.authentik = {
    ldap.enable = lib.mkEnableOption "the local Authentik LDAP outpost";
    emailGroupMappings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      description = "Groups to assign after users verify their matching email during enrollment.";
    };
  };

  config =
    lib.mkIf ((config.server.secrets.enable or false) && config.networking.hostName == "rico")
      {
        services.authentik = {
          enable = true;
          inherit authentikComponents;
          settings = {
            disable_startup_analytics = true;
            avatars = "initials";
            blueprints_dir = "${blueprints}/blueprints";
            listen = {
              http = [ "127.0.0.1:9000" ];
              https = [ "127.0.0.1:9443" ];
            };
            email = {
              host = "mail.outworld66.ru";
              port = 587;
              username = "id@outworld66.ru";
              use_tls = true;
              use_ssl = false;
              from = "id@outworld66.ru";
            };
          };
        };

        sops.templates."authentik/smtp-environment" = {
          owner = "root";
          group = "root";
          mode = "0400";
          content = ''
            AUTHENTIK_EMAIL__PASSWORD=${config.sops.placeholder."authentik/smtp-password"}
          '';
        };

        systemd.services.authentik-secret = {
          description = "Generate the persistent Authentik secret key";
          before = [
            "authentik.service"
            "authentik-worker.service"
          ];
          requiredBy = [
            "authentik.service"
            "authentik-worker.service"
          ];
          path = [ pkgs.coreutils ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "authentik-secret" ''
              set -eu
              install -d -m 0750 /var/lib/authentik
              if [ ! -s /var/lib/authentik/environment ] \
                || ! grep -q '^AUTHENTIK_SECRET_KEY=.' /var/lib/authentik/environment \
                || ! grep -qx 'AUTHENTIK_HOST=https://${domain}' /var/lib/authentik/environment; then
                umask 077
                printf 'AUTHENTIK_SECRET_KEY=%s\nAUTHENTIK_HOST=https://${domain}\n' "$(${pkgs.openssl}/bin/openssl rand -base64 60)" > /var/lib/authentik/environment.tmp
                chmod 0600 /var/lib/authentik/environment.tmp
                mv /var/lib/authentik/environment.tmp /var/lib/authentik/environment
              fi
              if [ ! -s /var/lib/authentik/oidc-gotify-secret ]; then
                umask 077
                ${pkgs.openssl}/bin/openssl rand -hex 32 > /var/lib/authentik/oidc-gotify-secret
                chmod 0400 /var/lib/authentik/oidc-gotify-secret
              fi
              for client in immich cloudreve pomerium donetick filebrowser stoat openhands; do
                if [ ! -s "/var/lib/authentik/oidc-$client-secret" ]; then
                  umask 077
                  ${pkgs.openssl}/bin/openssl rand -hex 32 > "/var/lib/authentik/oidc-$client-secret"
                  chmod 0400 "/var/lib/authentik/oidc-$client-secret"
                fi
                done
              gotify_secret=$(cat /var/lib/authentik/oidc-gotify-secret)
              umask 077
              for client in immich cloudreve pomerium donetick filebrowser stoat openhands; do
                secret=$(cat "/var/lib/authentik/oidc-$client-secret")
                env_client=$(printf '%s' "$client" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
                printf 'AUTHENTIK_OIDC_%s_SECRET=%s\n' "$env_client" "$secret"
              done > /var/lib/authentik/oidc-clients-environment
              chmod 0400 /var/lib/authentik/oidc-clients-environment
              printf 'AUTHENTIK_OIDC_GOTIFY_SECRET=%s\n' "$gotify_secret" \
                >> /var/lib/authentik/oidc-clients-environment
              printf 'GOTIFY_OIDC_CLIENTSECRET=%s\n' "$gotify_secret" \
                > /var/lib/authentik/gotify-oidc-environment
              install -d -m 0750 /var/lib/pomerium
              if [ ! -s /var/lib/pomerium/cookie-secret ] || [ "$(wc -c < /var/lib/pomerium/cookie-secret)" -ne 44 ]; then
                ${pkgs.openssl}/bin/openssl rand -base64 32 > /var/lib/pomerium/cookie-secret
              fi
              if [ ! -s /var/lib/pomerium/shared-secret ] || [ "$(wc -c < /var/lib/pomerium/shared-secret)" -ne 44 ]; then
                ${pkgs.openssl}/bin/openssl rand -base64 32 > /var/lib/pomerium/shared-secret
              fi
              printf '%s\n' \
                "IDP_CLIENT_SECRET=$(cat /var/lib/authentik/oidc-pomerium-secret)" \
                "COOKIE_SECRET=$(cat /var/lib/pomerium/cookie-secret)" \
                "SHARED_SECRET=$(cat /var/lib/pomerium/shared-secret)" \
                > /var/lib/pomerium/authentik-environment
              chmod 0400 /var/lib/authentik/gotify-oidc-environment /var/lib/pomerium/authentik-environment
              install -d -m 0750 -o immich -g immich /var/lib/immich
              install -m 0400 -o immich -g immich /var/lib/authentik/oidc-immich-secret /var/lib/immich/oidc-client-secret
              install -d -m 0750 -o cloudreve -g cloudreve /var/lib/cloudreve
              install -m 0400 -o cloudreve -g cloudreve /var/lib/authentik/oidc-cloudreve-secret /var/lib/cloudreve/authentik-oidc-client-secret
              install -d -m 0750 /var/lib/filebrowser
              printf 'FILEBROWSER_OIDC_CLIENT_SECRET=%s\n' "$(cat /var/lib/authentik/oidc-filebrowser-secret)" \
                > /var/lib/filebrowser/authentik-oidc.env
              chmod 0400 /var/lib/filebrowser/authentik-oidc.env
              install -d -m 0750 -o donetick -g donetick /var/lib/donetick
              printf '%s\n' \
                DT_OAUTH2_CLIENT_ID=donetick \
                "DT_OAUTH2_CLIENT_SECRET=$(cat /var/lib/authentik/oidc-donetick-secret)" \
                > /var/lib/donetick/authentik-oidc.env
              chown donetick:donetick /var/lib/donetick/authentik-oidc.env
              chmod 0400 /var/lib/donetick/authentik-oidc.env
              test -s /var/lib/authentik/environment
            '';
          };
        };

        systemd.services.authentik = {
          requires = [ "authentik-secret.service" ];
          after = [ "authentik-secret.service" ];
          environment.AUTHENTIK_EMAIL_GROUP_MAPPINGS = builtins.toJSON config.server.authentik.emailGroupMappings;
          serviceConfig = {
            EnvironmentFile = [
              "/var/lib/authentik/environment"
              smtpEnvironment
            ];
          };
        };

        systemd.services.authentik-worker = {
          requires = [ "authentik-secret.service" ];
          after = [ "authentik-secret.service" ];
          restartTriggers = [ blueprints ];
          serviceConfig.LoadCredential = [
            "stoat-test-admin-password:/run/secrets/authentik/stoat-test-admin-password"
            "stoat-test-user-password:/run/secrets/authentik/stoat-test-user-password"
            "stoat-test-registered-password:/run/secrets/authentik/stoat-test-registered-password"
          ];
          serviceConfig.EnvironmentFile = [
            "/var/lib/authentik/environment"
            "/var/lib/authentik/oidc-clients-environment"
            smtpEnvironment
          ];
        };

        systemd.services.authentik-migrate = {
          requires = [ "authentik-secret.service" ];
          after = [ "authentik-secret.service" ];
          serviceConfig.EnvironmentFile = [ "/var/lib/authentik/environment" ];
        };

        services.authentik-ldap = lib.mkIf ldapEnabled {
          enable = true;
          environmentFile = "/run/authentik-ldap-bootstrap/environment";
        };

        systemd.services.authentik-ldap-bootstrap = lib.mkIf ldapEnabled {
          description = "Provision the Authentik LDAP outpost token";
          before = [ "authentik-ldap.service" ];
          requiredBy = [ "authentik-ldap.service" ];
          after = [ "authentik-worker.service" ];
          requires = [ "authentik-worker.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            DynamicUser = true;
            User = "authentik";
            StateDirectory = "authentik";
            RuntimeDirectory = "authentik-ldap-bootstrap";
            RuntimeDirectoryMode = "0750";
            WorkingDirectory = "/var/lib/authentik";
            EnvironmentFile = "/var/lib/authentik/environment";
            ExecStart = ldapBootstrap;
          };
        };

        systemd.services.authentik-ldap = lib.mkIf ldapEnabled {
          requires = [ "authentik-ldap-bootstrap.service" ];
          after = [ "authentik-ldap-bootstrap.service" ];
          environment = {
            AUTHENTIK_LISTEN__LDAP = "127.0.0.1:3389";
            AUTHENTIK_LISTEN__LDAPS = "127.0.0.1:6636";
          };
        };

        services.caddy.virtualHosts.${domain}.extraConfig = ''
          log {
            output file /var/log/caddy/access.log
          }
          @frontendEntry path /static/dist/admin/AdminInterface-*.js /static/dist/user/UserInterface-*.js /static/dist/flow/FlowInterface-*.js /static/dist/poly-*.js
          header @frontendEntry Cache-Control "no-cache, max-age=0, must-revalidate"
          reverse_proxy 127.0.0.1:9000
        '';
      };
}
