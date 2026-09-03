{
  config,
  pkgs,
  lib,
  ...
}:

let
  # ── pi base configuration (Nix-native) ────────────────────────────────
  # pi (earendil-works pi coding agent) keeps its agent config in
  # ~/.pi/agent. `pi install <pkg>` rewrites settings.json, which is
  # impossible for the store symlink below, so packages are declared
  # directly in the `packages` array (npm package sources) and pi resolves
  # them at startup. Runtime state such as sessions, keybindings, prompts
  # and skills stays unmanaged and writable in ~/.pi/agent.
  #
  # MCP support comes from the pi-mcp-adapter package. It reads the
  # tool-agnostic standard file ~/.config/mcp/mcp.json (project overrides
  # live in .mcp.json) and only ever writes its own enable/disable flags
  # to project-local .pi/mcp.json, so the Nix-managed global file is
  # never rewritten. Secret-bearing values use the adapter's `!command`
  # form: the command runs when the server connects and its stdout
  # becomes the value, so key material is read at runtime, never stored.

  json = pkgs.formats.json { };

  basePiSettings = {
    packages = [
      "npm:pi-subagents"
      "npm:@dietrichgebert/ponytail"
      "npm:pi-mcp-adapter"
    ];
  };

  basePiMcpConfig = {
    mcpServers = {
      flux-schema-catalog.url = "https://schemas.fluxoperator.dev/mcp";
      siderolabs-docs.url = "https://docs.siderolabs.com/mcp";
      context7 = {
        url = "https://mcp.context7.com/mcp";
        auth = "bearer";
        bearerToken = "!cat ~/.secrets/context7-api-key";
      };
      drawio = {
        command = "npx";
        args = [ "@drawio/mcp" ];
      };
    };
  };
in
{
  # ── Module options ──────────────────────────────────────────────────────
  # Expose the base settings so the private companion can reference them
  # when building the org-specific config (recursiveUpdate over the
  # option; plain home.file values there win over mkDefault here).

  options.pi = {
    baseSettings = lib.mkOption {
      type = lib.types.attrs;
      default = basePiSettings;
      description = "Base ~/.pi/agent/settings.json configuration attrset.";
    };

    baseMcpConfig = lib.mkOption {
      type = lib.types.attrs;
      default = basePiMcpConfig;
      description = "Base ~/.config/mcp/mcp.json MCP server configuration attrset.";
    };
  };

  # ── Default config file ─────────────────────────────────────────────────
  # Hosts without a private overlay get the base settings. The private
  # companion overrides this via home.file (plain values win over
  # mkDefault), mirroring the opencode.json pattern.

  config = {
    home.file = {
      ".pi/agent/settings.json".source = lib.mkDefault (
        json.generate "pi-settings-base.json" config.pi.baseSettings
      );
      ".config/mcp/mcp.json".source = lib.mkDefault (
        json.generate "mcp-base.json" config.pi.baseMcpConfig
      );
    };
  };
}
