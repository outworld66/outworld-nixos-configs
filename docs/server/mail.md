# Mail server

Rico runs Stalwart 0.16.22. Its NixOS module stores the database at
`/var/lib/stalwart/db`, keeps the administrator and Pocket ID SMTP account
passwords in SOPS, and applies the initial server configuration through
`stalwart-cli`.
The 0.15 database is not migrated during the 0.16 upgrade.

## Access

The Stalwart web interface is available at `https://mail.outworld66.ru`.
The administrator account is `admin@outworld66.ru`. Its password comes from
the private SOPS secret `mail/stalwart-admin-password`.

The Pocket ID mail account is:

```text
id@outworld66.ru
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

`stalwart-provision-pocket-id-users` reconciles local Stalwart accounts from
the private Pocket ID user-group mapping. Users with `mail-admin` or `mail-user`
are added; accounts that leave those groups have SMTP/IMAP authentication
disabled. The helper preserves the explicit SOPS mailboxes and never deletes
mailboxes.

Run the helper on Rico as root. It reads the Stalwart administrator password from its configured file:

```bash
ssh root@192.168.0.4 stalwart-provision-pocket-id-users
```

The `outworld66@outworld66.ru` mailbox password is stored in the private
repository's SOPS file. To display it locally when needed:

```bash
nix run nixpkgs#sops -- --decrypt --extract '["mail"]["outworld66-password"]' ../outworld-nixos-private/secrets/private.yaml
```

The helper reconciles account creation and login eligibility; IMAP and SMTP
clients continue to authenticate with Stalwart passwords. Pocket ID changes do
not migrate Stalwart mailbox passwords.

## DKIM DNS record

The current active DKIM public key can be printed as a DNS TXT record with:

```bash
ssh root@192.168.0.4 stalwart-dkim-dns
```

Copy both the DNS name and TXT value into the `outworld66.ru` DNS zone. The
command only reads the public key from Stalwart; it does not change DNS.
