{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.server.gotify;
  pocketIdIssuer = "https://id.outworld66.ru";
  pocketIdOidcReady = pkgs.writeShellScript "gotify-pocket-id-oidc-ready" ''
    for _ in $(${pkgs.coreutils}/bin/seq 1 60); do
      if ${pkgs.curl}/bin/curl --fail --silent --show-error --max-time 3 \
        "${pocketIdIssuer}.well-known/openid-configuration" \
        | ${pkgs.jq}/bin/jq -e '.id_token_signing_alg_values_supported | index("RS256") != null' >/dev/null; then
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 2
    done
    echo "Pocket ID Gotify OIDC provider is not ready with RS256" >&2
    exit 1
  '';
  gotifySrc = pkgs.fetchFromGitHub {
    owner = "gotify";
    repo = "server";
    tag = "v3.1.0";
    hash = "sha256-s3oU6mEvhbguLHcLUaavDlR44EX7sDnd0SxrtbMCeyI=";
  };
  gotifyUi = pkgs.gotify-server.ui.overrideAttrs (_: {
    version = "3.1.0";
    src = "${gotifySrc}/ui";
    yarnOfflineCache = pkgs.fetchYarnDeps {
      yarnLock = "${gotifySrc}/ui/yarn.lock";
      hash = "sha256-PUO8HWTjtZfzWtLkDa827HoRx0LBxxO11My3mhito+I=";
    };
  });
  gotifyPackage = pkgs.gotify-server.overrideAttrs (_: {
    version = "3.1.0";
    src = gotifySrc;
    ui = gotifyUi;
    vendorHash = "sha256-ERRPIRZFhJN+QKEwBbZVUKTaTOLrlC+cb8yQNGHgMxg=";
  });
in
{
  options.server.gotify.enable = lib.mkEnableOption "gotify service";

  config = lib.mkIf cfg.enable {
    users.groups.gotify = { };
    users.users.gotify = {
      isSystemUser = true;
      group = "gotify";
    };

    services.gotify = {
      enable = true;
      package = gotifyPackage;
      environment = {
        GOTIFY_SERVER_PORT = 8090;
        GOTIFY_DATABASE_DIALECT = "sqlite3";
        GOTIFY_OIDC_ENABLED = "true";
        GOTIFY_OIDC_ISSUER = pocketIdIssuer;
        GOTIFY_OIDC_CLIENTID = "gotify";
        GOTIFY_OIDC_REDIRECTURL = "https://gotify.outworld66.ru/auth/oidc/callback";
        GOTIFY_OIDC_AUTOREGISTER = "true";
        GOTIFY_OIDC_USERNAMECLAIM = "preferred_username";
        GOTIFY_OIDC_LINK_BY_USERNAME = "true";
        GOTIFY_OIDC_SCOPES = "openid,profile,email,groups";
        GOTIFY_OIDC_PROMPT = "";
        GOTIFY_OIDC_GROUPS_CLAIM = "groups";
        GOTIFY_OIDC_GROUPS_USER = "gotify-user";
        GOTIFY_OIDC_GROUPS_ADMIN = "gotify-admin";
      };
      environmentFiles = [
        "/var/lib/gotify/default.env"
        "/var/lib/gotify/oidc.env"
      ];
    };

    systemd.services.gotify-default-password = {
      description = "Generate the Gotify bootstrap password";
      before = [ "gotify-server.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "gotify-default-password" ''
          install -d -m 0750 -o gotify -g gotify /var/lib/gotify
          if [ ! -s /var/lib/gotify/default-password ]; then
            umask 077
            head -c 32 /dev/urandom | base64 -w0 > /var/lib/gotify/default-password
          fi
          chown gotify:gotify /var/lib/gotify/default-password
          chmod 0400 /var/lib/gotify/default-password
          cat > /var/lib/gotify/default.env <<EOF
          GOTIFY_DEFAULTUSER_NAME=admin
          GOTIFY_DEFAULTUSER_PASS_FILE=/var/lib/gotify/default-password
          EOF
          chown gotify:gotify /var/lib/gotify/default.env
          chmod 0400 /var/lib/gotify/default.env
        '';
        User = lib.mkForce "root";
        Group = lib.mkForce "root";
      };
    };

    systemd.services.gotify-server = {
      after = [
        "gotify-default-password.service"
        "pocket-id-oidc-provision.service"
        "pocket-id.service"
      ];
      requires = [
        "gotify-default-password.service"
        "pocket-id-oidc-provision.service"
        "gotify-default-password.service"
        "pocket-id-oidc-provision.service"
        "pocket-id.service"
      ];
      serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = "gotify";
        Group = "gotify";
        RestartSec = "10s";
        ExecStartPre = [
          "+${pkgs.coreutils}/bin/chown -R gotify:gotify /var/lib/gotify-server"
          pocketIdOidcReady
        ];
      };
    };

    systemd.services.gotify-password-migrate = {
      description = "Replace the insecure Gotify bootstrap password";
      after = [ "gotify-server.service" ];
      requires = [ "gotify-server.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.curl ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "gotify-password-migrate" ''
          password=$(cat /var/lib/gotify/default-password)
          curl --fail --silent --show-error \
            -u "admin:admin" \
            -H 'Content-Type: application/json' \
            -X POST \
            -d "{\"pass\":\"$password\"}" \
            http://127.0.0.1:8090/current/user/password >/dev/null || true
        '';
      };
    };
  };
}
