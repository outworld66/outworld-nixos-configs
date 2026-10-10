{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "filebrowser.outworld66.ru";
  configFile = pkgs.writeText "filebrowser-config.yaml" (
    builtins.toJSON {
      server = {
        cacheDir = "/home/filebrowser/data/cache";
        database.path = "/home/filebrowser/data/filebrowser.sqlite";
        sources = [
          {
            name = "Completed torrents";
            path = "/srv/torrents";
            config = {
              defaultEnabled = true;
              readOnly = true;
            };
          }
          {
            name = "Streamline";
            path = "/srv/streamline";
            config = {
              defaultEnabled = true;
              readOnly = true;
            };
          }
        ];
      };
      auth.methods = {
        password.enabled = false;
        oidc = {
          enabled = true;
          adminGroup = "media-admin";
          userGroups = [
            "media-admin"
            "media-user"
          ];
          groupsClaim = "groups";
          userIdentifier = "preferred_username";
          createUser = true;
          clientId = "filebrowser";
          issuerUrl = "https://id.outworld66.ru";
          scopes = "openid email profile groups";
        };
      };
      http = {
        externalUrl = "https://${domain}";
        trustProxyHeaders = true;
      };
    }
  );
in
lib.mkIf (config.server.secrets.enable or false) {
  users.users.filebrowser = {
    isSystemUser = true;
    uid = 2002;
    group = "media";
  };

  systemd.tmpfiles.rules = [ "d /var/lib/filebrowser 0750 filebrowser media -" ];

  virtualisation.oci-containers.containers.filebrowser = {
    image = "ghcr.io/gtsteffaniak/filebrowser:stable@sha256:9d42f635e32913d7daf05259428b6c70061cfdca3affc9602b4c31717e0a4bae";
    ports = [ "127.0.0.1:8193:80" ];
    environmentFiles = [ "/var/lib/filebrowser/oidc.env" ];
    volumes = [
      "${configFile}:/home/filebrowser/config.yaml:ro"
      "/var/lib/filebrowser:/home/filebrowser/data"
      "/srv/media/downloads/complete:/srv/torrents:ro"
      "/srv/media/downloads/complete/streamline:/srv/streamline:ro"
    ];
    extraOptions = [ "--user=2002:2000" ];
  };

  systemd.services.docker-filebrowser = {
    requires = [ "pocket-id-oidc-provision.service" ];
    after = [ "pocket-id-oidc-provision.service" ];
  };

  services.caddy.virtualHosts.${domain}.extraConfig = ''
    reverse_proxy 127.0.0.1:8193
  '';
}
