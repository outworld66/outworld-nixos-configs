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
      clientID = "roundcube";
      clientSecretFile = "/var/lib/roundcube/oidc-client-secret";
      cookie.secretFile = "/var/lib/roundcube/oauth2-cookie-secret";
      redirectURL = "https://${cfg.webmail.hostname}/oauth2/callback";
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

    systemd.services.roundcube-oauth2-secret = lib.mkIf cfg.webmail.enable {
      description = "Generate Roundcube OAuth2 proxy cookie secret";
      before = [ "oauth2-proxy.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "roundcube-oauth2-secret" ''
          install -d -m 0750 /var/lib/roundcube
          if [ ! -s /var/lib/roundcube/oauth2-cookie-secret ]; then
            umask 077
            head -c 32 /dev/urandom | base64 -w0 > /var/lib/roundcube/oauth2-cookie-secret
          fi
          chmod 0400 /var/lib/roundcube/oauth2-cookie-secret
        '';
      };
    };

    systemd.services.oauth2-proxy = lib.mkIf cfg.webmail.enable {
      after = [
        "roundcube-oauth2-secret.service"
        "pocket-id-oidc-provision.service"
      ];
      requires = [
        "roundcube-oauth2-secret.service"
        "pocket-id-oidc-provision.service"
      ];
    };
  };
}
