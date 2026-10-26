{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "gym.outworld66.ru";
  docker = "${config.virtualisation.docker.package}/bin/docker";
in
lib.mkIf (config.server.secrets.enable or false) {
  systemd.tmpfiles.rules = [ "d /var/lib/opengym 0750 root root -" ];

  systemd.services.docker-opengym-network = {
    description = "Create the private openGym container network";
    wantedBy = [ "multi-user.target" ];
    wants = [ "docker.service" ];
    after = [ "docker.service" ];
    before = [
      "docker-opengym-api.service"
      "docker-opengym-web.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "opengym-network" ''
        ${docker} network inspect opengym >/dev/null 2>&1 || ${docker} network create opengym >/dev/null
      '';
    };
  };

  virtualisation.oci-containers.containers = {
    opengym-api = {
      image = "ghcr.io/duartesantos8/opengym-api:1.4.0@sha256:c9679fde2557231c7246c9c5cfa36fb7fff8a5160a46a88b7bdeb0c40841bbbd";
      volumes = [ "/var/lib/opengym:/data" ];
      extraOptions = [
        "--network=opengym"
        "--network-alias=opengym-api"
      ];
      environment = {
        PORT = "3000";
        DATA_DIR = "/data";
        TRUST_PROXY = "1";
        RP_ID = domain;
        ORIGIN = "https://${domain}";
        RP_NAME = "openGym";
        FIRST_USER_ADMIN = "1";
        ALLOW_GUEST = "0";
      };
    };
    opengym-web = {
      image = "ghcr.io/duartesantos8/opengym-web:1.4.0@sha256:9c05c97aa209d520c873858e0e00d1118f701eaf676dd400702624acba7ec377";
      ports = [ "127.0.0.1:8098:80" ];
      extraOptions = [
        "--network=opengym"
        "--network-alias=opengym-web"
      ];
      environment = {
        NGINX_PORT = "80";
        BACKEND = "opengym-api";
        PORT = "3000";
        RESOLVER = "127.0.0.11";
        BASE_PATH = "";
      };
    };
  };

  systemd.services.docker-opengym-api = {
    requires = [ "docker-opengym-network.service" ];
    after = [ "docker-opengym-network.service" ];
  };
  systemd.services.docker-opengym-web = {
    requires = [
      "docker-opengym-network.service"
      "docker-opengym-api.service"
    ];
    after = [
      "docker-opengym-network.service"
      "docker-opengym-api.service"
    ];
  };

  services.pomerium.settings.routes = lib.mkAfter [
    {
      from = "https://${domain}";
      to = "http://127.0.0.1:8098";
      policy = [
        {
          allow.and = [ { "claim/groups" = "opengym-admin"; } ];
        }
      ];
    }
  ];

  services.caddy.virtualHosts.${domain}.extraConfig = ''
    reverse_proxy 127.0.0.1:8443
  '';
}
