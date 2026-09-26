{
  inputs,
  pkgs,
  user,
  ...
}:
let
  homepageDomain = "home.private.outworld66.ru";
  bitmagnetDomain = "bitmagnet.private.outworld66.ru";
  portfolioDomain = "portfolio.private.outworld66.ru";
  gotifyDomain = "gotify.private.outworld66.ru";
  elengrabDomain = "elengrab.private.outworld66.ru";
  donetickDomain = "donetick.private.outworld66.ru";
  cloudreveDomain = "cloudreve.private.outworld66.ru";
  pocketIdDomain = "id.private.outworld66.ru";
  immichDomain = "immich.private.outworld66.ru";
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
            "Pocket ID" = {
              href = "https://${pocketIdDomain}";
              icon = "https://github.com/pocket-id/pocket-id.png?size=64";
              description = "OIDC identity provider";
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
          {
            "Gotify" = {
              href = "https://${gotifyDomain}";
              icon = "https://gotify.net/img/logo.png";
              description = "Push notifications";
            };
          }
          {
            "Ente" = {
              href = "https://ente-photos.private.outworld66.ru";
              icon = "https://github.com/ente-io.png?size=64";
              description = "Encrypted photos and albums";
            };
          }
          {
            "Immich" = {
              href = "https://${immichDomain}";
              icon = "immich.png";
              description = "Photo and video backup";
            };
          }
          {
            "Elengrab" = {
              href = "https://${elengrabDomain}";
              icon = "https://github.com/neosy.png?size=64";
              description = "Video and audio downloader";
            };
          }
          {
            "Donetick" = {
              href = "https://${donetickDomain}";
              icon = "vikunja.png";
              description = "Tasks and reminders";
            };
          }
          {
            "Cloudreve" = {
              href = "https://${cloudreveDomain}";
              icon = "https://github.com/cloudreve.png?size=64";
              description = "Cloud file storage";
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

  server.cloudreve.enable = true;
  server.donetick.enable = true;
  server.elengrab.enable = true;
  server.ente.enable = true;
  server.gotify.enable = true;
  server.immich.enable = true;

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

    ${pocketIdDomain} = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }
        reverse_proxy 127.0.0.1:1411
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

    ${gotifyDomain} = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }
        reverse_proxy 127.0.0.1:8090
      '';
    };

    ${elengrabDomain} = {
      extraConfig = ''
        forward_auth 127.0.0.1:9091 {
          uri /api/authz/forward-auth
          copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
        }
        reverse_proxy 127.0.0.1:8080
      '';
    };

    ${donetickDomain} = {
      extraConfig = ''
        forward_auth 127.0.0.1:9091 {
          uri /api/authz/forward-auth
          copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
        }
        reverse_proxy 127.0.0.1:2021
      '';
    };

    ${cloudreveDomain} = {
      extraConfig = ''
        forward_auth 127.0.0.1:9091 {
          uri /api/authz/forward-auth
          copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
        }
        reverse_proxy 127.0.0.1:5212
      '';
    };

    "ente-api.private.outworld66.ru" = {
      extraConfig = "reverse_proxy 127.0.0.1:8081";
    };
    "ente-accounts.private.outworld66.ru" = {
      extraConfig = "reverse_proxy 127.0.0.1:8081";
    };
    "ente-cast.private.outworld66.ru" = {
      extraConfig = "reverse_proxy 127.0.0.1:8081";
    };
    "ente-albums.private.outworld66.ru" = {
      extraConfig = "reverse_proxy 127.0.0.1:8081";
    };
    "ente-photos.private.outworld66.ru" = {
      extraConfig = "reverse_proxy 127.0.0.1:8081";
    };

    ${immichDomain} = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }
        forward_auth 127.0.0.1:9091 {
          uri /api/authz/forward-auth
          copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
        }
        reverse_proxy 127.0.0.1:2283
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
