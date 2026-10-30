# LiteLLM and FreeLLMAPI

Rico exposes LiteLLM at `https://llm.outworld66.ru/v1`. LiteLLM routes the
local `qwen3-vl` model and the `freellmapi-auto` model. The latter forwards to
FreeLLMAPI on `127.0.0.1:3001`; FreeLLMAPI selects and fails over between the
providers configured in its dashboard. Its dashboard and API are not exposed
through Caddy or Homepage because FreeLLMAPI is a single-user service. Use an
SSH tunnel for setup:

```sh
ssh -L 3001:127.0.0.1:3001 root@192.168.0.4
```

Then open `http://127.0.0.1:3001`. The initial dashboard account is
`admin@localhost`; retrieve its password from the private SOPS configuration
with `sops --decrypt --extract '["freellmapi"]["admin-password"]' secrets/private.yaml`.
The service encryption key is also stored in SOPS, and provider API keys are
encrypted by FreeLLMAPI in its persistent database under
`/var/lib/freellmapi`.

Add your provider keys in the FreeLLMAPI dashboard and copy its unified API
key. Store the key in `/var/lib/llm-gateway/credentials.env` as
`FREELLMAPI_API_KEY=...`, then restart LiteLLM. Keep the key in that root-only
runtime file; it is not stored in this repository. Until this setup is done,
`freellmapi-auto` is listed but requests to it will fail authentication.

Clients with an authorized LiteLLM API key can call model
`freellmapi-auto` at `https://llm.outworld66.ru/v1`. In OpenHands Agent Canvas,
add a profile under **Settings → LLM → Advanced** with model
`litellm_proxy/freellmapi-auto`, base URL `https://llm.outworld66.ru`, and a
LiteLLM virtual key restricted to this model. Codex ACP sessions keep using
their own Codex login; this profile is for OpenHands agents that use LLM
profiles. Free-tier provider quotas and availability vary, and requests are
sent to the provider selected by FreeLLMAPI.

FreeLLMAPI is intended for personal experimentation, has no service-level
availability guarantee, and shares its provider keys and quotas across all
LiteLLM clients using this model. Prompts and responses are sent to whichever
upstream provider FreeLLMAPI selects; use only providers whose terms allow
this shared proxy use.

The LiteLLM dashboard is at `https://llm.outworld66.ru/ui`. Pomerium restricts
the dashboard to the `litellm-admin` Pocket ID group, and LiteLLM uses Pocket ID
for its native OIDC sign-in. Members of that group receive the `proxy_admin`
role. LiteLLM stores SSO users and settings in its dedicated local PostgreSQL
database. The LiteLLM release in use supports SSO for up to five users without
an Enterprise license.
