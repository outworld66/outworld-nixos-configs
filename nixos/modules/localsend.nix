{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [ localsend ];
  programs.localsend = {
    enable = true;
    openFirewall = true;
  };
}
