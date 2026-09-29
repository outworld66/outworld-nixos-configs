{
  config,
  inputs,
  lib,
  pkgs,
  system,
  ...
}:
let
  cfg = config.server.mail;
  unstable = inputs.nixpkgs-unstable.legacyPackages.${system};
  stalwart = unstable.stalwart_0_16;
  cli = unstable.stalwart-cli;
  dataDir = "/var/lib/stalwart";
  configFile = pkgs.writeText "stalwart-config.json" (
    builtins.toJSON {
      "@type" = "RocksDb";
      path = "${dataDir}/db";
    }
  );
  resolverConfig = pkgs.writeText "stalwart-dns-resolver.json" (
    builtins.toJSON {
      "@type" = "Custom";
      servers."0" = {
        address = "192.168.0.1";
        port = 53;
        protocol = "tcp";
      };
      attempts = 2;
      concurrency = 2;
      enableEdns = true;
      preserveIntermediates = true;
      tcpOnError = true;
      timeout = 5000;
    }
  );
  accountEntries = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (email: account: ''
      ${pkgs.jq}/bin/jq -cn \
        --arg key ${lib.escapeShellArg ("account-" + builtins.head (lib.splitString "@" email))} \
        --arg name ${lib.escapeShellArg (builtins.head (lib.splitString "@" email))} \
        --rawfile password ${lib.escapeShellArg (toString account.passwordFile)} \
        '{key:$key,value:{"@type":"User",name:$name,domainId:"#domain",credentials:{"0":{"@type":"Password",secret:($password|rtrimstr("\n"))}},roles:{"@type":"User"},permissions:{"@type":"Inherit"},quotas:{},aliases:{},memberGroupIds:{},encryptionAtRest:{"@type":"Disabled"}}}' \
        >> "$tmp/accounts.ndjson"
    '') cfg.accounts
  );
  launcher = pkgs.writeShellScript "stalwart-launch" ''
    set -euo pipefail

    if [ ! -e ${dataDir}/.configured ]; then
      tmp=$(${pkgs.coreutils}/bin/mktemp -d)
      recovery_pid=
      cleanup() {
        if [ -n "$recovery_pid" ]; then
          kill -INT "$recovery_pid" 2>/dev/null || true
          wait "$recovery_pid" 2>/dev/null || true
        fi
        ${pkgs.coreutils}/bin/rm -rf "$tmp"
      }
      trap cleanup EXIT INT TERM

      test -r /var/lib/stalwart/tls/cert.pem
      test -r /var/lib/stalwart/tls/key.pem
      if [ ! -s ${dataDir}/dkim.key ]; then
        ${pkgs.openssl}/bin/openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out ${dataDir}/dkim.key
        ${pkgs.coreutils}/bin/chmod 0600 ${dataDir}/dkim.key
      fi

      admin_password=$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/admin-password")
      STALWART_RECOVERY_MODE=1 \
      STALWART_RECOVERY_MODE_PORT=18080 \
      STALWART_RECOVERY_ADMIN="admin:$admin_password" \
        ${stalwart}/bin/stalwart --config=${configFile} &
      recovery_pid=$!

      ${pkgs.curl}/bin/curl --fail --silent --show-error --retry 60 --retry-connrefused --retry-delay 1 \
        --user "admin:$admin_password" http://127.0.0.1:18080/jmap/session >/dev/null

      : > "$tmp/accounts.ndjson"
      ${pkgs.jq}/bin/jq -cn --arg name admin --rawfile password "$CREDENTIALS_DIRECTORY/admin-password" \
        '{key:"admin",value:{"@type":"User",name:$name,domainId:"#domain",credentials:{"0":{"@type":"Password",secret:($password|rtrimstr("\n"))}},roles:{"@type":"Admin"},permissions:{"@type":"Inherit"},quotas:{},aliases:{},memberGroupIds:{},encryptionAtRest:{"@type":"Disabled"}}}' \
        >> "$tmp/accounts.ndjson"
      ${accountEntries}
      ${pkgs.jq}/bin/jq -sc 'map({(.key):.value})|add' "$tmp/accounts.ndjson" > "$tmp/accounts.json"

      ${pkgs.jq}/bin/jq -cn \
        --arg hostname ${lib.escapeShellArg cfg.hostname} \
        --arg domain ${lib.escapeShellArg cfg.primaryDomain} \
        --arg tlsKey ${lib.escapeShellArg "${dataDir}/tls/key.pem"} \
        --arg dkimKey ${lib.escapeShellArg "${dataDir}/dkim.key"} \
        --slurpfile accounts "$tmp/accounts.json" \
        --rawfile certificate ${lib.escapeShellArg "${dataDir}/tls/cert.pem"} \
        '[
          {"@type":"upsert","object":"Domain","matchOn":["name"],"value":{"domain":{"name":$domain,"isEnabled":true,"dkimManagement":{"@type":"Manual"}}}},
          {"@type":"create","object":"Certificate","value":{"cert":{"certificate":{"@type":"Text","value":$certificate},"privateKey":{"@type":"File","filePath":$tlsKey}}}},
          {"@type":"upsert","object":"NetworkListener","matchOn":["name"],"value":{
            "smtp":{"name":"smtp","protocol":"smtp","bind":{"[::]:25":true}},
            "submission":{"name":"submission","protocol":"smtp","bind":{"[::]:587":true}},
            "submissions":{"name":"submissions","protocol":"smtp","bind":{"[::]:465":true},"tlsImplicit":true},
            "imaptls":{"name":"imaptls","protocol":"imap","bind":{"[::]:993":true},"tlsImplicit":true},
            "http":{"name":"http","protocol":"http","bind":{"127.0.0.1:8080":true}}
          }},
          {"@type":"upsert","object":"DkimSignature","matchOn":["selector","domainId"],"value":{"dkim":{"@type":"Dkim1RsaSha256","domainId":"#domain","privateKey":{"@type":"File","filePath":$dkimKey},"selector":"rico","stage":"active"}}},
          {"@type":"upsert","object":"Account","matchOn":["name","domainId"],"value":$accounts[0]},
          {"@type":"update","object":"SystemSettings","value":{"defaultDomainId":"#domain","defaultHostname":$hostname,"defaultCertificateId":"#cert"}}
        ]' | ${pkgs.jq}/bin/jq -c '.[]' > "$tmp/plan.ndjson"

      STALWART_URL=http://127.0.0.1:18080 \
      STALWART_USER=admin \
      STALWART_PASSWORD="$admin_password" \
      XDG_CACHE_HOME=/var/cache/stalwart \
        ${cli}/bin/stalwart-cli apply --file "$tmp/plan.ndjson"

      kill -INT "$recovery_pid"
      wait "$recovery_pid" || true
      recovery_pid=
      touch ${dataDir}/.configured
      trap - EXIT INT TERM
      ${pkgs.coreutils}/bin/rm -rf "$tmp"
    fi

    exec ${stalwart}/bin/stalwart --config=${configFile}
  '';
  provisionScript = pkgs.writeShellScriptBin "stalwart-provision-pocket-users" ''
    set -euo pipefail
    : "''${POCKET_ID_API_KEY_FILE:?set POCKET_ID_API_KEY_FILE}"
    api_key=$(${pkgs.coreutils}/bin/cat "$POCKET_ID_API_KEY_FILE")
    pocket_api="''${POCKET_ID_URL:-http://127.0.0.1:1411}/api"
    allowed_groups="''${STALWART_ALLOWED_GROUPS:-mail-admin,mail-user}"
    tmp=$(${pkgs.coreutils}/bin/mktemp -d)
    trap '${pkgs.coreutils}/bin/rm -rf "$tmp"' EXIT
    : > "$tmp/desired"
    ${pkgs.curl}/bin/curl --fail --silent --show-error -H "X-API-KEY: $api_key" \
      "$pocket_api/users?pagination%5Blimit%5D=1000" \
      | ${pkgs.jq}/bin/jq -c '.data[] | select(.emailVerified == true) | {email,id}' \
      | while IFS= read -r user; do
        email=$(printf '%s' "$user" | ${pkgs.jq}/bin/jq -er .email)
        user_id=$(printf '%s' "$user" | ${pkgs.jq}/bin/jq -er .id)
        groups=$(${pkgs.curl}/bin/curl --fail --silent --show-error -H "X-API-KEY: $api_key" "$pocket_api/users/$user_id/groups")
        if printf '%s' "$groups" | ${pkgs.jq}/bin/jq -e --arg allowed "$allowed_groups" \
          '($allowed | split(",")) as $names | any(.[]; .name as $name | $names | index($name))' >/dev/null; then
          printf '%s\n' "$email" >> "$tmp/desired"
        fi
      done

    domain="''${STALWART_DOMAIN:-${cfg.primaryDomain}}"
    domain_id=$(${cli}/bin/stalwart-cli query Domain --json --fields id,name \
      | ${pkgs.jq}/bin/jq -er --arg domain "$domain" 'select(.name==$domain)|.id')
    current=$(${cli}/bin/stalwart-cli query Account --json --fields id,emailAddress,permissions)
    while IFS= read -r email; do
      [ -n "$email" ] || continue
      localpart=''${email%%@*}
      account=$(printf '%s\n' "$current" | ${pkgs.jq}/bin/jq -c --arg email "$email" 'select(.emailAddress==$email)')
      if [ -z "$account" ]; then
        ${pkgs.jq}/bin/jq -cn --arg name "$localpart" --arg domain "$domain_id" \
          '{"@type":"User",name:$name,domainId:$domain,credentials:{},roles:{"@type":"User"},permissions:{"@type":"Inherit"},quotas:{},aliases:{},memberGroupIds:{},encryptionAtRest:{"@type":"Disabled"}}' \
          | ${cli}/bin/stalwart-cli create Account/User --stdin >/dev/null
      elif printf '%s' "$account" | ${pkgs.jq}/bin/jq -e '.permissions.disabledPermissions.authenticate == true' >/dev/null; then
        id=$(printf '%s' "$account" | ${pkgs.jq}/bin/jq -er .id)
        ${cli}/bin/stalwart-cli update Account "$id" --json \
          '{"permissions":{"@type":"Inherit"}}' >/dev/null
      fi
    done < "$tmp/desired"

    printf '%s\n' "$current" | ${pkgs.jq}/bin/jq -r '.emailAddress // empty' | while IFS= read -r email; do
      [ "$email" = "admin@${cfg.primaryDomain}" ] && continue
      [ "$email" = "pocket-id@${cfg.primaryDomain}" ] && continue
      if ! ${pkgs.gnugrep}/bin/grep -Fqx "$email" "$tmp/desired"; then
        id=$(printf '%s\n' "$current" | ${pkgs.jq}/bin/jq -er --arg email "$email" 'select(.emailAddress==$email)|.id')
        ${cli}/bin/stalwart-cli update Account "$id" --json \
          '{"permissions":{"@type":"Merge","disabledPermissions":{"authenticate":true}}}' >/dev/null
      fi
    done
  '';
  dkimDnsScript = pkgs.writeShellScriptBin "stalwart-dkim-dns" ''
    set -euo pipefail
    export STALWART_URL="''${STALWART_URL:-http://127.0.0.1:8080}"
    export STALWART_USER="''${STALWART_USER:-admin@${cfg.primaryDomain}}"
    password_file="''${STALWART_PASSWORD_FILE:-${cfg.adminPasswordFile}}"
    if [ -z "''${STALWART_PASSWORD:-}" ]; then
      STALWART_PASSWORD=$(${pkgs.coreutils}/bin/cat "$password_file")
    fi
    export STALWART_PASSWORD
    domain="''${STALWART_DOMAIN:-${cfg.primaryDomain}}"
    domain_id=$(${cli}/bin/stalwart-cli query Domain --json --fields id,name \
      | ${pkgs.jq}/bin/jq -er --arg domain "$domain" 'select(.name==$domain)|.id')
    signature=$(${cli}/bin/stalwart-cli query DkimSignature --json \
      --fields domainId,selector,publicKey,stage \
      | ${pkgs.jq}/bin/jq -sc --arg id "$domain_id" '[.[]|select(.domainId==$id and .stage=="active")] | if length == 1 then .[0] else error("expected exactly one active DKIM signature") end')
    selector=$(${pkgs.jq}/bin/jq -er .selector <<<"$signature")
    public_key=$(${pkgs.jq}/bin/jq -er .publicKey <<<"$signature")
    tmp=$(${pkgs.coreutils}/bin/mktemp -d)
    trap '${pkgs.coreutils}/bin/rm -rf "$tmp"' EXIT
    printf '%s' "$public_key" | ${pkgs.coreutils}/bin/base64 -d > "$tmp/public.der"
    value=$(${pkgs.openssl}/bin/openssl rsa -pubin -inform DER -in "$tmp/public.der" -RSAPublicKey_out -outform DER 2>/dev/null \
      | ${pkgs.coreutils}/bin/base64 -w0)
    printf 'DNS name: %s._domainkey.%s\nTXT value: v=DKIM1; k=rsa; p=%s\n' \
      "$selector" "$domain" "$value"
  '';
in
{
  options.server.mail = {
    enable = lib.mkEnableOption "Stalwart mail server";
    hostname = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
    };
    primaryDomain = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
    };
    adminPasswordFile = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/stalwart/admin-password";
    };
    accounts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.passwordFile = lib.mkOption { type = lib.types.path; };
        }
      );
      default = { };
    };
    certificateSource = lib.mkOption { type = lib.types.path; };
    keySource = lib.mkOption { type = lib.types.path; };
  };

  config = lib.mkIf cfg.enable {
    users.groups.stalwart = { };
    users.users.stalwart = {
      isSystemUser = true;
      group = "stalwart";
    };
    systemd.tmpfiles.rules = [ "d '${dataDir}' 0750 stalwart stalwart - -" ];
    systemd.services.stalwart = {
      description = "Stalwart Mail Server";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "stalwart-certs.service"
      ];
      requires = [ "stalwart-certs.service" ];
      serviceConfig = {
        Type = "simple";
        User = "stalwart";
        Group = "stalwart";
        StateDirectory = "stalwart";
        StateDirectoryMode = "0750";
        CacheDirectory = "stalwart";
        ExecStart = launcher;
        LoadCredential = [ "admin-password:${cfg.adminPasswordFile}" ];
        Restart = "on-failure";
        RestartSec = 5;
        LimitNOFILE = 65536;
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
        KillSignal = "SIGINT";
        KillMode = "process";
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ dataDir ];
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        UMask = "0077";
      };
    };

    systemd.services.stalwart-dns-resolver = {
      description = "Configure Stalwart DNSSEC-capable resolver";
      wantedBy = [ "stalwart.service" ];
      after = [ "stalwart.service" ];
      requires = [ "stalwart.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "stalwart";
        Group = "stalwart";
        LoadCredential = [ "admin-password:${cfg.adminPasswordFile}" ];
        Environment = [
          "STALWART_URL=http://127.0.0.1:8080"
          "STALWART_USER=admin@${cfg.primaryDomain}"
          "XDG_CACHE_HOME=/var/cache/stalwart"
        ];
        ExecStart = pkgs.writeShellScript "stalwart-dns-resolver" ''
          set -euo pipefail
          export STALWART_PASSWORD=$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/admin-password")
          for _ in $(${pkgs.coreutils}/bin/seq 1 60); do
            if ${pkgs.curl}/bin/curl --fail --silent http://127.0.0.1:8080/jmap/session >/dev/null; then
              exec ${cli}/bin/stalwart-cli update DnsResolver --file ${resolverConfig}
            fi
            ${pkgs.coreutils}/bin/sleep 1
          done
          echo "Stalwart HTTP listener did not become ready" >&2
          exit 1
        '';
      };
    };

    systemd.services.stalwart-certs = {
      description = "Install the Stalwart TLS certificate";
      wantedBy = [ "stalwart.service" ];
      before = [ "stalwart.service" ];
      after = [ "caddy.service" ];
      wants = [ "caddy.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "stalwart-certs" ''
          set -eu
          until [ -r ${lib.escapeShellArg (toString cfg.certificateSource)} ] && [ -r ${lib.escapeShellArg (toString cfg.keySource)} ]; do ${pkgs.coreutils}/bin/sleep 1; done
          ${pkgs.coreutils}/bin/install -d -m 0750 -o stalwart -g stalwart ${dataDir}/tls
          ${pkgs.coreutils}/bin/install -m 0640 -o stalwart -g stalwart ${lib.escapeShellArg (toString cfg.certificateSource)} ${dataDir}/tls/cert.pem
          ${pkgs.coreutils}/bin/install -m 0640 -o stalwart -g stalwart ${lib.escapeShellArg (toString cfg.keySource)} ${dataDir}/tls/key.pem
        '';
      };
    };

    networking.firewall.allowedTCPPorts = [
      25
      465
      587
      993
    ];
    environment.systemPackages = [
      cli
      provisionScript
      dkimDnsScript
    ];

    systemd.services.stalwart-provision-pocket-users = {
      description = "Provision verified Pocket ID users in Stalwart";
      after = [
        "stalwart.service"
        "pocket-id.service"
      ];
      requires = [
        "stalwart.service"
        "pocket-id.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        Environment = [
          "XDG_CACHE_HOME=/var/cache/stalwart"
          "POCKET_ID_API_KEY_FILE=/var/lib/pocket-id/static-api-key"
          "STALWART_URL=http://127.0.0.1:8080"
          "STALWART_USER=admin@${cfg.primaryDomain}"
          "STALWART_PASSWORD_FILE=${cfg.adminPasswordFile}"
        ];
        ExecStart = pkgs.writeShellScript "stalwart-provision-pocket-users" ''
          set -eu
          export STALWART_PASSWORD=$(${pkgs.coreutils}/bin/cat "$STALWART_PASSWORD_FILE")
          exec ${provisionScript}/bin/stalwart-provision-pocket-users
        '';
      };
    };

    systemd.timers.stalwart-provision-pocket-users = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "5min";
        Persistent = true;
      };
    };
  };
}
