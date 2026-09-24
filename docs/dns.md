# DNS management

DNS records for `outworld66.ru.` are managed with octoDNS and Selectel's
current DNS Hosting API. The repository manages the `private` record through
the managed source; the imported source preserves the rest of the existing
zone.

The Selectel DNS provider expects a short-lived Keystone project token in
`KEYSTONE_PROJECT_TOKEN`. Keep it only in the current shell and do not store it
in Git, SOPS, shell history, or a persistent environment file:

```sh
read -rsp 'Selectel token: ' KEYSTONE_PROJECT_TOKEN
export KEYSTONE_PROJECT_TOKEN
echo
```

## Plan and apply

Run the single interactive task:

```sh
task dns
```

On the first run, the task imports the current Selectel zone into
`.octodns/zones/imported/outworld66.ru.yaml`. Review the generated file and
commit it. The task then shows the plan and asks for confirmation before
modifying Selectel.

The task reads `KEYSTONE_PROJECT_TOKEN` without echoing it. If the variable is
already set, it reuses that value; otherwise it prompts for the token. The
token exists only in the task process and is not saved by the repository.

The managed file currently points `private.outworld66.ru.` to the temporary
address `192.168.0.3`. Replace it before exposing the service outside the
local network.

The Selectel zone must use the current DNS Hosting service and the
`a.ns.selectel.ru`, `b.ns.selectel.ru`, `c.ns.selectel.ru`, and
`d.ns.selectel.ru` authoritative servers. Do not use the deprecated legacy
DNS API.
