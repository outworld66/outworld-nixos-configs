{
  config,
  lib,
  inputs,
  pkgs,
  hostname,
  stateVersion,
  ...
}:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./disko.nix
    ../../nixos/modules/server/services.nix
    ./services.nix
    ../../nixos/modules/zapret.nix
  ];

  networking.hostName = hostname;
  services.caddy.enable = lib.mkForce (config.server.secrets.enable or false);
  networking.useDHCP = lib.mkForce false;
  networking.interfaces.eno1.ipv4.addresses = [
    {
      address = "192.168.0.4";
      prefixLength = 16;
    }
  ];
  networking.defaultGateway = {
    address = "192.168.0.1";
    interface = "eno1";
  };
  networking.nameservers = [ "192.168.0.1" ];
  system.stateVersion = stateVersion;

  hardware.enableRedistributableFirmware = true;
  environment.systemPackages = [ pkgs.mergerfs ];
  programs.fuse.userAllowOther = true;

  fileSystems."/srv" = {
    device = "/data1:/data2";
    fsType = "fuse.mergerfs";
    options = [
      "allow_other"
      "use_ino"
      "category.create=mfs"
    ];
  };
}
