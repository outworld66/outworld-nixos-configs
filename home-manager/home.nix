{
  homeStateVersion,
  extraHomeModules,
  user,
  ...
}:
{
  imports = [
    ./modules
    ./home-packages.nix
  ]
  ++ extraHomeModules;

  home = {
    username = user;
    homeDirectory = "/home/${user}";
    stateVersion = homeStateVersion;
  };
}
