{ inputs, ... }:
{
  imports = [ inputs.umbriel.homeModules.default ];

  programs.umbriel = {
    enable = true;
    settings = {
      input.keyboard = {
        layout = "us,ru";
        options = "grp:lalt_lshift_toggle,compose:ralt,ctrl:nocaps";
      };

      keybinds = {
        "Mod+T" = "spawn:alacritty";
        "Mod+D" = "spawn:vicinae open";
        "Mod+L" = "spawn:noctalia msg session lock";
        "Mod+Q" = "window-close";
        "Mod+Left" = "window-focus-left";
        "Mod+Right" = "window-focus-right";
        "Mod+Up" = "window-focus-up";
        "Mod+Down" = "window-focus-down";
        "Mod" = "spawn:noctalia msg panel-toggle launcher";
        "XF86AudioRaiseVolume" = "spawn:noctalia msg volume-up";
        "XF86AudioLowerVolume" = "spawn:noctalia msg volume-down";
        "XF86AudioMute" = "spawn:noctalia msg volume-mute";
        "XF86MonBrightnessUp" = "spawn:noctalia msg brightness-up";
        "XF86MonBrightnessDown" = "spawn:noctalia msg brightness-down";
      };
    };
  };
}
