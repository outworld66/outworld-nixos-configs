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
  };

  config = lib.mkIf cfg.enable {
    services.maddy = {
      enable = true;
      inherit (cfg) hostname;
      inherit (cfg) primaryDomain;
      localDomains = [ cfg.primaryDomain ];
      openFirewall = true;
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
      465
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
  };
}
