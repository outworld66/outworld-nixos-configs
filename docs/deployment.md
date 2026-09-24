# Deploying the NixOS configuration

The setup uses two checkouts:

- `outworld-nixos-configs` — the public configuration;
- `outworld-nixos-private` — private modules and encrypted secrets.

## Manual deployment from a workstation

This is the recommended mode for now. The server does not need GitHub access:
the workstation updates both repositories and deploys the evaluated
configuration over SSH.

```bash
cd ~/nix/outworld-nixos-private
git pull --ff-only

cd ../outworld-nixos-configs
nix flake check --no-build --no-write-lock-file \
  --override-input private path:../outworld-nixos-private

nixos-rebuild switch --flake .#private \
  --target-host root@192.168.0.3 \
  --override-input private path:../outworld-nixos-private
```

If the build should run on the server, add `--build-host` or copy both
checkouts to the server first. This is usually unnecessary.

Check the result:

```bash
ssh root@192.168.0.3 systemctl --failed
ssh root@192.168.0.3 systemctl status caddy webdav goaccess gobackup
ssh root@192.168.0.3 nix-env --list-generations --profile /nix/var/nix/profiles/system
```

Roll back to the previous generation:

```bash
ssh root@192.168.0.3 nixos-rebuild switch --rollback
```

## Pull-based updates on the server

In this model the server fetches changes and activates them from a timer. For
example, store the checkouts as follows:

```text
/var/lib/nixos-configs/public   # outworld-nixos-configs
/var/lib/nixos-configs/private  # outworld-nixos-private
```

The update commands should be equivalent to:

```bash
git -C /var/lib/nixos-configs/public pull --ff-only
git -C /var/lib/nixos-configs/private pull --ff-only

nixos-rebuild switch \
  --flake /var/lib/nixos-configs/public#private \
  --override-input private \
  path:/var/lib/nixos-configs/private
```

For automation, put these commands in a root-owned systemd service and trigger
it with a `systemd.timer`. The service should:

1. use `set -eu`;
2. use only `git pull --ff-only`;
3. run `nix flake check` or a build before activation;
4. never change `flake.lock` automatically;
5. write complete output to the journal; and
6. report a failed deployment as failed.

Example timer schedule: once per day:

```nix
systemd.timers.nixos-private-update = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "*-*-* 04:00:00";
    RandomizedDelaySec = "30m";
    Persistent = true;
  };
};
```

### Access to the private GitHub repository

The server needs a separate read-only deploy key:

```text
GitHub deploy key
        ↓
SSH_AUTH_SOCK или файл ~/.ssh/id_ed25519
        ↓
git pull private repository
```

The private key can be provisioned through `sops-nix`, for example at
`/run/secrets/github-deploy-key`, and used through `GIT_SSH_COMMAND`. The key
must not enter the Nix store, a flake, or the systemd journal.

There is a bootstrap constraint: `sops-nix` needs an age identity before it can
decrypt this key. Therefore the GitHub deploy key cannot be used to fetch the
flake that first defines the secret. First generate the server identity, add
its public recipient to `.sops.yaml`, re-encrypt the secrets, and only then
enable the pull-based deployment.

Basic checks after setup:

```bash
systemctl start nixos-private-update.service
journalctl -u nixos-private-update.service -e
systemctl list-timers nixos-private-update.timer
```

## Which model to choose

For the first installation of a server with SOPS, use the bootstrap tasks
described in the [server bootstrap guide](server-bootstrap.md). They separate
machine-key generation from secret activation and stop for confirmation before
changing encrypted data.

For one or a few home servers, start with manual deployment. It is simpler,
does not require GitHub credentials on the server, and lets you review the
configuration before activation.

Pull-based updates make sense when a server must update without a workstation.
Restrict the deploy key to read-only access to the required repository, disable
automatic `nix flake update`, and keep normal NixOS generation rollback.
