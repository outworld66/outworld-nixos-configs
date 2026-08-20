{
  inputs,
  pkgs,
  lib,
  ...
}:

let
  # ── OpenCode base configuration (Nix-native) ───────────────────────────
  # The full default config is defined here as a Nix attrset.
  # The private companion overrides it via home.file (no mkDefault
  # on the private side wins over mkDefault here), or via the
  # opencode.baseConfig module option.

  json = pkgs.formats.json { };

  # Default restrictive permissions for the unsandboxed session.
  defaultPermissions = {
    bash = {
      "*" = "ask";
      "sort *" = "allow";
      "uniq *" = "allow";
      "cue *" = "allow";
      "git status *" = "allow";
      "git log *" = "allow";
      "git diff *" = "allow";
      "git branch *" = "allow";
      "git add *" = "allow";
      "grep *" = "allow";
      "find *" = "allow";
      "head *" = "allow";
      "tail *" = "allow";
      "rg *" = "allow";
      "ls *" = "allow";
      "cat *" = "allow";
      "cargo test *" = "ask";
      "cargo build *" = "ask";
      "npm test *" = "ask";
      "npm run *" = "ask";
      "rtk find *" = "allow";
      "rtk grep *" = "allow";
      "rtk head *" = "allow";
      "rtk ls *" = "allow";
      "rtk tree *" = "allow";
      "rtk cat *" = "allow";
      "rtk read *" = "allow";
      "rtk go *" = "allow";
      "rtk init *" = "allow";
      "rtk wc *" = "allow";
      "rtk rg *" = "allow";
      "rtk make golangci-lint" = "allow";
      "rtk make lint" = "allow";
      "rtk go test *" = "allow";
      "rtk go build *" = "allow";
      "rtk make acc-tests" = "allow";
      "rtk git status *" = "allow";
      "rtk git diff *" = "allow";
      "rtk git log *" = "allow";
      "rtk git add *" = "allow";
      "rtk git commit *" = "allow";
      "rtk git push *" = "allow";
      "git commit *" = "deny";
      "git push *" = "deny";
      "git pull *" = "deny";
      "rm *" = "deny";
      "sudo *" = "deny";
      "chmod *" = "deny";
      "curl *" = "ask";
      "wget *" = "ask";
    };
    read = {
      "*" = "allow";
      "*.env" = "deny";
      "*.env.*" = "deny";
      "*.p12" = "deny";
      "*.key" = "deny";
      "*.pem" = "deny";
      "~/.ssh/*" = "deny";
      "~/.aws/*" = "deny";
      "~/.kube/*" = "deny";
      "~/.docker/*" = "deny";
      "*/secrets/*" = "deny";
      "*/credentials/*" = "deny";
    };
    glob = {
      "*" = "allow";
    };
    grep = {
      "*" = "allow";
    };
    task = {
      "*" = "ask";
      "explore" = "allow";
      "quick" = "allow";
    };
    skill = {
      "*" = "ask";
    };
    external_directory = {
      "~/projects/*" = "allow";
      "~/.config/*" = "ask";
      "~/.local/*" = "ask";
      "/tmp/*" = "ask";
    };
    doom_loop = "ask";
  };

  # Relaxed permissions for the sandboxed session.
  # The bwrap sandbox constrains filesystem access; inside it we can
  # safely auto-approve tools that would normally require confirmation.
  defaultSandboxPermissions = {
    bash = {
      "*" = "allow";
      "rm *" = "deny";
      "sudo *" = "deny";
      "chmod *" = "deny";
    };
    read = {
      "*" = "allow";
      "*.env" = "deny";
      "*.env.*" = "deny";
      "*.p12" = "deny";
      "*.key" = "deny";
      "*.pem" = "deny";
      "~/.ssh/*" = "deny";
      "~/.aws/*" = "deny";
      "~/.kube/*" = "deny";
      "~/.docker/*" = "deny";
      "*/secrets/*" = "deny";
      "*/credentials/*" = "deny";
    };
    glob = {
      "*" = "allow";
    };
    grep = {
      "*" = "allow";
    };
    task = {
      "*" = "allow";
    };
    skill = {
      "*" = "allow";
    };
    external_directory = {
      "*" = "allow";
    };
    doom_loop = "allow";
  };

  baseOpencodeConfig = {
    "$schema" = "https://opencode.ai/config.json";
    plugin = [
      "oh-my-openagent@latest"
      "@plannotator/opencode@latest"
    ];
    permission = defaultPermissions;
    mcp = {
      flux-schema-catalog = {
        type = "remote";
        url = "https://schemas.fluxoperator.dev/mcp";
        enabled = true;
      };
      siderolabs-docs = {
        type = "remote";
        url = "https://docs.siderolabs.com/mcp";
        enabled = true;
      };
      context7 = {
        type = "local";
        command = [
          "npx"
          "-y"
          "@upstash/context7-mcp"
          "--api-key"
          "{file:~/.secrets/context7-api-key}"
        ];
        enabled = true;
      };
      drawio = {
        type = "local";
        command = [
          "npx"
          "@drawio/mcp"
        ];
        enabled = true;
      };
    };
  };

  baseOpenagentConfig = {
    "$schema" =
      "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/assets/oh-my-opencode.schema.json";
  };

  drawioSkillSrc = "${inputs.drawio-skill}/skills/drawio-skill";
in
{
  # ── Module options ──────────────────────────────────────────────────────
  # Expose the base config and sandbox permissions as options so that
  # the private companion can reference them when building the full
  # org-specific config (recursiveUpdate + sandbox override).

  options.opencode = {
    baseConfig = lib.mkOption {
      type = lib.types.attrs;
      default = baseOpencodeConfig;
      description = "Base opencode.json configuration attrset.";
    };

    baseOpenagentConfig = lib.mkOption {
      type = lib.types.attrs;
      default = baseOpenagentConfig;
      description = "Base oh-my-openagent.json configuration attrset.";
    };

    sandboxPermissions = lib.mkOption {
      type = lib.types.attrs;
      default = defaultSandboxPermissions;
      description = "Permissions for the sandboxed opencode session.";
    };
  };

  # ── Default config files ────────────────────────────────────────────────
  # Hosts without a private overlay get these generated from the base
  # attrsets.  The private companion overrides them via home.file
  # (plain values win over mkDefault).

  config = {
    home.file = {
      ".config/opencode/opencode.json".source = lib.mkDefault (
        json.generate "opencode-base.json" baseOpencodeConfig
      );
      ".config/opencode/oh-my-openagent.json".source = lib.mkDefault (
        json.generate "oh-my-openagent-base.json" baseOpenagentConfig
      );
    };

    xdg.configFile."opencode/skills/drawio-skill".source = drawioSkillSrc;
  };
}
