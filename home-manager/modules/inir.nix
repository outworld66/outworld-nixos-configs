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
  # 3. UtilButton: no hover expansion; the animated width change re-renders
  #    the whole util-buttons pill at a visible stutter on this machine.
  # 4. ClockWidgetPopup: larger calendar popup (560px wide, taller week strip).
  # 5. NotificationUnreadCount: hover opens a notifications-only popup
  #    (NotifPopup, built on the stock StyledPopup used by the clock widget).
  # 6. StyledPopup input mask fix.
  # 7. MprisController zombie-player filter.
  # 8. Lock screen authentication: absolute PAM module paths (NixOS has no
  #    /lib/security, so bare "pam_fprintd.so" never loaded and the fingerprint
  #    did nothing), a pam_unix-only password config (upstream defaults to
  #    /etc/pam.d/login whose stack waits on pam_fprintd before the password),
  #    replies to pam_fprintd prompts (Quickshell blocks the subprocess until
  #    respond() is called), retry on PAM errors, visible scan/failure states,
  #    and password field clipping so long passwords stay inside the field.
  # The seds are no-ops if upstream changes the anchored lines.
  inirPatched =
    (pkgs.callPackage "${inputs.inir}/nix/package.nix" { inherit pkgs; }).overrideAttrs
      (old: {
        postInstall = (old.postInstall or "") + ''
                    dir="$out/share/quickshell/inir"

                    # 1. Keyboard layout leaves the systemIcons cluster.
                    sed -i 's/active: KeyboardIndicators.hasPanelIndicators/active: false/' \
                      "$dir/modules/barM3/SystemIcons.qml"

                    # 2. Caffeine button replaces the light-mode toggle.
                    f="$dir/modules/barM3/UtilButtons.qml"
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

                    # 3. No hover expansion on util buttons.
                    u="$dir/modules/barM3/UtilButton.qml"
                    sed -i 's/implicitWidth: vertical ? 26 : (hovered ? 54 : 26)/implicitWidth: 26/' "$u"
                    sed -i 's/implicitHeight: vertical ? (hovered ? 54 : 26) : 26/implicitHeight: 26/' "$u"

                    # 4. Bigger calendar popup.
                    c="$dir/modules/barM3/ClockWidgetPopup.qml"
                    sed -i 's/Math.max(390, Math.round(410 \* Appearance.fontSizeScale))/Math.max(560, Math.round(600 * Appearance.fontSizeScale))/' "$c"
                    sed -i 's/height: Math.max(58, Math.round(60 \* Appearance.fontSizeScale))/height: Math.max(80, Math.round(84 * Appearance.fontSizeScale))/' "$c"

                    # 5. Notifications-only hover popup for the center bar widget.
                    printf '%s\n' \
                      'import qs.modules.barM3' \
                      'import qs.modules.common' \
                      'import qs.modules.common.widgets' \
                      'import qs.modules.sidebarRight.notifications' \
                      'import qs.services' \
                      'import QtQuick' \
                      'import QtQuick.Layouts' \
                      'import Quickshell' \
                      'import Quickshell.Wayland' \
                      ' ' \
                      'StyledPopup {' \
                      '    id: root' \
                      '    hoverActivates: true' \
                      '    closeOnOutsideClick: false' \
                      '    centerOnScreen: true' \
                      '    onRequestClose: root._hoverHold = false' \
                      ' ' \
                      '    Item {' \
                      '        id: contentBox' \
                      '        implicitWidth: 460' \
                      '        implicitHeight: 520' \
                      '        width: implicitWidth' \
                      '        height: implicitHeight' \
                      ' ' \
                      '        // Outside-click catcher, ContextMenu pattern: a Top-layer' \
                      '        // fullscreen surface stays below this Overlay popup, so clicks' \
                      '        // on the popup work and any click outside closes it. The' \
                      '        // StyledPopup backdrop is dead (its contentItem slot is' \
                      '        // overwritten by this very item), hence a local catcher.' \
                      '        PanelWindow {' \
                      '            visible: CompositorService.isNiri && root.active' \
                      '            color: "transparent"' \
                      '            exclusiveZone: 0' \
                      '            WlrLayershell.layer: WlrLayer.Top' \
                      '            WlrLayershell.namespace: "quickshell:notifPopupBackdrop"' \
                      '            anchors { top: true; bottom: true; left: true; right: true }' \
                      '            MouseArea {' \
                      '                anchors.fill: parent' \
                      '                onClicked: root.requestClose()' \
                      '            }' \
                      '        }' \
                      ' ' \
                      '        NotificationListView {' \
                      '            id: list' \
                      '            anchors {' \
                      '                top: parent.top' \
                      '                left: parent.left' \
                      '                right: parent.right' \
                      '                bottom: statusRow.top' \
                      '                bottomMargin: 6' \
                      '            }' \
                      '            popup: false' \
                      '        }' \
                      ' ' \
                      '        RowLayout {' \
                      '            id: statusRow' \
                      '            anchors {' \
                      '                left: parent.left' \
                      '                right: parent.right' \
                      '                bottom: parent.bottom' \
                      '            }' \
                      '            spacing: 6' \
                      ' ' \
                      '            NotificationStatusButton {' \
                      '                Layout.fillHeight: false' \
                      '                Layout.fillWidth: false' \
                      '                Layout.preferredHeight: 36' \
                      '                Layout.preferredWidth: 80' \
                      '                buttonIcon: "notifications_paused"' \
                      '                toggled: Notifications.silent' \
                      '                onClicked: () => {' \
                      '                    Notifications.silent = !Notifications.silent;' \
                      '                }' \
                      '            }' \
                      ' ' \
                      '            NotificationStatusButton {' \
                      '                Layout.fillHeight: false' \
                      '                Layout.preferredHeight: 36' \
                      '                enabled: false' \
                      '                Layout.fillWidth: true' \
                      '                buttonText: Translation.tr("%1 notifications").arg(Notifications.list.length)' \
                      '            }' \
                      ' ' \
                      '            NotificationStatusButton {' \
                      '                Layout.fillHeight: false' \
                      '                Layout.fillWidth: false' \
                      '                Layout.preferredHeight: 36' \
                      '                Layout.preferredWidth: 80' \
                      '                buttonIcon: "delete_sweep"' \
                      '                onClicked: () => {' \
                      '                    Notifications.discardAllNotifications()' \
                      '                }' \
                      '            }' \
                      '        }' \
                      '    }' \
                      '}' > "$dir/modules/barM3/NotifPopup.qml"
                    echo "NotifPopup 1.0 NotifPopup.qml" >> "$dir/modules/barM3/qmldir"

                    # 6. StyledPopup input mask: Region { item } snapshots geometry while
                    # the open animation runs (scale 0.94) and never updates on scale, so
                    # the real input region stays ~6% smaller than the popup (bottom ~32px
                    # and side ~14px are dead). Track a scale-free proxy item instead.
                    sp="$dir/modules/barM3/StyledPopup.qml"
                    sed -i 's/mask: Region { item: popupBackground }/mask: Region { item: popupMaskProxy }/' "$sp"
                    sed -i 's/^        Rectangle {$/        Item {\n            id: popupMaskProxy\n            anchors.fill: popupBackground\n        }\n\n        Rectangle {/' "$sp"
                    # Optional screen-centered horizontal position (NotifPopup uses it).
                    sed -i 's/^    property real popupBackgroundMargin: 0$/    property real popupBackgroundMargin: 0\n    property bool centerOnScreen: false/' "$sp"
                    sed -i 's/^                return popupWindow.centerOffsetX$/                if (root.centerOnScreen) {\n                    const sw = popupWindow.screen?.width ?? 0\n                    if (sw > 0)\n                        return Math.max(Appearance.sizes.elevationMargin,\n                            (sw - popupWindow.implicitWidth) \/ 2)\n                }\n                return popupWindow.centerOffsetX/' "$sp"

                    n="$dir/modules/barM3/NotificationUnreadCount.qml"
                    sed -i 's/^    RippleButton {$/    RippleButton {\n        id: notifButton/' "$n"
                    # Hover opens the popup (like the clock widget); click does nothing.
                    sed -i 's/GlobalStates.toggleSidebarRight(root.QsWindow.window?.screen?.name ?? "")//' "$n"
                    sed -i '$d' "$n"
                    printf '%s\n' \
                      ' ' \
                      '    NotifPopup {' \
                      '        id: notifPopup' \
                      '        hoverTarget: notifButton' \
                      '    }' \
                      '}' >> "$n"

                    # 7. MprisController: drop zombie MPRIS players (e.g. TelegramDesktop
                    # after a voice message) that claim Playing but never advance their
                    # position. Frozen for 3 consecutive sweeps (~7.5s) -> filtered out
                    # of the player list until the position moves or the state changes.
                    mp="$dir/services/MprisController.qml"
                    sed -i 's|function isRealPlayer(player) {|function isRealPlayer(player) {\n\t\tif (root._zombieStuck[player?.dbusName ?? ""]) return false;|' "$mp"
                    python3 - "$mp" <<'PYEOF'
          import sys
          f = sys.argv[1]
          s = open(f).read()
          block = """\t// --- Patched: zombie player filter (claims Playing, frozen position) ---
          \tproperty var _zombieStuck: ({})
          \tproperty var _zombieLastPos: ({})
          \tproperty var _zombieStale: ({})

          \tfunction zombieSweep(): void {
          \t\tlet changed = false;
          \t\tconst seen = {};
          \t\tfor (const player of Mpris.players.values) {
          \t\t\tconst name = player?.dbusName ?? "";
          \t\t\tif (!name) continue;
          \t\t\tseen[name] = true;
          \t\t\tif (player.isPlaying && (player.length ?? 0) > 0) {
          \t\t\t\tconst prev = _zombieLastPos[name];
          \t\t\t\tconst cur = player.position ?? 0;
          \t\t\t\tif (prev !== undefined && cur === prev) {
          \t\t\t\t\t_zombieStale[name] = (_zombieStale[name] ?? 0) + 1;
          \t\t\t\t\tif (_zombieStale[name] >= 3 && !_zombieStuck[name]) {
          \t\t\t\t\t\t_zombieStuck[name] = true;
          \t\t\t\t\t\tchanged = true;
          \t\t\t\t\t}
          \t\t\t\t} else {
          \t\t\t\t\t\t_zombieStale[name] = 0;
          \t\t\t\t\t\tif (_zombieStuck[name]) { _zombieStuck[name] = false; changed = true; }
          \t\t\t\t}
          \t\t\t\t_zombieLastPos[name] = cur;
          \t\t\t\t\tplayer.positionChanged();
          \t\t\t} else if (_zombieStuck[name]) {
          \t\t\t\t_zombieStuck[name] = false;
          \t\t\t\tchanged = true;
          \t\t\t}
          \t\t}
          \t\tfor (const k of Object.keys(_zombieLastPos)) {
          \t\t\tif (!seen[k]) { delete _zombieLastPos[k]; delete _zombieStale[k]; delete _zombieStuck[k]; }
          \t\t}
          \t\tif (changed) _rebuildPlayerList();
          \t}

          \tTimer {
          \t\tinterval: 2500
          \t\trepeat: true
          \t\trunning: true
          \t\tonTriggered: zombieSweep()
          \t}
          """
          idx = s.rstrip().rfind('\n}')
          assert idx > 0, 'unexpected file tail'
          open(f, 'w').write(s[:idx + 1] + block + s[idx:].lstrip('\n'))
          PYEOF

                    # 8. Lock screen authentication (see the header comment).
                    # NixOS has no /lib/security, so bare PAM module names in the
                    # shipped pam/fprintd.conf never loaded; write both PAM
                    # configs with absolute store paths. The QML changes live in
                    # patches/inir-lock-auth.patch so the exact indentation of
                    # the edited files is not at the mercy of Nix string
                    # dedentation.
                    pamdir="$dir/modules/lock/pam"
                    printf 'auth    sufficient    ${pkgs.fprintd}/lib/security/pam_fprintd.so\n' > "$pamdir/fprintd.conf"
                    printf 'auth    required      ${pkgs.pam}/lib/security/pam_unix.so\n' > "$pamdir/password.conf"
                    # 9. The installPhase strip of /usr/bin/ only matches files with
                    # extensions; scripts/inir has none, so its pgrep cleanup
                    # pattern for orphaned swayidle never matched the real
                    # binary path and stale swayidle instances accumulated across
                    # inir restarts (each still firing screen-off/suspend).
                    sed -i '1!s#/usr/bin/##g' "$dir/scripts/inir"

                    patch -d "$dir" -p1 --no-backup-if-mismatch < ${../patches/inir-lock-auth.patch}
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
