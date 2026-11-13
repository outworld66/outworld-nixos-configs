{ config, lib, ... }:
let
  domain = "archivebox.outworld66.ru";
in
lib.mkIf (config.server.secrets.enable or false) {
  systemd.tmpfiles.rules = [
    "d /var/lib/archivebox 0750 911 911 -"
    "d /srv/archivebox 0750 911 911 -"
  ];

  virtualisation.oci-containers.containers.archivebox = {
    image = "ghcr.io/archivebox/archivebox:0.9.73@sha256:6478ae1e030db1478858a7c8bb5967b2f6c198cd74cea70b9a74e24ee7ee3e4c";
    ports = [ "127.0.0.1:5797:5797" ];
    volumes = [
      "/var/lib/archivebox:/data"
      "/srv/archivebox:/data/archive"
    ];
    environment = {
      BASE_URL = "https://${domain}";
      SERVER_SECURITY_MODE = "safe-onedomain-nojsreplay";
      PUBLIC_INDEX = "False";
      PUBLIC_ADD_VIEW = "False";
      PERMISSIONS = "private";
      ARCHIVEDOTORG_ENABLED = "False";
      PUID = "911";
      PGID = "911";
    };
    extraOptions = [
      "--shm-size=1g"
      "--pids-limit=2048"
    ];
  };

  services.pomerium.settings.routes = lib.mkAfter [
    {
      from = "https://${domain}";
      to = "http://127.0.0.1:5797";
      policy = [
        {
          allow = {
            or = [
              { "claim/groups" = "homepage-admin"; }
              { "claim/groups" = "homepage-user"; }
            ];
          };
        }
      ];
    }
  ];

  services.caddy.virtualHosts.${domain}.extraConfig = ''
    reverse_proxy 127.0.0.1:8443
  '';

  services.homepage-dashboard.settings.layout.Research = {
    style = "row";
    columns = 3;
  };

  services.homepage-dashboard.services = lib.mkAfter [
    {
      Research = [
        {
          ArchiveBox = {
            href = "https://${domain}";
            icon = "mdi-archive-outline";
            description = "Web archive for articles and other links";
          };
        }
      ];
    }
  ];
}
