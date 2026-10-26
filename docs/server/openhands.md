# OpenHands Agent Canvas

Rico runs OpenHands Agent Canvas at `https://openhands.outworld66.ru`. NixOS
installs Agent Canvas `1.28.1`, its matching Agent Server container `1.56.0`,
Codex ACP, Node.js, Python 3.14, and the
`openhands` service from Nix derivations. Agent Server is installed by `uvx`
from the pinned `outworld66/software-agent-sdk` commit configured in
`hosts/rico/openhands.nix`; its packages are cached in
`/var/lib/openhands/.cache/uv`, outside the Nix store. Conversations use the
release-matched `ghcr.io/openhands/agent-server:1.56.0-python` image, which
is pulled at service startup when absent, and the fork's dedicated rootless
Docker daemon; Rico's other services continue using
the system Docker daemon. Codex and ACP traffic uses the AmneziaVPN route.

The public URL is protected by OpenHands native OIDC with Pocket ID. Members
of `ai-admin` and `ai-user` can sign in; `ai-admin` receives the administrator
role. Agent Server limits accounts to their own conversations and workspaces.
The backend listens on loopback and sends its outbound traffic through Rico's
AmneziaVPN tunnel; it refuses to start without that route.

OpenHands starts as the `openhands` system user. Its first Codex ACP session
uses the Codex CLI OAuth login already present on Rico. On first start, a
root-owned one-shot service copies the existing login into
`/var/lib/openhands/.codex/auth.json` if no copy exists. The old panel service
is removed, but `/var/lib/codex-web-panel` is retained so its previous
workspace and login are not deleted automatically.

## First use

1. Open `https://openhands.outworld66.ru` and sign in through Pocket ID with an
   account assigned to `ai-admin` or `ai-user`.
2. Agent Canvas asks for its local backend API key because it runs in public
   mode. On Rico, read the value from `/var/lib/openhands/environment` with
   root access. Keep it private; it grants access to the backend.
3. In the onboarding dialog, select Codex. Leave API-key fields empty; the
   backend reuses the migrated Codex login.
4. Start a conversation and choose a repository or workspace.

Nix installs the Codex ACP server and Python 3.14 in advance. When Agent
Canvas runs the Codex preset's `npx -y @zed-industries/codex-acp` command, the
service resolves it to that installed binary. The Python Agent Server and its
pinned dependencies are still bootstrapped by `uvx` and cached outside the Nix
store. Rico uses the Tsinghua PyPI mirror because PyPI's wheel host does not
respond through the AmneziaVPN route.

The app uses the single Codex login on Rico, so all authorized admins use that
account. If the login expires, sign in as the service user and keep the
dedicated Codex home:

```bash
sudo -u openhands env \
  HOME=/var/lib/openhands \
  CODEX_HOME=/var/lib/openhands/.codex \
  codex login
```

## MCP servers and skills

Agent Canvas stores `Customize > MCP Servers`, `Customize > Skills`, and
`Settings > Secrets` per backend. With this one self-hosted backend, those
settings apply to its conversations and are shared by every person allowed
through Pomerium. Add MCP credentials under `Settings > Secrets`, not in a
repository. Skills installed with `/add-skill <github-url>` are available to
new conversations after starting a new conversation.

When using the Codex ACP agent, configure Codex itself:

- For MCP servers used by every Codex task on Rico, edit
  `/var/lib/openhands/.codex/config.toml`.
- For a project-only MCP server, add `.codex/config.toml` to that project;
  Codex reads project settings only for trusted projects.
- For a reusable skill available to all Rico workspaces, install it under
  `/var/lib/openhands/.agents/skills/<skill>/SKILL.md`.
- For a project-specific skill, commit it under
  `<repo>/.agents/skills/<skill>/SKILL.md`; use the repository's `AGENTS.md`
  for instructions that should apply to every task in that project.

OpenHands' own MCP and skill settings do not automatically configure the
external Codex ACP process. Keep credentials in the server's protected
Codex/OpenHands state or the OpenHands secret store, not in Git.

## Operations

```bash
systemctl status openhands.service vpn.service
journalctl -u openhands.service -e
ip -4 route get 1.1.1.1 uid "$(id -u openhands)"
```

For a conversation-creation `422`, the journal records sanitized validation
field paths and messages without request values.

For personal ChatGPT subscriptions and administrator-managed shared access,
see [openhands-chatgpt-access.md](openhands-chatgpt-access.md).

The route lookup must show `dev vpn0`. Restart with
`systemctl restart openhands.service`. Recover the previous NixOS generation
using the [server deployment guide](deployment.md).
