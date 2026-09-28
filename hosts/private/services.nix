{
  inputs,
  pkgs,
  user,
  ...
}:
let
  homepageDomain = "home.outworld66.ru";
  bitmagnetDomain = "bitmagnet.outworld66.ru";
  portfolioDomain = "portfolio.outworld66.ru";
  gotifyDomain = "gotify.outworld66.ru";
  elengrabDomain = "elengrab.outworld66.ru";
  donetickDomain = "donetick.outworld66.ru";
  cloudreveDomain = "cloudreve.outworld66.ru";
  pocketIdDomain = "id.outworld66.ru";
  immichDomain = "immich.outworld66.ru";
  mailHostname = "mail.outworld66.ru";
  mailDomain = "outworld66.ru";
  authDomain = "auth.outworld66.ru";
  portfolioSource = inputs.self + "/portfolio";
  portfolioSite = pkgs.runCommand "portfolio-site" { nativeBuildInputs = [ pkgs.hugo ]; } ''
    hugo --source ${portfolioSource} --destination "$out" --minify --noBuildLock --baseURL=https://${portfolioDomain}/
  '';
in
{
  services.pomerium = {
    enable = true;
    secretsFile = "/var/lib/pomerium/environment";
    settings = {
      address = "127.0.0.1:8443";
      insecure_server = true;
      authenticate_service_url = "https://${authDomain}";
      idp_provider = "oidc";
      idp_provider_url = "https://id.outworld66.ru";
      idp_client_id = "pomerium";
      idp_scopes = [
        "openid"
        "profile"
        "email"
        "groups"
        "offline_access"
      ];
      routes = [
        {
          from = "https://stats.outworld66.ru";
          to = "http://127.0.0.1:7891";
          allow_websockets = true;
          policy = [
            {
              allow = {
                and = [
                  { "claim/groups" = "stats-user"; }
                ];
              };
            }
          ];
        }
        {
          from = "https://${bitmagnetDomain}";
          to = "http://127.0.0.1:3333";
          policy = [
            {
              allow = {
                or = [
                  { "claim/groups" = "media-admin"; }
                  { "claim/groups" = "media-user"; }
                ];
              };
            }
          ];
        }
        {
          from = "https://${homepageDomain}";
          to = "http://127.0.0.1:8082";
          policy = [
            {
              allow = {
                or = [
                  { "claim/groups" = "media-admin"; }
                  { "claim/groups" = "media-user"; }
                ];
              };
            }
          ];
        }
        {
          from = "https://${elengrabDomain}";
          to = "http://127.0.0.1:8084";
          set_request_headers = {
            "X-Forwarded-Proto" = "https";
          };
          preserve_host_header = true;
          policy = [
            {
              allow = {
                or = [
                  { "claim/groups" = "media-admin"; }
                  { "claim/groups" = "media-user"; }
                ];
              };
            }
          ];
        }
        {
          from = "https://${donetickDomain}";
          to = "http://127.0.0.1:2021";
          policy = [
            {
              allow = {
                or = [
                  { "claim/groups" = "donetick-admin"; }
                  { "claim/groups" = "donetick-user"; }
                ];
              };
            }
          ];
        }
      ];
    };
  };

  services.caddy.globalConfig = ''
    servers {
      protocols h1 h2
    }
  '';

  services.caddy.extraConfig = ''
    http://127.0.0.1:7891 {
      root * /srv/goaccess
      @websocket header Connection *Upgrade
      handle @websocket {
        reverse_proxy 127.0.0.1:7890
      }
      handle {
        file_server
      }
    }
  '';

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
            "Pocket ID" = {
              href = "https://${pocketIdDomain}";
              icon = "pocket-id.png";
              description = "OIDC identity provider";
            };
          }
          {
            "GoAccess" = {
              href = "https://stats.outworld66.ru";
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
              href = "https://files.outworld66.ru/webdav";
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
              icon = "donetick.png";
              description = "Tasks and reminders";
            };
          }
          {
            "Cloudreve" = {
              href = "https://${cloudreveDomain}";
              icon = "cloudreve.png";
              description = "Cloud file storage";
            };
          }
          {
            "Mail" = {
              href = "https://${mailHostname}";
              icon = "mdi-email-outline";
              description = "Stalwart mail server";
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
  server.gotify.enable = true;
  server.immich.enable = true;

  systemd.services.elengrab.environment.ELENGRAB_BASE_URL = "https://${elengrabDomain}";

  server.mail = {
    enable = true;
    hostname = mailHostname;
    primaryDomain = mailDomain;
    certificateSource = "/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/wildcard_.outworld66.ru/wildcard_.outworld66.ru.crt";
    keySource = "/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/wildcard_.outworld66.ru/wildcard_.outworld66.ru.key";
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
    "*.outworld66.ru" = {
      extraConfig = ''
        abort
      '';
    };

    "auth.outworld66.ru" = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }
        reverse_proxy 127.0.0.1:8443
      '';
    };

    ${pocketIdDomain} = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }
        handle /pomerium-global-logout {
          header Content-Type text/html
          respond <<HTML
        <!doctype html>
        <html><body>
        <iframe hidden src="https://stats.outworld66.ru/.pomerium/sign_out"></iframe>
        <iframe hidden src="https://${bitmagnetDomain}/.pomerium/sign_out"></iframe>
        <iframe hidden src="https://${homepageDomain}/.pomerium/sign_out"></iframe>
        <iframe hidden src="https://${elengrabDomain}/.pomerium/sign_out"></iframe>
        <iframe hidden src="https://${donetickDomain}/.pomerium/sign_out"></iframe>
        <script>setTimeout(() => location.replace("/"), 1500);</script>
        </body></html>
        HTML 200
        }
        handle {
          reverse_proxy 127.0.0.1:1411
        }
      '';
    };

    "files.outworld66.ru" = {
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

    "stats.outworld66.ru" = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }
        reverse_proxy 127.0.0.1:8443
      '';
    };

    ${bitmagnetDomain} = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }

        reverse_proxy 127.0.0.1:8443
      '';
    };

    ${homepageDomain} = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }

        reverse_proxy 127.0.0.1:8443
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
        reverse_proxy 127.0.0.1:8443
      '';
    };

    ${donetickDomain} = {
      extraConfig = ''
        reverse_proxy 127.0.0.1:8443
      '';
    };

    ${cloudreveDomain} = {
      extraConfig = ''
        reverse_proxy 127.0.0.1:5212
      '';
    };

    ${immichDomain} = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }
        reverse_proxy 127.0.0.1:2283
      '';
    };

    ${mailHostname} = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }

        reverse_proxy 127.0.0.1:8080
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
