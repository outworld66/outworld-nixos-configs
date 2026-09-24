# Installing a server and enabling SOPS

The server is installed in two phases. The first phase installs a working
NixOS system and generates a machine-specific age identity. The second phase
adds that identity to the private SOPS file and enables the services that need
secrets.

## 1. Install the public server configuration

Boot a NixOS live ISO, review the disks, and run the installer script:

```bash
./scripts/install-flake-host --hostname private
```

The script uses the public `private` host configuration and does not activate
private secrets. Reboot into the installed system and verify SSH access:

```bash
ssh root@192.168.0.3 hostname
```

## 2. Generate the server age identity

The private flake starts the server in bootstrap mode:

```nix
{ server.secrets.bootstrap = true; }
```

Deploy that bootstrap configuration from the workstation:

```bash
cd ~/nix/outworld-nixos-configs
nixos-rebuild switch --flake .#private \
  --target-host root@192.168.0.3 \
  --override-input private path:../outworld-nixos-private
```

The configuration uses `sops.age.keyFile` and
`sops.age.generateKey = true`. `sops-nix` creates the key at:

```text
/var/lib/sops-nix/key.txt
```

The key is generated on the server and is not stored in Git or the Nix store.
Retrieve only its public recipient:

```bash
ssh root@192.168.0.3 \
  age-keygen -y /var/lib/sops-nix/key.txt
```

## 3. Add the recipient and re-encrypt secrets

Add the returned `age1...` value to the private repository's `.sops.yaml`:

```yaml
keys:
  - &admin age1...
  - &private age1...

creation_rules:
  - path_regex: secrets/.*\.yaml$
    key_groups:
      - age:
          - *admin
          - *private
```

Then re-encrypt the existing secret file:

```bash
cd ~/nix/outworld-nixos-private
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
nix run nixpkgs#sops -- updatekeys --yes secrets/private.yaml
```

## 4. Enable server secrets

In `outworld-nixos-private/flake.nix`, replace bootstrap mode:

```nix
{ server.secrets.bootstrap = true; }
```

with:

```nix
{ server.secrets.enable = true; }
```

Deploy again:

```bash
cd ~/nix/outworld-nixos-configs
nix flake check --no-build --no-write-lock-file \
  --override-input private path:../outworld-nixos-private
nixos-rebuild switch --flake .#private \
  --target-host root@192.168.0.3 \
  --override-input private path:../outworld-nixos-private
```

Verify the decrypted secrets and services without printing secret contents:

```bash
ssh root@192.168.0.3 systemctl status sops-nix webdav goaccess gobackup caddy
ssh root@192.168.0.3 test -e /run/secrets/webdav/username
ssh root@192.168.0.3 test -e /run/secrets/gobackup/config
```

## Why this is two-phase

An encrypted SOPS file needs the server's public recipient before the server
can decrypt it. The server cannot decrypt a secret that contains the key used
to decrypt that same secret. Generating the age identity during the first
bootstrap activation breaks this cycle cleanly.

Keep `/var/lib/sops-nix/key.txt` on persistent storage and never copy its
private contents into the repository. If the disk is lost, generate a new
identity, add its recipient, and run `sops updatekeys` again.
