{
  config,
  lib,
  ...
}:

let
  # ── Universal MCP server registry ─────────────────────────────────────
  # One canonical entry per server; harness modules (pi, opencode, ...)
  # map it into their own config format through the read-only `mcp.pi`
  # and `mcp.opencode` options. Adding a server here (or via
  # `mcp.servers` from the private companion) configures it for every
  # harness at once.
  #
  # Canonical entry fields:
  #   url        remote server base URL
  #   tokenFile  file whose contents authenticate a remote server
  #   command    stdio server executable
  #   args       stdio server arguments
  #   env        plain environment for a stdio server
  #   tokenFiles attrset of environment variable -> secret file
  #
  # Secrets stay in files and are adapted per harness at generation
  # time: pi-mcp-adapter reads `!cat <file>` when the server connects,
  # opencode interpolates `{file:<path>}` from its config.

  baseServers = {
    flux-schema-catalog.url = "https://schemas.fluxoperator.dev/mcp";
    siderolabs-docs.url = "https://docs.siderolabs.com/mcp";
    context7 = {
      url = "https://mcp.context7.com/mcp";
      tokenFile = "~/.secrets/context7-api-key";
    };
    drawio = {
      command = "npx";
      args = [ "@drawio/mcp" ];
    };
    mcp-mermaid = {
      command = "npx";
      args = [
        "-y"
        "mcp-mermaid"
      ];
    };
  };

  # pi / pi-mcp-adapter (~/.config/mcp/mcp.json) format.
  toPi =
    servers:
    lib.mapAttrs (
      _name: s:
      if s ? url then
        {
          inherit (s) url;
        }
        // (lib.optionalAttrs (s ? tokenFile) {
          auth = "bearer";
          bearerToken = "!cat ${s.tokenFile}";
        })
      else
        {
          inherit (s) command;
          args = s.args or [ ];
        }
        // (lib.optionalAttrs (s ? env || s ? tokenFiles) {
          env = (s.env or { }) // lib.mapAttrs (_: f: "!cat ${f}") (s.tokenFiles or { });
        })
    ) servers;

  # opencode (opencode.json `mcp` section) format.
  toOpenCode =
    servers:
    lib.mapAttrs (
      _name: s:
      if s ? url then
        {
          type = "remote";
          inherit (s) url;
          enabled = true;
        }
        // (lib.optionalAttrs (s ? tokenFile) {
          oauth = false;
          headers.Authorization = "Bearer {file:${s.tokenFile}}";
        })
      else
        {
          type = "local";
          command = [ s.command ] ++ (s.args or [ ]);
          enabled = true;
        }
        // (lib.optionalAttrs (s ? env || s ? tokenFiles) {
          environment = (s.env or { }) // lib.mapAttrs (_: f: "{file:${f}}") (s.tokenFiles or { });
        })
    ) servers;
in
{
  options.mcp = {
    baseServers = lib.mkOption {
      type = lib.types.attrs;
      default = baseServers;
      description = "Generic MCP servers configured for every harness.";
    };

    extraServers = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Host- or organization-specific servers merged over the base registry.";
    };

    servers = lib.mkOption {
      type = lib.types.attrs;
      default = config.mcp.baseServers // config.mcp.extraServers;
      readOnly = true;
      description = "Full canonical registry.";
    };

    pi = lib.mkOption {
      type = lib.types.attrs;
      default = toPi config.mcp.servers;
      readOnly = true;
      description = "Registry mapped to the pi MCP config format (mcp.json mcpServers).";
    };

    opencode = lib.mkOption {
      type = lib.types.attrs;
      default = toOpenCode config.mcp.servers;
      readOnly = true;
      description = "Registry mapped to the opencode MCP config format.";
    };
  };
}
