# Karakeep on Rico

Karakeep is available at `https://karakeep.outworld66.ru`. Sign in with Pocket
ID; the OIDC client currently allows the `karakeep-admin` group. The first
account created by OIDC becomes the Karakeep administrator. Password sign-in
is disabled. The previous `archivebox.outworld66.ru` address redirects here.

Save links from the web interface, browser extension, mobile app, or Karakeep
API. The crawler extracts article text and metadata, captures screenshots, and
can archive YouTube links. Full video capture uses yt-dlp and may depend on
YouTube's current access rules. AI tagging and summaries are not configured.

The SQLite database and saved assets are stored at `/var/lib/karakeep`, the
Meilisearch index at `/var/lib/karakeep-meilisearch`, and runtime secrets at
`/var/lib/karakeep-secrets`. Include all three paths in backups. The old
ArchiveBox data had no saved entries when Karakeep replaced it. Its files
remain untouched at `/var/lib/archivebox` and `/srv/archivebox` and are not
imported into Karakeep.

## Connect an agent with MCP

Create an API key in Karakeep's user settings, then configure an MCP client to
run the official MCP server over stdio:

```json
{
  "mcpServers": {
    "karakeep": {
      "command": "npx",
      "args": ["-y", "@karakeep/mcp"],
      "env": {
        "KARAKEEP_API_ADDR": "https://karakeep.outworld66.ru",
        "KARAKEEP_API_KEY": "<key>"
      }
    }
  }
}
```

The MCP server can add, search, edit, and delete bookmarks, lists, and tags.
Only connect agents you trust, and keep the API key out of shared config files.

## Verify and recover

Check `systemctl status docker-karakeep docker-karakeep-chrome docker-karakeep-meilisearch`
and `journalctl -u docker-karakeep`. Pocket ID provisions the OIDC client and
its runtime secret. Application and search secrets are generated under
`/var/lib/karakeep-secrets`; they are not stored in Nix or Git. Deploy with
`task server-update -- rico` and recover with the normal NixOS generation
rollback procedure. Karakeep is pinned to release 0.34.1, Chrome to its
upstream release image, and Meilisearch to 1.41.0.
