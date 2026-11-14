# Miniflux and Linkwarden on Rico

Miniflux collects RSS, Atom, JSON Feed, and YouTube channel feeds. Linkwarden
stores links and preserves selected pages. Both services use Pocket ID OIDC and
are available at:

- Miniflux: <https://miniflux.outworld66.ru>
- Linkwarden: <https://linkwarden.outworld66.ru>

Pocket ID restricts both OIDC clients to the `miniflux-admin` and
`linkwarden-admin` groups. The `outworld66` Pocket ID user is the initial
Miniflux administrator and the first Linkwarden account. Local password login
is disabled for both services.

## Connect Miniflux to Linkwarden

Miniflux includes a Linkwarden integration that saves a feed entry as a
Linkwarden bookmark. Create the API key once after the first login:

1. Sign in to Linkwarden with Pocket ID.
2. In Linkwarden settings, create an API key and copy it.
3. In Miniflux, open **Settings → Integrations → Linkwarden**.
4. Set the Linkwarden URL to `https://linkwarden.outworld66.ru`, paste the API
   key, and optionally choose a collection ID. Save the integration.
5. Use the Linkwarden action on an entry to save it.

The API key is stored in Miniflux's database. Revoke it in Linkwarden and
replace it in Miniflux if it is exposed. The integration sends the entry URL
and title; Linkwarden then handles page preservation.

## Operations

The Miniflux database is in the host PostgreSQL service. Linkwarden stores
preserved data under `/srv/linkwarden/data`; its PostgreSQL and Meilisearch data
are under `/var/lib/linkwarden/`. Runtime credentials are generated under
`/var/lib/miniflux-secrets/` and `/var/lib/linkwarden-secrets/`, outside the
Nix store.

Check the services:

```bash
systemctl status miniflux docker-linkwarden docker-linkwarden-postgres docker-linkwarden-meilisearch
curl -fsS https://miniflux.outworld66.ru/healthcheck
curl -fsS -o /dev/null -w '%{http_code}\n' https://linkwarden.outworld66.ru/
```

The first OIDC login to Miniflux links to the pre-created `outworld66`
administrator account. If the Pocket ID username changes, update Miniflux's
bootstrap `ADMIN_USERNAME` in its runtime environment and account mapping
before logging in.
