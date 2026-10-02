# Media services on Rico

Rico's media tree is `/data1/media`, on the confirmed ext4 filesystem with
about 11 TB free. It is separate from the existing Immich and Cloudreve data.
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
Jellyfin's `8096` backend port is not opened in the firewall.

## Shared paths

All download and library paths are below `/data1/media`:

```text
/data1/media/
├── downloads/
│   ├── incomplete/
│   └── complete/{movies,tv,books}/
└── library/{movies,tv,books,audiobooks}/
```

The download and library directories share one filesystem, allowing Radarr,
Sonarr, and Bindery to hard-link completed torrents into their libraries while
qBittorrent continues seeding. The firewall allows peer traffic on TCP/UDP
51413. Forward that port on the router if incoming peer connectivity is
desired. The Web UI is separate and remains closed to network interfaces.

## First-run setup

Credentials and API keys belong in each application's runtime configuration,
not Nix source.

1. Visit qBittorrent through its protected URL. Set a strong Web UI password.
   Create categories `movies`, `tv`, and `books`, saving them under
   `/data1/media/downloads/complete/movies`, `/data1/media/downloads/complete/tv`,
   and `/data1/media/downloads/complete/books`. Incomplete files use
   `/data1/media/downloads/incomplete`.
2. In Radarr, add qBittorrent at `127.0.0.1:8080`, using the Web UI credentials
   and category `movies`. Set `/data1/media/library/movies` as the movie root.
   Add Bitmagnet directly as a **Generic Torznab** indexer at
   `http://127.0.0.1:3333/torznab`. Add individual Jackett Torznab feeds only
   if more indexers are needed; copy each feed URL and API key from Jackett.
3. In Sonarr, add qBittorrent at `127.0.0.1:8080`, using category `tv`, and
   set `/data1/media/library/tv` as the series root. Configure any indexers
   needed for TV in Jackett and add their individual Torznab feeds to Sonarr.
4. In Bindery, create its administrator account during first-run setup. Add
   qBittorrent at `127.0.0.1:8080` with category `books`. Bindery uses
   `/data1/media/downloads/complete/books` for completed downloads,
   `/data1/media/library/books` for ebooks, and
   `/data1/media/library/audiobooks` for audiobooks.
5. In Jellyfin at `https://jellyfin.outworld66.ru`, complete first-run setup,
   create the admin and user accounts, and add the Movies and TV libraries at
   `/data1/media/library/movies` and `/data1/media/library/tv`.
6. In Seerr, configure Jellyfin at `http://127.0.0.1:8096`, then connect
   Radarr at `http://127.0.0.1:7878` and Sonarr at `http://127.0.0.1:8989`.
   Retrieve their API keys from each app's runtime settings. Seerr's Pomerium
   gate permits both `media-admin` and `media-user`; Seerr's own first-run
   settings determine which Jellyfin users may submit requests.

## Jellyfin

Jellyfin is the configured media server. Caddy serves its public TLS hostname
directly to `127.0.0.1:8096`; Pomerium does not wrap Jellyfin. The service can
read `/data1/media/library` but cannot modify or delete media. Plex remains
disabled.

For activation, follow the normal [server deployment workflow](deployment.md).
Do not move or rename `/data1/media` during rollback; keep it intact across
NixOS generations.
