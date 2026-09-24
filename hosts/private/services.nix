_: {
  services.caddy.virtualHosts = {
    "auth.private.outworld66.ru" = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }
        reverse_proxy 127.0.0.1:9091
      '';
    };

    "files.private.outworld66.ru" = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }
        @hasDest header_regexp dest ^https?://[^/]+(.*)$
        header @hasDest Destination {re.dest.1}
        handle /webdav* {
          reverse_proxy 127.0.0.1:6065
        }
      '';
    };

    "stats.private.outworld66.ru" = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }

        forward_auth 127.0.0.1:9091 {
          uri /api/authz/forward-auth
          copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
        }

        @websocket header Connection *Upgrade
        handle @websocket {
          reverse_proxy 127.0.0.1:7890
        }

        handle_path / {
          root * /srv/goaccess
          file_server
        }
      '';
    };
  };
}
