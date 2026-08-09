{
  virtualisation.docker.rootless = {
    enable = true;
    # Point the Docker client at the socket owned by the current user:
    # unix:///run/user/$UID/docker.sock
    setSocketVariable = true;
  };
}
