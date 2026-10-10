{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "filebrowser.outworld66.ru";
  image = "ghcr.io/gtsteffaniak/filebrowser:stable@sha256:9d42f635e32913d7daf05259428b6c70061cfdca3affc9602b4c31717e0a4bae";
  sharedPath = "/srv/media/downloads/complete";
  configFile = pkgs.writeText "filebrowser-config.yaml" (
    builtins.toJSON {
      server = {
        cacheDir = "/home/filebrowser/data/cache";
        database.path = "/home/filebrowser/data/filebrowser.sqlite";
        sources = [
          {
            name = "Personal files";
            path = "/home/filebrowser/data/users";
            config = {
              defaultEnabled = true;
              defaultUserScope = "/";
              createUserDir = true;
              defaultPermissions = {
                view = true;
                download = true;
                modify = true;
                delete = true;
                create = true;
                configured = true;
              };
            };
          }
          {
            name = "Torrents and Streamline";
            path = "/srv/shared-media";
            config = {
              denyByDefault = true;
              defaultEnabled = true;
              readOnly = true;
              defaultPermissions = {
                view = true;
                download = true;
                configured = true;
              };
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

  systemd.tmpfiles.rules = [
    "d /var/lib/filebrowser 0750 filebrowser media -"
    "d /var/lib/filebrowser/users 0750 filebrowser media -"
  ];

  virtualisation.oci-containers.containers.filebrowser = {
    inherit image;
    ports = [ "127.0.0.1:8193:80" ];
    environment.FILEBROWSER_CONFIG = "/home/filebrowser/config.yaml";
    environmentFiles = [ "/var/lib/filebrowser/oidc.env" ];
    volumes = [
      "${configFile}:/home/filebrowser/config.yaml:ro"
      "/var/lib/filebrowser:/home/filebrowser/data"
      "${sharedPath}:/srv/shared-media:ro"
    ];
    extraOptions = [ "--user=2002:2000" ];
  };

  systemd.services.filebrowser-access-bootstrap = {
    description = "Restrict the shared File Browser source to media admins";
    requires = [ "docker.service" ];
    after = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "filebrowser-access-bootstrap" ''
        ${config.virtualisation.docker.package}/bin/docker run --rm --pull=missing --network=none \
          --user=2002:2000 \
          --volume=${configFile}:/home/filebrowser/config.yaml:ro \
          --volume=/var/lib/filebrowser:/home/filebrowser/data \
          --volume=${sharedPath}:/srv/shared-media:ro \
          --entrypoint=/home/filebrowser/filebrowser \
          ${image} set rule \
          --source="Torrents and Streamline" \
          --path=/ \
          --role=group \
          --value=media-admin \
          --allow \
          --config=/home/filebrowser/config.yaml
      '';
    };
  };

  systemd.services.docker-filebrowser = {
    requires = [
      "pocket-id-oidc-provision.service"
      "filebrowser-access-bootstrap.service"
    ];
    after = [
      "pocket-id-oidc-provision.service"
      "filebrowser-access-bootstrap.service"
    ];
  };

  services.caddy.virtualHosts.${domain}.extraConfig = ''
    reverse_proxy 127.0.0.1:8193
  '';
}
