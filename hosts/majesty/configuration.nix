{
  inputs,
  lib,
  pkgs,
  stateVersion,
  hostname,
  ...
}:

let
  dnsServers = [
    "1.1.1.1"
    "1.0.0.1"
  ];
in
{
  imports = [
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./qwen38.nix
    ../../nixos/modules/zapret.nix
  ];

  networking.hostName = hostname;
  networking.nameservers = dnsServers;
  networking.networkmanager.dns = "none";
  networking.resolvconf.enable = false;
  environment.etc."resolv.conf".text =
    lib.concatMapStringsSep "\n" (server: "nameserver ${server}") dnsServers + "\noptions edns0\n";
  system.stateVersion = stateVersion;

  security.sudo.extraConfig = "Defaults@majesty timestamp_timeout=1440";

  hardware.enableRedistributableFirmware = true;

  boot.kernelPackages = pkgs.linuxPackages_zen;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  systemd.tmpfiles.rules = [
    "d /opt/google/chrome 0755 root root -"
    "L+ /opt/google/chrome/chrome - - - - ${pkgs.google-chrome}/bin/google-chrome-stable"
  ];
}
