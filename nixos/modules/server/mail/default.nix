{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.server.mail;
  maddyConfig =
    builtins.replaceStrings
      [
        "submission tcp://0.0.0.0:587"
        "imap tcp://0.0.0.0:143"
      ]
      [
        "submission tls://0.0.0.0:465 tcp://0.0.0.0:587"
        "imap tls://0.0.0.0:993 tcp://0.0.0.0:143"
      ]
      options.services.maddy.config.default;
in
{
  options.server.mail = {
    enable = lib.mkEnableOption "Maddy mail server";
    hostname = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = "Fully qualified hostname used by Maddy for SMTP.";
    };
    primaryDomain = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = "Primary mail domain served by Maddy.";
    };
    accounts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.passwordFile = lib.mkOption {
            type = lib.types.path;
            description = "File containing the account password.";
          };
        }
      );
      default = { };
      description = "Mail accounts and their password files.";
    };
    certificateSource = lib.mkOption {
      type = lib.types.path;
      description = "Certificate source copied from the existing certificate manager.";
    };
    keySource = lib.mkOption {
      type = lib.types.path;
      description = "Private key source copied from the existing certificate manager.";
    };
    webmail = {
      enable = lib.mkEnableOption "Roundcube webmail";
      hostname = lib.mkOption {
        type = lib.types.str;
        default = "webmail.localhost";
        description = "Hostname used by Roundcube webmail.";
      };
      backendPort = lib.mkOption {
        type = lib.types.port;
        default = 8083;
        description = "Local port used by the Roundcube nginx backend.";
      };
      oidcIssuer = lib.mkOption {
        type = lib.types.str;
        description = "OIDC issuer used by oauth2-proxy.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.maddy = {
      enable = true;
      inherit (cfg) hostname;
      inherit (cfg) primaryDomain;
      localDomains = [ cfg.primaryDomain ];
      openFirewall = false;
      ensureAccounts = builtins.attrNames cfg.accounts;
      ensureCredentials = cfg.accounts;
      tls = {
        loader = "file";
        certificates = [
          {
            certPath = "/var/lib/maddy/tls/mail.crt";
            keyPath = "/var/lib/maddy/tls/mail.key";
          }
        ];
      };
      config = maddyConfig;
    };

    networking.firewall.allowedTCPPorts = [
      25
      465
      587
      993
    ];

    systemd.services.maddy-certs = {
      description = "Install the Maddy TLS certificate";
      wantedBy = [ "maddy.service" ];
      before = [ "maddy.service" ];
      after = [ "caddy.service" ];
      wants = [ "caddy.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "maddy-certs" ''
          install -d -m 0750 -o maddy -g maddy /var/lib/maddy/tls
          install -m 0640 -o maddy -g maddy ${lib.escapeShellArg cfg.certificateSource} /var/lib/maddy/tls/mail.crt
          install -m 0640 -o maddy -g maddy ${lib.escapeShellArg cfg.keySource} /var/lib/maddy/tls/mail.key
        '';
      };
    };

    systemd.services.maddy-dkim-migrate = {
      description = "Migrate the Maddy DKIM key to the primary domain";
      wantedBy = [ "maddy.service" ];
      before = [ "maddy.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "maddy-dkim-migrate" ''
          old=/var/lib/maddy/dkim_keys/private.outworld66.ru_default
          new=/var/lib/maddy/dkim_keys/${cfg.primaryDomain}_default
          if [ -e "$old.key" ] && [ ! -e "$new.key" ]; then
            install -d -m 0750 -o maddy -g maddy /var/lib/maddy/dkim_keys
            install -m 0600 -o maddy -g maddy "$old.key" "$new.key"
            install -m 0640 -o maddy -g maddy "$old.dns" "$new.dns"
          fi
        '';
      };
    };

    systemd.services.maddy = {
      after = [ "maddy-dkim-migrate.service" ];
      requires = [ "maddy-dkim-migrate.service" ];
    };

    systemd.timers.maddy-certs = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
        Unit = "maddy-certs.service";
      };
    };

    services.roundcube = lib.mkIf cfg.webmail.enable {
      enable = true;
      hostName = cfg.webmail.hostname;
      extraConfig = ''
        $config['imap_host'] = 'ssl://${cfg.hostname}:993';
        $config['smtp_host'] = 'ssl://${cfg.hostname}:465';
        $config['smtp_user'] = '%u';
        $config['smtp_pass'] = '%p';
        $config['product_name'] = 'Outworld Mail';
      '';
    };

    services.nginx.virtualHosts.${cfg.webmail.hostname} = lib.mkIf cfg.webmail.enable {
      forceSSL = false;
      enableACME = false;
      listen = [
        {
          addr = "127.0.0.1";
          port = cfg.webmail.backendPort;
        }
      ];
    };

    services.oauth2-proxy = lib.mkIf cfg.webmail.enable {
      enable = true;
      provider = "oidc";
      oidcIssuerUrl = cfg.webmail.oidcIssuer;
      clientID = "oauth2-proxy";
      clientSecretFile = "/var/lib/oauth2-proxy/client-secret";
      cookie.domain = ".outworld66.ru";
      cookie.secretFile = "/var/lib/oauth2-proxy/cookie-secret";
      redirectURL = "https://auth.outworld66.ru/oauth2/callback";
      httpAddress = "http://127.0.0.1:4180";
      upstream = [ "static://200" ];
      scope = "openid profile email groups";
      reverseProxy = true;
      trustedProxyIP = [ "127.0.0.1" ];
      setXauthrequest = true;
      email.domains = [ "*" ];
      extraConfig = {
        allowed-group = "admins";
        oidc-groups-claim = "groups";
      };
    };

    systemd.services.oauth2-proxy-secret = lib.mkIf cfg.webmail.enable {
      description = "Generate OAuth2 proxy cookie secret";
      before = [ "oauth2-proxy.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "oauth2-proxy-secret" ''
          install -d -m 0750 -o oauth2-proxy -g oauth2-proxy /var/lib/oauth2-proxy
          if [ ! -s /var/lib/oauth2-proxy/cookie-secret ] || [ "$(wc -c < /var/lib/oauth2-proxy/cookie-secret)" -ne 32 ]; then
            umask 077
            head -c 32 /dev/urandom > /var/lib/oauth2-proxy/cookie-secret
          fi
          chown oauth2-proxy:oauth2-proxy /var/lib/oauth2-proxy/cookie-secret
          chmod 0400 /var/lib/oauth2-proxy/cookie-secret
        '';
      };
    };

    systemd.services.oauth2-proxy = lib.mkIf cfg.webmail.enable {
      after = [
        "oauth2-proxy-secret.service"
        "pocket-id-oidc-provision.service"
      ];
      requires = [
        "oauth2-proxy-secret.service"
        "pocket-id-oidc-provision.service"
      ];
    };
  };
}
