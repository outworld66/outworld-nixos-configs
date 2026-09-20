{ inputs, pkgs, ... }:

{
  environment.systemPackages =
    with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
    [
      claude-code
      opencode
      codex
      oh-my-codex
      pi
      herdr
      zcode
      rtk
      dsh
      codegraph
      bernstein
      gastown
      gascity
      backlog-md
      cc-sdd
      openspec
    ]
    ++ [
      pkgs.orca
      pkgs.pane
      pkgs.agterm
      pkgs.genoffice
    ];
}
