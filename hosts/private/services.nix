{
  inputs,
  pkgs,
  user,
  ...
}:
let
  homepageDomain = "homepage.private.outworld66.ru";
  bitmagnetDomain = "bitmagnet.private.outworld66.ru";
  portfolioDomain = "portfolio.private.outworld66.ru";
  portfolioSource = inputs.self + "/portfolio";
  portfolioSite = pkgs.runCommand "portfolio-site" { nativeBuildInputs = [ pkgs.hugo ]; } ''
    hugo --source ${portfolioSource} --destination "$out" --minify --noBuildLock --baseURL=https://${portfolioDomain}/
  '';
in
{
  services.homepage-dashboard = {
    enable = true;
    allowedHosts = homepageDomain;
    settings = {
      title = "Outworld services";
      theme = "dark";
      color = "slate";
      headerStyle = "clean";
      layout = {
        Infrastructure = {
          style = "row";
          columns = 4;
        };
        Applications = {
          style = "row";
          columns = 4;
        };
      };
    };
    services = [
      {
        Infrastructure = [
          {
            "Authelia" = {
              href = "https://auth.private.outworld66.ru";
              icon = "authelia.png";
              description = "Authentication portal";
            };
          }
          {
            "GoAccess" = {
              href = "https://stats.private.outworld66.ru";
              icon = "goaccess.png";
              description = "Web traffic statistics";
            };
          }
        ];
      }
      {
        Applications = [
          {
            "Portfolio" = {
              href = "https://${portfolioDomain}";
              icon = "hugo.png";
              description = "Personal portfolio";
            };
          }
          {
            "WebDAV" = {
              href = "https://files.private.outworld66.ru/webdav";
              icon = "filebrowser.png";
              description = "Private files";
            };
          }
          {
            "Bitmagnet" = {
              href = "https://${bitmagnetDomain}";
              icon = "https://cdn.jsdelivr.net/gh/bitmagnet-io/bitmagnet@main/webui/public/favicon.png";
              description = "BitTorrent indexer";
            };
          }
        ];
      }
    ];
  };

  services.bitmagnet = {
    enable = true;
    openFirewall = true;
    settings.http_server.port = "127.0.0.1:3333";
  };

  systemd.services.portfolio-hugo = {
    description = "Hugo portfolio site";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python -m http.server 1313 --bind 127.0.0.1 --directory ${portfolioSite}";
      Restart = "always";
      User = user;
      WorkingDirectory = portfolioSite;
      ProtectSystem = "strict";
      PrivateTmp = true;
      NoNewPrivileges = true;
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
    "*.private.outworld66.ru" = {
      extraConfig = ''
        abort
      '';
    };

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

    ${bitmagnetDomain} = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }

        forward_auth 127.0.0.1:9091 {
          uri /api/authz/forward-auth
          copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
        }

        reverse_proxy 127.0.0.1:3333
      '';
    };

    ${homepageDomain} = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }

        forward_auth 127.0.0.1:9091 {
          uri /api/authz/forward-auth
          copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
        }

        reverse_proxy 127.0.0.1:8082
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
