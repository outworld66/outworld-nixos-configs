{ hostname, stateVersion, ... }:
{
  networking.hostName = hostname;
  system.stateVersion = stateVersion;
}
