{
  inputs,
  user,
  gitUsername,
  gitMail,
  hostname,
  homeStateVersion,
  configDirectory,
  extraHomeModules,
  extraSpecialArgs,
  ...
}:
{
  imports = [ inputs.home-manager.nixosModules.default ];

  home-manager = {
    backupFileExtension = "backup";
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      inherit
        inputs
        user
        gitUsername
        gitMail
        hostname
        homeStateVersion
        configDirectory
        extraHomeModules
        ;
    }
    // extraSpecialArgs;
    users.${user} = import ../../home-manager/home.nix;
  };
}
