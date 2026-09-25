#!/usr/bin/env bash
# Run sequential or parallel pi agents in an existing agterm window.
# Usage: launch.sh <workdir> <workspace> <plan.tsv>
# plan.tsv rows: role<TAB>task-file<TAB>artifact; '-' means do not wait.
# AGENT_SKILLS is comma-separated and defaults to ponytail.
# WAIT_TIMEOUT is the artifact wait limit in seconds and defaults to 420.
set -euo pipefail

if [[ $# -ne 3 ]]; then
  sed -n '2,7p' "$0" >&2
  exit 2
fi

DIR=$(realpath "$1")
WS=$2
PLAN=$3
WAIT_TIMEOUT=${WAIT_TIMEOUT:-420}
AGENT_SKILLS=${AGENT_SKILLS:-ponytail}

if ! agtermctl tree --json | jq -e --arg ws "$WS" \
  '.result.tree.workspaces[] | select(.name == $ws)' >/dev/null; then
  agtermctl workspace new "$WS" >/dev/null
fi

launch() {
  local role=$1 task=$2 artifact=$3
  if [[ ! -f "$DIR/$task" ]]; then
    echo "Skipping $role: task file does not exist: $task" >&2
    return 1
  fi
  if [[ $artifact != - && ! -f "$DIR/$artifact" ]]; then
    echo "Skipping $role: required artifact does not exist: $artifact" >&2
    return 1
  fi

  local cmd=pi skill
  local IFS=,
  for skill in $AGENT_SKILLS; do
    cmd+=" --skill $skill"
  done
  printf -v cmd '%s -n %q @%q' "$cmd" "$role" "$DIR/$task"

  # Keep the session realized: --no-select prevents the process from starting.
  agtermctl session new --name "$role" --cwd "$DIR" \
    --command "$cmd" --workspace-name "$WS" >/dev/null
  echo "Started pi agent $role in agterm workspace $WS"
}

wait_for() {
  local file=$1 elapsed=0
  while (( elapsed < WAIT_TIMEOUT )); do
    [[ -f "$DIR/$file" ]] && return 0
    sleep 5
    ((elapsed += 5))
  done
  echo "Timed out waiting for $file (${WAIT_TIMEOUT}s)" >&2
  return 1
}

while IFS=$'\t' read -r role task artifact; do
  [[ -z ${role:-} || $role == \#* ]] && continue
  launch "$role" "${task:-}" "${artifact:--}"
  [[ ${artifact:--} == - ]] || wait_for "$artifact"
done < "$PLAN"
