---
name: limux-multiagent
description: Run coordinated Codex or pi agents in Limux panes, with sequential artifact-gated stages or parallel launches from the current Limux workspace.
---

# Multi-agent workflows in Limux

Use this skill when agents should run in Limux. Limux exports
LIMUX_WORKSPACE_ID, LIMUX_SURFACE_ID, LIMUX_PANE_ID, and LIMUX_SOCKET inside
its terminals, so commands normally target the current Limux instance.

## Built-in team mode

For direct peer-to-peer collaboration, use Limux's native team command:

    limux agent-team --agents codex,claude --cwd "$PWD"

It creates one workspace per agent and writes an AGENTS.md describing the
agent-msg protocol. Do not run it in a directory with an existing AGENTS.md;
Limux refuses to replace one. Preview first when needed:

    limux --json agent-team --dry-run

## Artifact-gated workflow

For planner -> coder -> reviewer pipelines, create task files and a
tab-separated plan.tsv with rows:

    role<TAB>task-file<TAB>artifact

Use - as the artifact to launch a stage without waiting. Run:

    scripts/launch.sh <workdir> <plan.tsv>

The launcher creates one Limux pane per stage to the right of the current pane,
waits for each artifact, and supports both pi and codex through AGENT_COMMAND:

    AGENT_COMMAND=pi scripts/launch.sh . plan.tsv
    AGENT_COMMAND=codex scripts/launch.sh . plan.tsv

For pi, AGENT_SKILLS supplies comma-separated --skill values and defaults to
ponytail. For Codex, the task file is passed as the initial prompt.

## Communication and targeting

Use limux identify --json and limux list-panels to inspect the current
workspace. Use limux new-pane --direction right --command <agent> for a
one-off peer. Use limux send only with an explicit peer workspace or surface
target; do not guess IDs.

Limux is the terminal manager here. Do not use agtermctl, agterm workspaces,
or pi-only flags unless the selected agent is pi and the command is part of its
own invocation.
