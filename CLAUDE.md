# CLAUDE.md

Godot 4.7 (GDScript) проект: текстовая survival-RPG для телефона, portrait 1080×1920. Язык кода-комментариев, логов и UI — русский.

## Команды

- Проверка контента (после любой правки `data/`): `python tools/validate_content.py`. Если ломается вывод в консоли Windows, добавить `PYTHONIOENCODING=utf-8`.
- Смоук-тест логики (после правок в `autoload/` или контенте среза): `<Godot 4.7 console exe> --headless --path . res://scenes/Main.tscn` → ожидается `SMOKE OK`. Godot не в PATH — спросить пользователя путь к exe. В облачной сессии Claude Code (web) Godot ставит `.claude/hooks/session-start.sh`: `godot --headless --path . res://scenes/Main.tscn`. Тест перезаписывает `run.json`/`checkpoint.json` в `user://`: сохранить их до прогона и вернуть после.
- UI проверяется через MCP-сервер `godot` (`run_project` → `screenshot` → `click`, см. docs/MCP.md) или руками по чек-листу в docs/DEVELOPMENT.md.

## Архитектура — правила

- Логика находится в автозагрузках `autoload/`. Порядок в `project.godot` важен, `GameState` стоит последним.
- Модель контента: узел карты → локация (`data/locations`, описание + события) → событие (auto/manual, разовое/повторяемое, `triggers`) → ситуация или мгновенные `text`/`effects`.
- Персонаж: `InventorySystem` — сумка; `CharacterSystem` — снаряжение (5 слотов), навыки, характеристики (`stats`); `CraftingSystem` — рецепты. UI — оверлей `scenes/ui/CharacterPanel.gd` (+ `CharacterDollView`, `UiKit`).
- Экраны переключает **только** `GameState` (`enter_location`, `enter_situation`, `start_location_event`, `leave_location`).
- Эффекты и условия из JSON применяются только через `EffectResolver`. Новый тип требует правок в `EffectResolver.gd`, `tools/validate_content.py` и `docs/CONTENT.md`.
- Контент лежит только в `data/`; id в коде не хардкодить.
- Система с состоянием забега реализует `reset_for_new_run` / `to_save_data` / `load_save_data` и подключается в `SaveManager`.
- UI (`scenes/Game.gd`, `scenes/ui/SectorMapView.gd`) строится из кода и перерисовывается целиком по `GameState.screen_changed`.
- GDScript: отступы табами.

## Документация

- `docs/ARCHITECTURE.md` — системы, потоки (модули и события), сохранения, бой, экономика.
- `docs/CONTENT.md` — схемы JSON, правила событий, рецепты.
- `docs/DEVELOPMENT.md` — окружение, проверки, чек-лист, известные проблемы.
- `docs/MCP.md` — MCP-мост.

При изменении поведения обновлять соответствующий документ.
