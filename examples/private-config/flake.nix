{
  description = "Optional private data and modules for a public NixOS flake";

  outputs =
    _:
    let
      personal = import ./personal.nix;
    in
    {
      config = personal;
      specialArgs = { inherit personal; };

      # Use a hostname exported by the public repository.
      hostConfigurations.tpx13 = {
        extraModules = [ ];
        extraHomeModules = [ ];
      };
    };
}
