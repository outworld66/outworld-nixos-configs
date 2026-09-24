# Authelia

The private server uses three HTTPS names:

- `auth.private.outworld66.ru` — Authelia portal;
- `stats.private.outworld66.ru` — GoAccess, restricted to the `admins` group;
- `files.private.outworld66.ru` — WebDAV with WebDAV Basic Authentication.

Authelia protects GoAccess through Caddy `forward_auth`. WebDAV keeps its own
Basic Authentication because desktop WebDAV clients do not reliably support a
browser redirect to an Authelia login portal. WebDAV users and their
directories are configured separately in the WebDAV settings.

## Add Authelia secrets

The private flake expects these keys in the SOPS file:

```yaml
authelia:
  storage-encryption-key: generate-a-long-random-value
  session-secret: generate-another-long-random-value
  jwt-secret: generate-one-more-long-random-value
  users-database: |
    users:
      admin:
        disabled: false
        displayname: Administrator
        password: "$argon2id$..."
        groups:
          - admins
      user:
        disabled: false
        displayname: User
        password: "$argon2id$..."
        groups: []
```

Use `sops` to edit the existing private file. Do not commit plaintext values.
Generate Argon2 password hashes locally with the Authelia CLI and insert only
the hashes into the users database.

## TLS

Caddy currently uses its `internal` CA because the server address is local.
Clients must trust Caddy's local root CA before opening the HTTPS services. If
the DNS record later points to a publicly reachable address, replace `tls
internal` with the normal public certificate configuration.

## Apply order

1. Add the Authelia secrets and users database to the private SOPS file.
2. Run `task dns` and apply the three DNS records.
3. Trust Caddy's local CA on each client.
4. Deploy the NixOS configuration with `task server-update -- private`.

The first login to GoAccess must use a user in the `admins` group. Users not
in that group are denied by Authelia.
