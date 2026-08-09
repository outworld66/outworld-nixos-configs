{ inputs, lib, ... }:

{
  imports = [ inputs.nirinit.nixosModules.nirinit ];

  services.nirinit.enable = true;

  # The upstream module only uses graphical-session.target, which may already
  # be active (or absent) when the package is first installed during a switch.
  systemd.user.services.nirinit.wantedBy = lib.mkForce [ "default.target" ];
}
