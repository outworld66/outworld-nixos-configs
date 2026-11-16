{ allowedUnfreePackages, lib, ... }:
{
  nixpkgs.config.allowUnfree = true;
  documentation.doc.enable = false;
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) allowedUnfreePackages;
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];

    # Configure the cache in the trusted system daemon rather than in
    # flake.nix, where an unprivileged client cannot authorize it.
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
    auto-optimise-store = true;
  };

  # Weekly garbage collection keeps /nix/store bounded; anything reachable
  # only through a profile or generation older than 30 days is removed,
  # including old system generations.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
}
