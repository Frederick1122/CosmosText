extends Node
## Два уровня сохранения — run (обнуляется при смерти) и meta (переживает
## смерть) — плюс чекпоинт для платного/рекламного отката.
## См. gdd-v1.md раздел 5.6 и tech-spec-v1.md раздел 7.

const RUN_PATH := "user://run.json"
const META_PATH := "user://meta.json"
const CHECKPOINT_PATH := "user://checkpoint.json"

var _config: Dictionary = {}


func _ready() -> void:
	_config = _load_res_json("res://data/config.json")
	EventBus.player_died.connect(_on_player_died)
	EventBus.returned_to_hub.connect(_on_returned_to_hub)
	load_meta()


func get_start_sector_id() -> String:
	return str(_config.get("start_sector_id", "wreck_01"))


func get_opening_situation_id() -> String:
	return str(_config.get("opening_situation_id", ""))


func start_new_run() -> void:
	ResourceSystem.reset_for_new_run(_config)
	InventorySystem.reset_for_new_run(_config)
	CharacterSystem.reset_for_new_run(_config)  # после ресурсов и сумки: применяет бонусы
	SituationEngine.reset_for_new_run()
	LocationSystem.reset_for_new_run()
	CombatSystem.reset_for_new_run()
	EconomyManager.reset_for_new_run()
	_delete_file(RUN_PATH)
	_delete_file(CHECKPOINT_PATH)


func save_run() -> void:
	var data := {
		"resources": ResourceSystem.to_save_data(),
		"inventory": InventorySystem.to_save_data(),
		"character": CharacterSystem.to_save_data(),
		"situation": SituationEngine.to_save_data(),
		"locations": LocationSystem.to_save_data(),
		"map": MapSystem.to_save_data(),
		"economy_run": EconomyManager.to_run_save_data(),
	}
	_write_json(RUN_PATH, data)


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
	SituationEngine.load_save_data(situation_data)
	LocationSystem.load_save_data(data.get("locations", {}))
	EconomyManager.load_run_save_data(data.get("economy_run", {}))
	return true


func clear_run() -> void:
	start_new_run()


func write_checkpoint() -> void:
	save_run()
	if FileAccess.file_exists(RUN_PATH):
		var text := FileAccess.get_file_as_string(RUN_PATH)
		var f := FileAccess.open(CHECKPOINT_PATH, FileAccess.WRITE)
		if f:
			f.store_string(text)


func has_checkpoint() -> bool:
	return FileAccess.file_exists(CHECKPOINT_PATH)


func restore_checkpoint() -> void:
	if not has_checkpoint():
		clear_run()
		return
	var text := FileAccess.get_file_as_string(CHECKPOINT_PATH)
	var f := FileAccess.open(RUN_PATH, FileAccess.WRITE)
	if f:
		f.store_string(text)
	load_run()


func save_meta() -> void:
	var data := {
		"archive": ArchiveSystem.to_save_data(),
		"economy": EconomyManager.to_save_data(),
	}
	_write_json(META_PATH, data)


func load_meta() -> void:
	var data := _read_json(META_PATH)
	if data.is_empty():
		return
	ArchiveSystem.load_save_data(data.get("archive", []))
	EconomyManager.load_save_data(data.get("economy", {}))


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
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


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
