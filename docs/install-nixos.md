# Installing NixOS from the live ISO

`scripts/install-flake-host` installs one of this flake's hosts from a NixOS live
environment. It intentionally does not reboot the machine.

The script:

1. receives the host name and a local flake checkout;
2. asks the user to type the hostname as confirmation;
3. if a custom Disko file is supplied, copies it to
   `hosts/<hostname>/disko.nix`, so the installed flake uses exactly the layout
   that formatted the disk;
4. runs Disko in `destroy,format,mount` mode, which mounts the target system at
   `/mnt`;
5. runs `nixos-generate-config --no-filesystems --root /mnt` and copies the
   generated hardware configuration into `hosts/<hostname>/`; Disko remains
   the sole source of filesystem and LUKS definitions;
6. evaluates the resulting host configuration with `--store /mnt`;
7. invokes `nixos-install --flake <checkout>#<hostname> --root /mnt` without
   setting a root password;
8. finds the regular user created by the NixOS configuration and prompts twice
   for its password.

Both the explicit evaluation and `nixos-install` use the target local store.
That places the Nix store at `/mnt/nix/store` and Nix's SQLite metadata at
`/mnt/nix/var/nix/db`, rather than in the ISO's RAM-backed store. Disko itself
must still run from the live store because the target does not exist yet.

When the selected Disko config declares `keyFile = "/tmp/secret.key"`, the
script prompts twice for a non-empty LUKS password without echoing it. It writes
the exact bytes entered (no newline) to `/tmp/secret.key` with mode `0600`, uses
it for Disko, then deletes the file. The password is not passed as a command
argument or recorded in the script output.

After installation, the script finds the first regular account (UID 1000–59999,
excluding `nobody`) in the target's `/etc/passwd`. In the public configuration
this is `nixos`; an optional private identity override may choose another name.
It asks twice for a non-empty password, then supplies it to `chpasswd` through
standard input. Newlines are not accepted by `read`; a colon is also rejected
because `chpasswd` uses it as a field separator. The script does not configure
a root password.

## Prerequisites

Boot a NixOS installer ISO, connect to the network, then clone or otherwise
copy this repository to a writable local directory. The selected host must
already exist in `nixosConfigurations` and its `configuration.nix` must import
its generated `hardware-configuration.nix` through the flake host list.

Review the Disko config and its disk paths with `lsblk` before continuing. The
script's Disko step is destructive: it erases every device declared in the
selected configuration. It uses the current `disko/latest` flake as an
installer dependency; the installed system itself remains pinned by this
repository's `flake.lock`.

The supplied layout must be compatible with the host's NixOS module. In this
repository, `majesty` imports `hosts/majesty/disko.nix`; passing `--disko`
replaces that file after confirmation so both steps stay aligned. Any LUKS key
file at `/tmp/secret.key` is created and removed by the script as described
above.

## Example: `majesty`

The repository's `majesty` layout is at `hosts/majesty/disko.nix`. From the
repository root on the live system, run:

```bash
./scripts/install-flake-host --hostname majesty
```

To use a Disko file outside the host directory:

```bash
./scripts/install-flake-host \
  --hostname majesty \
  --disko /path/to/majesty-disko.nix
```

To install from a checkout in another directory:

```bash
/path/to/outworld-nixos-configs/scripts/install-flake-host \
  --hostname majesty \
  --flake /path/to/outworld-nixos-configs
```

After a successful install, inspect the generated
`hosts/majesty/hardware-configuration.nix`, preserve it in version control, and
reboot. Do not run Disko again after installation unless you intentionally want
to recreate the target disk.

## Install an already mounted target

If Disko was run manually and its target remains mounted at `/mnt`, use
`--mounted` to skip both Disko and `nixos-generate-config`:

```bash
./scripts/install-flake-host --hostname majesty --mounted
```

This mode uses the generated hardware configuration already present in the
cloned repository and installs it with the equivalent of
`nixos-install --flake ./#majesty --root /mnt`. It never creates or reads
`/tmp/secret.key`, but still prompts for the configured regular user's
password after installation. Do not combine this option with `--disko`.

## Existing tooling

[`nixos-anywhere`](https://github.com/nix-community/nixos-anywhere) already
combines Disko, flake installation and generation of a hardware configuration.
It is particularly useful when the target can be reached over SSH; its quick
start documents `--generate-hardware-config nixos-generate-config ...`.
For a local, USB-booted installation, this script keeps the same building
blocks while making the disk layout and confirmation step explicit.
