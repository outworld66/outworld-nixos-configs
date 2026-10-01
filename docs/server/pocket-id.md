# Pocket ID

The server uses Pocket ID at `https://id.outworld66.ru` as its OIDC identity
provider. Browser-based services are protected by Pomerium at
`https://auth.outworld66.ru`; the Pomerium OIDC client and persistent session
secrets are created automatically during activation.

## Android passkeys with KeePassDX

When using KeePassDX Libre with Pocket ID in Chrome or another Android browser,
add that browser manually to `Settings -> Form filling -> Passkeys settings ->
Privileged apps`. Otherwise KeePassDX can create the passkey successfully but
later return an invalid WebAuthn signature during login. The KeePassDX Free
build validates the browser automatically.

If login still fails after changing this setting, remove the affected passkey
from Pocket ID and create it again from the browser. Do not disable WebAuthn
signature validation on the server.

## Users and groups

Pocket ID is the source of truth for users, group membership, and the OIDC
`groups` claim. The public configuration does not contain organization-specific
email mappings; those are defined in the companion private repository at
`modules/server-secrets.nix` through `services.pocket-id.userGroupMappings`.

The server creates these groups automatically:

- `media` — access to the media and general user services;
- `donetick` — access to Donetick;
- `admins` — administrative access to protected services and to the Pocket ID
  administration UI.

The `admins` group is also synchronized to Pocket ID's built-in administrator
flag. It is therefore the only group that grants access to the Pocket ID admin
UI; `media` remains a regular user group.

The AI role groups `ai-admin` and `ai-user` are provisioned as managed groups.
The private `admin` mapping also assigns `ai-admin`, so mapped administrators
can manage LiteLLM and future AI services. `ai-user` currently has no members.
On LiteLLM, `ai-user` is limited to the Model Hub and its public metadata;
`ai-admin` can access the full UI and Swagger. Model API requests under `/v1`
continue to use LiteLLM Bearer keys. The Model Hub may also require a LiteLLM
user API key to load its model list.

Email mappings are applied only to verified Pocket ID users. The provisioning
job adds all groups listed for the email to the user's existing groups; it does
not remove groups manually assigned in the Pocket ID UI. Keep one mapping per
email and put all assigned groups in its `groups` list. The job runs
automatically after activation and periodically from its systemd timer.

For example, the private configuration maps the administrator's verified
address to `admins` and the media user's verified address to `media` and
`donetick`. New users
without a configured mapping have no service groups and therefore do not match
the protected service policies.

## Service access

The service ACL is separate from the Pocket ID group mapping. Pomerium
allows users in `admins` or `media` for the common browser-protected services:

- `home.outworld66.ru` — Homepage;
- `bitmagnet.outworld66.ru` — Bitmagnet;
- `elengrab.outworld66.ru` — Elengrab;
- `donetick.outworld66.ru` — Donetick;
- `cloudreve.outworld66.ru` — Cloudreve;

`donetick.outworld66.ru` also permits the dedicated `donetick` group.
`stats.outworld66.ru` is an exception: Pomerium permits only the `admins`
group before proxying GoAccess and its websocket.
The LiteLLM web interface and non-API routes on `llm.outworld66.ru` also
require `admins`; its `/v1` model API remains protected by LiteLLM Bearer keys.

Gotify uses its native OIDC integration and accepts only `admins`. Immich uses
its native Pocket ID OIDC login for both the web and mobile clients; it is not
wrapped in Pomerium. Immich does not auto-register OAuth users, so an existing
Immich account must use the same email as the verified Pocket ID account before
its owner can log in. WebDAV keeps its own Basic Authentication because desktop
WebDAV clients do not reliably support browser-based OIDC redirects.

Immich role mapping is declared separately in
`server.immich.oauthRoleMappings`: Pocket ID `admins` maps to the Immich
`admin` role, and Pocket ID `media` maps to the Immich `user` role. These are
Immich application roles, not additional Pocket ID groups.

The relevant access rules live in `hosts/rico/services.nix`; Pocket ID's group
creation, email mapping application, and OIDC client provisioning live in
`nixos/modules/server/pocket-id/default.nix`, with organization-specific group
mappings in the private flake. Adding a user to a Pocket ID group does not by
itself grant access to every service: the service's Pomerium, Caddy, or native
OIDC configuration must also allow that group.

## Apply order

1. Verify the Pocket ID OIDC client is provisioned after deployment.
2. Open `https://auth.outworld66.ru` and sign in with Pocket ID.
3. Open the requested service.

New users can register in Pocket ID, but remain without service access until
explicitly granted an allowed group.
