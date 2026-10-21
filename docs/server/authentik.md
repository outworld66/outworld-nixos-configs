# Authentik identity migration

Authentik is deployed at `https://identity.outworld66.ru`. All configured
web-service OIDC clients, including Stoat, use Authentik. Existing application
links may use different subject identifiers from the previous identity
provider, so verify account linking per app. Pocket ID's service configuration
has been removed; its persistent data directory is retained for rollback and
has no active service. `https://id.outworld66.ru` redirects to Authentik to keep
old identity links working; the Pomerium global-sign-out page remains there.

Authentik's database is the identity and group directory. The repository
blueprint declares service groups, the LDAP provider, and its outpost; the
LDAP outpost exposes the same Authentik users and groups to services that need
LDAP. LDAP is a view of Authentik data, not a separate writable directory.
Keep LDAP bound to the host's loopback interface unless a service must connect
from another machine; use LDAPS for remote clients.

The NixOS packaging comes from the community `authentik-nix` project and is
not supported by the Authentik upstream project.

OAuth providers and applications are declared in the blueprint. Their client
secrets are generated once and stored under `/var/lib/authentik`; include that
directory in backups. Gotify links an existing local account when the
Authentik `preferred_username` matches its username; its admin permission is
reconciled from the `gotify-admin` group on each login.

## First setup

The NixOS module runs Authentik with the host's PostgreSQL service and sends
mail through Stalwart using the `id@outworld66.ru` mailbox.
The Authentik secret key is generated once and kept in
`/var/lib/authentik/environment`. Back up `/var/lib/authentik` together with
the Authentik PostgreSQL database; losing the key can invalidate encrypted
data in the database.

After deployment:

1. Complete Authentik's one-time initial setup. On Rico, the resulting `akadmin`
   account was renamed to `outworld66` while preserving its UUID and email.
   Its bootstrap password is encrypted at `authentik/admin-password` in the
   private SOPS file. Password changes made in Authentik must also be updated
   there; this value is not reapplied on service restart.
2. Confirm that Authentik can send a test email through Stalwart.
3. Wait for the `Outworld directory and LDAP` blueprint to apply. It creates
   the service groups, LDAP provider and outpost, and the email-verified
   enrollment flow. The normal login page links to that flow. Open enrollment
   is enabled; new users are inactive until they verify their email and receive
   only `registered` by default. The OIDC email scope maps the active state to
   `email_verified`, so inactive users cannot authenticate to OIDC clients.
4. The LDAP outpost token and the read-only `stalwart-ldap` bind password are
   reconciled at runtime from Authentik's database and stored under
   `/var/lib/authentik` and `/run/authentik-ldap`. LDAP and LDAPS listen only
   on loopback (`127.0.0.1:3389` and `127.0.0.1:6636`); do not expose them on
   the public firewall. The bind account belongs to the declarative
   `ldap-directory-reader` group, which has search access to the LDAP provider.
5. The remaining provider and application objects are reconciled from the
   blueprint. Check their callback URLs and `groups` claims in the blueprint
   when adding another OIDC client.

## Passkey and password sign-in

The default authentication flow skips its password stage for users with a
confirmed WebAuthn authenticator. Authentik then validates that authenticator
as the sign-in factor. Users without one continue to sign in with their
password; the standard MFA stage still applies to other authenticators they
have enrolled. The password-stage policy and its binding are declared in the
blueprint, so keep changes there rather than editing the built-in flow only in
the UI.

Users who have enrolled WebAuthn should register a backup passkey or retain an
administrator recovery path. The password stage is skipped while a confirmed
WebAuthn device remains registered, even if the user cannot access that device.

The existing service access groups are:

- `registered` — low-privilege default for open registration
- `media-admin`, `media-user`
- `donetick-admin`, `donetick-user`
- `gotify-admin`, `gotify-user`, `stats-user`
- `mail-admin`, `mail-user`
- `ai-admin`, `ai-user` (OpenHands; `ai-admin` is the application administrator)
- `stoat-admin`, `stoat-user`
- `ldap-directory-reader` — read-only full directory search for Stalwart

The former `admin` and `family` aliases are not needed in Authentik. Assign the
corresponding service groups directly to each user. Identity-provider
administrator access is managed through Authentik's built-in administrators
group, separately from service access groups.

## Registration and reserved access

The blueprint creates the low-privilege `registered` group and enrollment
flow. Private Nix configuration maps reserved, verified email addresses to
groups during enrollment. Unmapped registrations receive only `registered`.
For a one-off invitation with different rights, create a single-use invitation
in Authentik with fixed data containing the reserved email and service groups,
for example:

```json
{
  "email": "person@example.net",
  "groups": ["media-user", "mail-user"]
}
```

The flow's declarative policy checks the submitted address against the
invitation's fixed email and only accepts service group names defined by the
blueprint. A forwarded invitation cannot grant the reserved rights to a
different address. Send the invitation to the reserved mailbox from Authentik;
the person can finish registration later, verify the address, and choose their
own password. Invitations without a service group list are rejected. For open
registration, no invitation is present, so the account receives only
`registered`.

## OIDC clients to migrate

These configured services now use Authentik OIDC, with client secrets stored
outside the Nix store:

- Pomerium, File Browser, Immich, Donetick, Gotify, Cloudreve, Streamline,
  Stoat, and OpenHands

Stoat is declared in `hosts/rico/stoat.nix` and uses a pinned Outworld backend
fork with OIDC support. Its callback is
`https://stoat.outworld66.ru/api/auth/session/oidc/callback`. The web and API
containers are part of the declarative Compose stack; OIDC credentials are
generated at runtime from the Authentik client secret.

Stalwart account reconciliation now reads verified, active users and their
`mail-admin` or `mail-user` memberships from the local Authentik LDAP outpost.
IMAP and SMTP clients continue to use Stalwart credentials directly.

The Pocket ID service, package input, and client-provisioning job have been
removed. Its state directory remains on disk as a rollback copy; remove it only
after the Authentik sign-in and account-link checks are complete and the backup
retention window has passed.

## Recovery

If an Authentik sign-in fails, use the application's local recovery account
where available and restore Authentik's PostgreSQL database and
`/var/lib/authentik` from the same backup point. For a host deployment failure,
follow the recovery procedure in [`deployment.md`](deployment.md).
