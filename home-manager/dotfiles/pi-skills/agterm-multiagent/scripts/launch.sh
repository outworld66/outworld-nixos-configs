#!/usr/bin/env bash
# Мультиагентный ворклоу в agterm: каждый агент — отдельная интерактивная
# pi-сессия (вкладка) в одном воркспейсе ТЕКУЩЕГО окна agterm; этапы связаны
# ожиданием артефактов (файлов) в рабочей директории.
#
# usage: launch.sh <workdir> <workspace> <plan.tsv>
#   plan.tsv: строки "role<TAB>taskfile<TAB>artifact" (artifact «-» — не
#   ждать, агент запускается параллельно с предыдущими)
# env: WAIT_TIMEOUT (сек на этап, 420), AGENT_SKILLS (через запятую, по
#   умолчанию ponytail — передаётся агентам через --skill)
set -euo pipefail

if [[ $# -ne 3 ]]; then
  sed -n '2,10p' "$0" >&2
  exit 2
fi
DIR=$(realpath "$1")
WS=$2
PLAN=$3
WAIT_TIMEOUT=${WAIT_TIMEOUT:-420}
AGENT_SKILLS=${AGENT_SKILLS:-ponytail}

# один воркспейс на всех агентов (workspace new не дедуплицирует имена)
if ! agtermctl tree --json | jq -e --arg ws "$WS" '.result.tree.workspaces[] | select(.name==$ws)' >/dev/null; then
  agtermctl workspace new "$WS" >/dev/null
fi

launch() { # role taskfile expect
  local role=$1 task=$2 expect=$3
  if [[ ! -f "$DIR/$task" ]]; then
    echo "!! нет файла задачи $task, агент $role пропущен" >&2
    return 1
  fi
  if [[ $expect != "-" && ! -f "$DIR/$expect" ]]; then
    echo "!! артефакт $expect не найден, агент $role пропущен" >&2
    return 1
  fi
  local cmd="pi" s
  local IFS=,
  for s in $AGENT_SKILLS; do cmd+=" --skill $s"; done
  printf -v cmd '%s -n %q @%q' "$cmd" "$role" "$DIR/$task"
  # ВАЖНО: без --no-select — нереализованная (not realized) сессия не запускает процесс
  agtermctl session new --name "$role" --cwd "$DIR" \
    --command "$cmd" --workspace-name "$WS" >/dev/null
  echo "агент $role запущен (воркспейс $WS, текущее окно)"
}

wait_for() {
  local file=$1 i
  for ((i = 0; i < WAIT_TIMEOUT; i += 5)); do
    [[ -f "$DIR/$file" ]] && return 0
    sleep 5
  done
  echo "!! таймаут ожидания $file (${WAIT_TIMEOUT}s)" >&2
  return 1
}

while IFS=$'\t' read -r role task expect; do
  [[ -z ${role:-} || $role == \#* ]] && continue
  launch "$role" "${task:-}" "${expect:--}"
  [[ ${expect:--} == "-" ]] || wait_for "$expect"
done < "$PLAN"
