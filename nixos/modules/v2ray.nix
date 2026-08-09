{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    #v2raya
    #v2ray
    v2rayn
    throne
  ];
  programs.throne = {
    enable = true;
  };
  #services.v2raya = {
  #  enable = true;
  #};
  #services.v2ray = {
  #  enable = true;
  #  config = {
  #    inbounds = [
  #      {
  #        listen = "127.0.0.1";
  #        port = 1080;
  #        protocol = "http";
  #      }
  #    ];
  #    outbounds = [
  #      {
  #        protocol = "freedom";
  #      }
  #    ];
  #  };
  #};
}
