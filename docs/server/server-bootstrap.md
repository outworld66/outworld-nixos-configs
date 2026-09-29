# Installing a server and enabling SOPS

Bootstrap takes two activations. The first installs a minimal host profile and
generates a machine-specific age identity. The second adds its public
recipient to the private SOPS configuration, re-encrypts the shared secret
file, and enables that host's secret-backed services.

## Before bootstrap

1. Add `hosts/<hostname>/` and expose the host in the public flake. Configure
   its static IPv4 address on `eno1`.
2. Add a host configuration in the private flake with
   `{ server.secrets.bootstrap = true; }`. Do not enable secret-backed
   services yet. The age key path is `/var/lib/sops-nix/key.txt`.
3. Boot a NixOS live ISO, review the host's Disko layout, and install with
   `./scripts/install-flake-host --hostname <hostname>`. Disko formats the
   declared disks. Reboot, then check root SSH access.
4. On the admin workstation, pull both repositories. Make the admin age
   identity available at `~/.config/sops/age/keys.txt` or set
   `SOPS_AGE_KEY_FILE`.

The Taskfile derives the SSH target from the selected host's configured
`eno1` IPv4 address. Override it with `SERVER_TARGET` if the host is reached
through another address. Rico's normal bootstrap commands are:

```bash
task server-bootstrap-key SERVER_HOST=rico
task server-bootstrap-finish SERVER_HOST=rico
```

Use `SERVER_HOST=<hostname>` for another server. `PRIVATE_FLAKE` can select a
different private checkout.

## Generate the key and enable secrets

`server-bootstrap-key` activates the host's bootstrap profile and prints only
the public age recipient. The private key remains on the server. Review or
record that recipient, then run `server-bootstrap-finish`. It asks for
confirmation, adds the recipient to `.sops.yaml`, re-encrypts
`secrets/private.yaml` using the admin identity, changes the selected private
flake host from `bootstrap` to `enable`, checks the flake, and deploys the
final configuration through `server-update`.

```bash
task server-bootstrap-key SERVER_HOST=rico
task server-bootstrap-finish SERVER_HOST=rico
```

The bootstrap tasks leave the recipient, encrypted file, and private flake
mode change in the private repository for review. Commit and push those
changes so future deployments use the updated SOPS recipients:

```bash
cd ../outworld-nixos-private
git diff -- .sops.yaml flake.nix
git diff --numstat -- secrets/private.yaml
git add .sops.yaml flake.nix secrets/private.yaml
git commit -m "Enable rico server secrets"
git push origin main
```

Verify the deployed generation and services without printing secret contents:

```bash
ssh root@192.168.0.4 systemctl is-system-running
ssh root@192.168.0.4 systemctl --failed
ssh root@192.168.0.4 test -r /var/lib/sops-nix/key.txt
```

Replace the example IP with the selected server's configured address.

## Why bootstrap has two activations

An encrypted SOPS file needs the server's public recipient before the server
can decrypt it. The server cannot decrypt a secret that contains the key used
to decrypt that same secret. Generating the age identity during the first
activation breaks this cycle.

Keep `/var/lib/sops-nix/key.txt` on persistent storage and never copy its
private contents into the repository. If the disk is lost, generate a new
identity, add its recipient, and run `sops updatekeys` again.
