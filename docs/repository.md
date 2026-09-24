# Repository layout

The public repository contains reusable system code and host-specific hardware
and service configuration:

```text
flake.nix
hosts/<hostname>/              host behavior, hardware, and Disko
nixos/modules/                 shared NixOS modules
nixos/modules/server/          reusable server-service modules
home-manager/                  Home Manager profiles and dotfiles
defaults/private/              empty fallback for the private input
examples/private-config/       private repository template
```

The separate `outworld-nixos-packages` repository provides reusable package
derivations through the `outworld-packages` flake input.

## Private companion repository

Keep the repositories next to each other:

```text
~/nix/
├── outworld-nixos-configs/
├── outworld-nixos-packages/
└── outworld-nixos-private/
```

The private flake is a library, not a second system entry point. It exports
`config`, `specialArgs`, and `hostConfigurations`; the public flake consumes
these outputs through an input override.

Create a new private repository from the template:

```bash
cp -R examples/private-config ../outworld-nixos-private
cd ../outworld-nixos-private
git init
```

Keep identities and organization-only modules there. Do not store passwords,
tokens, private keys, or other plaintext credentials in either repository; use
sops-nix or another secret manager.

Evaluate the complete configuration explicitly:

```bash
cd ../outworld-nixos-configs
nix flake check --no-build --print-build-logs \
  --no-write-lock-file \
  --override-input private path:../outworld-nixos-private
```
