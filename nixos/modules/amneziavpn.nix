{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    amnezia-vpn
  ];
  systemd.services.amnezia-vpn = {
    description = "AmneziaVPN-service";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.amnezia-vpn}/bin/AmneziaVPN-service";
      Type = "simple";
      Restart = "on-failure";
      RestartSec = "5s";

      # The daemon configures tunnel interfaces and routes, but does not need
      # unrestricted root capabilities or access to unrelated devices.
      CapabilityBoundingSet = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
      ];
      DeviceAllow = [ "/dev/net/tun rw" ];
      DevicePolicy = "closed";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_NETLINK"
        "AF_UNIX"
      ];

      LockPersonality = true;
      NoNewPrivileges = true;
      PrivateMounts = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectProc = "invisible";
      ProtectSystem = "full";
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;

      RuntimeDirectory = "amneziavpn";
      RuntimeDirectoryMode = "0755";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
