#!/usr/bin/env bash
# Run artifact-gated agents in Limux.
# Usage: launch.sh <workdir> <plan.tsv>
# plan.tsv rows: role<TAB>task-file<TAB>artifact; '-' means do not wait.
# AGENT_COMMAND is pi or codex and defaults to pi.
# AGENT_SKILLS applies to pi and defaults to ponytail.
# WAIT_TIMEOUT is the artifact wait limit in seconds and defaults to 420.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  sed -n '2,7p' "$0" >&2
  exit 2
fi

DIR=$(realpath "$1")
PLAN=$2
AGENT_COMMAND=${AGENT_COMMAND:-pi}
AGENT_SKILLS=${AGENT_SKILLS:-ponytail}
WAIT_TIMEOUT=${WAIT_TIMEOUT:-420}

launch() {
  local role=$1 task=$2 artifact=$3 cmd skill
  if [[ ! -f "$DIR/$task" ]]; then
    echo "Skipping $role: task file does not exist: $task" >&2
    return 1
  fi
  if [[ $artifact != - && ! -f "$DIR/$artifact" ]]; then
    echo "Skipping $role: required artifact does not exist: $artifact" >&2
    return 1
  fi

  case $AGENT_COMMAND in
    pi)
      cmd=pi
      local IFS=,
      for skill in $AGENT_SKILLS; do
        cmd+=" --skill $skill"
      done
      printf -v cmd '%s -n %q @%q' "$cmd" "$role" "$DIR/$task"
      ;;
    codex)
      printf -v cmd 'codex %q' "$(<"$DIR/$task")"
      ;;
    *)
      echo "AGENT_COMMAND must be pi or codex" >&2
      return 2
      ;;
  esac

  limux new-pane --direction right --command "$cmd" >/dev/null
  echo "Started $AGENT_COMMAND agent $role in Limux"
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
