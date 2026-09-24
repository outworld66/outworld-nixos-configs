{ pkgs, ... }:

{
  services.caddy.enable = true;
  services.caddy.package = pkgs.caddy.withPlugins {
    plugins = [ "github.com/WEBzaytsev/caddy-selectel@v1.4.0" ];
    hash = "sha256-RCZJpczNnB6eHni1bzFX40A0sT+yUvKezPa6dfKCCzg=";
  };
  services.caddy.globalConfig = ''
    acme_dns selectel {
      user {$SELECTEL_USER}
      password {$SELECTEL_PASSWORD}
      account_id {$SELECTEL_ACCOUNT_ID}
      project_name {$SELECTEL_PROJECT_NAME}
    }
  '';
}
