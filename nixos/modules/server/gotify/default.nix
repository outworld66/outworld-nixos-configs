{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.server.gotify;
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
      };
      environmentFiles = [
        "/var/lib/gotify/default.env"
        "/var/lib/gotify/oidc.env"
      ];
    };

    systemd.services.gotify-default-password = {
      description = "Generate the Gotify bootstrap password";
      before = [
        "gotify-server.service"
        "pocket-id-oidc-provision.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "gotify-default-password" ''
          install -d -m 0750 -o gotify -g gotify /var/lib/gotify
          if [ ! -s /var/lib/gotify/default-password ]; then
            umask 077
            head -c 32 /dev/urandom | base64 -w0 > /var/lib/gotify/default-password
            chown gotify:gotify /var/lib/gotify/default-password
            chmod 0400 /var/lib/gotify/default-password
          fi
          cat > /var/lib/gotify/default.env <<EOF
          GOTIFY_DEFAULTUSER_NAME=admin
          GOTIFY_DEFAULTUSER_PASS_FILE=/var/lib/gotify/default-password
          EOF
          chown gotify:gotify /var/lib/gotify/default.env
          chmod 0400 /var/lib/gotify/default.env
        '';
      };
    };

    systemd.services.pocket-id-oidc-provision = {
      after = [ "gotify-default-password.service" ];
      requires = [ "gotify-default-password.service" ];
    };

    systemd.services.gotify-server = {
      after = [ "pocket-id-oidc-provision.service" ];
      requires = [
        "gotify-default-password.service"
        "pocket-id-oidc-provision.service"
      ];
      serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = "gotify";
        Group = "gotify";
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
