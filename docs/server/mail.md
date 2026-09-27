# Mail server

The private host uses Stalwart Mail Server. The old Maddy and Roundcube
services are no longer enabled. No mailbox data is migrated; the new Stalwart
store starts empty.

## Access

The Stalwart web interface is available at `https://mail.outworld66.ru`.
The recovery administrator is `admin`; its generated password is stored only
on the server in `/var/lib/stalwart/admin-password`.

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

## Free provisioning helper

`stalwart-provision-pocket-users` reconciles local Stalwart accounts with
verified Pocket ID users in the `admins` or `media` groups. It creates missing
accounts, re-enables matching accounts, and disables SMTP/IMAP authentication
for accounts that leave the allowed set. It never deletes mailboxes, so the
script is safe to run manually without Stalwart Enterprise/SCIM.

The helper expects a Pocket ID API key file and Stalwart administrator
credentials:

```bash
ssh root@192.168.0.3 \
  'export POCKET_ID_API_KEY_FILE=/var/lib/pocket-id/static-api-key
   export STALWART_URL=http://127.0.0.1:8080
   export STALWART_USER=admin
   export STALWART_PASSWORD="$(cat /var/lib/stalwart/admin-password)"
   export STALWART_ALLOWED_GROUPS=admins,media
   stalwart-provision-pocket-users'
```

The helper is the free replacement for the SCIM lifecycle part. OIDC
authentication for those accounts still requires configuring Stalwart's OIDC
directory; the current deployment keeps the internal directory so Pocket ID
can continue using its password-authenticated SMTP account.
