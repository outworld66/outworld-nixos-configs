{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    # essential
    vim
    git
    pciutils
    inetutils

    go-task
    git-credential-manager
  ];
}
