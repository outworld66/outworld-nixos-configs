{
  stateVersion,
  hostname,
  pkgs,
  ...
}:

{
  imports = [
    ./ai-packages.nix
  ];

  networking.hostName = hostname;

  # tpx13 is the interactive workstation; keep the desktop-oriented Zen
  # kernel opt-in local to this host. The shared module remains the fallback
  # if Zen-specific behaviour or compatibility becomes a problem.
  boot.kernelPackages = pkgs.linuxPackages_zen;

  system.stateVersion = stateVersion;
}
