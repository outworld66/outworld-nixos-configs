{
  config,
  inputs,
  lib,
  pkgs,
  system,
  ...
}:
let
  cfg = config.server.immich;
in
{
  options.server.immich.enable = lib.mkEnableOption "immich service";
  config = lib.mkIf cfg.enable {
    services.immich = {
      enable = true;
      package = inputs.llama-cpp-nixpkgs.legacyPackages.${system}.immich;
      host = "127.0.0.1";
      port = 2283;
      mediaLocation = "/srv/immich";
      settings = {
        server.externalDomain = "https://immich.outworld66.ru";
        oauth = {
          enabled = true;
          issuerUrl = "https://id.outworld66.ru";
          clientId = "immich";
          clientSecret._secret = "/var/lib/immich/oidc-client-secret";
          scope = "openid email profile groups";
          buttonText = "Login with Pocket ID";
          autoRegister = true;
          autoLaunch = false;
        };
      };
    };

    systemd.services.immich-storage-migration = {
      before = [ "immich-server.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "immich-storage-migration" ''
          install -d -m 0750 -o immich -g immich /srv/immich
          if [ ! -e /srv/immich/.migrated-from-var-lib-immich ]; then
            find /var/lib/immich -mindepth 1 -maxdepth 1 \
              ! -name oidc-client-secret \
              ! -name .migrated-from-var-lib-immich \
              -exec mv -t /srv/immich -- {} +
            touch /srv/immich/.migrated-from-var-lib-immich
          fi
          chown -R immich:immich /srv/immich
        '';
      };
    };

    systemd.services.immich-server = {
      after = [
        "immich-storage-migration.service"
        "pocket-id-oidc-provision.service"
      ];
      requires = [
        "immich-storage-migration.service"
        "pocket-id-oidc-provision.service"
      ];
    };
  };
}
