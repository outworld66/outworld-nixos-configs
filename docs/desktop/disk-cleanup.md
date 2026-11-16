# Automatic disk cleanup

The repository enables automatic cleanup so `/nix/store` and per-user caches
do not grow without bound. Everything below runs weekly and needs no manual
action.

## System-wide garbage collection

Configured in `nixos/modules/nix.nix`, active on every host:

- `nix.gc.automatic` runs the collector weekly with
  `--delete-older-than 30d`. This removes store paths reachable only
  through a profile generation older than 30 days, including old system
  generations, so rollbacks are only possible within that window. Older
  states have to be rebuilt from the flake.
- `nix.settings.auto-optimise-store` deduplicates identical store paths via
  hardlinks as they are written.

## Boot menu limit

`boot.loader.systemd-boot.configurationLimit = 10` (in
`nixos/modules/boot.nix` and `nixos/modules/server/default.nix`) keeps only
the newest 10 entries in the boot menu.

## Per-user cleanup on desktop hosts

`home-manager/modules/maintenance.nix` adds two systemd user timers (the
server profiles do not use Home Manager, and the system collector already
covers their store paths):

- `nix-profile-gc` runs `nix-collect-garbage --delete-older-than 30d`.
  The system-level collector only sees root profiles; this one cleans the
  user's `nix-env` profile and the Home Manager generations in
  `~/.local/state/nix/profiles`.
- `container-prune` runs `docker system prune -f` against the default and
  the rootless docker sockets (whichever daemon answers) and
  `podman system prune -f`. It removes stopped containers, unused
  networks, dangling images and build cache, but not tagged images or
  volumes.

Verify from a desktop host with `systemctl --user list-timers` and inspect
a run with `journalctl --user -u nix-profile-gc.service`.

## Not automated on purpose

- `~/Downloads`, browser caches and Trash stay untouched; cleaning them is
  a manual decision.
- `docker system prune -a` (removing tagged images too) is not used to keep
  re-pulls and local builds cheap.
