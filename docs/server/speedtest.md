# Server speed test

LibreSpeed is available at `https://speedtest.outworld66.ru` and tests the
connection to the `rico` server. The page is public and does not require a
Pocket ID account.

Caddy serves the static page and forwards only `/backend/` requests to the
LibreSpeed service on `127.0.0.1:8990`. The backend is not exposed directly,
and test telemetry and result storage are disabled.

After changing the service configuration, deploy with:

```bash
task server-update -- rico
```
