# ArchiveBox on Rico

ArchiveBox is available at `https://archivebox.outworld66.ru`. The web interface
is protected by Pocket ID through Pomerium; users must belong to the
`homepage-user` or `homepage-admin` group and then sign in to ArchiveBox itself.
Create the first ArchiveBox administrator at `/admin/` after deployment.

The collection is private, the public index and anonymous URL submission are
disabled, and URL submissions are not sent to Internet Archive. The application
uses `safe-onedomain-nojsreplay`: archived pages do not run their original
JavaScript. Full JavaScript replay needs wildcard DNS and TLS, which this service
does not configure. The web database and configuration are on local storage at
`/var/lib/archivebox`; captured files are on Rico's merged `/srv` storage at
`/srv/archivebox`. Include both paths in backups.

## Connect an agent with MCP

ArchiveBox provides an MCP server over stdio. In an MCP client configuration,
use SSH to start it inside the ArchiveBox container:

```json
{
  "mcpServers": {
    "archivebox": {
      "command": "ssh",
      "args": [
        "root@192.168.0.4",
        "docker",
        "exec",
        "-i",
        "archivebox",
        "archivebox",
        "mcp"
      ]
    }
  }
}
```

The agent needs SSH access to Rico. This MCP connection operates on the
collection through ArchiveBox's CLI and can change or delete archived data, so
only connect agents you trust. The web UI is also available for manual imports;
this deployment does not expose a separate remote MCP endpoint.

## Verify and recover

Check `systemctl status docker-archivebox` and
`journalctl -u docker-archivebox`. Add a link from the host with:

```sh
ssh root@192.168.0.4 docker exec -i archivebox archivebox add https://example.com
```

Deploy with `task server-update -- rico`. Recover with the normal NixOS
generation rollback procedure. ArchiveBox upgrades are pinned to a release
image digest; update the pin deliberately after reviewing the upstream release
and migration notes.
