{ activationFlake, ... }: {
  programs.nh = {
    enable = true;
    flake = activationFlake;
  };
}
