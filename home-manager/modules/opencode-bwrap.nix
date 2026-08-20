{
  pkgs,
  ...
}:

let
  # ── Sandbox config ──────────────────────────────────────────────────────
  # Relaxed permissions for the sandboxed opencode.  The sandbox itself
  # constrains filesystem access; inside it we can safely auto-approve
  # tools that would normally require confirmation.

  sandboxConfig = pkgs.writeTextDir "opencode/opencode.json" (
    builtins.toJSON {
      "$schema" = "https://opencode.ai/config.json";
      plugin = [
        "oh-my-openagent@latest"
        "@plannotator/opencode@latest"
      ];
      permission = {
        bash = {
          "*" = "allow";
          "rm *" = "deny";
          "sudo *" = "deny";
          "chmod *" = "deny";
        };
        read = {
          "*" = "allow";
          "*.env" = "deny";
          "*.env.*" = "deny";
          "*.p12" = "deny";
          "*.key" = "deny";
          "*.pem" = "deny";
          "~/.ssh/*" = "deny";
          "~/.aws/*" = "deny";
          "~/.kube/*" = "deny";
          "~/.docker/*" = "deny";
          "*/secrets/*" = "deny";
          "*/credentials/*" = "deny";
        };
        glob = {
          "*" = "allow";
        };
        grep = {
          "*" = "allow";
        };
        task = {
          "*" = "allow";
        };
        skill = {
          "*" = "allow";
        };
        external_directory = {
          "*" = "allow";
        };
        doom_loop = "allow";
      };
      mcp = {
        flux-schema-catalog = {
          type = "remote";
          url = "https://schemas.fluxoperator.dev/mcp";
          enabled = true;
        };
        siderolabs-docs = {
          type = "remote";
          url = "https://docs.siderolabs.com/mcp";
          enabled = true;
        };
        context7 = {
          type = "local";
          command = [
            "npx"
            "-y"
            "@upstash/context7-mcp"
            "--api-key"
            "{file:~/.secrets/context7-api-key}"
          ];
          enabled = true;
        };
        drawio = {
          type = "local";
          enabled = true;
          command = [
            "npx"
            "@drawio/mcp"
          ];
        };
      };
    }
  );

  sandboxConfigPath = "${sandboxConfig}/opencode";

  opencodeSandbox = pkgs.writeShellApplication {
    name = "opencode-sandbox";
    runtimeInputs = with pkgs; [
      bubblewrap
      coreutils
    ];

    text = ''
      set -euo pipefail

      # ── Sandbox directories ──────────────────────────────────────────
      # tmpfiles.rules ensure these exist, but mkdir -p is a safety net
      # for the very first launch after a fresh install.

      OP_DATA="$HOME/.local/share/opencode"
      OP_CACHE="$HOME/.cache/opencode"
      OP_STATE="$HOME/.local/state/opencode"

      # Sandbox-specific config dir — separate from the normal
      # ~/.config/opencode so that the relaxed permissions don't leak
      # into the unsandboxed session.
      OP_SANDBOX_CONFIG="$HOME/.config/opencode-sandbox"

      mkdir -p "$OP_DATA" "$OP_CACHE" "$OP_STATE" "$OP_SANDBOX_CONFIG"

      # Populate the sandbox config dir if the generated file is newer.
      # Uses cp --update=none to avoid overwriting user modifications
      # (e.g. plugin state) that may have been written inside the sandbox.
      cp --update=none --no-dereference \
          "${sandboxConfigPath}/opencode.json" \
          "$OP_SANDBOX_CONFIG/opencode.json" 2>/dev/null || true

      # ── Workspace (current directory) ────────────────────────────────
      WORKSPACE="$(pwd)"

      # ── Collect optional read-only binds ─────────────────────────────
      RO_BINDS=()

      # API keys used by opencode providers
      [[ -d "$HOME/.secrets" ]]   && RO_BINDS+=(--ro-bind-try "$HOME/.secrets"   "$HOME/.secrets")

      # Git identity
      [[ -f "$HOME/.gitconfig" ]] && RO_BINDS+=(--ro-bind-try "$HOME/.gitconfig" "$HOME/.gitconfig")

      # GitHub CLI (gh) auth
      [[ -d "$HOME/.config/gh" ]] && RO_BINDS+=(--ro-bind-try "$HOME/.config/gh"  "$HOME/.config/gh")

      # ── NixOS-specific paths ─────────────────────────────────────────
      # Every executable lives in /nix/store; bind it read-only so that
      # npx, uvx, bash, git, node … all resolve.
      # /run/current-system is the system profile symlink.
      # /etc is needed for resolv.conf, SSL certs, nix daemon config.

      NIX_BINDS=()
      [[ -d /nix/store ]]          && NIX_BINDS+=(--ro-bind /nix/store /nix/store)
      [[ -d /run/current-system ]] && NIX_BINDS+=(--ro-bind /run/current-system /run/current-system)

      # Nix daemon socket — required for nix build/develop.
      # ro-bind is enough: the socket mediates all writes.
      [[ -S /nix/var/nix/daemon-socket/socket ]] && \
          NIX_BINDS+=(--ro-bind /nix/var/nix/daemon-socket /nix/var/nix/daemon-socket)

      # Home-manager profile wrappers
      [[ -d /etc/profiles/per-user ]] && NIX_BINDS+=(--ro-bind /etc/profiles/per-user /etc/profiles/per-user)

      # ── Launch sandbox ──────────────────────────────────────────────
      # The sandbox config dir is mounted as ~/.config/opencode so
      # opencode picks up the relaxed permissions.  XDG_CONFIG_HOME
      # stays at the default ~/.config so other apps (gh, git, etc.)
      # still find their own configs under ~/.config/gh and friends.
      # Data, cache and state dirs are shared with the normal session.

      exec bwrap \
          --unshare-all \
          --share-net \
          --die-with-parent \
          --new-session \
          \
          --proc /proc \
          --dev /dev \
          --tmpfs /tmp \
          --tmpfs "/run/user/$(id -u)" \
          \
          --ro-bind /etc /etc \
          "''${NIX_BINDS[@]}" \
          \
          --dir "$HOME" \
          --dir "$HOME/.config" \
          --setenv HOME "$HOME" \
          --setenv PATH "$PATH" \
          --setenv TERM "$TERM" \
          --setenv TMPDIR /tmp \
          ''${NIX_SSL_CERT_FILE:+--setenv NIX_SSL_CERT_FILE "$NIX_SSL_CERT_FILE"} \
          ''${SSL_CERT_FILE:+--setenv SSL_CERT_FILE "$SSL_CERT_FILE"} \
          --chdir "$WORKSPACE" \
          \
          --bind "$OP_SANDBOX_CONFIG" "$HOME/.config/opencode" \
          --bind "$OP_DATA"  "$HOME/.local/share/opencode" \
          --bind "$OP_CACHE" "$HOME/.cache/opencode" \
          --bind "$OP_STATE" "$HOME/.local/state/opencode" \
          \
          --bind "$WORKSPACE" "$WORKSPACE" \
          \
          "''${RO_BINDS[@]}" \
          \
          -- opencode "$@"
    '';
  };
in
{
  home.packages = [ opencodeSandbox ];

  # Ensure sandbox directories exist on activation.
  systemd.user.tmpfiles.rules = [
    "d %h/.local/share/opencode   0750 - - -"
    "d %h/.local/state/opencode    0750 - - -"
    "d %h/.cache/opencode          0750 - - -"
    "d %h/.config/opencode-sandbox 0750 - - -"
    "d %h/.secrets                  0700 - - -"
  ];
}
