# Immich AI search and descriptions

The `rico` host uses two different models for photo search:

- Immich Smart Search uses `ViT-SO400M-16-SigLIP2-384__webli` for image and
  text embeddings. It supports Russian and English search queries through
  Immich's built-in machine-learning service.
- `immich-analyze` uses `qwen3-vl:4b-instruct-q4_K_M` through LiteLLM to write
  a short Russian description and an English description for each asset.

The CLIP model is not served by LiteLLM. Immich calls its own local
machine-learning service for embeddings; `immich-analyze` calls LiteLLM for
image descriptions.

## Endpoints and authorization

LiteLLM listens on all host interfaces on port `4000`. The firewall keeps that
port private; external clients use the TLS endpoint
`https://llm.outworld66.ru/v1`. Model API requests require a LiteLLM Bearer
key. The key is created once at runtime and stored in
`/var/lib/llm-gateway/credentials.env`, outside the Nix store and repository.
The same generated key is passed to `immich-analyze` as its model API key.

The public `/v1` API remains available to clients with a valid Bearer key.
Every other LiteLLM route, including `/ui`, the Model Hub page
(`/ui/model_hub_table`), Swagger (`/docs`), and the OpenAPI schema, passes
through Pomerium and requires membership in the Pocket ID `admins` group.
LiteLLM may also ask for its own admin UI password after Pocket ID login; this
is the gateway master key in the root-owned credentials file. Do not expose or
share that key.

The local Ollama API is bound to localhost and is not exposed publicly.
`immich-analyze` uses host networking to reach both Immich at
`http://127.0.0.1:2283` and LiteLLM on the same machine.

For the `llamacpp` interface, set `IMMICH_ANALYZE_HOSTS` to the server root,
for example `http://127.0.0.1:4000`. The application appends `/v1` itself for
OpenAI-compatible requests and model discovery. Do not include `/v1` in this
variable.

## Immich API key prerequisite

Immich API keys are user credentials and must be created once by an
authenticated Immich user. They cannot be minted by the NixOS configuration
without an existing authenticated Immich session.

Create a key in Immich account settings with these permissions:

- `asset.read`
- `asset.view`
- `asset.update`

On `rico`, the root-owned directory `/var/lib/immich-analyze` is created by
NixOS. Create `/var/lib/immich-analyze/immich-api.env` through a hidden prompt,
so the key is not echoed or placed in shell history:

```bash
sudo bash -c 'read -rsp "Immich API key: " key; printf "\\n"; umask 077; printf "IMMICH_API_KEY=%s\\n" "$key" > /var/lib/immich-analyze/immich-api.env'
```

The systemd path unit starts `docker-immich-analyze.service` when this file
changes. At boot, the container unit starts automatically if the file already
exists. If the service previously failed and hit its start limit, clear that
state and start it after fixing the configuration:

```bash
sudo systemctl reset-failed docker-immich-analyze.service
sudo systemctl start docker-immich-analyze.service
```

Do not put the Immich API key in this repository or the public Nix flake. If
the key must be managed declaratively, store it in the private SOPS secrets and
render the environment file from that secret.

## Deployment and reindexing

Apply host changes with the documented deployment task:

```bash
task server-update -- rico
```

This activates the host configuration and restarts affected systemd services.
The first activation downloads the Ollama model. Immich may also need to
recreate Smart Search embeddings after the CLIP model changes. In Immich, run
the **Smart Search** job for **All** assets.

Check the services with:

```bash
systemctl --failed
systemctl status ollama ollama-model-loader litellm immich-server \
  immich-machine-learning docker-immich-analyze caddy
ollama list
```

If `docker-immich-analyze.service` is inactive, check whether the API key file
exists and inspect its result:

```bash
test -s /var/lib/immich-analyze/immich-api.env
systemctl show -p Result,ConditionResult docker-immich-analyze.service
journalctl -u docker-immich-analyze.service -n 50 --no-pager
```

The public model API base URL is `https://llm.outworld66.ru/v1`, and the model
name is `qwen3-vl`. The gateway key can be read from the server's root-owned
credentials file; do not include it in command history, logs, or repository
files.
