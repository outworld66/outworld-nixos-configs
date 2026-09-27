# Pocket ID

The server uses Pocket ID at `https://id.outworld66.ru` as its OIDC identity
provider. Browser-based services are protected by OAuth2 Proxy at
`https://auth.outworld66.ru`; the OAuth2 client is created automatically during
activation.

The default Pocket ID signup group is `nogroup`. It has no service access.
Grant users membership in `admins` or `media` from Pocket ID as needed.

The following services require the `admins` or `media` group through OAuth2
Proxy:

- `home.outworld66.ru` — Homepage;
- `stats.outworld66.ru` — GoAccess;
- `bitmagnet.outworld66.ru` — Bitmagnet;
- `elengrab.outworld66.ru` — Elengrab;
- `donetick.outworld66.ru` — Donetick;
- `cloudreve.outworld66.ru` — Cloudreve;
- `immich.outworld66.ru` — Immich;
- `webmail.outworld66.ru` — Roundcube.

Gotify and Immich also use their native OIDC integrations. WebDAV keeps its
own Basic Authentication because desktop WebDAV clients do not reliably
support browser-based OIDC redirects.

## Apply order

1. Verify the Pocket ID OIDC client is provisioned after deployment.
2. Open `https://auth.outworld66.ru/oauth2/start` and sign in with Pocket ID.
3. Open the requested service.

New users can register in Pocket ID, but remain in `nogroup` until explicitly
granted access.
