{
  config,
  inputs,
  lib,
  pkgs,
  user,
  group,
  ...
}:
{
  imports = [
    inputs.sops-nix.nixosModules.sops
    ../kernel.nix
    ../nix.nix
    ../nh.nix
    ../timezone.nix
    ../zram.nix
    ./caddy
    ./gobackup
    ./goaccess
    ./webdav
  ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
    timeout = 0;
  };
  boot.initrd.systemd.enable = true;

  nix.settings.extra-substituters = lib.mkForce [ ];
  nix.settings.extra-trusted-public-keys = lib.mkForce [ ];

  networking.useDHCP = true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  users.users.${user} = {
    isNormalUser = true;
    inherit group;
    extraGroups = [ "wheel" ];
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB1VOIwkUN62qmYrBg9Xn/VocYvxLVuHxv+pxTqaPU10"
    ];
  };

  users.users.root.openssh.authorizedKeys.keys =
    config.users.users.${user}.openssh.authorizedKeys.keys;
  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    curl
    git
    htop
    vim
    go-task
  ];
}
