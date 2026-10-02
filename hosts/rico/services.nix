{
  config,
  lib,
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
  nocodbDomain = "nocodb.outworld66.ru";
  pocketIdDomain = "id.outworld66.ru";
  immichDomain = "immich.outworld66.ru";
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
  server.goaccess.wsUrl = "wss://stats.outworld66.ru:443/ws";

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
