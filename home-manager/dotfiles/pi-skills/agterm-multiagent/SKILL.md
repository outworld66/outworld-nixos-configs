---
name: agterm-multiagent
description: Multi-agent workflows in agterm where each agent is a separate interactive pi session (tab) in one workspace of the current agterm window, chained sequentially via artifact files (planner → coder → reviewer style). Use when asked to orchestrate, run, or test multiple pi agents in agterm sessions or windows.
---

# Мультиагентный ворклоу в agterm

Каждый агент — отдельная интерактивная pi-сессия (вкладка) в одном воркспейсе
текущего окна agterm. Агенты запускаются последовательно: следующий стартует,
когда предыдущий создал артефакт-файл в рабочей директории.

## Использование

1. Создай рабочую директорию, напиши файлы задач (по одной на агента) и план
   `plan.tsv` со строками вида:

   ```
   role<TAB>taskfile<TAB>artifact
   ```

   `artifact` — файл, который должен создать агент; следующий агент не
   стартует, пока он не появится. `-` — не ждать (параллельный запуск).

   Пример (план planner → coder → reviewer):

   ```
   planner	task-planner.md	plan.md
   coder	task-coder.md	script.py
   reviewer	task-reviewer.md	review.md
   ```

2. Запусти лаунчер (пути — относительно директории этого skill):

   ```bash
   scripts/launch.sh <workdir> <workspace> <plan.tsv>
   ```

## Что делает скрипт

- создаёт воркспейс (без дублей, `workspace new` не дедуплицирует имена) в
  текущем окне agterm;
- `agtermctl session new` с командой `pi --skill <skills> -n <role> @<taskfile>`,
  рабочая директория — `<workdir>`;
- ждёт артефакт перед запуском следующего агента (poll 5 с, лимит
  `WAIT_TIMEOUT`).

## Настройка (env)

- `AGENT_SKILLS` — скиллы, форсируемые в агентах через `--skill`, через
  запятую. По умолчанию `ponytail`: агенты обязаны следовать минимальному
  подходу ponytail (лестница YAGNI/stdlib/кратчайший дифф);
- `WAIT_TIMEOUT` — секунды на этап (по умолчанию 420).

## Грабли (проверено на практике)

- Не задавай `--no-select` у `session new`: невидимая (not realized) сессия
  не запускает процесс — pi просто не стартует.
- Не редактируй `launch.sh` во время выполнения: bash читает скрипт
  инкрементально, правка по сдвигу строк даёт мусорные команды.
- Создание сессии переключает активную вкладку окна на нового агента.
