# sing-box desktop VPN

The `tpx13` and `majesty` profiles provide a sing-box TUN client for the
VLESS + REALITY inbound on the VPS. Each host has its own 3x-ui client UUID.
Private connection parameters stay in a host-local JSON file; the Nix store
contains only its path. The VPN is started manually so a missing credential
file does not disrupt boot or an ordinary system switch.

Before starting the service on each host, copy that host's outbound JSON to
`/etc/sing-box/vless-outbound.json` with root ownership and mode `0600`:

```bash
sudo install -d -m 0700 /etc/sing-box
sudo install -o root -g root -m 0600 \
  ~/.config/sing-box/$(hostname)-outbound.json \
  /etc/sing-box/vless-outbound.json
```

The generated files currently reside on `majesty` under
`~/.config/sing-box/`. Transfer `tpx13-outbound.json` to `tpx13` over SSH
before running the install command there. Never add these files or exported
3x-ui links to Git.

If another VPN is already routing traffic through a virtual interface, set
`bind_interface` in that host's private outbound JSON to its physical network
interface. On `majesty` this is `enp10s0`; check `ip route get 45.128.60.15`
on other hosts to identify their physical route.

DNS requests are intercepted by sing-box and sent to Cloudflare over TLS
through the VLESS tunnel. This avoids depending on DNS settings inherited from
another VPN or the local network.

After activating the committed NixOS configuration, connect and disconnect
with:

```bash
sudo systemctl start sing-box
sudo systemctl stop sing-box
```

Check the connection with `systemctl status sing-box`,
`journalctl -u sing-box -e`, and an external IP lookup. Private IPv4 ranges
remain on the local network. If the tunnel fails, stop the service to restore
normal routing, then check that the file matches the host's 3x-ui client and
that the VPS still listens on TCP 443. To rotate access, generate a new client
in 3x-ui and replace only that host's local JSON file.
