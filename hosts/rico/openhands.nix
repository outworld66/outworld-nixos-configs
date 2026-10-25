{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  stateDirectory = "/var/lib/openhands";
  oldCodexAuth = "/var/lib/codex-web-panel/codex-home/auth.json";
  codex = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex;
  codexAcpNpx = pkgs.writeShellScriptBin "npx" ''
    # shortcut: intercepts Canvas's Codex preset command; update if its default changes.
    if [ "$#" -eq 2 ] && [ "$1" = "-y" ] && [ "$2" = "@zed-industries/codex-acp" ]; then
      exec ${pkgs.codex-acp}/bin/codex-acp
    fi
    exec ${pkgs.nodejs_24}/bin/npx "$@"
  '';
  codexAuthMigration = pkgs.writeShellScript "openhands-codex-auth-migration" ''
    set -eu
    source=${oldCodexAuth}
    destination=${stateDirectory}/.codex/auth.json
    if [ -s "$source" ] && [ ! -s "$destination" ]; then
      install -D -m 0600 -o openhands -g openhands "$source" "$destination"
    fi
  '';
  createApiKey = pkgs.writeShellScript "openhands-api-key" ''
    set -eu
    umask 077
    [ -s ${stateDirectory}/environment ] || printf 'LOCAL_BACKEND_API_KEY=%s\n' "$(${pkgs.openssl}/bin/openssl rand -base64 32)" > ${stateDirectory}/environment
    grep -q '^OH_SECRET_KEY=.' ${stateDirectory}/environment || printf 'OH_SECRET_KEY=%s\n' "$(${pkgs.openssl}/bin/openssl rand -hex 32)" >> ${stateDirectory}/environment
    printf 'OH_OIDC_CLIENT_SECRET=%s\n' "$(cat /var/lib/authentik/oidc-openhands-secret)" > ${stateDirectory}/oidc-environment
    ${pkgs.coreutils}/bin/chmod 0400 ${stateDirectory}/environment ${stateDirectory}/oidc-environment
  '';
  vpnRouteCheck = pkgs.writeShellScript "check-openhands-vpn-route" ''
    set -eu
    uid="$(${pkgs.coreutils}/bin/id -u openhands)"
    route="$(${pkgs.iproute2}/bin/ip -4 route get 1.1.1.1 uid "$uid")"
    case "$route" in
      *"dev vpn0"*) ;;
      *) echo "OpenHands has no AmneziaVPN route; refusing to start" >&2; exit 1 ;;
    esac
  '';
  rootlessDockerCheck = pkgs.writeShellScript "check-openhands-rootless-docker" ''
    set -eu
    for attempt in $(${pkgs.coreutils}/bin/seq 1 30); do
      if ${pkgs.docker}/bin/docker info >/dev/null 2>&1; then
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done
    echo "OpenHands rootless Docker daemon is unavailable" >&2
    exit 1
  '';
in
{
  virtualisation.docker.rootless = {
    enable = true;
    extraPackages = with pkgs; [
      fuse-overlayfs
      slirp4netns
    ];
  };

  users.groups.openhands = { };
  users.users.openhands = {
    isSystemUser = true;
    group = "openhands";
    uid = 980;
    linger = true;
    subUidRanges = [
      {
        startUid = 165536;
        count = 65536;
      }
    ];
    subGidRanges = [
      {
        startGid = 165536;
        count = 65536;
      }
    ];
    home = stateDirectory;
    createHome = true;
    shell = "${pkgs.shadow}/bin/nologin";
  };

  systemd.tmpfiles.rules = [ "d ${stateDirectory} 0700 openhands openhands -" ];

  systemd.services.openhands-api-key = {
    description = "Create a persistent OpenHands Agent Canvas API key";
    before = [ "openhands.service" ];
    requires = [ "authentik-secret.service" ];
    after = [ "authentik-secret.service" ];
    requiredBy = [ "openhands.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = createApiKey;
    };
  };

  systemd.services.openhands-codex-auth = {
    description = "Copy the existing Codex login to OpenHands once";
    before = [ "openhands.service" ];
    requiredBy = [ "openhands.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = codexAuthMigration;
    };
  };

  systemd.services.openhands = {
    description = "OpenHands Agent Canvas with Codex ACP";
    wantedBy = [ "multi-user.target" ];
    requires = [
      "openhands-codex-auth.service"
      "openhands-api-key.service"
      "authentik-secret.service"
      "user@980.service"
      "vpn.service"
    ];
    after = [
      "openhands-codex-auth.service"
      "openhands-api-key.service"
      "authentik-secret.service"
      "user@980.service"
      "vpn.service"
    ];
    partOf = [ "vpn.service" ];
    path = with pkgs; [
      codexAcpNpx
      pkgs.docker
      bash
      coreutils
      git
      nodejs_24
      python314
      uv
      codex
      openhands-agent-canvas
    ];
    environment = {
      CODEX_HOME = "${stateDirectory}/.codex";
      HOME = stateDirectory;
      LD_LIBRARY_PATH = lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ];
      NPM_CONFIG_UPDATE_NOTIFIER = "false";
      DOCKER_HOST = "unix:///run/user/980/docker.sock";
      OH_AGENT_SERVER_GIT_REF = "4a1bf8ff960181d5732b6294a4ebfbe49d5ce4b5";
      OH_CONVERSATION_RUNTIME = "docker";
      OH_OIDC_ISSUER_URL = "https://identity.outworld66.ru/application/o/openhands/";
      OH_OIDC_CLIENT_ID = "openhands";
      OH_OIDC_ALLOWED_GROUPS_0 = "ai-admin";
      OH_OIDC_ALLOWED_GROUPS_1 = "ai-user";
      OH_OIDC_ADMIN_GROUPS_0 = "ai-admin";
      UV_PYTHON_DOWNLOADS = "never";
    };
    serviceConfig = {
      EnvironmentFile = [
        "${stateDirectory}/environment"
        "${stateDirectory}/oidc-environment"
      ];
      ExecStartPre = [
        vpnRouteCheck
        rootlessDockerCheck
      ];
      ExecStart = "${pkgs.openhands-agent-canvas}/bin/agent-canvas --public";
      Restart = "on-failure";
      RestartSec = "5s";
      StateDirectory = "openhands";
      StateDirectoryMode = "0700";
      WorkingDirectory = stateDirectory;
      User = "openhands";
      Group = "openhands";
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = "read-only";
      ProtectSystem = "strict";
      ReadWritePaths = [ stateDirectory ];
      RestrictAddressFamilies = [
        "AF_NETLINK"
        "AF_UNIX"
        "AF_INET"
      ];
    };
  };
}
