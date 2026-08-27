# Private configuration template

Copy this directory next to the public checkout, rename it, replace the example
identity, then initialize it as a private Git repository. Do not publish this
repository.

Additional organization inputs and machine-specific modules belong here. Export
them through `hostConfigurations.<hostname>` and `specialArgs`; the public flake
consumes this repository with `--override-input private path:<directory>`.

Keep organization-specific Git identities in `personal.nix`. The system user
and default Git identity are defined by the public flake. Optional settings such
as `syncthing` and `proximityLock` may be omitted; their modules must remain
disabled when values are absent.

This repository is a library and does not need a committed `flake.lock`.
