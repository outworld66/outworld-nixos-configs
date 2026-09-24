# Development and activation workflow

## Checks

Run commands from the public repository root:

```bash
nix fmt
nix flake check --no-build --print-build-logs
git diff --check
```

Use the development shell to inspect available tasks:

```bash
nix develop
task --list
```

The main tasks are:

```text
task fmt       format and lint Nix code
task ci        run secret scan and flake checks
task build     build the selected host
task switch    check and activate the selected host
```

If the private repository is not a sibling checkout, provide its path:

```bash
task build PRIVATE_FLAKE=/path/to/outworld-nixos-private
task switch PRIVATE_FLAKE=/path/to/outworld-nixos-private
```

## Activation

The public checkout is the activation entry point:

```bash
cd ~/nix/outworld-nixos-configs
task build
task switch
```

`task build` does not activate anything. `task switch` changes the running
system. Roll back to the previous generation with:

```bash
sudo nixos-rebuild switch --rollback
```

## State versions and flake inputs

`system.stateVersion` and `home.stateVersion` describe compatibility with the
original installation. Do not change them only because nixpkgs was updated.

Update inputs deliberately and review the lockfile:

```bash
nix flake update <input-name>
git diff -- flake.lock
```

Before staging changes, inspect the worktree and run a secret scan:

```bash
git status --short
git diff
gitleaks dir --no-banner --redact .
```
