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

  # The X13 Gen 1 lid switch is buggy: the EC emits phantom "Lid closed"
  # ACPI events while the lid is physically open (kernel logs "The lid
  # device is not compliant to SW_LID"), and logind answers each one with
  # suspend even on AC. Ignore lid events on external power; on battery the
  # default suspend-on-close still applies.
  services.logind.lidSwitchExternalPower = "ignore";

  system.stateVersion = stateVersion;
}
