{
  inputs,
  pkgs,
  ...
}:
let
  awgPackages = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  interface = "vpn0";
  runtimeDir = "/run/vpn";
  sourceConfig = "/var/lib/vpn/client.vpn";
  runtimeConfig = "${runtimeDir}/${interface}.conf";
  routeTable = "168";
  jackettRulePriority = "1099";
  jellyfinRulePriority = "1100";
  jellyfinArtworkHost = "image.tmdb.org";
  jellyfinRouteState = "${runtimeDir}/jellyfin-artwork-addresses";

  extractConfig = pkgs.writeText "extract-amnezia-vpn.py" ''
    import base64
    import json
    import pathlib
    import sys
    import zlib

    try:
        encoded = pathlib.Path(sys.argv[1]).read_text().strip().removeprefix("vpn://")
        payload = base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4))
        shared = json.loads(zlib.decompress(payload[4:]))
        container = next(item for item in shared["containers"] if item["container"] == shared["defaultContainer"])
        last_config = json.loads(container["awg"]["last_config"])
        config = last_config["config"]
        if "[Interface]" not in config or "[Peer]" not in config:
            raise ValueError("missing WireGuard sections")
        mtu = int(last_config["mtu"])
        if not 576 <= mtu <= 9000:
            raise ValueError("invalid MTU")
        lines = config.splitlines()
        in_interface = False
        has_mtu = False
        for line in lines:
            if line.strip() == "[Interface]":
                in_interface = True
            elif line.startswith("["):
                in_interface = False
            elif in_interface and line.partition("=")[0].strip().lower() == "mtu":
                has_mtu = True
        if not has_mtu:
            lines.insert(lines.index("[Interface]") + 1, f"MTU = {mtu}")
        config = "\n".join(lines) + "\n"
        print(config, end="")
    except Exception:
        print("Invalid Amnezia .vpn configuration", file=sys.stderr)
        sys.exit(1)
  '';

  prepareConfig = pkgs.writeShellScript "prepare-vpn-config" ''
    set -euo pipefail
    trap '${pkgs.coreutils}/bin/rm -f ${runtimeDir}/export.conf' EXIT
    ${pkgs.python3}/bin/python ${extractConfig} ${sourceConfig} > ${runtimeDir}/export.conf
    # Native exports often request default-route and DNS changes, which this
    # split-tunnel service does not use.
    ${pkgs.gawk}/bin/awk '
      /^\[Interface\][[:space:]]*$/ { in_interface = 1; found = 1; print; print "Table = off"; next }
      /^\[/ { in_interface = 0 }
      in_interface && /^[[:space:]]*I[1-5][[:space:]]*=[[:space:]]*$/ { next }
      in_interface && /^[[:space:]]*(Table|DNS|PreUp|PostUp|PreDown|PostDown|SaveConfig)[[:space:]]*=/ { next }
      { print }
      END { if (!found) exit 1 }
    ' ${runtimeDir}/export.conf > ${runtimeConfig}
    ${pkgs.coreutils}/bin/chmod 600 ${runtimeConfig}
  '';

  updateRoutes = pkgs.writeShellScript "update-media-vpn-routes" ''
    set -euo pipefail
    jackett_uid="$(${pkgs.coreutils}/bin/id -u jackett)"
    jellyfin_uid="$(${pkgs.coreutils}/bin/id -u jellyfin)"
    old_jellyfin_addresses="$(${pkgs.coreutils}/bin/cat ${jellyfinRouteState} 2>/dev/null || true)"

    if [ "''${1:-}" = down ]; then
      ${pkgs.iproute2}/bin/ip -4 rule del priority ${jackettRulePriority} uidrange "$jackett_uid-$jackett_uid" table ${routeTable} || true
      for address in $old_jellyfin_addresses; do
        ${pkgs.iproute2}/bin/ip -4 rule del priority ${jellyfinRulePriority} to "$address" uidrange "$jellyfin_uid-$jellyfin_uid" table ${routeTable} || true
      done
      # Remove the former catch-all Jellyfin rule when switching generations.
      ${pkgs.iproute2}/bin/ip -4 rule del priority ${jellyfinRulePriority} uidrange "$jellyfin_uid-$jellyfin_uid" table ${routeTable} || true
      ${pkgs.coreutils}/bin/rm -f ${jellyfinRouteState}
      ${pkgs.iproute2}/bin/ip -4 route flush table ${routeTable} 2>/dev/null || true
      exit 0
    fi

    # The unreachable route prevents fallback to the ordinary gateway if the tunnel disappears.
    ${pkgs.iproute2}/bin/ip -4 route replace unreachable default table ${routeTable} metric 10000
    ${pkgs.iproute2}/bin/ip -4 route replace default dev ${interface} table ${routeTable} metric 100
    if ! ${pkgs.iproute2}/bin/ip -4 rule show | ${pkgs.gnugrep}/bin/grep -Fq "uidrange $jackett_uid-$jackett_uid lookup ${routeTable}"; then
      ${pkgs.iproute2}/bin/ip -4 rule add priority ${jackettRulePriority} uidrange "$jackett_uid-$jackett_uid" table ${routeTable}
    fi
    # Only route Jellyfin's TMDB artwork CDN addresses through the VPN.
    new_jellyfin_addresses="$(
      for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
        ${pkgs.coreutils}/bin/timeout 1s ${pkgs.glibc.getent}/bin/getent ahostsv4 ${jellyfinArtworkHost} || true
      done \
        | ${pkgs.gawk}/bin/awk '$2 == "STREAM" { print $1 }' \
        | ${pkgs.coreutils}/bin/sort -u
    )"
    if [ -n "$new_jellyfin_addresses" ]; then
      # Keep prior DNS answers for this tunnel session because the CDN rotates them.
      jellyfin_addresses="$(
        printf '%s\n%s\n' "$old_jellyfin_addresses" "$new_jellyfin_addresses" \
          | ${pkgs.gawk}/bin/awk -F. 'NF == 4 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && $4 ~ /^[0-9]+$/ { print }' \
          | ${pkgs.coreutils}/bin/sort -u
      )"
      for address in $jellyfin_addresses; do
        if ! ${pkgs.iproute2}/bin/ip -4 rule show | ${pkgs.gnugrep}/bin/grep -Fq "to $address uidrange $jellyfin_uid-$jellyfin_uid lookup ${routeTable}"; then
          ${pkgs.iproute2}/bin/ip -4 rule add priority ${jellyfinRulePriority} to "$address" uidrange "$jellyfin_uid-$jellyfin_uid" table ${routeTable}
        fi
      done
      printf '%s\n' "$jellyfin_addresses" > ${jellyfinRouteState}
    else
      echo "No IPv4 records for ${jellyfinArtworkHost}; keeping the current artwork routes" >&2
    fi
  '';
in
{
  networking.firewall.checkReversePath = "loose";

  environment.systemPackages = [ awgPackages.amneziawg-tools ];
  systemd.tmpfiles.rules = [ "d /var/lib/vpn 0700 root root -" ];

  systemd.services.vpn = {
    description = "AmneziaWG VPN client";
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = sourceConfig;
    path = [
      awgPackages.amneziawg-tools
      awgPackages.amneziawg-go
      pkgs.iproute2
      pkgs.glibc.getent
      pkgs.coreutils
      pkgs.python3
    ];
    environment.WG_QUICK_USERSPACE_IMPLEMENTATION = "${awgPackages.amneziawg-go}/bin/amneziawg-go";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "vpn";
      RuntimeDirectoryMode = "0700";
      UMask = "0077";
      ExecStartPre = prepareConfig;
      ExecStart = "${awgPackages.amneziawg-tools}/bin/awg-quick up ${runtimeConfig}";
      ExecStartPost = "${updateRoutes} refresh";
      ExecStop = "${awgPackages.amneziawg-tools}/bin/awg-quick down ${runtimeConfig}";
      ExecStopPost = "${updateRoutes} down";
    };
  };

  systemd.services.jackett = {
    after = [ "vpn.service" ];
    requires = [ "vpn.service" ];
    partOf = [ "vpn.service" ];
  };

  systemd.services.jellyfin.after = [ "vpn.service" ];

  systemd.services.jellyfin-artwork-vpn-routes = {
    description = "Refresh Jellyfin artwork CDN VPN routes";
    after = [ "vpn.service" ];
    requires = [ "vpn.service" ];
    unitConfig.ConditionPathExists = runtimeConfig;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${updateRoutes} refresh";
    };
  };

  systemd.timers.jellyfin-artwork-vpn-routes = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      AccuracySec = "1s";
      OnBootSec = "10s";
      OnUnitActiveSec = "15s";
      Unit = "jellyfin-artwork-vpn-routes.service";
    };
  };

}
