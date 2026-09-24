# NixOS and Home Manager configuration

This repository contains reusable NixOS and Home Manager modules, desktop and
server host profiles, package re-exports, formatting, checks, and developer
tooling.
Identity and organization-specific inputs belong in a separate private flake.
Host hardware configurations and Disko layouts are versioned here, so review
their hardware identifiers and device paths before publishing.

See the [repository layout](docs/repository.md), [development workflow](docs/workflow.md),
[deployment models](docs/deployment.md), [server bootstrap sequence](docs/server-bootstrap.md),
and [installation guide](docs/install-nixos.md).

The public flake is the only system entry point. Its bundled `private` input is
an empty library, so the repository evaluates without a private checkout or
access to organization repositories. Reusable package derivations come from
the public `outworld-nixos-packages` input. Without private data the user
defaults to `nixos` and optional private modules are absent.
