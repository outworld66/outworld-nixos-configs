{
  config,
  lib,
  pkgs,
  configDirectory,
  ...
}:

let
  codexNotify = pkgs.writeShellApplication {
    name = "codex-notify";
    runtimeInputs = [
      pkgs.jq
      pkgs.libnotify
    ];
    text = ''
      payload="''${1-}"
      if [[ -z "$payload" ]]; then
        payload="{}"
      fi

      if [[ "$(${pkgs.jq}/bin/jq -r '.type // empty' <<< "$payload")" != "agent-turn-complete" ]]; then
        exit 0
      fi

      cwd="$(${pkgs.jq}/bin/jq -r '.cwd // empty' <<< "$payload")"
      message="$(${pkgs.jq}/bin/jq -r '."last-assistant-message" // "Задача завершена"' <<< "$payload")"

      if [[ -n "$cwd" ]]; then
        title="Codex — ''${cwd##*/}"
      else
        title="Codex"
      fi

      notify-send \
        --app-name="Codex" \
        --icon="dialog-information" \
        "$title" \
        "$message"
    '';
  };

  codexNotifyApproval = pkgs.writeShellApplication {
    name = "codex-notify-approval";
    runtimeInputs = [
      pkgs.jq
      pkgs.libnotify
    ];
    text = ''
      payload="$(cat)"

      if ! ${pkgs.jq}/bin/jq -e '.hook_event_name == "PermissionRequest"' >/dev/null <<< "$payload"; then
        exit 0
      fi

      cwd="$(${pkgs.jq}/bin/jq -r '.cwd // empty' <<< "$payload")"
      message="$(${pkgs.jq}/bin/jq -r '.tool_input.description // "Требуется подтверждение в терминале"' <<< "$payload")"

      if [[ -n "$cwd" ]]; then
        title="Codex — ''${cwd##*/}"
      else
        title="Codex"
      fi

      notify-send \
        --app-name="Codex" \
        --icon="dialog-question" \
        --urgency="normal" \
        --expire-time="10000" \
        --hint="int:transient:1" \
        "$title" \
        "$message"
    '';
  };

  dotfilesDirectory = "${configDirectory}/home-manager/dotfiles";
in
{
  home.packages = [
    codexNotify
    codexNotifyApproval
  ];

  home.file.".codex/config.toml" = {
    source = lib.mkForce (config.lib.file.mkOutOfStoreSymlink "${dotfilesDirectory}/codex/config.toml");
    text = lib.mkForce null;
  };
}
