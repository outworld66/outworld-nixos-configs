{
  description = "Empty private configuration used by the public flake";

  outputs = _: {
    config = { };
    hostConfigurations = { };
    specialArgs = { };
  };
}
