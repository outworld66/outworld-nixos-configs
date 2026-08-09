# Replace this file with the output generated for the target machine:
# nixos-generate-config --show-hardware-config
{ lib, ... }:
{
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
