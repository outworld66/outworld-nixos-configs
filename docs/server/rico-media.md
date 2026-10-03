# Media services on Rico

Rico's shared media tree is `/srv/media`, on the mergerfs mount combining
`/data1` and `/data2`. It is separate from the existing Immich and Cloudreve data.
The `media` group grants qBittorrent, Radarr, Sonarr, Bindery, and Jellyfin
access to the shared tree. The setgid directories keep files in that group.
Jellyfin has read-only access to the library. Jackett and Seerr do not need
filesystem access.

Administrative interfaces are routed through Caddy and Pomerium and restricted
to `media-admin`. The Seerr request portal allows both `media-admin` and
`media-user` through Pomerium:

- qBittorrent: `torrent.outworld66.ru`
- Radarr: `radarr.outworld66.ru`
- Sonarr: `sonarr.outworld66.ru`
- Jackett: `jackett.outworld66.ru`
- Bindery: `books.outworld66.ru`
- Seerr requests portal: `requests.outworld66.ru`, available to the
  `media-admin` and `media-user` Pocket ID groups through Pomerium.
- Jellyfin: `jellyfin.outworld66.ru`, served directly by Caddy with TLS and
  Jellyfin's native login. It is not behind Pomerium, so native TV and mobile
  clients can authenticate normally.

The qBittorrent, Radarr, Sonarr, and Jackett web ports are not opened in the
firewall. Bindery uses host networking so it can connect to loopback-only
qBittorrent; its 8787 port is also closed in the firewall and reached through
Pomerium. qBittorrent, Radarr, and Sonarr are configured to listen on loopback;
Jackett's upstream default is local-only. The NixOS Seerr module exposes no
bind-address option; its port is closed in the firewall and its only configured
external path is its Pomerium route for `media-admin` and `media-user`.
The qBittorrent Pomerium route preserves the public Host header so its Web UI
accepts requests whose Host and Origin both use `torrent.outworld66.ru`.
Jellyfin's `8096` backend port is not opened in the firewall.

## Authentication

Pomerium delegates interactive sign-in to Pocket ID. qBittorrent, Radarr,
Sonarr, Jackett, Bindery, Bitmagnet, Homepage, and Seerr are reached through
Pomerium. Management interfaces allow `media-admin`; Seerr and Bitmagnet also
allow `media-user`. Service credentials and API keys are configured in each
application for local service-to-service calls.

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
credentials: Radarr, Sonarr, and Bindery use qBittorrent's Web UI credentials;
Radarr, Sonarr, and Bindery use Jackett's loopback Torznab endpoint; Seerr
uses Jellyfin for login and libraries, plus Radarr/Sonarr API keys. These
connections are provisioned by `media-stack-bootstrap`. Pomerium is not placed
between these services because their API requests are not interactive browser
sessions. The public TCP/UDP peer port `51413` is BitTorrent traffic, not a web
login endpoint, so Pocket ID/Pomerium cannot authenticate it.

Other public Rico services keep their existing authentication: Cloudreve,
Donetick, Gotify, and Immich use Pocket ID OIDC; NocoDB, Elengrab, LiteLLM's
browser UI, stats, and Homepage use Pomerium. Pocket ID and Pomerium's own
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
│       ├── movies/             # qBittorrent category used by Radarr
│       ├── tv/                  # qBittorrent category used by Sonarr
│       └── books/               # qBittorrent category used by Bindery
└── library/{movies,tv,books,audiobooks}/
```

qBittorrent writes completed downloads to the category folders above. Radarr
imports its managed movie downloads into `/srv/media/library/movies`; Sonarr
imports its managed series downloads into `/srv/media/library/tv`; Bindery
uses the books download folder and the books/audiobooks library folders.
Jellyfin reads only `/srv/media/library/movies` and
`/srv/media/library/tv`, which are configured as its Movies and TV libraries.
The services use one mergerfs namespace over two filesystems. Radarr and Sonarr
can hard-link an import when its source and destination are on the same backing
filesystem; otherwise they copy it while qBittorrent keeps seeding. Jellyfin
sees the imported file through its library scan.

The normal flow is to request a movie or series in Seerr: Radarr or Sonarr
matches it, sends the torrent to qBittorrent with the right category, and
imports the completed file into the Jellyfin library. A torrent added manually
to qBittorrent is not automatically adopted by Radarr or Sonarr just because it
is in a category; import it through the matching manager (or place it in the
library folder) for Jellyfin to see it. The firewall allows peer traffic on
TCP/UDP 51413. Forward that port on the router if incoming peer connectivity is
desired. The Web UI is separate and remains closed to network interfaces.

## Declarative setup

The `media-stack-bootstrap.service` reconciles the first-run state and service
connections after the applications start. It reads administrator passwords
from SOPS and does not put them in the Nix store or journal. To create a missing
password once, run `scripts/bootstrap-media-passwords`; it preserves existing
values and never prints them.

On activation, the bootstrap service:

- Sets qBittorrent's Web UI password and creates `movies`, `tv`, and `books`
  categories with the matching shared download paths, updating existing
  category locations when the media mount changes.
- Adds the qBittorrent download client and movie/TV root folders to Radarr and
  Sonarr. Sonarr receives the individual AniLibria Torznab endpoint with RSS,
  automatic, and interactive searches enabled; Sonarr does not support
  Jackett's aggregate `all` endpoint. The current tracker returns no movie
  category results, so the bootstrap does not attach it to Radarr. It removes
  unused old disk-specific root
  folders; existing media entries keep their assigned roots. Their web
  authentication uses Pomerium's Pocket ID policy; their APIs remain protected
  by their generated API keys.
- Creates Jellyfin's Movies and TV libraries from the merged mount, replacing
  old disk-specific library paths.
- Creates the Bindery `admin` account from SOPS and connects its qBittorrent
  downloader and Jackett indexer.
- Logs in to Jellyfin from Seerr using the SOPS administrator password, selects
  both libraries, connects Radarr and Sonarr, and finishes Seerr initialization.
  Seerr logins use Jellyfin accounts; newly provisioned users receive request
  permission, not management permission.

These services are reachable through Pomerium and restricted to the Pocket ID
`media-admin` group, except Seerr, which allows both `media-admin` and
`media-user`. qBittorrent and Bindery also use their SOPS-managed local admin
credentials. Jackett has no local multi-user accounts: Pomerium is its web
login. Radarr and Sonarr's `External` authentication delegates browser access
to Pomerium; their API keys are generated and persisted by each application.

Sonarr creates an individual Torznab connection for each configured Jackett
tracker that advertises TV categories. The bootstrap reconciles these entries
on activation, so adding or removing a TV tracker in Jackett updates Sonarr
automatically. It enables Sonarr's Anime category `5070` for every TV-capable
tracker: Jackett may expose tracker-specific anime category IDs instead of the
standard Torznab category, while Sonarr disables anime searches when this field
is empty.
Bindery uses Jackett's aggregate Torznab feed. AniLibria returns TV categories
but no movie categories, so Radarr needs a movie-capable tracker before it can
use Jackett. Add or manage tracker connections in Jackett itself. Any private
tracker credentials stay in Jackett's runtime configuration.

For anime, add the correctly titled series in Sonarr with its series type set
to `Anime`; anime releases often use absolute episode numbers. The series
lookup and release search are separate steps. Select the matching show (for
example, *JoJo's Bizarre Adventure (2012)*), add it to the TV root, then run an
interactive episode search. The indexer connection is healthy when Jackett's
Torznab search returns results; an empty Jellyfin library does not need to be
imported before adding a series.
Sonarr uses SkyHook for TV metadata independently of Jackett. Rico has no
default IPv6 route, so IPv6 is disabled for Sonarr's .NET process. A SkyHook
timeout can therefore break title lookup while Jackett searches still work;
Sonarr has an [upstream report of SkyHook requests timing out on pooled HTTP/2
connections](https://github.com/Sonarr/Sonarr/issues/8912).

## Jackett and Sonarr VPN routes

Rico can send Sonarr's SkyHook requests through an AmneziaWG tunnel. Export a
client from AmneziaVPN in its `.vpn` sharing format. The service extracts the
AmneziaWG configuration from the selected container at startup; no desktop
client is needed on Rico.

Copy the exported file to Rico as root at
`/var/lib/vpn/client.vpn`, owned by root with mode `0600`. Keep it
out of Git and the Nix store. After deploying the NixOS configuration, place
the file and start the tunnel:

```bash
scp amnezia_config_rico.vpn root@192.168.0.4:/root/vpn-client.vpn
ssh root@192.168.0.4 \
  'install -m 600 /root/vpn-client.vpn /var/lib/vpn/client.vpn && rm /root/vpn-client.vpn && systemctl restart vpn.service'
```

The service extracts the embedded AmneziaWG config into `/run`, then removes
default-route, DNS, and hook directives, plus empty optional `I1`–`I5` fields,
before starting the tunnel. All outbound IPv4 traffic from Jackett uses the
VPN, covering tracker requests even when a tracker changes its IP address.
Jackett is ordered after and tied to the VPN service, so a VPN restart also
restarts Jackett. Sonarr traffic to `skyhook.sonarr.tv` and
`services.sonarr.tv` uses the same tunnel; a timer refreshes their IPv4
addresses every five minutes. The latter serves Sonarr's scene mappings, which
include anime title aliases. Other services keep their existing routes. Rico
uses loose reverse-path filtering because its per-user VPN routes are
asymmetric with the host's default route; strict filtering would drop valid
replies arriving on `vpn0`.

Verify the tunnel and the route after loading the client configuration:

```bash
ssh root@192.168.0.4 'systemctl status vpn.service; awg show vpn0'
ssh root@192.168.0.4 '
  address=$(getent ahostsv4 skyhook.sonarr.tv | head -n1 | cut -d " " -f1)
  ip -4 route get "$address" uid "$(id -u sonarr)"
  address=$(getent ahostsv4 services.sonarr.tv | head -n1 | cut -d " " -f1)
  ip -4 route get "$address" uid "$(id -u sonarr)"
  ip -4 route get 1.1.1.1 uid "$(id -u jackett)"
  runuser -u sonarr -- curl -4 --connect-timeout 10 --max-time 20 \
    -sS -o /dev/null -w "HTTP %{http_code}\\n" https://skyhook.sonarr.tv/
  runuser -u sonarr -- curl -4 --connect-timeout 10 --max-time 20 \
    -sS -o /dev/null -w "HTTP %{http_code}\\n" https://services.sonarr.tv/v1/scenemapping
'
```

All three routes should show `dev vpn0`; both curls should return an HTTP
status. If the exported configuration changes, replace the file and run
`systemctl restart vpn.service`. The service skips startup until `client.vpn`
exists.

Seerr provisions the Jellyfin API key through Jellyfin's API and stores it in
its own protected application database. Seerr and Jellyfin user records are
created from Jellyfin sign-ins; there is no separate Seerr user/password list
to maintain.

Seerr uses the newest package currently available in the locked nixpkgs-unstable
input (3.4.1). Image caching is enabled by the media bootstrap; this proxies
TMDB images through Seerr for browsers that cannot reach TMDB directly. Seerr
prefers IPv4 because Rico has no IPv6 default route, and stores cached images
under its config directory while periodically removing stale entries.

Rico uses Quad9 DNS (`9.9.9.9`, `149.112.112.112`) because the router and
Cloudflare resolvers return loopback addresses for TMDB's API host. Quad9
returns public addresses, allowing Seerr to load discovery pages and artwork.

To recreate Jellyfin with its SOPS administrator password, deploy the
configuration and run `scripts/reset-jellyfin` on Rico. That script keeps a
dated backup of `/var/lib/jellyfin` and `/var/cache/jellyfin`; it does not touch
`/srv/media`. A reset removes Jellyfin users, settings, watched state,
libraries, and generated metadata. The declarative bootstrap recreates the
administrator and libraries, and the media-stack bootstrap reconnects Seerr.

## Jellyfin

Jellyfin is the configured media server. Caddy serves its public TLS hostname
directly to `127.0.0.1:8096`; Pomerium does not wrap Jellyfin. The service can
read `/srv/media/library` but cannot modify or delete media. Plex remains
disabled.

For activation, follow the normal [server deployment workflow](deployment.md).
Do not move or rename `/srv/media` during rollback; keep it intact across
NixOS generations.
