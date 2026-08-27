{
  pkgs,
  user,
  group,
  ...
}:
{
  programs.fish.enable = true;

  users = {
    defaultUserShell = pkgs.fish;
    users.${user} = {
      group = "${group}";
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "networkmanager"
      ];
    };
  };
}
