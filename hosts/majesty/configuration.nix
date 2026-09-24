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
    ./qwen38.nix
    ../../nixos/modules/zapret.nix
  ];

  networking.hostName = hostname;
  system.stateVersion = stateVersion;

  security.sudo.extraConfig = "Defaults@majesty timestamp_timeout=1440";

  hardware.enableRedistributableFirmware = true;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
