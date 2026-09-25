---
name: agterm-multiagent
description: Run sequential or parallel multi-agent workflows in agterm, with one interactive pi session per agent and file artifacts connecting the stages.
---

# Multi-agent workflows in agterm

Use this skill only when the agents run inside agterm. It is pi-specific: the
launcher creates interactive pi sessions, passes --skill options, and uses
pi's -n and @task-file arguments.

Do not use this skill for Codex, Limux, or another terminal manager. Use the
matching agent or terminal skill instead; the commands and session model are
different.

## Workflow

Create a working directory containing one task file per agent and a tab-separated
plan named plan.tsv:

    role<TAB>task-file<TAB>artifact

Example:

    planner<TAB>task-planner.md<TAB>plan.md
    coder<TAB>task-coder.md<TAB>result.patch
    reviewer<TAB>task-reviewer.md<TAB>review.md

The launcher starts each row in the current agterm window and workspace. It
waits for the artifact before starting the next row. Use - as the artifact to
start that row without waiting.

    scripts/launch.sh <workdir> <workspace> <plan.tsv>

## Environment

- AGENT_SKILLS: comma-separated skills passed to every pi session. Defaults to
  ponytail.
- WAIT_TIMEOUT: maximum wait per artifact in seconds. Defaults to 420.

## Operational constraints

- Run the launcher from an existing agterm window; it creates the named
  workspace in that window if needed.
- Do not add --no-select to agtermctl session new: an unrealized session does
  not start its process.
- Do not edit scripts/launch.sh while it is running; the shell may be reading
  the file incrementally.
- The launcher only coordinates processes. Agents still need clear task files,
  explicit artifact paths, and instructions to write those artifacts.
