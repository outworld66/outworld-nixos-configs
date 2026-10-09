{ pkgs, ... }:
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
  services.fprintd.enable = false;

  systemd.user.services = {
    # Keep a polkit agent available for graphical authentication prompts.
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

  security.pam.services = {
    greetd = {
      enableGnomeKeyring = true;
      fprintAuth = false;
    };
    greetd-password.enableGnomeKeyring = true;
    sudo.fprintAuth = false;
  };
}
