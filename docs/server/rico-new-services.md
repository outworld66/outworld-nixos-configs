# File Browser and openGym on Rico

These services are configured in NixOS and deployed with `task server-update -- rico`.

## File Browser Quantum

Open File Browser at `https://filebrowser.outworld66.ru`. It uses Pocket ID OIDC. Users must belong to the Pocket ID `media-admin` or `media-user` group; `media-admin` users receive File Browser administrator rights. Each non-admin account gets a writable `Personal files` source scoped to its own directory under `/srv/filebrowser/users/<preferred_username>`. Administrators can access all personal files.

`Media files` is one read-only source backed by `/srv/media`; the `downloads/complete/streamline/` directory remains inside it. A deny-by-default access rule allows only the Pocket ID `media-admin` group to browse or download this source. A startup service reconciles that rule before File Browser starts. Each non-admin account gets a private directory under `/srv/filebrowser/users/<preferred_username>` on Rico's mergerfs-backed `/srv` storage. The startup service moves existing personal files when activity history identifies one owner, migrates account scopes, and keeps a one-time database backup at `/var/lib/filebrowser/filebrowser.sqlite.before-personal-scope`. If ownership is ambiguous, bootstrap fails closed before File Browser starts. File Browser's database and cache remain under `/var/lib/filebrowser`.

Verify the ACL bootstrap with `systemctl status filebrowser-access-bootstrap` and `journalctl -u filebrowser-access-bootstrap`. Test with one `media-user` account: its personal folder should be writable, and the shared source should contain no accessible files. A `media-admin` account should be able to browse and download the shared files, but the source remains read-only.

## openGym

Open openGym at `https://gym.outworld66.ru`. Pomerium protects the site with Pocket ID and currently allows only the `media-admin` group. The first profile created on an empty instance becomes the openGym administrator. Guest mode is disabled.

The application data is stored under `/var/lib/opengym` and should be included in server backups. The mobile app's API pairing flow is behind Pomerium too, so mobile pairing is unavailable with this access policy. Browser use works through the protected site.

## Deployment and recovery

Run the standard update workflow from the repository root:

```sh
task server-update -- rico
```

File Browser and openGym run as Docker containers managed by NixOS. Their logs are available with `journalctl -u docker-filebrowser -u docker-opengym-api -u docker-opengym-web`. Stoat runs in the `stoat.service` Docker Compose stack; see [rico-stoat.md](rico-stoat.md). Roll back with the normal NixOS generation rollback if an activation fails.
