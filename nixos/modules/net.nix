{
  config,
  pkgs,
  ...
}:
let
  amneziawg-module = pkgs.amneziawg.withKernel config.boot.kernelPackages;
in
{
  networking.networkmanager = {
    enable = true;
    plugins = with pkgs; [
      networkmanager-openvpn
      networkmanager-openconnect
      networkmanager-l2tp
      network-manager-amneziawg
    ];
  };
  environment.systemPackages = with pkgs; [
    amneziawg-tools
    networkmanagerapplet
    strongswan
  ];
  boot.extraModulePackages = [ amneziawg-module ];
  boot.kernelModules = [ "amneziawg" ];
  environment.etc."strongswan.conf".text = ""; # https://github.com/NixOS/nixpkgs/issues/375352
  services.strongswan = {
    enable = true;
  };

  # networkmanager-l2tp writes its temporary PSK configuration here.
  # The directory must be writable instead of being managed through /etc.
  systemd.tmpfiles.rules = [
    "d /etc/ipsec.d 0700 root root -"
  ];
}
