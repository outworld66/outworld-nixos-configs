{
  config,
  lib,
  pkgs,
  ...
}:
let
  minifluxDomain = "miniflux.outworld66.ru";
  linkwardenDomain = "linkwarden.outworld66.ru";
  minifluxSecrets = "/var/lib/miniflux-secrets";
  linkwardenSecrets = "/var/lib/linkwarden-secrets";
  linkwardenData = "/srv/linkwarden/data";
  postgresData = "/var/lib/linkwarden/postgres";
  meiliData = "/var/lib/linkwarden/meilisearch";
  minifluxEnvironmentFile = "${minifluxSecrets}/environment";
  linkwardenEnvironmentFile = "${linkwardenSecrets}/environment";
  postgresEnvironmentFile = "${linkwardenSecrets}/postgres-environment";
  meiliEnvironmentFile = "${linkwardenSecrets}/meilisearch-environment";
  images = {
    linkwarden = "ghcr.io/linkwarden/linkwarden:v2.16.3@sha256:6bafe0a62b3236dcb5917b03d0da501505fbd03831f9157f8ebbcbb88673386f";
    meilisearch = "getmeili/meilisearch:v1.13.3";
    postgres = "postgres:16-alpine";
  };
  generateSecrets = pkgs.writeShellScript "miniflux-linkwarden-secrets" ''
    set -eu
    install -d -m 0750 ${minifluxSecrets} ${linkwardenSecrets}
    install -d -m 0750 -o 1000 -g 1000 ${linkwardenData} ${meiliData}
    install -d -m 0700 -o 70 -g 70 ${postgresData}
    umask 077
    [ -s ${linkwardenSecrets}/nextauth-secret ] || ${pkgs.openssl}/bin/openssl rand -base64 36 > ${linkwardenSecrets}/nextauth-secret
    [ -s ${linkwardenSecrets}/postgres-password ] || ${pkgs.openssl}/bin/openssl rand -hex 32 > ${linkwardenSecrets}/postgres-password
    [ -s ${linkwardenSecrets}/meili-master-key ] || ${pkgs.openssl}/bin/openssl rand -hex 32 > ${linkwardenSecrets}/meili-master-key

    {
      printf 'NEXTAUTH_SECRET=%s\n' "$(cat ${linkwardenSecrets}/nextauth-secret)"
      printf 'POSTGRES_PASSWORD=%s\n' "$(cat ${linkwardenSecrets}/postgres-password)"
      printf 'MEILI_MASTER_KEY=%s\n' "$(cat ${linkwardenSecrets}/meili-master-key)"
      printf 'DATABASE_URL=postgresql://postgres:%s@linkwarden-postgres:5432/postgres\n' "$(cat ${linkwardenSecrets}/postgres-password)"
      printf 'OIDC_CLIENT_SECRET=%s\n' "$(cat ${linkwardenSecrets}/oidc-client-secret)"
    } > ${linkwardenEnvironmentFile}.new
    chmod 0400 ${linkwardenEnvironmentFile}.new
    if ! cmp -s ${linkwardenEnvironmentFile}.new ${linkwardenEnvironmentFile}; then
      mv ${linkwardenEnvironmentFile}.new ${linkwardenEnvironmentFile}
    else
      rm ${linkwardenEnvironmentFile}.new
    fi

    printf 'POSTGRES_PASSWORD=%s\n' "$(cat ${linkwardenSecrets}/postgres-password)" > ${postgresEnvironmentFile}.new
    chmod 0400 ${postgresEnvironmentFile}.new
    if ! cmp -s ${postgresEnvironmentFile}.new ${postgresEnvironmentFile}; then
      mv ${postgresEnvironmentFile}.new ${postgresEnvironmentFile}
    else
      rm ${postgresEnvironmentFile}.new
    fi

    printf 'MEILI_MASTER_KEY=%s\n' "$(cat ${linkwardenSecrets}/meili-master-key)" > ${meiliEnvironmentFile}.new
    chmod 0400 ${meiliEnvironmentFile}.new
    if ! cmp -s ${meiliEnvironmentFile}.new ${meiliEnvironmentFile}; then
      mv ${meiliEnvironmentFile}.new ${meiliEnvironmentFile}
    else
      rm ${meiliEnvironmentFile}.new
    fi

    {
      printf 'OAUTH2_CLIENT_SECRET=%s\n' "$(cat ${minifluxSecrets}/oidc-client-secret)"
      printf 'ADMIN_USERNAME=outworld66\n'
      if [ ! -s ${minifluxSecrets}/admin-password ]; then
        ${pkgs.openssl}/bin/openssl rand -base64 36 > ${minifluxSecrets}/admin-password
      fi
      printf 'ADMIN_PASSWORD=%s\n' "$(cat ${minifluxSecrets}/admin-password)"
    } > ${minifluxEnvironmentFile}.new
    chmod 0400 ${minifluxEnvironmentFile}.new
    if ! cmp -s ${minifluxEnvironmentFile}.new ${minifluxEnvironmentFile}; then
      mv ${minifluxEnvironmentFile}.new ${minifluxEnvironmentFile}
    else
      rm ${minifluxEnvironmentFile}.new
    fi
  '';
  createNetwork = pkgs.writeShellScript "linkwarden-network" ''
    ${pkgs.docker}/bin/docker network inspect linkwarden >/dev/null 2>&1 \
      || ${pkgs.docker}/bin/docker network create linkwarden >/dev/null
  '';
in
lib.mkIf (config.server.secrets.enable or false) {
  services.postgresql = {
    ensureDatabases = [ "miniflux" ];
    ensureUsers = [
      {
        name = "miniflux";
        ensureDBOwnership = true;
      }
    ];
  };

  services.miniflux = {
    enable = true;
    createDatabaseLocally = false;
    adminCredentialsFile = minifluxEnvironmentFile;
    config = {
      BASE_URL = "https://${minifluxDomain}/";
      LISTEN_ADDR = "127.0.0.1:8099";
      DATABASE_URL = "user=miniflux host=/run/postgresql dbname=miniflux";
      OAUTH2_PROVIDER = "oidc";
      OAUTH2_CLIENT_ID = "miniflux";
      OAUTH2_REDIRECT_URL = "https://${minifluxDomain}/oauth2/oidc/callback";
      OAUTH2_OIDC_DISCOVERY_ENDPOINT = "https://id.outworld66.ru/";
      OAUTH2_OIDC_PROVIDER_NAME = "Pocket ID";
      OAUTH2_USER_CREATION = 1;
      CREATE_ADMIN = 1;
      DISABLE_LOCAL_AUTH = 1;
      FETCH_YOUTUBE_WATCH_TIME = 1;
    };
  };
  systemd.services.miniflux.serviceConfig.EnvironmentFile = minifluxEnvironmentFile;
  systemd.services.miniflux = {
    requires = [
      "postgresql.service"
      "miniflux-linkwarden-secrets.service"
    ];
    after = [
      "postgresql.service"
      "miniflux-linkwarden-secrets.service"
    ];
  };

  systemd.services.linkwarden-network = {
    description = "Create the Linkwarden container network";
    before = [
      "docker-linkwarden.service"
      "docker-linkwarden-postgres.service"
      "docker-linkwarden-meilisearch.service"
    ];
    requires = [ "docker.service" ];
    after = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = createNetwork;
    };
  };

  systemd.services.miniflux-linkwarden-secrets = {
    description = "Prepare Miniflux and Linkwarden runtime secrets";
    before = [
      "miniflux.service"
      "docker-linkwarden.service"
      "docker-linkwarden-postgres.service"
      "docker-linkwarden-meilisearch.service"
    ];
    requires = [ "pocket-id-oidc-provision.service" ];
    after = [ "pocket-id-oidc-provision.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = generateSecrets;
    };
  };

  virtualisation.oci-containers.containers = {
    linkwarden = {
      image = images.linkwarden;
      user = "1000:1000";
      ports = [ "127.0.0.1:5798:3000" ];
      environmentFiles = [ linkwardenEnvironmentFile ];
      environment = {
        MEILI_HOST = "http://linkwarden-meilisearch:7700";
        NEXTAUTH_URL = "https://${linkwardenDomain}/api/v1/auth";
        NEXT_PUBLIC_CREDENTIALS_ENABLED = "false";
        NEXT_PUBLIC_OIDC_ENABLED = "true";
        OIDC_CUSTOM_NAME = "Pocket ID";
        OIDC_WELLKNOWN_URL = "https://id.outworld66.ru/.well-known/openid-configuration";
        OIDC_CLIENT_ID = "linkwarden";
        OIDC_SCOPES = "openid email profile groups";
      };
      volumes = [ "${linkwardenData}:/data/data" ];
      extraOptions = [ "--network=linkwarden" ];
    };
    linkwarden-postgres = {
      image = images.postgres;
      environmentFiles = [ postgresEnvironmentFile ];
      volumes = [ "${postgresData}:/var/lib/postgresql/data" ];
      extraOptions = [ "--network=linkwarden" ];
    };
    linkwarden-meilisearch = {
      image = images.meilisearch;
      environmentFiles = [ meiliEnvironmentFile ];
      environment.MEILI_NO_ANALYTICS = "true";
      volumes = [ "${meiliData}:/meili_data" ];
      extraOptions = [ "--network=linkwarden" ];
    };
  };

  systemd.services.docker-linkwarden = {
    requires = [
      "miniflux-linkwarden-secrets.service"
      "linkwarden-network.service"
      "docker-linkwarden-postgres.service"
      "docker-linkwarden-meilisearch.service"
    ];
    after = [
      "miniflux-linkwarden-secrets.service"
      "linkwarden-network.service"
      "docker-linkwarden-postgres.service"
      "docker-linkwarden-meilisearch.service"
    ];
  };
  systemd.services.docker-linkwarden-postgres = {
    requires = [
      "miniflux-linkwarden-secrets.service"
      "linkwarden-network.service"
    ];
    after = [
      "miniflux-linkwarden-secrets.service"
      "linkwarden-network.service"
    ];
  };
  systemd.services.docker-linkwarden-meilisearch = {
    requires = [
      "miniflux-linkwarden-secrets.service"
      "linkwarden-network.service"
    ];
    after = [
      "miniflux-linkwarden-secrets.service"
      "linkwarden-network.service"
    ];
  };

  services.caddy.virtualHosts.${minifluxDomain}.extraConfig = ''
    reverse_proxy 127.0.0.1:8099
  '';
  services.caddy.virtualHosts.${linkwardenDomain}.extraConfig = ''
    reverse_proxy 127.0.0.1:5798
  '';

  services.homepage-dashboard.services = lib.mkAfter [
    {
      Research = [
        {
          Miniflux = {
            href = "https://${minifluxDomain}";
            icon = "miniflux";
            description = "RSS feeds, filters, and read later";
          };
        }
        {
          Linkwarden = {
            href = "https://${linkwardenDomain}";
            icon = "linkwarden";
            description = "Save and preserve articles and videos";
          };
        }
      ];
    }
  ];
}
