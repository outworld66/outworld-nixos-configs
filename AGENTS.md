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
- Do not stage or commit unrelated or pre-existing dirty state; committing and
  pushing follows the automated policy below and requires its mandatory secret
  check.
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
- Keep comments focused on non-obvious constraints and reasons, not a
  line-by-line restatement of Nix syntax.

## Automated commit and push

When the requested changes are complete and the Validation requirements for
the changed file types have passed, commit and push to `origin/main` without
asking for confirmation. This permission is scoped to the current task only:
stage the files this task touched (explicit `git add <paths>`; `git add .`
only when every change in the worktree belongs to the task), and never
commit in a sibling repository as part of the same task.

Sequence:

1. Stage the task's files.
2. Run the secret check below; any match or suspicion aborts the automation.
3. Commit with a concise message describing the change.
4. Push the current branch to its existing upstream only. If the branch has
   no upstream, stop and ask. Never force-push.

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
