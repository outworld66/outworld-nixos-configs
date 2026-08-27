# NixOS and Home Manager configuration

This repository contains reusable NixOS and Home Manager modules, two example
host profiles, package re-exports, formatting, checks, and developer tooling.
Identity and organization-specific inputs belong in a separate private flake.
Host hardware configurations and Disko layouts are versioned here, so review
their hardware identifiers and device paths before publishing.

The public flake is the only system entry point. Its bundled `private` input is
an empty library, so the repository evaluates without a private checkout or
access to organization repositories. Reusable package derivations come from
the public `outworld-nixos-packages` input. Without private data the user
defaults to `nixos` and optional private modules are absent.

## Repository layout

- `flake.nix` exports `lib.makeSystem`, modules, checks, packages and apps.
- `nixos/modules/` contains shared system configuration.
- `home-manager/` contains the Home Manager profile and declarative dotfiles.
- `hosts/` contains host behavior, generated hardware configurations and Disko
  layouts.
- The `outworld-packages` input provides reusable packages from the separate
  `outworld-nixos-packages` repository.
- `defaults/private/` is the empty fallback for the optional `private` input.
- `examples/private-config/` is a template for identity and private modules.

## Create the private companion repository

Keep the public and private repositories next to each other:

```text
~/src/
├── outworld-nixos-configs/          # public
├── outworld-nixos-packages/         # public package library
└── outworld-nixos-private/          # private
```

Bootstrap the private repository without copying Git history:

```bash
cp -R outworld-nixos-configs/examples/private-config outworld-nixos-private
cd outworld-nixos-private
git init
```

Then:

1. Edit `personal.nix`.
2. Add private inputs and organization-only modules to the private `flake.nix`.
3. Keep VPN credentials, tokens and encryption keys out of both repositories;
   use sops-nix or agenix for secret material.
4. Create the remote repository as **private** before pushing.

The private flake is a library. It exports `config`, `specialArgs`, and
`hostConfigurations`; it does not build systems and does not need its own
`flake.lock`. The public flake consumes those outputs only when its `private`
input is overridden. Supported per-host extension points are `extraModules`,
`extraHomeModules`, and `extraSpecialArgs`. Generated hardware configuration
and Disko layouts are versioned with their public host profiles.

To inspect a private configuration explicitly:

```bash
nix flake check --no-build --print-build-logs \
  --no-write-lock-file \
  --override-input private path:../outworld-nixos-private
```

## Checks

Enter the development shell and list the available tasks:

```bash
nix develop
task --list
```

Use:

```bash
task fmt       # nixfmt, statix and deadnix
task ci        # secret scan, flake checks and whitespace validation
task build     # build this host, using a sibling private library if present
task switch    # check and activate, using a sibling private library if present
```

At minimum, run this after changing Nix code:

```bash
nix fmt
nix flake check --no-build --print-build-logs
git diff --check
```

To build a package re-exported from `outworld-nixos-packages`:

```bash
nix build .#<package> --no-link --print-build-logs
```

Enable the versioned pre-push hook once per clone:

```bash
nix run .#install-hooks
```

## Activation

Run activation commands from the public checkout. They use the sibling private
library automatically when it exists, and otherwise use public defaults:

```bash
cd ../outworld-nixos-configs
task build
task switch
```

If the private repository is elsewhere, override its path:

```bash
task build PRIVATE_FLAKE=/path/to/private-flake
task switch PRIVATE_FLAKE=/path/to/private-flake
```

For package-library development, the tasks automatically use the sibling
`outworld-nixos-packages`. Override its location with
`PACKAGES_FLAKE=/path/to/outworld-nixos-packages`.

`task switch` changes the running system; `task build` does not. Review the
build and diff first. Roll back with the boot menu or
`sudo nixos-rebuild switch --rollback`.

The public defaults are intended for safe evaluation, not installation: inspect
the selected hardware module and identity before activation. Never run Disko
without confirming that its target device is correct.

## State versions and lock updates

`system.stateVersion` and `home.stateVersion` describe compatibility with the
original installation. Do not increase them merely because nixpkgs was
updated.

Update inputs deliberately and review `flake.lock`:

```bash
nix flake update <input-name>
git diff -- flake.lock
```

## Adding changes safely

Review and stage explicit files so runtime state or secrets cannot be included
accidentally:

```bash
git status --short
git diff
git add path/to/file
gitleaks dir --no-banner --redact .
```
