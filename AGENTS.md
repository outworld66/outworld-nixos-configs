# Repository guide

This public repository defines two `x86_64-linux` NixOS systems. Home Manager
is integrated as a NixOS module. The bundled empty `private` input uses the
safe default user `nixos`; an optional private library can override identity
and add extra modules.

- `tpx13` is a workstation profile with additional llm-agents packages.
- `majesty` is the second host profile. Machine-specific Disko layouts and
  hardware configuration live with their public host profiles.

## Repository map

- `flake.nix`: inputs, optional-private-library contract, shared host arguments,
  NixOS configurations, formatter, checks, development shell and runnable apps.
- `defaults/private/`: empty flake used when no private library is supplied.
- `hosts/<hostname>/`: host configuration, hardware configuration and
  host-specific packages.
- `nixos/modules/`: shared system modules imported by both hosts through
  `nixos/modules/default.nix`.
- `home-manager/home.nix`: Home Manager entry point.
- `home-manager/home-packages.nix`: user package list.
- `home-manager/modules/`: declarative user and desktop configuration.
- `home-manager/dotfiles/`: files linked out of the checkout into the user's
  home directory. Some applications may modify these files at runtime.
- `outworld-packages` flake input: reusable packages supplied by the separate
  `outworld-nixos-packages` repository and exposed through a Nixpkgs overlay.
- `Taskfile.yml`: local commands for formatting, checks and system activation.
- `.githooks/pre-push`: optional local CI hook installed with
  `nix run .#install-hooks`.

## Validation

Run checks from the repository root.

- After changing Nix code, run `nix fmt`.
- Do not manually make purely visual formatting changes to Nix files;
  `nix fmt` owns their formatting.
- Always run `git diff --check`.
- At minimum, evaluate all outputs with
  `nix flake check --no-build --print-build-logs`.
- After changing the private-library interface, also evaluate with
  `--no-write-lock-file --override-input private
  path:../outworld-nixos-private` when that sibling checkout is available.
- Change package derivations in `outworld-nixos-packages`, not in this
  repository. Public flake outputs re-export them for convenience.
- `task ci` runs formatting followed by the full `nix flake check`; unlike
  `--no-build`, it can build both complete NixOS systems and all re-exported
  packages.

The following repository-scoped commands are pre-authorized and may be run
without asking for separate approval:

- `nix eval`, including additional read-only evaluation flags;
- `nix flake check`, including variants such as `--no-build`;
- `nix fmt`.

These commands are also pre-authorized with a task-specific temporary cache,
for example `XDG_CACHE_HOME=/tmp/<task-name>-nix-cache nix eval ...`,
`XDG_CACHE_HOME=/tmp/<task-name>-nix-cache nix flake check ...` and
`XDG_CACHE_HOME=/tmp/<task-name>-nix-cache nix fmt`. Prefer this form when the
normal user cache is unavailable or read-only.

This pre-authorization does not extend to commands that activate a NixOS or
Home Manager configuration.

Review formatter changes before proceeding. The formatter also runs statix and
deadnix and may make semantic cleanups such as removing unused module
arguments.

## Safety boundaries

- Never run `task switch`, `nh os switch`, `nixos-rebuild switch`, Disko,
  installation commands or other system-activating commands unless the user
  explicitly requests activation.
- Do not edit `hosts/*/hardware-configuration.nix` unless the task is
  specifically about detected hardware. These files are generated and excluded
  from treefmt.
- Do not update `flake.lock` unless an input change requires it or the user
  explicitly asks for an update. Prefer targeted input updates over updating
  the entire lock file.
- Do not stage, commit, push or broadly run `git add .` unless explicitly
  requested.
- Do not add secrets, credentials, private keys, tokens or machine runtime
  state to the repository.
- Treat files under `home-manager/dotfiles/` carefully: they are linked
  out-of-store and may contain application-managed state. Avoid unrelated bulk
  rewrites.
- Keep identities and private organization inputs in the optional companion
  private library.
- Preserve host differences and state versions. Do not copy settings between
  `tpx13` and `majesty` without checking whether they are hardware-specific.

## Change conventions

- Put shared NixOS behavior in `nixos/modules/` and host-only behavior in the
  corresponding `hosts/<hostname>/` directory.
- Put user-level behavior in Home Manager rather than system modules when it
  does not require system privileges.
- Keep package-specific implementation in the `outworld-nixos-packages`
  repository; consume packages here through its overlay.
- Keep comments focused on non-obvious constraints and reasons, not a
  line-by-line restatement of Nix syntax.
