# Evaluation-only placeholder. Real systems must override this module with the
# generated hardware configuration from their private companion repository.
{ lib, ... }:
{
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_ROOT";
    fsType = "ext4";
  };
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
