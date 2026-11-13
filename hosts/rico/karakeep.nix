{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "karakeep.outworld66.ru";
  legacyDomain = "archivebox.outworld66.ru";
  stateDir = "/var/lib/karakeep";
  meiliDir = "/var/lib/karakeep-meilisearch";
  secretDir = "/var/lib/karakeep-secrets";
  environmentFile = "${secretDir}/environment";
  meiliEnvironmentFile = "${secretDir}/meilisearch-environment";
  images = {
    app = "ghcr.io/karakeep-app/karakeep:0.34.1@sha256:69ae5315c618b7c14c1af3e34c6e211acdb231793af424ecd1cab0b70691d987";
    chrome = "ghcr.io/karakeep-app/karakeep-chrome:release@sha256:6c80ed470871bb8c129dc58692ca1714cddbc1392faad3ebf59aecd2e6e58eac";
    meilisearch = "getmeili/meilisearch:v1.41.0@sha256:860fa4baed04ae1c235de870edab0c8006227546dea1bbb6411fbfc5e27cf1db";
  };
  generateSecrets = pkgs.writeShellScript "karakeep-secrets" ''
    set -eu
    install -d -m 0750 -o 1000 -g 1000 ${stateDir} ${meiliDir}
    install -d -m 0750 ${secretDir}
    umask 077
    [ -s ${secretDir}/nextauth-secret ] || ${pkgs.openssl}/bin/openssl rand -base64 36 > ${secretDir}/nextauth-secret
    [ -s ${secretDir}/meili-master-key ] || ${pkgs.openssl}/bin/openssl rand -hex 32 > ${secretDir}/meili-master-key
    {
      printf 'NEXTAUTH_SECRET=%s\n' "$(cat ${secretDir}/nextauth-secret)"
      printf 'MEILI_MASTER_KEY=%s\n' "$(cat ${secretDir}/meili-master-key)"
      printf 'OAUTH_CLIENT_SECRET=%s\n' "$(cat ${secretDir}/oidc-client-secret)"
    } > ${environmentFile}.new
    chmod 0400 ${environmentFile}.new
    if ! cmp -s ${environmentFile}.new ${environmentFile}; then
      mv ${environmentFile}.new ${environmentFile}
    else
      rm ${environmentFile}.new
    fi
    printf 'MEILI_MASTER_KEY=%s\n' "$(cat ${secretDir}/meili-master-key)" > ${meiliEnvironmentFile}.new
    chmod 0400 ${meiliEnvironmentFile}.new
    if ! cmp -s ${meiliEnvironmentFile}.new ${meiliEnvironmentFile}; then
      mv ${meiliEnvironmentFile}.new ${meiliEnvironmentFile}
    else
      rm ${meiliEnvironmentFile}.new
    fi
  '';
  createNetwork = pkgs.writeShellScript "karakeep-network" ''
    ${pkgs.docker}/bin/docker network inspect karakeep >/dev/null 2>&1 \
      || ${pkgs.docker}/bin/docker network create karakeep >/dev/null
  '';
in
lib.mkIf (config.server.secrets.enable or false) {
  systemd.services.karakeep-network = {
    description = "Create the Karakeep container network";
    before = [
      "docker-karakeep.service"
      "docker-karakeep-chrome.service"
      "docker-karakeep-meilisearch.service"
    ];
    requires = [ "docker.service" ];
    after = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = createNetwork;
    };
  };

  systemd.services.karakeep-secrets = {
    description = "Create Karakeep secrets and runtime environment";
    before = [
      "docker-karakeep.service"
      "docker-karakeep-meilisearch.service"
    ];
    requires = [ "pocket-id-oidc-provision.service" ];
    after = [ "pocket-id-oidc-provision.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = generateSecrets;
    };
  };

  virtualisation.oci-containers.containers = {
    karakeep = {
      image = images.app;
      ports = [ "127.0.0.1:5797:3000" ];
      environmentFiles = [ environmentFile ];
      environment = {
        DATA_DIR = "/data";
        MEILI_ADDR = "http://karakeep-meilisearch:7700";
        BROWSER_WEB_URL = "http://karakeep-chrome:9222";
        NEXTAUTH_URL = "https://${domain}";
        AUTH_TRUSTED_ORIGINS = "https://${domain}";
        OAUTH_WELLKNOWN_URL = "https://id.outworld66.ru/.well-known/openid-configuration";
        OAUTH_CLIENT_ID = "karakeep";
        OAUTH_SCOPE = "openid email profile groups";
        OAUTH_PROVIDER_NAME = "Pocket ID";
        OAUTH_AUTO_REDIRECT = "true";
        DISABLE_PASSWORD_AUTH = "true";
      };
      volumes = [ "${stateDir}:/data" ];
      extraOptions = [ "--network=karakeep" ];
    };
    karakeep-chrome = {
      image = images.chrome;
      extraOptions = [
        "--init"
        "--shm-size=1g"
        "--network=karakeep"
      ];
    };
    karakeep-meilisearch = {
      image = images.meilisearch;
      environmentFiles = [ meiliEnvironmentFile ];
      environment.MEILI_NO_ANALYTICS = "true";
      volumes = [ "${meiliDir}:/meili_data" ];
      extraOptions = [ "--network=karakeep" ];
    };
  };

  systemd.services.docker-karakeep = {
    requires = [
      "karakeep-secrets.service"
      "karakeep-network.service"
      "docker-karakeep-chrome.service"
      "docker-karakeep-meilisearch.service"
    ];
    after = [
      "karakeep-secrets.service"
      "karakeep-network.service"
      "docker-karakeep-chrome.service"
      "docker-karakeep-meilisearch.service"
    ];
  };
  systemd.services.docker-karakeep-meilisearch = {
    requires = [
      "karakeep-secrets.service"
      "karakeep-network.service"
    ];
    after = [
      "karakeep-secrets.service"
      "karakeep-network.service"
    ];
  };

  services.caddy.virtualHosts.${domain}.extraConfig = ''
    reverse_proxy 127.0.0.1:5797
  '';
  services.caddy.virtualHosts.${legacyDomain}.extraConfig = ''
    redir https://${domain}{uri} permanent
  '';

  services.homepage-dashboard.services = lib.mkAfter [
    {
      Research = [
        {
          Karakeep = {
            href = "https://${domain}";
            icon = "mdi-bookmark-multiple";
            description = "Save and search articles and video links";
          };
        }
      ];
    }
  ];
}
