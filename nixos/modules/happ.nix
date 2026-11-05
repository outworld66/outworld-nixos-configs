{ inputs, ... }:

{
  # Community packaging of the Happ proxy client (VLESS/VMess/Trojan/
  # Shadowsocks over TUN, Xray-based). The module provides the package,
  # a root `happd` daemon for TUN mode, the /var/lib/dbus/machine-id link
  # Happ's HWID needs, and firewall/TUN wiring.
  imports = [ inputs.happ.nixosModules.default ];

  services.happ.enable = true;
}
