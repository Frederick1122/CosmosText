extends Node
## Два уровня сохранения — run (обнуляется при смерти) и meta (переживает
## смерть) — плюс чекпоинт для платного/рекламного отката.
## См. gdd-v1.md раздел 5.6 и tech-spec-v1.md раздел 7.
##
## Запись атомарная: сначала во временный файл, затем переименование. Обрыв
## питания или краш в момент записи не оставляет обрезанный JSON.
## У каждого файла есть "version"; сейв новее игры не загружается.

const RUN_PATH := "user://run.json"
const META_PATH := "user://meta.json"
const CHECKPOINT_PATH := "user://checkpoint.json"

## 0 — сейвы до введения поля (читаются, недостающие блоки берут значения по
## умолчанию), 1 — кислород по таймеру (ключ resources.o2_seconds),
## 2 — кислород за действия (resources.o2) и журнал забега.
const SAVE_VERSION := 2

var _config: Dictionary = {}


func _ready() -> void:
	_config = _load_res_json("res://data/config.json")
	EventBus.player_died.connect(_on_player_died)
	EventBus.returned_to_hub.connect(_on_returned_to_hub)
	load_meta()


## Сворачивание, кнопка «назад» и закрытие приложения — последний шанс
## сохраниться: на мобильных процесс может быть убит системой без выхода.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST, \
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			autosave()
			save_meta()


func get_start_sector_id() -> String:
	return str(_config.get("start_sector_id", "wreck_01"))


func get_opening_situation_id() -> String:
	return str(_config.get("opening_situation_id", ""))


func start_new_run() -> void:
	ResourceSystem.reset_for_new_run(_config)
	InventorySystem.reset_for_new_run(_config)
	CharacterSystem.reset_for_new_run(_config)  # после ресурсов и сумки: применяет бонусы
	ProgressionSystem.reset_for_new_run()
	NeedsSystem.reset_for_new_run()
	QuestSystem.reset_for_new_run()
	ExplorationSystem.reset_for_new_run()
	SituationEngine.reset_for_new_run()
	LocationSystem.reset_for_new_run()
	CombatSystem.reset_for_new_run()
	JournalSystem.reset_for_new_run()
	NarrativeSystem.reset_for_new_run()
	EconomyManager.reset_for_new_run()
	NotificationSystem.reset_for_new_run()
	_delete_file(RUN_PATH)
	_delete_file(CHECKPOINT_PATH)

func save_run() -> void:
	var data := {
		"version": SAVE_VERSION,
		"resources": ResourceSystem.to_save_data(),
		"inventory": InventorySystem.to_save_data(),
		"character": CharacterSystem.to_save_data(),
		"progression": ProgressionSystem.to_save_data(),
		"needs": NeedsSystem.to_save_data(),
		"quests": QuestSystem.to_save_data(),
		"exploration": ExplorationSystem.to_save_data(),
		"situation": SituationEngine.to_save_data(),
		"locations": LocationSystem.to_save_data(),
		"map": MapSystem.to_save_data(),
		"journal": JournalSystem.to_save_data(),
		"narrative": NarrativeSystem.to_save_data(),
		"notifications": NotificationSystem.to_save_data(),
		"economy_run": EconomyManager.to_run_save_data(),
	}
	_write_json(RUN_PATH, data)


## Сохранение забега в безопасной точке — на карте и на экране модуля.
## Бой и ситуацию не сохраняем: прерванный бой должен переигрываться с входа
## в модуль, а не пропускаться. Вызывают GameState при смене экрана и сам
## SaveManager при сворачивании приложения.
func autosave() -> void:
	if MapSystem.current_sector_id == "":
		return  # забег не начат
	var screen: int = GameState.current_screen
	if screen != GameState.Screen.SECTOR_MAP and screen != GameState.Screen.LOCATION:
		return
	save_run()


func load_run(fallback_sector_id: String = "wreck_01") -> bool:
	var data := _read_json(RUN_PATH)
	if data.is_empty():
		return false
	var resource_data: Dictionary = data.get("resources", data)
	var situation_data: Dictionary = data.get("situation", {
		"flags": data.get("flags", {}),
		"current_id": data.get("current_situation", ""),
	})
	var map_data: Dictionary = data.get("map", {
		"sector_id": data.get("sector_id", ""),
		"nodes": data.get("nodes", {}),
	})
	if not MapSystem.load_save_data(map_data, fallback_sector_id):
		return false
	ResourceSystem.load_save_data(resource_data)
	InventorySystem.load_save_data(data.get("inventory", []))
	CharacterSystem.load_save_data(data.get("character", {}))  # после ресурсов и сумки
	ProgressionSystem.load_save_data(data.get("progression", {}))
	NeedsSystem.load_save_data(data.get("needs", {}))
	QuestSystem.load_save_data(data.get("quests", {}))
	ExplorationSystem.load_save_data(data.get("exploration", {}))
	SituationEngine.load_save_data(situation_data)
	LocationSystem.load_save_data(data.get("locations", {}))
	var journal_data = data.get("journal", [])
	JournalSystem.load_save_data(journal_data if journal_data is Array else [])
	NotificationSystem.load_save_data(data.get("notifications", {}))
	var narrative_data = data.get("narrative", [])
	NarrativeSystem.load_save_data(narrative_data if narrative_data is Array else [])
	EconomyManager.load_run_save_data(data.get("economy_run", {}))
	return true


func clear_run() -> void:
	start_new_run()


func write_checkpoint() -> void:
	save_run()
	if FileAccess.file_exists(RUN_PATH):
		_write_text(CHECKPOINT_PATH, FileAccess.get_file_as_string(RUN_PATH))


func has_checkpoint() -> bool:
	return FileAccess.file_exists(CHECKPOINT_PATH)


func restore_checkpoint() -> void:
	if not has_checkpoint():
		clear_run()
		return
	_write_text(RUN_PATH, FileAccess.get_file_as_string(CHECKPOINT_PATH))
	load_run()


func save_meta() -> void:
	var data := {
		"version": SAVE_VERSION,
		"archive": ArchiveSystem.to_save_data(),
		"chronicle": ChronicleSystem.to_save_data(),
		"economy": EconomyManager.to_save_data(),
	}
	_write_json(META_PATH, data)


func load_meta() -> void:
	var data := _read_json(META_PATH)
	if data.is_empty():
		return
	ArchiveSystem.load_save_data(data.get("archive", []))
	ChronicleSystem.load_save_data(data.get("chronicle", {}))
	EconomyManager.load_save_data(data.get("economy", {}))


## Победа: забег закончен и продолжать его нечем — стираем run и чекпойнт,
## итог уже записан в хронику, её и фиксируем в meta.
func finish_run() -> void:
	save_meta()
	_delete_file(RUN_PATH)
	_delete_file(CHECKPOINT_PATH)


## Экран смерти вызывает confirm_restart() или confirm_rollback() по выбору
## игрока — SaveManager сам ничего не решает, только исполняет.
func confirm_restart() -> void:
	clear_run()
	save_meta()


## Экономика (какой именно путь — платный или рекламный — списывает откат)
## решается ДО вызова этого метода, самим вызывающим кодом (см. Game.gd
## _death_rollback) — иначе EconomyManager.use_rollback() легко списать дважды.
func confirm_rollback() -> void:
	restore_checkpoint()
	save_meta()


func _on_player_died(_cause: String) -> void:
	# Само решение restart/rollback — за игроком на экране смерти (GameState.Screen.DEATH).
	# Здесь только фиксируем meta (счётчики отката не должны потеряться при краше).
	save_meta()


func _on_returned_to_hub() -> void:
	write_checkpoint()


func _write_json(path: String, data) -> void:
	_write_text(path, JSON.stringify(data))


## Атомарная запись: во временный файл, затем переименование поверх целевого.
## Прерванная запись портит только .tmp, а не сам сейв.
func _write_text(path: String, text: String) -> void:
	var tmp_path := path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: не удалось открыть %s на запись (ошибка %d)" % [tmp_path, FileAccess.get_open_error()])
		return
	f.store_string(text)
	f.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		push_error("SaveManager: не удалось открыть каталог сейвов %s" % path.get_base_dir())
		return
	var err := dir.rename(tmp_path, path)
	if err != OK:
		push_error("SaveManager: не удалось заменить %s (ошибка %d)" % [path, err])


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		push_error("SaveManager: сейв %s повреждён и не прочитан" % path)
		return {}
	var version := int(parsed.get("version", 0))
	if version > SAVE_VERSION:
		push_error("SaveManager: сейв %s версии %d новее игры (%d) — не загружаем" % [path, version, SAVE_VERSION])
		return {}
	return parsed


func _delete_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _load_res_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("SaveManager: файл не найден %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
