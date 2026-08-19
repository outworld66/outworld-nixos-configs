{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    # essential
    vim
    git
    pciutils
    inetutils
  ];
}
