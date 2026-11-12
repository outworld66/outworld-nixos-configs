{ lib, ... }:

{
  services.sing-box = {
    enable = true;
    settings = {
      inbounds = [
        {
          type = "tun";
          tag = "tun-in";
          interface_name = "sing-box";
          address = [ "172.19.0.1/30" ];
          auto_route = true;
          auto_redirect = true;
          strict_route = true;
          route_exclude_address = [
            "10.0.0.0/8"
            "172.16.0.0/12"
            "192.168.0.0/16"
          ];
        }
      ];
      outbounds = [
        {
          _secret = "/etc/sing-box/vless-outbound.json";
          quote = false;
        }
        {
          type = "direct";
          tag = "direct";
        }
      ];
      route = {
        auto_detect_interface = true;
        final = "vpn";
      };
    };
  };

  # Start only after provisioning the host-specific outbound outside the Nix store.
  systemd.services.sing-box.wantedBy = lib.mkForce [ ];
}
