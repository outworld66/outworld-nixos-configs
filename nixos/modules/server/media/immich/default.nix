{
  config,
  inputs,
  lib,
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
      mediaLocation = "/var/lib/immich";
      settings = {
        server.externalDomain = "https://immich.private.outworld66.ru";
        oauth = {
          enabled = true;
          issuerUrl = "https://id.private.outworld66.ru";
          clientId = "immich";
          clientSecret._secret = "/var/lib/immich/oidc-client-secret";
          scope = "openid email profile groups";
          buttonText = "Login with Pocket ID";
          autoRegister = true;
          autoLaunch = false;
        };
      };
    };

    systemd.services.immich-server = {
      after = [ "pocket-id-oidc-provision.service" ];
      requires = [ "pocket-id-oidc-provision.service" ];
    };
  };
}
