# Authelia

The private server uses four HTTPS names:

- `auth.outworld66.ru` — Authelia portal;
- `home.outworld66.ru` — Homepage service dashboard, available to
  every authenticated user;
- `stats.outworld66.ru` — GoAccess, restricted to the `admins` group;
- `files.outworld66.ru` — WebDAV with WebDAV Basic Authentication.

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

## Generate an Argon2 password hash

Run the Authelia CLI once through Nix:

```sh
nix run nixpkgs#authelia -- crypto hash generate argon2
```

Enter the password and confirmation, then copy the value after `Digest:` into
the user's `password` field. The generated digest already contains its salt:

```yaml
password: "$argon2id$v=19$m=65536,t=3,p=4$..."
```

For a one-off non-interactive invocation, use `--password` (avoid this for real
passwords because the value can be visible in shell history and process lists):

```sh
nix run nixpkgs#authelia -- crypto hash generate argon2 --password 'replace-me'
```

Keep both the plaintext password and the resulting hash out of the public
repository. See the [Authelia password hashing guide](https://www.authelia.com/reference/guides/passwords/)
for the command reference and users-file format.

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
