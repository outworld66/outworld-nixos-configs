{ lib, ... }:

let
  controlChar = code: builtins.fromJSON ''"\u00${code}"'';

  # Ctrl+A..Z produce the C0 control characters U+0001..U+001A. With a
  # non-Latin layout Alacritty cannot derive them from the received text, so
  # map every Russian key at the same physical position explicitly.
  russianControlChars = {
    "Ф" = controlChar "01"; # A
    "И" = controlChar "02"; # B
    "С" = controlChar "03"; # C
    "В" = controlChar "04"; # D
    "У" = controlChar "05"; # E
    "А" = controlChar "06"; # F
    "П" = controlChar "07"; # G
    "Р" = controlChar "08"; # H
    "Ш" = controlChar "09"; # I
    "О" = controlChar "0a"; # J
    "Л" = controlChar "0b"; # K
    "Д" = controlChar "0c"; # L
    "Ь" = controlChar "0d"; # M
    "Т" = controlChar "0e"; # N
    "Щ" = controlChar "0f"; # O
    "З" = controlChar "10"; # P
    "Й" = controlChar "11"; # Q
    "К" = controlChar "12"; # R
    "Ы" = controlChar "13"; # S
    "Е" = controlChar "14"; # T
    "Г" = controlChar "15"; # U
    "М" = controlChar "16"; # V
    "Ц" = controlChar "17"; # W
    "Ч" = controlChar "18"; # X
    "Н" = controlChar "19"; # Y
    "Я" = controlChar "1a"; # Z
  };
in
{
  programs.alacritty = {
    enable = true;
    settings = {
      terminal.shell = {
        program = "zellij";
        args = [
          "options"
          "--default-shell"
          "fish"
        ];
      };

      window.opacity = 1.0;

      # Alacritty's own terminfo is often absent on SSH targets. Use the
      # widely available compatible entry so remote less/vim/tmux work.
      env.TERM = "xterm-256color";

      font = {
        builtin_box_drawing = true;
        normal = {
          #family = "JetBrainsMono Nerd Font";
          style = lib.mkForce "Bold";
        };
      };

      keyboard.bindings =
        (lib.mapAttrsToList (key: chars: {
          inherit key chars;
          mods = "Control";
        }) russianControlChars)
        ++ [
          # Wayland applications receive layout-dependent keysyms. Alacritty's
          # built-in Ctrl+Shift bindings therefore need Russian equivalents.
          {
            key = "М";
            mods = "Control|Shift";
            action = "Paste";
          }
          {
            key = "С";
            mods = "Control|Shift";
            action = "Copy";
          }
          {
            key = "А";
            mods = "Control|Shift";
            mode = "~Search";
            action = "SearchForward";
          }
          {
            key = "И";
            mods = "Control|Shift";
            mode = "~Search";
            action = "SearchBackward";
          }
        ];
    };
  };
}
