# Mail server

Rico runs Stalwart 0.16.22. Its NixOS module stores the database at
`/var/lib/stalwart/db`, keeps the administrator and Pocket ID account passwords
in SOPS, and applies the initial server configuration through `stalwart-cli`.
The 0.15 database is not migrated during the 0.16 upgrade.

## Access

The Stalwart web interface is available at `https://mail.outworld66.ru`.
The administrator account is `admin@outworld66.ru`. Its password comes from
the private SOPS secret `mail/stalwart-admin-password`.

The Pocket ID mail account remains:

```text
pocket-id@outworld66.ru
```

Pocket ID uses this account to send verification mail through Stalwart on
submission port `587`.

## Public ports

The firewall and router continue to need the same mail ports:

- `25/tcp` — incoming SMTP from other mail servers;
- `465/tcp` — implicit-TLS SMTP submission;
- `587/tcp` — STARTTLS SMTP submission;
- `993/tcp` — implicit-TLS IMAP.

No new public port is required. Stalwart's HTTP listener is bound to
`127.0.0.1:8080` and is published through Caddy on `443`.

## Pocket ID account provisioning

`stalwart-provision-pocket-users` reconciles local Stalwart accounts with
verified Pocket ID users in the `mail-admin` or `mail-user` groups. It creates missing
accounts, re-enables matching accounts, and disables SMTP/IMAP authentication
for accounts that leave the allowed set. It never deletes mailboxes, so the
script is safe to run manually without Stalwart Enterprise/SCIM.

Run the helper on Rico as root. It reads the Pocket ID API key and the SOPS
managed Stalwart administrator password from their configured files:

```bash
ssh root@192.168.0.4 stalwart-provision-pocket-users
```

The helper is the free replacement for the SCIM lifecycle part. OIDC
authentication for those accounts still requires configuring Stalwart's OIDC
directory; the current deployment keeps the internal directory so Pocket ID
can continue using its password-authenticated SMTP account.

## DKIM DNS record

The current active DKIM public key can be printed as a DNS TXT record with:

```bash
ssh root@192.168.0.4 stalwart-dkim-dns
```

Copy both the DNS name and TXT value into the `outworld66.ru` DNS zone. The
command only reads the public key from Stalwart; it does not change DNS.
