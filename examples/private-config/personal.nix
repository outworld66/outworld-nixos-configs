{
  configDirectory = "/home/your-user/nix/outworld-nixos-configs";
  activationFlake = "/home/your-user/nix/outworld-nixos-configs";

  # Omit these attributes to leave the corresponding feature disabled.
  syncthing = null;
  proximityLock.enable = false;
}
