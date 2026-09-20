{
  config,
  lib,
  pkgs,
  ...
}:
let
  # The Synaptics Prometheus reader occasionally wedges even with fprintd
  # kept alive; a USB re-initialization is what a reboot does. Expose the
  # reset as a command (`fingerprint-reset`) and run it automatically after
  # every resume, where the failure is most often observed.
  fingerprintReset = pkgs.writeShellScriptBin "fingerprint-reset" ''
    for dev in /sys/bus/usb/devices/*/idVendor; do
        dir="$(dirname "$dev")"
        if [ "$(cat "$dev")" = "06cb" ] && [ "$(cat "$dir/idProduct")" = "00bd" ]; then
            echo 0 > "$dir/authorized"
            sleep 1
            echo 1 > "$dir/authorized"
        fi
    done
    systemctl try-restart fprintd.service
  '';
in
{
  services.dbus = {
    enable = true;
    packages = [
      pkgs.gnome-keyring
      pkgs.gcr
    ];
  };

  programs.seahorse.enable = true;

  security.polkit.enable = true;

  services.gnome.gnome-keyring.enable = true;
  services.fwupd.enable = true;
  services.fprintd.enable = true;

  # Reinitializing the Synaptics Prometheus reader resets it over USB. After
  # enough daemon idle exits and restarts, the reader can come back in a state
  # that libfprint reports as an unsupported firmware version. Keep fprintd
  # alive so sudo and the greeter reuse the initialized device.
  systemd.services.fprintd.serviceConfig.ExecStart = lib.mkForce [
    ""
    "${config.services.fprintd.package}/libexec/fprintd --no-timeout"
  ];

  environment.systemPackages = [ fingerprintReset ];

  systemd.services.fingerprint-reset-on-resume = {
    description = "Re-initialize the fingerprint reader after resume";
    after = [ "suspend.target" ];
    wantedBy = [ "suspend.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${fingerprintReset}/bin/fingerprint-reset";
    };
  };

  systemd.user.services = {
    # Ambxst does not ship a polkit agent, so run one for the
    # graphical session.
    polkit-kde-agent = {
      description = "Polkit authentication agent";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1";
        Restart = "on-failure";
      };
    };

    network-manager-applet = {
      description = "NetworkManager secret agent";
      wantedBy = [ "graphical-session.target" ];
      after = [
        "graphical-session.target"
        "gnome-keyring-daemon.service"
      ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator";
        Restart = "on-failure";
      };
    };
  };

  # Keep the Synaptics Prometheus fingerprint reader awake. On this device
  # autosuspend can reset the reader in the middle of fprintd verification.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="06cb", ATTR{idProduct}=="00bd", TEST=="power/control", ATTR{power/control}="on"
  '';

  security.pam.services = {
    greetd = {
      enableGnomeKeyring = true;
      fprintAuth = true;
    };
    greetd-password.enableGnomeKeyring = true;
    sudo.fprintAuth = true;
  };
}
