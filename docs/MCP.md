# MCP: Claude Code ↔ Godot

Через MCP Claude Code может работать с редактором и запущенной игрой: смотреть дерево сцены, запускать проект, делать скриншоты и кликать по UI.

Код основан на [slangwald/godot-mcp](https://github.com/slangwald/godot-mcp).

> Это **не** npm-пакет `@coding-solo/godot-mcp`. Тот сервер устроен иначе и с плагином этого проекта не общается.

## Как устроено

```
Claude Code ──stdio──► mcp/godot_mcp_server.py (FastMCP)
                           │
                           ├─TCP 127.0.0.1:9500─► addons/mcp_bridge/plugin.gd   (EditorPlugin, в редакторе)
                           └─TCP 127.0.0.1:9501─► mcp_bridge_game.gd            (автозагрузка McpBridgeGame, в игре)
```

- **Протокол:** одна JSON-команда `{"cmd": "...", ...}` и ответ JSON, завершённые переводом строки. Каждый вызов инструмента открывает новое TCP-соединение.
- **Плагин редактора** включён в `project.godot` (`[editor_plugins]`) и слушает порт, пока открыт редактор.
- **Мост игры** — автозагрузка, которая стартует при каждом запуске игры, в том числе из редактора по F5.

## Установка

1. Зависимости сервера (один раз):

   ```bash
   uv sync --directory mcp
   ```

2. Регистрация сервера в Claude Code для этого проекта. Выполнять из корня репозитория:

   ```bash
   claude mcp add godot --scope project -- uv run --directory mcp godot_mcp_server.py
   ```

   Команда создаст `.mcp.json` в корне; его можно закоммитить, чтобы сервер был у всей команды. Эквивалент вручную:

   ```json
   {
     "mcpServers": {
       "godot": {
         "type": "stdio",
         "command": "uv",
         "args": ["run", "--directory", "mcp", "godot_mcp_server.py"]
       }
     }
   }
   ```

3. Открыть проект в редакторе Godot. В Output должно появиться `MCP Bridge: Listening on 127.0.0.1:9500`.

4. Перезапустить сессию Claude Code и проверить, что сервер `godot` подключён (`claude mcp list`).

## Порты

По умолчанию редактор слушает 9500, игра — 9501. Чтобы изменить порты, создайте в корне проекта `mcp_ports.cfg` (он не обязателен и отсутствует в репозитории):

```ini
[mcp]
editor_port=9510
game_port=9511
```

Файл читают все три стороны: плагин, игровой мост и Python-сервер. После изменения перезапустите редактор и сессию Claude Code.

## Инструменты

### Редактор (порт 9500, нужен открытый редактор)

| Инструмент | Что делает |
|---|---|
| `get_editor_state` | Открытая сцена и флаг, запущена ли игра |
| `get_scene_tree` | Дерево открытой в редакторе сцены |
| `open_scene(path)` | Открыть сцену (`res://...`) |
| `save_scene` | Сохранить открытую сцену |
| `get_node_properties(node_path)` | Свойства узла |
| `modify_node(node_path, properties)` | Изменить свойства узла |
| `create_node(parent_path, type, name)` / `delete_node(node_path)` | Создать или удалить узел |
| `instantiate_scene(parent_path, scene_path, name)` | Вставить сцену как дочерний узел |
| `set_resource(...)` | Создать ресурс и присвоить его свойству |
| `attach_script(node_path, source)` / `set_script(node_path, path)` | Встроенный или файловый скрипт на узел |
| `get_signals` / `connect_signal` | Сигналы узла и их подключения |
| `list_resources(directory, extensions)` | Список файлов проекта |
| `run_project` / `run_scene(path)` / `stop_project` | Запуск и остановка игры |
| `get_output` | Последние 50 строк `user://logs/godot.log` (лог последнего запуска игры, не панель Output редактора) |
| `undo` / `redo` | История правок редактора |

### Игра (порт 9501, игра должна быть запущена)

| Инструмент | Что делает |
|---|---|
| `screenshot` | PNG корневого viewport |
| `click(x, y)` | Нажатие и отпускание ЛКМ в координатах viewport. Ориентируйтесь на пиксели последнего скриншота |
| `get_runtime_tree` | Живое дерево узлов (имена и типы). UI строится из кода, так что узлы видны только здесь, а не в `get_scene_tree` |

## Типовой цикл проверки

1. `run_project`.
2. `screenshot`.
3. `click` по кнопке.
4. Снова `screenshot`.
5. `get_output` при ошибках.
6. `stop_project`.

Кнопки в `Game.gd` имеют говорящие имена (`MapButton`, `ArchiveButton`, `MapNode_<id>`, `MapFloor_<id>`), их удобно искать через `get_runtime_tree`.

Скриншоты, которые сохраняются по ходу работы, складывайте в `artifacts/` (папка в `.gitignore`).

## Неполадки

| Симптом | Причина |
|---|---|
| `Cannot connect to Godot editor on port 9500` | Редактор не открыт, или плагин *MCP Bridge* выключен (*Project Settings → Plugins*) |
| `Cannot connect to Godot game on port 9501` | Игра не запущена (`run_project`) |
| `Failed to listen on port ...` в Output | Порт занят (например, второй экземпляр редактора). Смените порт в `mcp_ports.cfg` |
| `Timeout waiting for response` | Редактор или игра зависли на паузе, или ответ не пришёл за 5 с (для скриншота — за 10 с) |

## Безопасность

- Оба моста слушают только `127.0.0.1`.
- Мост редактора умеет выполнять произвольный GDScript (`attach_script`) — не пробрасывайте порт наружу.
- `McpBridgeGame` — это автозагрузка. **Уберите её перед релизной сборкой**, см. [DEVELOPMENT.md](DEVELOPMENT.md#экспорт).
