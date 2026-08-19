{ pkgs, inputs, ... }: {
  environment.systemPackages =
    with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
    [
      # AI Coding Agents
      claude-code
      opencode
      codex
      oh-my-codex
      rtk

      # Workflow & Project Management
      bernstein
      gastown
      gascity
      backlog-md
      cc-sdd
      openspec
    ]
    ++ [
      # ADE from outworld-packages overlay
      pkgs.orca
    ];
}
