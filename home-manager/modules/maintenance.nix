{ pkgs, ... }:
let
  pruneContainers = pkgs.writeShellScript "prune-containers" ''
    if ${pkgs.docker}/bin/docker info >/dev/null 2>&1; then
      ${pkgs.docker}/bin/docker system prune -f
    fi
    export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock"
    if ${pkgs.docker}/bin/docker info >/dev/null 2>&1; then
      ${pkgs.docker}/bin/docker system prune -f
    fi
    if ${pkgs.podman}/bin/podman info >/dev/null 2>&1; then
      ${pkgs.podman}/bin/podman system prune -f
    fi
  '';
in
{
  systemd.user = {
    # The system-level nix.gc does not touch per-user profiles, so the
    # nix-env and Home Manager generations need their own collector.
    services.nix-profile-gc = {
      Unit.Description = "Delete user profile generations older than 30 days";
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.nix}/bin/nix-collect-garbage --delete-older-than 30d";
      };
    };
    timers.nix-profile-gc = {
      Unit.Description = "Weekly user nix profile garbage collection";
      Timer = {
        OnCalendar = "weekly";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    services.container-prune = {
      Unit.Description = "Prune dangling images and stopped containers";
      Service = {
        Type = "oneshot";
        ExecStart = pruneContainers;
      };
    };
    timers.container-prune = {
      Unit.Description = "Weekly rootless docker/podman cleanup";
      Timer = {
        OnCalendar = "weekly";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
