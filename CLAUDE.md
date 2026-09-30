# CLAUDE.md

Godot 4.7 (GDScript) проект: текстовая survival-RPG для телефона, portrait 1080×1920. Язык кода-комментариев, логов и UI — русский.

## Команды

- Проверка контента (после любой правки `data/`): `python tools/validate_content.py`. Если ломается вывод в консоли Windows, добавить `PYTHONIOENCODING=utf-8`.
- Смоук-тест логики (после правок в `autoload/` или контенте среза): `<Godot 4.7 console exe> --headless --path . res://scenes/Main.tscn` → ожидается `SMOKE OK`. Локальный Godot: `D:\Repos\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`. Тест перезаписывает `run.json`/`checkpoint.json`/`meta.json` в `user://`: сохранить их до прогона и вернуть после.
- UI проверяется через MCP-сервер `godot` (`run_project` → `screenshot` → `click`, см. docs/MCP.md) или руками по чек-листу в docs/DEVELOPMENT.md.
- Пиксельный арт (после правок `assets/art`): `python tools/make_pixel_art.py`, затем импорт `<Godot 4.7 console exe> --headless --path . --import`.
- Звуки (после правок таблицы `SOUNDS` в `tools/import_sounds.py`): `python tools/import_sounds.py "D:/Repos/400 Sounds Pack"`, затем тот же импорт Godot.

## Архитектура — правила

- Логика находится в автозагрузках `autoload/`. Порядок в `project.godot` важен, `GameState` стоит последним.
- Модель контента: узел карты → локация (`data/locations`, описание + события) → событие (auto/manual, разовое/повторяемое, `triggers`) → ситуация или мгновенные `text`/`effects`.
- Персонаж: `InventorySystem` — сумка; `CharacterSystem` — снаряжение (5 слотов), навыки, характеристики (`stats`); `CraftingSystem` — рецепты. UI — оверлей `scenes/ui/CharacterPanel.gd` (+ `CharacterDollView`, `UiKit`).
- Экраны переключает **только** `GameState` (`enter_location`, `enter_situation`, `start_location_event`, `leave_location`).
- Эффекты и условия из JSON применяются только через `EffectResolver`. Новый тип требует правок в `EffectResolver.gd`, `tools/validate_content.py` и `docs/CONTENT.md`.
- Контент лежит только в `data/`; id в коде не хардкодить.
- Система с состоянием забега реализует `reset_for_new_run` / `to_save_data` / `load_save_data` и подключается в `SaveManager`.
- UI (`scenes/Game.gd`, `scenes/ui/SectorMapView.gd`) строится из кода и перерисовывается целиком по `GameState.screen_changed`.
- Экран модуля и экран ситуации — общая лента `NarrativeSystem`: текст дописывается снизу, ничего не очищается. Выбор в ситуации → реплика игрока → эффекты → `result` → кнопка «Продолжить» (`SituationEngine.confirm_continue`).
- Отдельной кнопки «Выйти на карту» нет: из модуля выводит кнопка «Карта» в HUD.
- Размеры шрифта задаются только через `UiKit.fs()`; настройки интерфейса — `SettingsSystem` (`user://settings.json`), анимации переходов включаются там же.
- Кислород тратится не по таймеру, а на действия: цены в `data/config.json` → `o2_costs`, списывает `ResourceSystem.spend_o2`.
- Ключи — предметы категории `key` с `unlocks`; замок (`lock`) ставится на узел сектора или на событие локации, открывает `EffectResolver.can_open_lock` / `open_lock`.
- Модуль-база — локация с `base: true`: чекпойнт, склад (stash локации) и верстак.
- Бой — манёвры и дистанция в духе Neo Scavenger (`CombatSystem` + `scenes/ui/CombatView.gd`), ходы сторон разыгрываются одновременно.
- Пиксельные картинки: `assets/art/scenes/<image>.png` подключаются полем `image` у ситуаций, локаций и событий; иконки `assets/art/items/<item_id>.png` — по id предмета. Рисует `tools/make_pixel_art.py`.
- Звуки: `assets/sounds/<id>.wav`, играет `SoundSystem` (автозагрузка перед `GameState`) — по сигналам систем или `SoundSystem.play(id)` из UI; в `--headless` молчит. Включение и громкость — `SettingsSystem`.
- GDScript: отступы табами.

## Документация

- `docs/ARCHITECTURE.md` — системы, потоки (модули и события), сохранения, бой, экономика.
- `docs/CONTENT.md` — схемы JSON, правила событий, рецепты.
- `docs/DEVELOPMENT.md` — окружение, проверки, чек-лист, известные проблемы.
- `docs/MCP.md` — MCP-мост.

При изменении поведения обновлять соответствующий документ.
