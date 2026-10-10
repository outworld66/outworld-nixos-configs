# File Browser, Matrix, and openGym on Rico

These services are configured in NixOS and deployed with `task server-update -- rico`.

## File Browser Quantum

Open File Browser at `https://filebrowser.outworld66.ru`. It uses Pocket ID OIDC. Users must belong to the Pocket ID `media-admin` or `media-user` group; `media-admin` users receive File Browser administrator rights.

The `Completed torrents` and `Streamline` sources are mounted read-only from `/srv/media/downloads/complete` and `/srv/media/downloads/complete/streamline`. File Browser cannot rename or delete torrent data. Its SQLite database and cache live under `/var/lib/filebrowser`.

## Matrix and Element

- Element Web: `https://chat.outworld66.ru`
- Matrix homeserver: `https://matrix.outworld66.ru`
- User IDs: `@name:matrix.outworld66.ru`

Pocket ID handles Matrix login. Assign each user to `media-admin` or `media-user` before they sign in. The first administrator account must be created manually; later allowed users are created on their first OIDC login. Federation is disabled, so users on other Matrix servers cannot join or message this server.

Before the first OIDC login, create the first administrator using the same local name as the user's Pocket ID `preferred_username`:

```sh
sudo matrix-synapse-register_new_matrix_user --admin --user <preferred_username>
```

The command prompts for an initial password. Synapse password login is disabled; after this account is linked by the Pocket ID login, authenticate through OIDC. Existing Synapse accounts can be promoted through the Synapse Admin API once an administrator token is available.

Element's in-app group calls use MatrixRTC and the local LiveKit server. Rico's host firewall allows LiveKit media on UDP `7882` and TCP `7881`. Forward both ports on the home router to `192.168.0.4`; without this NAT forwarding, call signaling may work while audio/video media cannot reach Rico. HTTPS signaling uses `matrix-rtc.outworld66.ru` through Caddy.

Synapse stores its PostgreSQL database and media under `/var/lib/matrix-synapse`. Back up the `matrix-synapse` PostgreSQL database and the media store together. Check service health with:

```sh
systemctl status matrix-synapse livekit lk-jwt-service
```

## openGym

Open openGym at `https://gym.outworld66.ru`. Pomerium protects the site with Pocket ID and currently allows only the `media-admin` group. The first profile created on an empty instance becomes the openGym administrator. Guest mode is disabled.

The application data is stored under `/var/lib/opengym` and should be included in server backups. The mobile app's API pairing flow is behind Pomerium too, so mobile pairing is unavailable with this access policy. Browser use works through the protected site.

## Deployment and recovery

Run the standard update workflow from the repository root:

```sh
task server-update -- rico
```

File Browser and openGym run as Docker containers managed by NixOS. Their logs are available with `journalctl -u docker-filebrowser -u docker-opengym-api -u docker-opengym-web`. Matrix services use systemd units listed above. Roll back with the normal NixOS generation rollback if an activation fails.
