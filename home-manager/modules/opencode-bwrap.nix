{
  pkgs,
  ...
}:

let
  # ── Sandbox wrapper ────────────────────────────────────────────────────
  # Bubblewrap sandbox for opencode.  The sandbox config (opencode.json,
  # oh-my-openagent.json) lives in ~/.config/opencode-sandbox/ and is
  # populated declaratively by home-manager — NOT generated at runtime.
  # This module only provides the bwrap launcher and directory setup;
  # the actual config files are written by the private overlay.

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
      OP_SANDBOX_CONFIG="$HOME/.config/opencode-sandbox"

      mkdir -p "$OP_DATA" "$OP_CACHE" "$OP_STATE" "$OP_SANDBOX_CONFIG"

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

      # OpenCode skills (read-only, managed by home-manager)
      [[ -d "$HOME/.config/opencode/skills" ]] && RO_BINDS+=(--ro-bind-try "$HOME/.config/opencode/skills" "$HOME/.config/opencode/skills")

      # OpenCode custom commands and plugins (out-of-store symlinks)
      [[ -d "$HOME/.config/opencode/command" ]] && RO_BINDS+=(--ro-bind-try "$HOME/.config/opencode/command" "$HOME/.config/opencode/command")
      [[ -d "$HOME/.config/opencode/plugins" ]] && RO_BINDS+=(--ro-bind-try "$HOME/.config/opencode/plugins" "$HOME/.config/opencode/plugins")

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
      # opencode picks up the sandbox-specific permissions.  XDG_CONFIG_HOME
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
