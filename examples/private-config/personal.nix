{
  systemUser = {
    name = "your-user";
    group = "users";
  };

  gitUsers.default = {
    name = "Your Name";
    email = "you@example.invalid";
  };

  configDirectory = "/home/your-user/outworld-nixos-configs";
  activationFlake = "/home/your-user/outworld-nixos-configs";

  # Omit these attributes to leave the corresponding feature disabled.
  syncthing = null;
  proximityLock.enable = false;
}
