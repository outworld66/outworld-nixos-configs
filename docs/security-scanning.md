# Security scanning

Run the CVE scan from the public repository root:

```bash
task cve
```

The task evaluates the local public, private, and package repositories without
writing `flake.lock`, builds each selected NixOS system closure, and scans its
runtime closure with `vulnix`. It then reads each selected host's configured
OCI image references from the evaluated NixOS configuration and scans those
images with Trivy. The default `CVE_HOST=all` covers every NixOS configuration;
set `CVE_HOST` to a hostname such as `rico` to scan just that configuration.

The scanners download or refresh their vulnerability data, so the task needs
network access. It uses the scanner versions from the locked nixpkgs input.
Finding a CVE makes the task return a non-zero status; image scans include
unfixed findings. Review reported package versions and advisories before
deciding on an update.

`vulnix` matches Nix package names and versions against NVD entries using a
heuristic, so its results can include false positives and may miss advisories
whose product names do not match. Trivy scans container image contents using
its vulnerability database. Neither scan proves that a system is free of
vulnerabilities; they report matches known to their data sources at scan time.
