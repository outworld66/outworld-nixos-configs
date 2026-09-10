{
  inputs,
  pkgs,
  ...
}:
let
  # Upstream patches, applied to the installed runtime only:
  # 1. SystemIcons: drop the embedded keyboard-layout indicator; it moves to
  #    its own bar widget (hyprlandXkbIndicator) with no upstream config flag.
  # 2. UtilButtons: replace the light-mode toggle with a "Keep awake"
  #    (caffeine) button that drives the built-in Idle inhibitor service.
  # The seds are no-ops if upstream changes the anchored lines.
  inirPatched =
    (pkgs.callPackage "${inputs.inir}/nix/package.nix" { inherit pkgs; }).overrideAttrs
      (old: {
        postInstall = (old.postInstall or "") + ''
          sed -i 's/active: KeyboardIndicators.hasPanelIndicators/active: false/' \
            "$out/share/quickshell/inir/modules/barM3/SystemIcons.qml"
          f="$out/share/quickshell/inir/modules/barM3/UtilButtons.qml"
          sed -i 's/sourceComponent: isMaterial ? darkModeM3 : legacyDarkMode/sourceComponent: caffeineM3/' "$f"
          sed -i 's/active: Config.options.bar.m3.utilButtons.showDarkModeToggle/active: true/' "$f"
          sed -i '$d' "$f"
          printf '%s\n' \
            ' ' \
            '        Component {' \
            '            id: caffeineM3' \
            '            UtilButton {' \
            '                toolTipText: Idle.inhibit ? Translation.tr("Allow sleep") : Translation.tr("Keep awake")' \
            '                iconText: Idle.inhibit ? "coffee" : "local_cafe"' \
            '                onClicked: Idle.toggleInhibit()' \
            '            }' \
            '        }' \
            '}' >> "$f"
        '';
      });
in
{
  imports = [ inputs.inir.homeModules.inir ];

  programs.inir = {
    enable = true;

    package = inirPatched;

    # Shell scripts and helper tools reference the traditional Quickshell
    # config path (~/.config/quickshell/inir).
    configSymlink.enable = true;

    # The niri client binary used by shell features that call `niri msg`.
    extraPackages = [ pkgs.niri ];
  };
}
