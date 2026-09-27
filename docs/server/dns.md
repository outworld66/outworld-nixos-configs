# DNS management

DNS records for `outworld66.ru.` are managed with octoDNS and Selectel's
current DNS Hosting API. The repository manages the private host and mail
records through the managed source; the imported source preserves the rest of
the existing zone.

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

The mail host is published at `85.142.172.131`, while the application host
remains on the private address `192.168.0.3`.

For Stalwart, forward these TCP ports from `85.142.172.131` to `192.168.0.3`:

- `25` for inbound SMTP and direct MX delivery;
- `465` for authenticated SMTPS submission;
- `993` for IMAPS mailbox access.

Port `587` may also be forwarded for clients that use SMTP submission with
STARTTLS. Port `143` is optional and should normally remain private.

The Selectel zone must use the current DNS Hosting service and the
`a.ns.selectel.ru`, `b.ns.selectel.ru`, `c.ns.selectel.ru`, and
`d.ns.selectel.ru` authoritative servers. Do not use the deprecated legacy
DNS API.
