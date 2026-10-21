{ ... }:
{
  imports = [
    ./caddy
    ./gobackup
    ./goaccess
    ./mail
    ./webdav
    ./media/donetick
    ./media/elengrab
    ./media/cloudreve
    ./gotify
    ./media/immich
  ];

  networking.firewall.allowedTCPPorts = [ 443 ];
}
