# Media services on Rico

Shared media data lives under `/srv/media`, the mergerfs mount across the
backing disks. Use this merged path in application settings and operator
commands. Jellyfin reads `/srv/media/library/movies` and
`/srv/media/library/tv`; qBittorrent writes completed downloads below
`/srv/media/downloads/complete`.

qBittorrent, Jackett, Prowlarr, and Bindery administration is routed through
Caddy and Pomerium. Pomerium delegates sign-in to Pocket ID and restricts these
interfaces to the `media-admin` group. Bitmagnet and Homepage also use
Pomerium, with media access groups configured in `hosts/rico/services.nix`.
Streamline (`https://streamline.outworld66.ru`) uses its native Pocket ID OIDC
login directly through Caddy, without Pomerium. Pocket ID's `media-admin` and
`media-user` groups map to Streamline's administrator and member roles. First
OIDC login provisions an account automatically. Local password login is blocked
at Caddy, and `/login` sends users to Pocket ID. Local account registration
requires an invite.
Jellyfin uses its own accounts and is served directly by Caddy so TV and mobile
clients can use its API and media streams.

The qBittorrent, Jackett, and Prowlarr web ports are not opened in the
firewall. Bindery uses host networking to reach loopback-only qBittorrent. The
public peer port `51413` is BitTorrent traffic and does not use web
authentication. Keep application credentials and API keys in their runtime
files or SOPS secrets; do not put them in this repository.

The `media-stack-bootstrap` service applies first-run settings for qBittorrent,
Jellyfin, and Bindery. It reads administrator passwords from SOPS and does not
write them to the Nix store or journal. The mergerfs mount must be available
before importing media so applications continue to use the shared namespace.
