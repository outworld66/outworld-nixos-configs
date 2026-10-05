{
  config,
  lib,
  inputs,
  pkgs,
  user,
  ...
}:
let
  mediaRoot = "/srv/media";
  jellyfinAdminPassword = config.sops.secrets."media/jellyfin-admin-password".path;
  jellyfinBootstrap = pkgs.writeShellScript "jellyfin-bootstrap" ''
    set -euo pipefail

    api=http://127.0.0.1:8096
    password_file=${jellyfinAdminPassword}
    info=""

    for attempt in $(seq 1 60); do
      if info="$(${pkgs.curl}/bin/curl --silent --show-error --fail "$api/System/Info/Public" 2>/dev/null)"; then
        break
      fi
      sleep 2
    done

    if [ -z "$info" ]; then
      echo "Jellyfin did not become ready for first-run setup." >&2
      exit 1
    fi

    if printf '%s' "$info" | ${pkgs.jq}/bin/jq -e '.StartupWizardCompleted == true' >/dev/null; then
      exit 0
    fi

    post_json() {
      local path="$1" payload="$2"
      for attempt in $(seq 1 60); do
        if printf '%s' "$payload" | ${pkgs.curl}/bin/curl --silent --show-error --fail \
          --request POST --header 'Content-Type: application/json' \
          --data-binary @- "$api$path" >/dev/null 2>&1; then
          return 0
        fi
        info="$(${pkgs.curl}/bin/curl --silent --show-error --fail "$api/System/Info/Public" 2>/dev/null || true)"
        if printf '%s' "$info" | ${pkgs.jq}/bin/jq -e '.StartupWizardCompleted == true' >/dev/null 2>&1; then
          echo "Jellyfin setup was already completed during bootstrap."
          exit 0
        fi
        sleep 2
      done
      echo "Jellyfin startup API did not accept $path." >&2
      return 1
    }

    post_json /Startup/Configuration '{"UICulture":"ru-RU","MetadataCountryCode":"RU","PreferredMetadataLanguage":"ru"}'
    user="$( ${pkgs.jq}/bin/jq -Rs '{Name:"admin",Password:rtrimstr("\n")}' "$password_file")"
    post_json /Startup/User "$user"
    post_json /Startup/RemoteAccess '{"EnableRemoteAccess":true,"EnableAutomaticPortMapping":false}'
    for attempt in $(seq 1 60); do
      if ${pkgs.curl}/bin/curl --silent --show-error --fail --request POST \
        "$api/Startup/Complete" >/dev/null 2>&1; then
        break
      fi
      sleep 2
    done
    info="$(${pkgs.curl}/bin/curl --silent --show-error --fail "$api/System/Info/Public")"
    printf '%s' "$info" | ${pkgs.jq}/bin/jq -e '.StartupWizardCompleted == true' >/dev/null

    echo "Created Jellyfin admin account from the SOPS password."
  '';

  homepageDomain = "home.outworld66.ru";
  bitmagnetDomain = "bitmagnet.outworld66.ru";
  prowlarrDomain = "prowlarr.outworld66.ru";
  portfolioDomain = "portfolio.outworld66.ru";
  gotifyDomain = "gotify.outworld66.ru";
  elengrabDomain = "elengrab.outworld66.ru";
  donetickDomain = "donetick.outworld66.ru";
  cloudreveDomain = "cloudreve.outworld66.ru";
  nocodbDomain = "nocodb.outworld66.ru";
  speedtestDomain = "speedtest.outworld66.ru";
  pocketIdDomain = "id.outworld66.ru";
  immichDomain = "immich.outworld66.ru";
  jellyfinDomain = "jellyfin.outworld66.ru";
  torrentDomain = "torrent.outworld66.ru";
  jackettDomain = "jackett.outworld66.ru";
  binderyDomain = "books.outworld66.ru";
  streamlineDomain = "streamline.outworld66.ru";
  llmDomain = "llm.outworld66.ru";
  llmCredentialsFile = "/var/lib/llm-gateway/credentials.env";
  immichAnalyzeApiKeyFile = "/var/lib/immich-analyze/immich-api.env";
  aiPortalPolicy = [
    {
      allow = {
        or = [
          { "claim/groups" = "ai-admin"; }
          { "claim/groups" = "ai-user"; }
        ];
      };
    }
  ];
  aiAdminPolicy = [
    {
      allow = {
        and = [
          { "claim/groups" = "ai-admin"; }
        ];
      };
    }
  ];
  mediaAdminPolicy = [
    {
      allow = {
        and = [ { "claim/groups" = "media-admin"; } ];
      };
    }
  ];
  mailHostname = "mail.outworld66.ru";
  mailDomain = "outworld66.ru";
  authDomain = "auth.outworld66.ru";
  portfolioSource = inputs.self + "/portfolio";
  portfolioSite = pkgs.runCommand "portfolio-site" { nativeBuildInputs = [ pkgs.hugo ]; } ''
    hugo --source ${portfolioSource} --destination "$out" --minify --noBuildLock --baseURL=https://${portfolioDomain}/
  '';
in
lib.mkIf (config.server.secrets.enable or false) {
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
      jwt_claims_headers = {
        "X-Remote-User" = "email";
      };
      routes = [
        {
          from = "https://stats.outworld66.ru";
          path = "/ws";
          to = "http://127.0.0.1:7890";
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
          from = "https://stats.outworld66.ru";
          to = "http://127.0.0.1:7891";
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
          from = "https://${torrentDomain}";
          to = "http://127.0.0.1:8181";
          preserve_host_header = true;
          policy = mediaAdminPolicy;
        }
        {
          from = "https://${jackettDomain}";
          to = "http://127.0.0.1:9117";
          timeout = "150s";
          policy = mediaAdminPolicy;
        }
        {
          from = "https://${prowlarrDomain}";
          to = "http://127.0.0.1:9696";
          pass_identity_headers = true;
          policy = mediaAdminPolicy;
        }
        {
          from = "https://${binderyDomain}";
          to = "http://127.0.0.1:8787";
          policy = mediaAdminPolicy;
        }
        {
          from = "https://${llmDomain}";
          to = "http://127.0.0.1:4000";
          prefix = "/ui/model_hub_table.html";
          policy = aiPortalPolicy;
        }
        {
          from = "https://${llmDomain}";
          to = "http://127.0.0.1:4000";
          prefix = "/litellm-asset-prefix";
          policy = aiPortalPolicy;
        }
        {
          from = "https://${llmDomain}";
          to = "http://127.0.0.1:4000";
          prefix = "/public";
          policy = aiPortalPolicy;
        }
        {
          from = "https://${llmDomain}";
          to = "http://127.0.0.1:4000";
          path = "/openapi.json";
          policy = aiPortalPolicy;
        }
        {
          from = "https://${llmDomain}";
          to = "http://127.0.0.1:4000";
          path = "/favicon.ico";
          policy = aiPortalPolicy;
        }
        {
          from = "https://${llmDomain}";
          to = "http://127.0.0.1:4000";
          prefix = "/ui/favicon.ico";
          policy = aiPortalPolicy;
        }
        {
          from = "https://${llmDomain}";
          to = "http://127.0.0.1:4000";
          allow_websockets = true;
          policy = aiAdminPolicy;
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
          from = "https://${nocodbDomain}";
          to = "http://127.0.0.1:8085";
          allow_websockets = true;
          preserve_host_header = true;
          policy = [
            {
              allow = {
                and = [
                  { "claim/groups" = "media-admin"; }
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
      file_server
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
          columns = 3;
        };
        Media = {
          style = "row";
          columns = 4;
        };
        "Photos & Files" = {
          style = "row";
          columns = 4;
        };
        Productivity = {
          style = "row";
          columns = 4;
        };
        "Personal & Network" = {
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
          {
            "LiteLLM" = {
              href = "https://${llmDomain}/ui";
              icon = "ollama.png";
              description = "LLM gateway and model hub";
            };
          }
        ];
      }
      {
        Media = [
          {
            "Bitmagnet" = {
              href = "https://${bitmagnetDomain}";
              icon = "https://cdn.jsdelivr.net/gh/bitmagnet-io/bitmagnet@main/webui/public/favicon.png";
              description = "BitTorrent indexer";
            };
          }
          {
            "qBittorrent" = {
              href = "https://${torrentDomain}";
              icon = "qbittorrent.png";
              description = "Torrent client (admins)";
            };
          }
          {
            "Jackett" = {
              href = "https://${jackettDomain}";
              icon = "jackett.png";
              description = "Torrent indexers (admins)";
            };
          }
          {
            "Prowlarr" = {
              href = "https://${prowlarrDomain}";
              icon = "prowlarr.png";
              description = "Torrent indexer manager (admins)";
            };
          }
          {
            "Bindery" = {
              href = "https://${binderyDomain}";
              icon = "mdi-book-open-page-variant";
              description = "Book and audiobook manager (admins)";
            };
          }
          {
            "Streamline" = {
              href = "https://${streamlineDomain}";
              icon = "mdi-movie-open-cog";
              description = "Unified media library and requests";
            };
          }
          {
            "Jellyfin" = {
              href = "https://${jellyfinDomain}";
              icon = "jellyfin.png";
              description = "Movies and TV";
            };
          }
        ];
      }
      {
        "Photos & Files" = [
          {
            "WebDAV" = {
              href = "https://files.outworld66.ru/webdav";
              icon = "filebrowser.png";
              description = "Private files";
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
            "Cloudreve" = {
              href = "https://${cloudreveDomain}";
              icon = "cloudreve.png";
              description = "Cloud file storage";
            };
          }
        ];
      }
      {
        Productivity = [
          {
            "Gotify" = {
              href = "https://${gotifyDomain}";
              icon = "https://gotify.net/img/logo.png";
              description = "Push notifications";
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
            "NocoDB" = {
              href = "https://${nocodbDomain}";
              icon = "nocodb.png";
              description = "Personal database and spreadsheet";
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
      {
        "Personal & Network" = [
          {
            "Portfolio" = {
              href = "https://${portfolioDomain}";
              icon = "hugo.png";
              description = "Personal portfolio";
            };
          }
          {
            "Speedtest" = {
              href = "https://${speedtestDomain}";
              icon = "mdi-speedometer";
              description = "Measure your connection to this server";
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

  users.groups.media.gid = 2000;
  users.users.bindery = {
    isSystemUser = true;
    uid = 2001;
    group = "media";
  };

  services.qbittorrent = {
    enable = true;
    group = "media";
    webuiPort = 8181;
    torrentingPort = 51413;
    serverConfig = {
      LegalNotice.Accepted = true;
      Preferences.WebUI.Address = "127.0.0.1";
      Downloads = {
        SavePath = "${mediaRoot}/downloads/complete";
        TempPath = "${mediaRoot}/downloads/incomplete";
        TempPathEnabled = true;
      };
    };
  };

  systemd.services.qbittorrent.serviceConfig = {
    ReadWritePaths = [ "${mediaRoot}/downloads" ];
    UMask = "0002";
  };
  services.jackett.enable = true;
  systemd.services.jackett.preStart = lib.mkAfter ''
    config_file=/var/lib/jackett/.config/Jackett/ServerConfig.json
    if [ -s "$config_file" ] && [ "$( ${pkgs.jq}/bin/jq -r '(.FlareSolverrUrl == "http://127.0.0.1:8191") and (.FlareSolverrMaxTimeout == 120000)' "$config_file")" != "true" ]; then
      umask 077
      ${pkgs.jq}/bin/jq '.FlareSolverrUrl = "http://127.0.0.1:8191" | .FlareSolverrMaxTimeout = 120000' "$config_file" > "$config_file.new"
      mv "$config_file.new" "$config_file"
    fi
  '';
  services.flaresolverr = {
    enable = true;
    openFirewall = false;
  };
  users.groups.flaresolverr = { };
  users.users.flaresolverr = {
    isSystemUser = true;
    group = "flaresolverr";
  };
  systemd.services.flaresolverr = {
    environment = {
      HOST = "127.0.0.1";
      BROWSER_WAIT_TIMEOUT = "10";
      LOG_LEVEL = "error";
    };
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "flaresolverr";
      Group = "flaresolverr";
    };
  };
  services.prowlarr = {
    enable = true;
    settings = {
      server.bindaddress = "127.0.0.1";
      server.port = 9696;
      auth.method = "External";
    };
  };
  services.streamline = {
    enable = true;
    package = inputs.streamline.packages.${pkgs.system}.streamline;
    mutableSettings = false;
    group = "media";
    credentials = {
      admin-password = config.sops.secrets."media/streamline-admin-password".path;
      jackett-api-key = "/var/lib/streamline/jackett-api-key";
      prowlarr-api-key = "/var/lib/streamline/prowlarr-api-key";
      pocket-id-client-secret = "/var/lib/streamline/oidc-client-secret";
      qbittorrent-password = config.sops.secrets."media/qbittorrent-webui-password".path;
      jellyfin-api-key = "/var/lib/streamline/jellyfin-api-key";
      tmdb-api-key = config.sops.secrets."media/streamline-tmdb-api-key".path;
      tvdb-api-key = config.sops.secrets."media/streamline-tvdb-api-key".path;
    };
    settings = {
      server = {
        host = "127.0.0.1";
        port = 8097;
        trusted_proxies = [ "127.0.0.1/32" ];
      };
      auth = {
        registration_mode = "invite";
        default_role = "member";
        seed_admin = {
          email = "outworld66@gmail.com";
          password_file = "/run/credentials/streamline.service/admin-password";
        };
        oidc = [
          {
            name = "pocket-id";
            issuer = "https://id.outworld66.ru";
            client_id = "streamline";
            client_secret_file = "/run/credentials/streamline.service/pocket-id-client-secret";
            email_linking = "all";
            auto_provision = true;
          }
        ];
      };
      metadata = {
        tmdb_api_key_file = "/run/credentials/streamline.service/tmdb-api-key";
        tvdb_api_key_file = "/run/credentials/streamline.service/tvdb-api-key";
      };
      media_server.servers = [
        {
          name = "Jellyfin";
          server_type = "jellyfin";
          host = "https://${jellyfinDomain}";
          api_key_file = "/run/credentials/streamline.service/jellyfin-api-key";
          enabled = true;
        }
      ];
      library = {
        movie_path = "${mediaRoot}/library/movies";
        series_path = "${mediaRoot}/library/tv";
        download_path = "${mediaRoot}/downloads/complete/streamline";
        allowed_download_roots = [ "${mediaRoot}/downloads/complete/streamline" ];
        import_mode = "copy";
      };
      download_clients = [
        {
          name = "qBittorrent";
          client_type = "qbittorrent";
          host = "127.0.0.1";
          port = 8181;
          auth_method = "password";
          username = "admin";
          password_file = "/run/credentials/streamline.service/qbittorrent-password";
          download_dir = "${mediaRoot}/downloads/complete/streamline";
          enabled = true;
        }
      ];
      indexers = [
        {
          name = "Jackett (all)";
          host = "127.0.0.1";
          port = 9117;
          path = "/api/v2.0/indexers/all/results/torznab/api";
          protocol = "torznab";
          api_key_file = "/run/credentials/streamline.service/jackett-api-key";
          enabled = true;
        }
        {
          name = "Bitmagnet";
          host = "127.0.0.1";
          port = 3333;
          path = "/torznab";
          protocol = "torznab";
          api_key_file = "/dev/null";
          priority = 2;
          enabled = true;
        }
        {
          name = "Prowlarr";
          host = "127.0.0.1";
          port = 9696;
          protocol = "prowlarr";
          api_key_file = "/run/credentials/streamline.service/prowlarr-api-key";
          priority = 3;
          enabled = true;
        }
      ];
    };
  };
  systemd.services.streamline-jackett-key = {
    description = "Provide Streamline with Jackett's current API key";
    after = [ "jackett.service" ];
    requires = [ "jackett.service" ];
    before = [ "streamline.service" ];
    partOf = [ "jackett.service" ];
    path = [
      pkgs.coreutils
      pkgs.jq
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "streamline-jackett-key" ''
        set -euo pipefail
        key=$(jq -er '.APIKey | select(type == "string" and length > 0)' \
          /var/lib/jackett/.config/Jackett/ServerConfig.json)
        install -d -m 0750 /var/lib/streamline
        printf '%s' "$key" > /var/lib/streamline/jackett-api-key.new
        chmod 0400 /var/lib/streamline/jackett-api-key.new
        mv /var/lib/streamline/jackett-api-key.new /var/lib/streamline/jackett-api-key
      '';
    };
  };
  systemd.services.streamline-prowlarr-key = {
    description = "Provide Streamline with Prowlarr's current API key";
    after = [ "prowlarr.service" ];
    requires = [ "prowlarr.service" ];
    before = [ "streamline.service" ];
    partOf = [ "prowlarr.service" ];
    path = [
      pkgs.coreutils
      pkgs.curl
      pkgs.gnugrep
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "streamline-prowlarr-key" ''
        set -euo pipefail
        key=""
        for _ in {1..60}; do
          if [ -r /var/lib/prowlarr/config.xml ]; then
            key=$(grep -oP '<ApiKey>\K[^<]+' /var/lib/prowlarr/config.xml | head -n1 || true)
            if [ -n "$key" ] && curl --silent --max-time 2 --output /dev/null http://127.0.0.1:9696; then
              break
            fi
          fi
          sleep 1
        done
        test -n "$key"
        curl --silent --max-time 2 --output /dev/null http://127.0.0.1:9696
        install -d -m 0750 /var/lib/streamline
        printf '%s' "$key" > /var/lib/streamline/prowlarr-api-key.new
        chmod 0400 /var/lib/streamline/prowlarr-api-key.new
        mv /var/lib/streamline/prowlarr-api-key.new /var/lib/streamline/prowlarr-api-key
      '';
    };
  };
  systemd.services.streamline = {
    after = [
      "jackett.service"
      "prowlarr.service"
      "pocket-id-oidc-provision.service"
      "streamline-jackett-key.service"
      "streamline-prowlarr-key.service"
      "streamline-jellyfin-key.service"
    ];
    requires = [
      "jackett.service"
      "prowlarr.service"
      "pocket-id-oidc-provision.service"
      "streamline-jackett-key.service"
      "streamline-prowlarr-key.service"
      "streamline-jellyfin-key.service"
    ];
    partOf = [
      "streamline-jackett-key.service"
      "streamline-prowlarr-key.service"
    ];
    environment.STREAMLINE_PUBLIC_URL = "https://${streamlineDomain}";
  };
  systemd.services.streamline-jellyfin-key = {
    description = "Provide Streamline with a Jellyfin API key";
    wantedBy = [ "multi-user.target" ];
    before = [ "streamline.service" ];
    requires = [
      "jellyfin.service"
      "jellyfin-bootstrap.service"
    ];
    after = [
      "jellyfin.service"
      "jellyfin-bootstrap.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.python3}/bin/python3 ${../../scripts/configure-media-stack.py} --streamline-jellyfin-key";
      UMask = "0077";
    };
  };
  services.jellyfin = {
    enable = true;
    group = "media";
  };
  systemd.services.jellyfin.serviceConfig.ReadOnlyPaths = [ "${mediaRoot}/library" ];
  systemd.services.jellyfin-bootstrap = {
    description = "Create the initial Jellyfin administrator from SOPS";
    wantedBy = [ "multi-user.target" ];
    requires = [ "jellyfin.service" ];
    after = [ "jellyfin.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = jellyfinBootstrap;
    };
  };
  systemd.services.media-stack-bootstrap = {
    description = "Configure media service accounts, libraries, and integrations";
    wantedBy = [ "multi-user.target" ];
    requires = [
      "qbittorrent.service"
      "jackett.service"
      "jellyfin.service"
      "docker-bindery.service"
    ];
    after = [
      "qbittorrent.service"
      "jackett.service"
      "jellyfin-bootstrap.service"
      "docker-bindery.service"
    ];
    path = [ pkgs.systemd ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.python3}/bin/python3 ${../../scripts/configure-media-stack.py}";
      TimeoutStartSec = "15min";
      UMask = "0077";
    };
  };
  environment.systemPackages = [ pkgs.jq ];

  virtualisation.oci-containers.containers.bindery = {
    image = "ghcr.io/vavallee/bindery:1.39.0";
    extraOptions = [
      "--network=host"
      "--user=2001:2000"
    ];
    volumes = [
      "/var/lib/bindery:/config"
      "${mediaRoot}:${mediaRoot}"
    ];
    environment = {
      BINDERY_PORT = "8787";
      BINDERY_DATA_DIR = "/config";
      BINDERY_DOWNLOAD_DIR = "${mediaRoot}/downloads/complete/books";
      BINDERY_LIBRARY_DIR = "${mediaRoot}/library/books";
      BINDERY_AUDIOBOOK_DIR = "${mediaRoot}/library/audiobooks";
      BINDERY_PUID = "2001";
      BINDERY_PGID = "2000";
    };
  };

  systemd.services.docker-bindery.serviceConfig.UMask = "0002";

  networking.firewall = {
    allowedTCPPorts = [ 51413 ];
    allowedUDPPorts = [ 51413 ];
  };

  server.cloudreve.enable = true;
  server.donetick.enable = true;
  server.elengrab.enable = true;
  server.gotify.enable = true;
  server.immich.enable = true;
  server.goaccess.wsUrl = "wss://stats.outworld66.ru:443/ws";

  services.librespeed = {
    enable = true;
    domain = speedtestDomain;
    frontend = {
      enable = true;
      contactEmail = "";
      pageTitle = "Outworld Server Speed Test";
      useNginx = false;
      settings.telemetry_level = "disabled";
    };
    settings = {
      bind_address = "127.0.0.1";
      listen_port = 8990;
      database_type = "none";
    };
  };

  services.ollama = {
    enable = true;
    package = pkgs.ollama-cpu;
    loadModels = [ "qwen3-vl:4b-instruct-q4_K_M" ];
  };

  services.litellm = {
    enable = true;
    host = "0.0.0.0";
    port = 4000;
    openFirewall = false;
    environmentFile = llmCredentialsFile;
    settings = {
      model_list = [
        {
          model_name = "qwen3-vl";
          litellm_params = {
            model = "ollama_chat/qwen3-vl:4b-instruct-q4_K_M";
            api_base = "http://127.0.0.1:11434";
          };
        }
      ];
      litellm_settings.public_model_groups = [ "qwen3-vl" ];
      general_settings.enable_public_model_hub = true;
      general_settings.master_key = builtins.concatStringsSep "" [
        "os.environ/"
        "LITELLM_MASTER_KEY"
      ];
    };
  };

  systemd.tmpfiles.rules = [
    "d ${mediaRoot} 2770 root media -"
    "d ${mediaRoot}/downloads 2770 root media -"
    "d ${mediaRoot}/downloads/incomplete 2770 root media -"
    "d ${mediaRoot}/downloads/complete 2770 root media -"
    "d ${mediaRoot}/downloads/complete/movies 2770 root media -"
    "d ${mediaRoot}/downloads/complete/tv 2770 root media -"
    "d ${mediaRoot}/downloads/complete/books 2770 root media -"
    "d ${mediaRoot}/downloads/complete/streamline 2770 root media -"
    "d ${mediaRoot}/library 2770 root media -"
    "d ${mediaRoot}/library/movies 2770 root media -"
    "d ${mediaRoot}/library/tv 2770 root media -"
    "d ${mediaRoot}/library/books 2770 root media -"
    "d ${mediaRoot}/library/audiobooks 2770 root media -"
    "d /var/lib/bindery 0750 bindery media -"
    "d /var/lib/llm-gateway 0700 root root -"
    "d /var/lib/immich-analyze 0700 root root -"
    "d /srv/nocodb 0750 root root -"
  ];

  systemd.services.llm-gateway-credentials = {
    description = "Create a persistent API key for the local LLM gateway";
    before = [ "litellm.service" ];
    requiredBy = [ "litellm.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      UMask = "0077";
      ExecStart = pkgs.writeShellScript "create-llm-gateway-credentials" ''
        set -eu
        if [ ! -s ${llmCredentialsFile} ]; then
          key="$(${pkgs.openssl}/bin/openssl rand -hex 32)"
          printf 'LITELLM_MASTER_KEY=sk-%s\nIMMICH_ANALYZE_API_KEY=sk-%s\n' "$key" "$key" > ${llmCredentialsFile}
        fi
        chmod 0600 ${llmCredentialsFile}
      '';
    };
  };

  systemd.services.litellm = {
    environment.PROXY_BASE_URL = "https://${llmDomain}";
    requires = [
      "llm-gateway-credentials.service"
      "ollama-model-loader.service"
    ];
    after = [
      "llm-gateway-credentials.service"
      "ollama-model-loader.service"
    ];
  };

  virtualisation.oci-containers.containers.immich-analyze = {
    image = "ghcr.io/timasoft/immich-analyze:v0.5.1";
    extraOptions = [ "--network=host" ];
    environmentFiles = [
      llmCredentialsFile
      immichAnalyzeApiKeyFile
    ];
    environment = {
      IMMICH_API_URL = "http://127.0.0.1:2283";
      IMMICH_ANALYZE_INTERFACE = "llamacpp";
      IMMICH_ANALYZE_HOSTS = "http://127.0.0.1:4000";
      IMMICH_ANALYZE_MODEL_NAME = "qwen3-vl";
      IMMICH_ANALYZE_LANG = "ru";
      IMMICH_ANALYZE_PROMPT = ''
        Describe the visible image content for search. Return exactly two concise lines: first "RU: ..." in Russian, then "EN: ..." in English. Mention concrete visible objects, actions, setting, and image type. Keep both descriptions factual and useful as search terms. Do not identify people or guess details that are not visible. Return no introduction or extra text.
      '';
      IMMICH_ANALYZE_OVERWRITE_POLICY = "missing-ai";
      IMMICH_ANALYZE_PRESERVE_HUMAN = "true";
      IMMICH_ANALYZE_MAX_IMAGE_SIZE = "1024";
      IMMICH_ANALYZE_MAX_CONCURRENT = "1";
    };
  };

  systemd.services.docker-immich-analyze = {
    unitConfig.ConditionPathExists = immichAnalyzeApiKeyFile;
    requires = [
      "immich-server.service"
      "litellm.service"
    ];
    after = [
      "immich-server.service"
      "litellm.service"
    ];
  };

  systemd.paths.immich-analyze-api-key = {
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathChanged = immichAnalyzeApiKeyFile;
      Unit = "docker-immich-analyze.service";
    };
  };

  virtualisation.docker.enable = true;
  virtualisation.oci-containers = {
    backend = "docker";
    containers.nocodb = {
      image = "nocodb/nocodb:2026.09.0@sha256:5c9296e0b554b9dce431d62fda224388a3ce33c06215cec04bc4ec5c67a76295";
      ports = [ "127.0.0.1:8085:8080" ];
      volumes = [ "/srv/nocodb:/usr/app/data" ];
      environment = {
        NC_APP_DATA_DIR = "/usr/app/data";
        NC_SITE_URL = "https://${nocodbDomain}";
      };
    };
  };

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
        <iframe hidden src="https://${nocodbDomain}/.pomerium/sign_out"></iframe>
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

    ${torrentDomain} = {
      extraConfig = ''
        reverse_proxy 127.0.0.1:8443
      '';
    };

    ${jackettDomain} = {
      extraConfig = ''
        reverse_proxy 127.0.0.1:8443
      '';
    };

    ${prowlarrDomain} = {
      extraConfig = ''
        reverse_proxy 127.0.0.1:8443
      '';
    };

    ${binderyDomain} = {
      extraConfig = ''
        reverse_proxy 127.0.0.1:8443
      '';
    };

    ${streamlineDomain} = {
      extraConfig = ''
        @streamlineLogin path /login
        redir @streamlineLogin /auth/oidc/pocket-id/start?next={query.next} 302

        @streamlineLocalAuth path /auth/login /auth/register
        respond @streamlineLocalAuth "Sign in with Pocket ID." 403

        reverse_proxy 127.0.0.1:8097
      '';
    };

    ${jellyfinDomain} = {
      extraConfig = ''
        reverse_proxy 127.0.0.1:8096
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
        reverse_proxy 127.0.0.1:2021
      '';
    };

    ${cloudreveDomain} = {
      extraConfig = ''
        reverse_proxy 127.0.0.1:5212
      '';
    };

    ${nocodbDomain} = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }
        reverse_proxy 127.0.0.1:8443
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

    ${llmDomain} = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }
        redir /ui /ui/ 308
        @uiPage path_regexp uiPage ^/ui/(([^./]+/)*[^./]+)/*$
        rewrite @uiPage /ui/{re.uiPage.1}.html
        @api path /v1 /v1/*
        handle @api {
          reverse_proxy 127.0.0.1:4000
        }
        handle {
          reverse_proxy 127.0.0.1:8443
        }
      '';
    };

    ${speedtestDomain} = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }
        handle /backend/* {
          reverse_proxy 127.0.0.1:8990
        }
        handle {
          root * ${config.services.librespeed.settings.assets_path}
          file_server
        }
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
