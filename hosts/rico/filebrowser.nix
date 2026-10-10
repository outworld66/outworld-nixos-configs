{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "filebrowser.outworld66.ru";
  image = "ghcr.io/gtsteffaniak/filebrowser:stable@sha256:9d42f635e32913d7daf05259428b6c70061cfdca3affc9602b4c31717e0a4bae";
  sharedPath = "/srv/media";
  personalFilesPath = "/srv/filebrowser/users";
  mediaSourcePath = "/srv/shared-media";
  personalScopeBootstrap = pkgs.writeText "filebrowser-personal-scope-bootstrap.py" (
    builtins.readFile ./filebrowser-personal-scope-bootstrap.py
  );
  configFile = pkgs.writeText "filebrowser-config.yaml" (
    builtins.toJSON {
      server = {
        cacheDir = "/home/filebrowser/data/cache";
        database.path = "/home/filebrowser/data/filebrowser.sqlite";
        sources = [
          {
            name = "Personal files";
            path = personalFilesPath;
            config = {
              defaultEnabled = true;
              defaultUserScope = "/";
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
            name = "Media files";
            path = mediaSourcePath;
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
    "d /srv/filebrowser 0750 filebrowser media -"
    "d ${personalFilesPath} 0750 filebrowser media -"
  ];

  virtualisation.oci-containers.containers.filebrowser = {
    inherit image;
    ports = [ "127.0.0.1:8193:80" ];
    environment.FILEBROWSER_CONFIG = "/home/filebrowser/config.yaml";
    environmentFiles = [ "/var/lib/filebrowser/oidc.env" ];
    volumes = [
      "${configFile}:/home/filebrowser/config.yaml:ro"
      "/var/lib/filebrowser:/home/filebrowser/data"
      "${personalFilesPath}:${personalFilesPath}"
      "${sharedPath}:${mediaSourcePath}:ro"
    ];
    extraOptions = [ "--user=2002:2000" ];
  };

  systemd.services.filebrowser-access-bootstrap = {
    description = "Reconcile File Browser personal scopes and media access";
    unitConfig.RequiresMountsFor = [
      personalFilesPath
      sharedPath
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "filebrowser-access-bootstrap" ''
        ${pkgs.python3}/bin/python3 ${personalScopeBootstrap} \
          /var/lib/filebrowser/filebrowser.sqlite \
          ${personalFilesPath} \
          ${personalFilesPath} \
          /home/filebrowser/data/users \
          /var/lib/filebrowser/users \
          ${mediaSourcePath}
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
