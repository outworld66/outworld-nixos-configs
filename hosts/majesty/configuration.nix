{
  inputs,
  stateVersion,
  hostname,
  ...
}:

{
  imports = [
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./qwen-flash-next.nix
    #../../nixos/modules/zapret.nix
  ];

  networking.hostName = hostname;
  system.stateVersion = stateVersion;

  hardware.enableRedistributableFirmware = true;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
