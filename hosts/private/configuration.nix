{
  lib,
  inputs,
  hostname,
  stateVersion,
  ...
}:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./services.nix
  ];

  networking.hostName = hostname;
  networking.useDHCP = lib.mkForce false;
  networking.interfaces.eno1.ipv4.addresses = [
    {
      address = "192.168.0.3";
      prefixLength = 16;
    }
  ];
  networking.defaultGateway = {
    address = "192.168.0.1";
    interface = "eno1";
  };
  networking.nameservers = [ "192.168.0.1" ];
  networking.firewall.allowedTCPPorts = [
    80
    7890
  ];
  system.stateVersion = stateVersion;
}
