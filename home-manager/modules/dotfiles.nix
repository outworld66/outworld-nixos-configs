{
  config,
  pkgs,
  user,
  gitUsername,
  gitMail,
  configDirectory,
  ...
}:

let
  # Keep the links writable, as in the source repository: applications edit the
  # files in the checkout instead of immutable copies in the Nix store.
  dotfilesDirectory = "${configDirectory}/home-manager/dotfiles";

  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfilesDirectory}/${path}";

  gitConfig = pkgs.replaceVars ../dotfiles/git/config {
    inherit user gitUsername gitMail;
    gitCredentialManager = "${pkgs.git-credential-manager}/bin/git-credential-manager-core";
  };

  configLinks = [
    "niri"
    "btop"
    "kitty"
    "yazi"
    "bat"
    "helix"
    "fish"
    "zed"
    "nvim"
    "tmux"
    "herdr"
    "zellij"
    "nushell"
    "ghostty"
    "wezterm"
    "flameshot"
    "spicy"
    "atuin"
    "qt5ct"
    "qt6ct"
    "gtk-3.0"
    "gtk-4.0"
    "mpv"
    "superfile"
    "broot"
    "qalculate"
    "navi"
    "snappy-switcher"
    "espanso"
    "tealdeer"
    "wlr-which-key"
    "libvirt"
    "xsettingsd"
    "cheat"
    "glow"
    "gh-dash"
    "fastfetch"
    "opencode/command"
    "opencode/plugins"
    "scripts"
    "vesktop/settings"
    "vesktop/themes"
    "vesktop/settings.json"
    "VSCodium/User/settings.json"
    "VSCodium/User/keybindings.json"
    "starship.toml"
    "mimeapps.list"
  ];
in
{
  home.file =
    builtins.listToAttrs (
      map (path: {
        name = ".config/${path}";
        # Private companion modules may replace selected public defaults.
        value.source = pkgs.lib.mkDefault (link path);
      }) configLinks
    )
    // {
      ".config/git/config".source = gitConfig;
    };
}
