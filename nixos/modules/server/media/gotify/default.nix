{ config, lib, ... }:
let
  cfg = config.server.gotify;
in
{
  options.server.gotify.enable = lib.mkEnableOption "gotify service";
  config = lib.mkIf cfg.enable {
    services.gotify = {
      enable = true;
      environment = {
        GOTIFY_SERVER_PORT = 8090;
        GOTIFY_DATABASE_DIALECT = "sqlite3";
      };
      environmentFiles = [ "/var/lib/gotify/oidc.env" ];
    };

    systemd.services.gotify-server = {
      after = [ "pocket-id-oidc-provision.service" ];
      requires = [ "pocket-id-oidc-provision.service" ];
    };
  };
}
