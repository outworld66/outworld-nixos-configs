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
  ];

  networking.hostName = hostname;
  system.stateVersion = stateVersion;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
