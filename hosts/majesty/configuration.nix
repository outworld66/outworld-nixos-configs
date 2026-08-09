{ stateVersion, hostname, ... }:

{
  networking.hostName = hostname;
  system.stateVersion = stateVersion;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
