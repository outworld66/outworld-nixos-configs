{
  configDirectory,
  pkgs,
  user,
  ...
}:
let
  portfolioDomain = "portfolio.private.outworld66.ru";
in
{
  systemd.services.portfolio-hugo = {
    description = "Hugo portfolio site";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.hugo}/bin/hugo server --source ${configDirectory}/portfolio --bind 127.0.0.1 --port 1313 --appendPort=false --disableLiveReload --baseURL=https://${portfolioDomain}/";
      Restart = "on-failure";
      User = user;
      WorkingDirectory = "${configDirectory}/portfolio";
      ReadWritePaths = [ "${configDirectory}/portfolio" ];
    };
  };

  systemd.services.anubis-portfolio = {
    description = "Anubis protection for the portfolio site";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      "portfolio-hugo.service"
    ];
    requires = [ "portfolio-hugo.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.anubis}/bin/anubis";
      Environment = [
        "BIND=127.0.0.1:8923"
        "COOKIE_SECURE=true"
        "REDIRECT_DOMAINS=${portfolioDomain}"
        "TARGET=http://127.0.0.1:1313"
      ];
      Restart = "on-failure";
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
    };
  };

  services.caddy.virtualHosts = {
    "auth.private.outworld66.ru" = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }
        reverse_proxy 127.0.0.1:9091
      '';
    };

    "files.private.outworld66.ru" = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }
        @hasDest header_regexp dest ^https?://[^/]+(.*)$
        header @hasDest Destination {re.dest.1}
        handle /webdav* {
          reverse_proxy 127.0.0.1:6065
        }
      '';
    };

    "stats.private.outworld66.ru" = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }

        forward_auth 127.0.0.1:9091 {
          uri /api/authz/forward-auth
          copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
        }

        @websocket header Connection *Upgrade
        handle @websocket {
          reverse_proxy 127.0.0.1:7890
        }

        handle_path / {
          root * /srv/goaccess
          file_server
        }
      '';
    };

    ${portfolioDomain} = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }

        reverse_proxy 127.0.0.1:8923 {
          header_up X-Real-Ip {remote_host}
          header_up X-Http-Version {http.request.proto}
        }
      '';
    };
  };
}
