# Pocket ID

The server uses Pocket ID at `https://id.outworld66.ru` as its OIDC identity
provider. Browser-based services are protected by OAuth2 Proxy at
`https://auth.outworld66.ru`; the OAuth2 client is created automatically during
activation.

## Users and groups

Pocket ID is the source of truth for users, group membership, and the OIDC
`groups` claim. The public configuration does not contain organization-specific
email mappings; those are defined in the companion private repository at
`modules/server-secrets.nix` through `services.pocket-id.userGroupMappings`.

The server creates these groups automatically:

- `nogroup` — the default group for newly registered users; it grants no
  service access;
- `media` — access to the media and general user services;
- `admins` — administrative access.

Email mappings are applied only to verified Pocket ID users. The provisioning
job adds the mapped group to the user's existing groups; it does not remove
groups manually assigned in the Pocket ID UI. The job runs automatically after
activation and periodically from its systemd timer.

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
- `immich.outworld66.ru` — Immich;
- `webmail.outworld66.ru` — Roundcube.

`stats.outworld66.ru` is an exception: Caddy performs the common OIDC check
and then permits only the `admins` group before serving GoAccess or its
websocket.

Gotify uses its native OIDC integration and accepts only `admins`. Immich also
has a native Pocket ID OIDC login, while its public web endpoint is protected
by the common OAuth2 Proxy. WebDAV keeps its own Basic Authentication because
desktop WebDAV clients do not reliably support browser-based OIDC redirects.

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
