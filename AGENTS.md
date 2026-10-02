# Repository guide

This public repository defines desktop and server `x86_64-linux` NixOS systems. Home Manager
is integrated as a NixOS module. The bundled empty `private` input uses the
safe default user `nixos`; an optional private library can override identity
and add extra modules.

- `tpx13` is a workstation profile with additional llm-agents packages.
- `majesty` is the second host profile. Machine-specific Disko layouts and
  hardware configuration live with their public host profiles.
- `private` is the first server profile; reusable server services live below
  `nixos/modules/server/` and host routing stays in `hosts/private/`.

## Repository map

The workspace may open one directory above this checkout. Before running
repository commands, confirm the checkout with `git rev-parse --show-toplevel`
and change to that directory; the flake root is the directory containing
`flake.nix`.

All repository documentation, including `README.md`, files under `docs/`, and
documentation comments intended for users, must be written in English.

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

The sibling repositories use this same file as their instructions:

- `../outworld-nixos-private/`: optional private flake library. Its main files
  are `flake.nix`, `personal.nix`, `models.nix`, `modules/`, `home/` and
  `certificates/`. It must export the public/private interface without becoming
  a second system-building entry point.
- `../outworld-nixos-packages/`: reusable package library. Its main files are
  `flake.nix` and `packages/<name>/default.nix`; it must stay independent of
  users, hosts and organization-specific configuration.

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
- For changes in `../outworld-nixos-private/`, validate from this checkout with
  the same override command and run `git -C ../outworld-nixos-private diff
  --check`. Do not add its standalone `flake.lock`.
- For changes in `../outworld-nixos-packages/`, run `nixfmt`,
  `nix flake check --no-build --no-write-lock-file --print-build-logs`, and
  `git diff --check`; build changed packages explicitly when practical.
- Change package derivations in `outworld-nixos-packages`, not in this
  repository. Public flake outputs re-export them for convenience.
- When adding a service with a user-facing web interface, add it to the
  appropriate Homepage group in the same change. If it should not appear in
  Homepage, document why.
- On hosts with a mergerfs pool, configure applications and user-facing docs
  to use the merged mount path for shared data. Refer to backing disk mount
  paths only in the mount and storage configuration itself.
- For a new web service, manage its administrator password through SOPS when
  the service supports it. Enable native OIDC when available; otherwise put
  the public UI behind Pomerium by default. Document any exception and why
  that authentication path does not fit (for example, Jellyfin clients need
  direct API and media-stream access). Before choosing ports, check both the
  host's declared service ports and currently listening ports for conflicts.
- Prefer declarative bootstrap or reconciliation for first-run settings when
  the application API supports it and the change is small and reliable. If it
  would require substantial code, ongoing complexity, or operator inconvenience,
  explain the cost and ask the user before choosing that approach. Document any
  remaining one-time manual setup.
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

- Before operational work, read the relevant documentation and follow its
  documented workflow. For server deployments, read `docs/server/deployment.md`
  and use `task server-update -- <host>` after bootstrap; do not substitute a
  hand-built activation command.

- Never run `task switch`, `nh os switch`, `nixos-rebuild switch`, Disko,
  installation commands or other system-activating commands unless the user
  explicitly requests activation.
- The user has explicitly authorized activation of the `private` server for
  the Pocket ID/Pomerium migration; after validation, use the documented
  `nixos-rebuild switch --flake .#private --target-host root@192.168.0.3`
  workflow and do not activate other hosts without a new request.
- Do not edit `hosts/*/hardware-configuration.nix` unless the task is
  specifically about detected hardware. These files are generated and excluded
  from treefmt.
- Do not update `flake.lock` unless an input change requires it or the user
  explicitly asks for an update. Prefer targeted input updates over updating
  the entire lock file.
- Do not stage or commit unrelated or pre-existing dirty state. Never commit
  or push unless the user explicitly asks for it in the current task.
- Keep secrets out of the repository regardless of the automated checks; the
  check is a heuristic gate, not permission to store credentials.
- Do not add secrets, credentials, private keys, tokens or machine runtime
  state to the repository.
- Treat files under `home-manager/dotfiles/` carefully: they are linked
  out-of-store and may contain application-managed state. Avoid unrelated bulk
  rewrites.
- Keep organization-specific identities and private inputs in the optional
  companion private library.
- Preserve host differences and state versions. Do not copy settings between
  `tpx13` and `majesty` without checking whether they are hardware-specific.

## Change conventions

- Put shared NixOS behavior in `nixos/modules/` and host-only behavior in the
  corresponding `hosts/<hostname>/` directory.
- Put user-level behavior in Home Manager rather than system modules when it
  does not require system privileges.
- Keep package-specific implementation in the `outworld-nixos-packages`
  repository; consume packages here through its overlay.
- When adding a service with a user-facing web interface, add it to the
  appropriate Homepage group in the same change. If it should not appear in
  Homepage, document why.
- Keep comments focused on non-obvious constraints and reasons, not a
  line-by-line restatement of Nix syntax.
- When a change adds or changes behavior that operators cannot infer from the
  configuration, update the relevant documentation in the same change. Explain
  the reason, prerequisites (including one-time manual steps), internal versus
  public endpoints, authorization, and how to verify or recover the service as
  relevant. Put user documentation in English under `docs/`, keep it in sync
  with the configuration, and avoid restating self-explanatory settings.

## Commits and pushes

Do not commit or push by default. A single explicit user authorization to
commit and push applies to subsequent tasks in all three repositories until
the user explicitly revokes it. When authorized, stage only the task's files,
run the mandatory secret check below, commit with a concise message, and push
only to the existing upstream. Never force-push.

### Mandatory secret check (after staging, before committing)

```bash
# suspicious file names in the staged change set
git diff --cached --name-only | grep -Ei \
  '(^|/)(\.env($|\.)|id_(rsa|ed25519|ecdsa)[^/]*|[^/]+\.(pem|key|p12|pfx)|secrets?)$'

# suspicious content in the staged diff
git diff --cached | grep -Ein \
  -e 'BEGIN [A-Z ]*PRIVATE KEY' \
  -e '(api[_-]?key|secret|token|pass(word|phrase)?|credential)[^a-zA-Z0-9_-]*[=:][[:space:]]*"[^"$]{8,}"' \
  -e '(AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20}|github_pat_[A-Za-z0-9_]+|sk-[A-Za-z0-9]{20}|xox[abpr]-|glpat-[A-Za-z0-9_-]{20}|sk_live_[A-Za-z0-9]+|AIza[0-9A-Za-z_-]{20})'
```

Exit status 1 from both greps means clean. On any match, or on any other
suspicion of credential material in the diff (high-entropy literals,
credentials embedded in URLs, pasted agent output), do nothing further: do
not commit, do not push, and report the matching lines to the user. A
confirmed false positive may be committed after the user clears it.

Known non-secrets that do not block automation: `sha256-...` derivation
hashes, `flake.lock` input hashes, and file-indirection references such as
`passwordFile = "/path"` (no literal credential value).
