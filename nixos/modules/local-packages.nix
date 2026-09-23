{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    # essential
    vim
    git
    pciutils
    inetutils

    git-credential-manager
  ];
}
