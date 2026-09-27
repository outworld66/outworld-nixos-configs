# Pocket ID

The server uses Pocket ID at `https://id.outworld66.ru` as its OIDC identity
provider. Browser-based services are protected by OAuth2 Proxy at
`https://auth.outworld66.ru`; the OAuth2 client is created automatically during
activation.

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

- `nogroup` — the default group for newly registered users; it grants no
  service access;
- `media` — access to the media and general user services;
- `admins` — administrative access to protected services and to the Pocket ID
  administration UI.

The `admins` group is also synchronized to Pocket ID's built-in administrator
flag. It is therefore the only group that grants access to the Pocket ID admin
UI; `media` and `nogroup` remain regular user groups.

Email mappings are applied only to verified Pocket ID users. The provisioning
job adds all groups listed for the email to the user's existing groups; it does
not remove groups manually assigned in the Pocket ID UI. Keep one mapping per
email and put all assigned groups in its `groups` list. The job runs
automatically after activation and periodically from its systemd timer.

For example, the private configuration maps the administrator's verified
address to `admins` and the media user's verified address to `media`. A new
signup still starts in `nogroup` until it is explicitly assigned another group.

## Service access

The service ACL is separate from the Pocket ID group mapping. OAuth2 Proxy
allows users in `admins` or `media` for the common browser-protected services:

- `home.outworld66.ru` — Homepage;
- `bitmagnet.outworld66.ru` — Bitmagnet;
- `elengrab.outworld66.ru` — Elengrab;
- `donetick.outworld66.ru` — Donetick;
- `cloudreve.outworld66.ru` — Cloudreve;
- `mail.outworld66.ru` — Stalwart Mail Server.

`stats.outworld66.ru` is an exception: Caddy performs the common OIDC check
and then permits only the `admins` group before serving GoAccess or its
websocket.

Gotify uses its native OIDC integration and accepts only `admins`. Immich uses
its native Pocket ID OIDC login for both the web and mobile clients; it is not
wrapped in the common OAuth2 Proxy. Immich does not auto-register OAuth users,
so an administrator must create an Immich account before its owner can log in.
Users who only have `nogroup` cannot create or use an Immich account. WebDAV
keeps its own Basic Authentication because desktop WebDAV clients do not
reliably support browser-based OIDC redirects.

Immich role mapping is declared separately in
`server.immich.oauthRoleMappings`: Pocket ID `admins` maps to the Immich
`admin` role, and Pocket ID `media` maps to the Immich `user` role. These are
Immich application roles, not additional Pocket ID groups.

The relevant access rules live in `hosts/private/services.nix`; Pocket ID's
group creation, email mapping application, and OIDC client provisioning live
in `nixos/modules/server/pocket-id/default.nix`. Adding a user to a Pocket ID
group does not by itself grant access to every service: the service's Caddy,
OAuth2 Proxy, or native OIDC configuration must also allow that group.

## Apply order

1. Verify the Pocket ID OIDC client is provisioned after deployment.
2. Open `https://auth.outworld66.ru/oauth2/start` and sign in with Pocket ID.
3. Open the requested service.

New users can register in Pocket ID, but remain in `nogroup` until explicitly
granted access.
