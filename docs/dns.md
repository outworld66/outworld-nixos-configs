# DNS management

DNS records for `outworld66.ru.` are managed with octoDNS and Selectel's
current DNS Hosting API. The repository manages the `private` record through
the managed source; the imported source preserves the rest of the existing
zone.

The Selectel DNS provider expects a Keystone project token in
`KEYSTONE_PROJECT_TOKEN`. Keep the token outside the repository. For example,
load it from the private SOPS checkout with `sops exec-env`.

## Initial import

Import the current Selectel zone before the first plan:

```sh
sops exec-env ../outworld-nixos-private/secrets/selectel.yaml \
  'task dns-import'
```

Review the generated `.octodns/zones/imported/outworld66.ru.yaml` and commit
it. The first import is intentionally separate from synchronization so that
existing records are not accidentally removed.

## Plan and apply

Show the changes without modifying Selectel:

```sh
sops exec-env ../outworld-nixos-private/secrets/selectel.yaml \
  'task dns-plan'
```

Apply the reviewed plan explicitly:

```sh
sops exec-env ../outworld-nixos-private/secrets/selectel.yaml \
  'DNS_CONFIRM=apply task dns-sync'
```

The managed file currently points `private.outworld66.ru.` to the temporary
address `192.168.0.3`. Replace it before exposing the service outside the
local network.

The Selectel zone must use the current DNS Hosting service and the
`a.ns.selectel.ru`, `b.ns.selectel.ru`, `c.ns.selectel.ru`, and
`d.ns.selectel.ru` authoritative servers. Do not use the deprecated legacy
DNS API.
