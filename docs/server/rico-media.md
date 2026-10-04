# Media services on Rico

Rico's shared media tree is `/srv/media`, on the mergerfs mount combining
`/data1` and `/data2`. It is separate from the existing Immich and Cloudreve data.
The `media` group grants qBittorrent, Bindery, Streamline, and Jellyfin access
to the shared tree. The setgid directories keep files in that group. Jellyfin
has read-only access to the library. Jackett does not need filesystem access.

Administrative interfaces are routed through Caddy and Pomerium and restricted
to `media-admin`:

- qBittorrent: `torrent.outworld66.ru`
- Jackett: `jackett.outworld66.ru`
- Prowlarr: `prowlarr.outworld66.ru`
- Bindery: `books.outworld66.ru`
- Streamline: `streamline.outworld66.ru`, protected by its native Pocket ID
  OIDC login and restricted to the `media-admin` and `media-user` groups.
- Jellyfin: `jellyfin.outworld66.ru`, served directly by Caddy with TLS and
  Jellyfin's native login. It is not behind Pomerium, so native TV and mobile
  clients can authenticate normally.

The qBittorrent, Jackett, and Prowlarr web ports are not opened in the firewall.
Bindery uses host networking so it can connect to loopback-only qBittorrent;
its 8787 port is also closed in the firewall and reached through Pomerium.
qBittorrent listens on loopback; Jackett and Prowlarr are reached through their
Pomerium routes.
The qBittorrent Pomerium route preserves the public Host header so its Web UI
accepts requests whose Host and Origin both use `torrent.outworld66.ru`.
Jellyfin's `8096` backend port is not opened in the firewall.

## Authentication

Pomerium delegates interactive sign-in to Pocket ID. qBittorrent, Jackett,
Prowlarr, Bindery, Bitmagnet, and Homepage are reached through Pomerium.
Management interfaces allow `media-admin`; Bitmagnet also allows `media-user`.
Streamline uses its native Pocket ID OIDC login and
restricts its Pocket ID client to `media-admin` and `media-user`. Streamline
3.2.0 assigns newly provisioned OIDC users the default `member` role; linking
the seeded administrator by email preserves that account's existing role.
Service credentials and API keys are configured in each application for local
service-to-service calls.

Jellyfin is the exception: Caddy terminates TLS and Jellyfin authenticates its
own accounts. Pomerium's browser redirect cannot serve as the only login path
for native TV/mobile clients that call Jellyfin APIs and request media streams
directly. Jellyfin requires WebSocket support and correct proxy forwarding for
those clients ([Jellyfin reverse-proxy guidance](https://jellyfin.org/docs/general/post-install/networking/reverse-proxy/)).
A community Pocket ID SSO plugin exists, but it is not part of the pinned
NixOS service module and is not managed by this configuration; native Jellyfin
login remains the supported path here. The plugin's Pocket ID setup is
documented by the [plugin project](https://github.com/Flowfin/jellyfin-plugin-sso).

Internal integrations use loopback endpoints and the target application's own
credentials: Bindery and Streamline use qBittorrent's Web UI credentials;
Bindery and Streamline use Jackett's loopback aggregate Torznab endpoint;
Streamline also queries Bitmagnet's Torznab endpoint and Prowlarr's search API.
`media-stack-bootstrap` configures Bindery's connections; Streamline's are
declared in Nix. Bitmagnet's Torznab API has no API-key authentication, so
Streamline uses an empty key file for that connection. Prowlarr generates its
own API key at first start; a local systemd helper copies it into
`/var/lib/streamline` and Streamline receives it as a systemd credential.
Streamline's Jellyfin integration uses
`https://jellyfin.outworld66.ru`: Streamline uses this single URL both for its
API connection and for **Play on** links, so it must be a browser-reachable
address rather than `127.0.0.1`. Rico can reach the public hostname through
Caddy. Pomerium is not placed between these services because their API requests
are not interactive browser sessions. The public TCP/UDP peer port `51413` is
BitTorrent traffic, not a web login endpoint, so Pocket ID/Pomerium cannot
authenticate it.

Other public Rico services keep their existing authentication: Cloudreve,
Donetick, Gotify, and Immich use Pocket ID OIDC; NocoDB, Elengrab, Prowlarr,
LiteLLM's browser UI, stats, and Homepage use Pomerium. Pocket ID and Pomerium's own
authenticate endpoint must remain reachable to complete login flows. WebDAV
and mail clients use their protocol-level credentials because redirect-based
Pomerium login does not work with WebDAV, IMAP, or SMTP clients. LibreSpeed
and the static portfolio stay public by design: the speed test is for anonymous
visitors, and the portfolio is public content.

## Shared paths

All media paths are below `/srv/media`, the mergerfs mount that combines
`/data1` and `/data2`:

```text
/srv/media/
├── downloads/
│   ├── incomplete/             # qBittorrent temporary/in-progress files
│   └── complete/
│       ├── movies/             # retained qBittorrent category
│       ├── tv/                  # retained qBittorrent category
│       ├── books/               # qBittorrent category used by Bindery
│       └── streamline/          # Streamline completed downloads
└── library/{movies,tv,books,audiobooks}/
```

qBittorrent writes completed downloads to the category folders above.
Streamline imports movies into `/srv/media/library/movies` and series into
`/srv/media/library/tv`; Bindery uses the books download folder and the
books/audiobooks library folders.
Jellyfin reads only `/srv/media/library/movies` and
`/srv/media/library/tv`, which are configured as its Movies and TV libraries.
The services use one mergerfs namespace over two filesystems. Streamline
uses copy mode because mergerfs can place the download and library directories
on different backing filesystems. Jellyfin sees the imported file through its
library scan. Jellyfin scans libraries every 12 hours; after a Streamline
import, use **Dashboard → Libraries → Scan All Libraries** to make the new
item appear immediately.

`/var/lib/streamline/data` is Streamline's local application state, including
its SQLite database. It is not a download or media directory; keep it on the
system disk. qBittorrent downloads and the Jellyfin library already use the
`/srv/media` mergerfs mount.

Use Streamline to search for or request a movie or series. Streamline submits
the torrent to qBittorrent and imports the completed file into the matching
Jellyfin library folder. Its indexer sources are:

- **Jackett (all)** queries Jackett's aggregate Torznab feed. It includes every
  indexer currently configured in Jackett, so Jackett additions appear on the
  next Streamline search. This gives up per-indexer controls in Streamline;
  a slow tracker can delay the combined response, and Jackett caps the
  aggregate at 1,000 results.
- **Bitmagnet** queries `http://127.0.0.1:3333/torznab` directly. Bitmagnet's
  official [Servarr integration guide](https://bitmagnet.io/guides/servarr-integration.html)
  documents this Torznab endpoint.
- **Prowlarr** uses its native search API at `http://127.0.0.1:9696`. Prowlarr
  starts without configured trackers; add indexers in its UI at
  `https://prowlarr.outworld66.ru`. Those Prowlarr indexers are queried by
  Streamline automatically on later searches.

Prowlarr and Jackett do not automatically synchronize their tracker
definitions. Adding an indexer to Jackett does not add it to Prowlarr, and
vice versa. Keep using Jackett's aggregate for Jackett-managed trackers; use
Prowlarr for additional trackers you add there. This avoids a migration step
and keeps private tracker credentials inside the manager where they were
entered. Prowlarr does not need its own download client for searches initiated
by Streamline; Streamline sends selected releases to qBittorrent directly.

The firewall allows peer traffic on TCP/UDP 51413. Forward that port on the
router if incoming peer connectivity is desired. The qBittorrent Web UI
remains closed to network interfaces.

Streamline's Jackett search failure and the local compatibility fix are
documented in [Streamline Jackett search](./streamline-jackett-search.md).

## Declarative setup

The `media-stack-bootstrap.service` reconciles the first-run state and service
connections after the applications start. It reads administrator passwords
from SOPS and does not put them in the Nix store or journal. To create a missing
password once, run `scripts/bootstrap-media-passwords`; it preserves existing
values and never prints them.

On activation, the bootstrap service:

- Sets qBittorrent's Web UI password and creates `movies`, `tv`, `books`, and
  `streamline`
  categories with the matching shared download paths, updating existing
  category locations when the media mount changes.
- Creates Jellyfin's Movies and TV libraries from the merged mount, replacing
  old disk-specific library paths.
- Creates the Bindery `admin` account from SOPS and connects its qBittorrent
  downloader and Jackett indexer.

Streamline seeds its initial administrator from SOPS on first start. The
Pocket ID provisioning service creates its OIDC client. Streamline's declared
configuration connects qBittorrent, Jackett's aggregate feed, Bitmagnet, and
Prowlarr. Jackett reads its configured indexers when the feed is queried, so
adding or removing an indexer in Jackett takes effect in Streamline on the next
search without a Nix change or service restart. Prowlarr's sources are managed
separately in its UI. If you regenerate Prowlarr's API key, run
`systemctl restart streamline-prowlarr-key.service streamline.service` to
refresh Streamline's copy.

qBittorrent and Bindery use their SOPS-managed local admin credentials.
Streamline uses native Pocket ID OIDC and keeps a SOPS-seeded local account for
recovery. Jackett has no local multi-user accounts: Pomerium is its web login.
Add or manage tracker connections in Jackett itself. Any private tracker
credentials stay in Jackett's runtime configuration.

For anime, add the show from **Series → Add Series**, then use the series menu's
**Series type** action and choose **Anime**. This enables absolute episode
number matching. Search by an English, Japanese, or romanized title, verify
the TVDB result, then run a release search for the season or episode. Streamline
3.2.0 matches standard episode filenames such as `Show.S01E01.mkv`; filenames
such as `Show.S01.E01.mkv` do not match its parser and need to be normalized
before a library import can attach them. An empty Jellyfin library does not
need to be imported before adding a series.

Streamline is the only movie and TV request and management application.
Jackett provides the aggregate Torznab feed, Bitmagnet and Prowlarr provide
additional search sources, qBittorrent downloads, and Jellyfin serves the
media. Streamline writes into the existing Jellyfin
library folders and uses copy imports so downloads work even when mergerfs
places source and destination on different backing disks.

Streamline uses loopback port `8097`; it is not opened in the firewall. Caddy
proxies directly to it. The `/login` page starts Pocket ID sign-in, and Caddy
rejects the local password-login and registration endpoints. Streamline has
no native option to disable password authentication, so these endpoints must
remain blocked at the public reverse proxy. Its Pocket ID client is provisioned
with only the `media-admin` and `media-user` groups allowed. Streamline 3.2.0
does not request a `groups` OIDC scope, so group-to-role mapping is unavailable;
new OIDC accounts receive the default `member` role. The seeded administrator
keeps its role when linked by email. The client secret stays under
`/var/lib/streamline`. The service reads the qBittorrent
password from SOPS and refreshes its Jackett API credential from Jackett's
runtime configuration before Streamline starts. Its Prowlarr API credential
is read from Prowlarr's runtime `config.xml` in the same way. Prowlarr itself
uses its `External` authentication mode behind the Pomerium route, which
forwards the authenticated Pocket ID email as `X-Remote-User`; its UI is
restricted to `media-admin`, and its backend only listens on loopback. This
delegated login is why Prowlarr does not have a second SOPS-managed local
password. The Streamline integration uses Prowlarr's API key, not the UI
session.

Streamline requires a TheTVDB API key for TV lookups and a TMDB API Read Access
Token for movie lookups. Missing credentials produce HTTP 401 responses, so
movie search and TV library import will not work. The encrypted SOPS fields
are `media.streamline-tvdb-api-key` and `media.streamline-tmdb-api-key`;
Streamline reads them through systemd credentials. Streamline settings are
read-only and come from Nix, so runtime UI edits to configuration are
intentionally unavailable.

Streamline's Jellyfin integration is declared in Nix. A bootstrap service
creates or reuses a Jellyfin API key named `Streamline`, stores it under
`/var/lib/streamline`, and passes it to Streamline as a systemd credential.
After a successful import, Streamline can notify Jellyfin to refresh its
library. Jellyfin still reads the files from `/srv/media/library`; Streamline's
`/var/lib/streamline/data` is only its own database and state.

## Jackett, FlareSolverr, and VPN

Jackett uses FlareSolverr for indexers protected by Cloudflare or similar
browser challenges. FlareSolverr is installed as a local service on
`127.0.0.1:8191`; Jackett's `FlareSolverrUrl` is reconciled from Nix before
Jackett starts. The endpoint has no authentication, is not published through
Caddy or Pomerium, and is not opened in the firewall. Keep it private; the
[FlareSolverr project warns against exposing it to the internet](https://github.com/FlareSolverr/FlareSolverr#docker).
It has no user-facing page, so it is not a separate Homepage entry. Most
indexers do not need it, so use it only for trackers that report a Cloudflare
or anti-bot challenge.
FlareSolverr's informational request logs can include POST data, so Rico runs
it with error-only logging to avoid writing indexer credentials to the journal.

Rico routes both Jackett and FlareSolverr's outbound IPv4 traffic through the
same AmneziaWG tunnel. The [FlareSolverr troubleshooting guide](https://github.com/FlareSolverr/FlareSolverr/wiki/Troubleshooting)
requires the solver and requesting application to use the same IP, so this
keeps challenge cookies and follow-up tracker requests on one egress address.
Export a client from
AmneziaVPN in its `.vpn` sharing format. The service extracts the AmneziaWG
configuration from the selected container at startup; no desktop client is
needed on Rico.

Opening the RuTracker setup form makes Jackett fetch RuTracker's login page and
captcha. When Cloudflare holds that request on its “Just a moment” challenge,
FlareSolverr reaches its 55-second default timeout; Jackett catches that error
and returns the form after about 57 seconds. Pomerium's default upstream route
timeout is 30 seconds, so it returned 504 before Jackett could send the form.
The Jackett Pomerium route now allows 90 seconds for this request. After
deployment, allow about a minute for the form to appear. This fixes the proxy
timeout, but does not make FlareSolverr solve the challenge; authentication may
still fail while RuTracker blocks the VPN exit address. The alternative
`rutracker.net` URL hit the same challenge in a direct solver check. Keep
FlareSolverr's timeout at its [Jackett-recommended default](https://github.com/Jackett/Jackett#configuring-flaresolverr),
and check `journalctl -u flaresolverr.service` if login still fails.
Pomerium's [route timeout reference](https://www.pomerium.com/docs/reference/routes/timeouts)
documents the 30-second default and per-route override.

Copy the exported file to Rico as root at `/var/lib/vpn/client.vpn`, owned by
root with mode `0600`. Keep it out of Git and the Nix store. After deploying
the NixOS configuration, place the file and start the tunnel:

```bash
scp amnezia_config_rico.vpn root@192.168.0.4:/root/vpn-client.vpn
ssh root@192.168.0.4 \
  'install -m 600 /root/vpn-client.vpn /var/lib/vpn/client.vpn && rm /root/vpn-client.vpn && systemctl restart vpn.service'
```

The service extracts the embedded AmneziaWG config into `/run`, then removes
default-route, DNS, and hook directives, plus empty optional `I1`–`I5` fields,
before starting the tunnel. All outbound IPv4 traffic from Jackett and
FlareSolverr uses the VPN. Jellyfin is narrower: only addresses returned for
`image.tmdb.org`, and only traffic from the Jellyfin service user, use the VPN.
Its other outbound traffic uses Rico's ordinary route; its proxy connection
and responses to Caddy stay on loopback.
The VPN route is destination-specific, so it does not change the source address
or path used for users' Jellyfin sessions. Their HTTPS connection ends at Caddy;
the Caddy-to-Jellyfin proxy connection stays local, and Caddy replies to users
over Rico's ordinary route. Direct Jellyfin requests to the image CDN stalled,
while the same poster downloaded successfully over the VPN. The CDN rotates
IPv4 answers, so the route updater samples DNS repeatedly and refreshes the
known address set every 15 seconds, retaining prior answers until the tunnel
stops. Jellyfin is ordered after VPN at startup but remains running during VPN
restarts. Rico uses loose reverse-path filtering because its per-user VPN
routes are asymmetric with the host's default route; strict filtering would
drop valid replies arriving on `vpn0`.

Verify the tunnel and route after loading the client configuration:

```bash
ssh root@192.168.0.4 'systemctl status vpn.service; awg show vpn0'
ssh root@192.168.0.4 'systemctl status flaresolverr.service; curl -fsS http://127.0.0.1:8191/'
ssh root@192.168.0.4 '
  ip -4 route get 1.1.1.1 uid "$(id -u flaresolverr)"
  ip -4 route get 1.1.1.1 uid "$(id -u jackett)"
  runuser -u jackett -- curl -4 --connect-timeout 10 --max-time 20 \
    -sS -o /dev/null -w "HTTP %{http_code}\\n" https://rutracker.org/
  artwork_ip=$(getent ahostsv4 image.tmdb.org | head -1 | cut -d " " -f 1)
  ip -4 route get 1.1.1.1 uid "$(id -u jellyfin)"
  ip -4 route get "$artwork_ip" uid "$(id -u jellyfin)"
'
```

FlareSolverr's and Jackett's routes and the artwork IP route should show
`dev vpn0`; Jellyfin's route to `1.1.1.1` should use Rico's ordinary gateway.
The FlareSolverr health request should return a JSON ready response, and the
tracker curl should return an HTTP status. If the exported configuration
changes, replace the file and run
`systemctl restart vpn.service`. The service skips startup until `client.vpn`
exists.

Rico uses Quad9 DNS (`9.9.9.9`, `149.112.112.112`) because the router and
Cloudflare resolvers return loopback addresses for TMDB's API host. Quad9
returns public addresses for service metadata requests.

To recreate Jellyfin with its SOPS administrator password, deploy the
configuration and run `scripts/reset-jellyfin` on Rico. That script keeps a
dated backup of `/var/lib/jellyfin` and `/var/cache/jellyfin`; it does not touch
`/srv/media`. A reset removes Jellyfin users, settings, watched state,
libraries, and generated metadata. The declarative bootstrap recreates the
administrator and libraries.

## Jellyfin

Jellyfin is the configured media server. Caddy serves its public TLS hostname
directly to `127.0.0.1:8096`; Pomerium does not wrap Jellyfin. The service can
read `/srv/media/library` but cannot modify or delete media. Plex remains
disabled.

For activation, follow the normal [server deployment workflow](deployment.md).
Do not move or rename `/srv/media` during rollback; keep it intact across
NixOS generations.
