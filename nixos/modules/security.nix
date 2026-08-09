{
  config,
  lib,
  pkgs,
  ...
}:
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

  systemd.user.services = {
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
    # The DMS lock screen runs its own fprint PAM conversation alongside the
    # password conversation. Its NixOS fallback is the login service; keeping
    # pam_fprintd in that stack makes DMS treat fingerprint auth as inline and
    # suppress the parallel fingerprint prompt.
    login.fprintAuth = false;
    sudo.fprintAuth = true;
  };
}
