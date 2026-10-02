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
  options.server.immich.oauthRoleMappings = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.enum [
        "admin"
        "user"
      ]
    );
    default = {
      media-admin = "admin";
      media-user = "user";
    };
    description = "Map Pocket ID groups from the groups claim to Immich roles.";
  };
  config = lib.mkIf cfg.enable {
    services.immich = {
      enable = true;
      package = inputs.nixpkgs-unstable.legacyPackages.${system}.immich.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          role_mappings='${builtins.toJSON cfg.oauthRoleMappings}'
          substituteInPlace "$out/lib/node_modules/immich/dist/services/auth.service.js" \
            --replace-fail \
              'const isRole = (role) => roles.includes(role);' \
              "const roleMappings = $role_mappings; const isRole = (role) => roles.some((group) => roleMappings[group] === role);" \
            --replace-fail \
              'if (!autoRegister) {' \
              'if (!autoRegister || !role) {' \
            --replace-fail \
              'User does not exist and auto registering is disabled.' \
              'User does not exist or has no mapped OAuth role.'
        '';
      });
      host = "127.0.0.1";
      port = 2283;
      mediaLocation = "/srv/immich";
      settings = {
        server.externalDomain = "https://immich.outworld66.ru";
        machineLearning = {
          clip.modelName = "ViT-SO400M-16-SigLIP2-384__webli";
          facialRecognition.maxDistance = 0.4;
          ocr.modelName = "ESLAV__PP-OCRv5_mobile";
        };
        oauth = {
          enabled = true;
          issuerUrl = "https://id.outworld66.ru";
          clientId = "immich";
          clientSecret._secret = "/var/lib/immich/oidc-client-secret";
          scope = "openid email profile groups";
          buttonText = "Login with Pocket ID";
          autoRegister = true;
          autoLaunch = false;
          mobileOverrideEnabled = true;
          mobileRedirectUri = "https://immich.outworld66.ru/api/oauth/mobile-redirect";
          roleClaim = "groups";
        };
        passwordLogin.enabled = false;
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
