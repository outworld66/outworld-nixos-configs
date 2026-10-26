# Pocket ID

Rico uses Pocket ID at `https://id.outworld66.ru` as its identity provider. The
old Pocket ID database and encryption key remain in `/var/lib/pocket-id`; the
service is being re-enabled against that existing database. Authentik is being
removed, and its PostgreSQL data is not imported.

## User and account migration

The private Nix configuration is the source of truth for three human users and
their service groups. The provisioning job reconciles existing Pocket ID users
by case-insensitive email, creates missing mapped users as email-verified, and
sets their usernames and groups. Synthetic test accounts, service identities,
and agent identities are not imported. Open registration is enabled. New users
receive no groups automatically, so registration alone does not grant access to
OIDC clients restricted to specific groups.

Pocket ID cannot import Authentik passwords or WebAuthn credentials. Users
created during this migration need a one-time access link from a Pocket ID
administrator, then must enroll a passkey. Existing Pocket ID users retain
their old user IDs and passkeys because the service reuses its existing
`/var/lib/pocket-id` database. Deleting and recreating a user changes its OIDC
subject and can orphan application accounts. Application accounts may also
need linking on first login if their former identity-provider subject differs.

## OIDC clients

Pocket ID provisions clients for Pomerium, File Browser, Immich, Donetick,
Gotify, Cloudreve, Stoat, OpenHands, and Streamline. Their client secrets are
stored in service state directories outside the Nix store. The `groups` claim
carries service roles such as `media-user`, `stoat-admin`, and `ai-user`.

New account creation in Stalwart is reconciled from the same private mapping:
only users assigned `mail-admin` or `mail-user` receive mail accounts. IMAP and
SMTP still use Stalwart passwords; these are independent of identity-provider
credentials.

## First activation and recovery

Before activation, ensure the existing Pocket ID state is included in the
server backup. Activation runs Pocket ID, provisions mapped users and OIDC
clients, and then starts dependent services. Verify the Pocket ID discovery
endpoint at `https://id.outworld66.ru/.well-known/openid-configuration`, sign
in to Pomerium, and test one native OIDC client. The old `identity.outworld66.ru`
host redirects to `id.outworld66.ru` for old bookmarks.

If Pocket ID does not start, follow the recovery workflow in
[`deployment.md`](deployment.md). Keep `/var/lib/pocket-id` and its encryption
key together; do not remove the retained Authentik database until the new
provider and application account links have been verified.
