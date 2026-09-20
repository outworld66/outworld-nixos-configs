{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  # Full upstream bar.json, expressed as Nix so every change is reviewable
  # and reproduced by `home-manager switch`.
  barConfig = {
    availableOnFullscreen = true;
    barColor = [
      [
        "surface"
        0
      ]
    ];
    containBar = false;
    enableFirefoxPlayer = false;
    frameEnabled = false;
    frameThickness = 8;
    hoverRegionHeight = 8;
    hoverToReveal = true;
    keepBarBorder = false;
    keepBarShadow = false;
    launcherIcon = "";
    launcherIconFullTint = true;
    launcherIconSize = 18;
    launcherIconTint = true;
    pillStyle = "default";
    pinnedOnStartup = true;
    position = "top";
    screenList = [ ];
    showPinButton = true;
    use12hFormat = false;
  };

  # These domains are absent from the upstream visual preset but are part of
  # Ambxst's complete config and would otherwise be generated at runtime.
  extraConfig = {
    ai = {
      systemPrompt = "You are a helpful assistant running on a Linux system. You have access to some tools to control the system.";
      tool = "none";
      extraModels = [ ];
      defaultModel = "gemini-2.0-flash";
      sidebarWidth = 400;
      sidebarPosition = "right";
      sidebarPinnedOnStartup = false;
    };
    general = {
      terminal = "kitty";
      terminalAdvanced = false;
      terminalCommand = "$TERMINAL -e $COMMAND";
    };
    prefix = {
      clipboard = "cc";
      emoji = "ee";
      tmux = "tt";
      wallpapers = "ww";
      notes = "nn";
    };
    weather = {
      location = "";
      unit = "C";
    };
  };

  configFiles = lib.mapAttrsToList (name: value: {
    inherit name;
    path = pkgs.writeText "ambxst-${name}.json" (builtins.toJSON value);
  }) ({ bar = barConfig; } // extraConfig);
in
{
  # The upstream preset supplies the large theme/compositor JSON files.
  # Local JSON generated below overrides the domains owned by this config.
  home.activation.ambxstConfig = ''
    ambxst_config="$HOME/.config/ambxst/config"
    mkdir -p "$ambxst_config"
    for config_file in "${inputs.ambxst}/assets/presets/Ambxst Default"/*.json; do
      [ -e "$config_file" ] || continue
      install -Dm644 "$config_file" "$ambxst_config/$(basename "$config_file")"
    done
    ${lib.concatMapStringsSep "\n" (
      configFile: "install -Dm644 ${configFile.path} \"$ambxst_config/${configFile.name}.json\""
    ) configFiles}

    # Niri parses includes before spawn-at-startup runs. Keep an empty,
    # writable first-generation file so the declarative config is valid on a
    # fresh install; Ambxst replaces it as soon as its daemon starts.
    ambxst_data="$HOME/.local/share/ambxst"
    mkdir -p "$ambxst_data"
    [ -e "$ambxst_data/niri.kdl" ] || : > "$ambxst_data/niri.kdl"
  '';

  # Upstream generates this file from compositor.json and binds.json and
  # rewrites it when those settings change; Niri only needs the include.
  xdg.configFile."ambxst/README-upstream".text = ''
    Ambxst configuration lives in ~/.config/ambxst/config/*.json and binds.json.
    The upstream preset is the base; local Nix overrides are applied on every switch.
    Change home-manager/modules/ambxst.nix and run home-manager switch.
  '';
}
