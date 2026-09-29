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
    ./pocket-id
  ];

  networking.firewall.allowedTCPPorts = [ 443 ];
}
