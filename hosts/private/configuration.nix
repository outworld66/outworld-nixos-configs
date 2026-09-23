{
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
  system.stateVersion = stateVersion;
}
