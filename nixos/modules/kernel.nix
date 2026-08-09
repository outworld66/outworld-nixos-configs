{ lib, pkgs, ... }: {
  # Keep the upstream NixOS kernel as the conservative fallback for hosts that
  # do not explicitly opt in to a workload-specific kernel.
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages;
}
