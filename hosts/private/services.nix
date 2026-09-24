_: {
  services.caddy.virtualHosts = {
    ":80" = {
      extraConfig = ''
        log {
          output file /var/log/caddy/access.log
        }

        handle /webdav/* {
          reverse_proxy 127.0.0.1:6065
        }

        handle_path /goaccess/* {
          root * /srv/goaccess
          file_server
        }
      '';
    };
  };
}
