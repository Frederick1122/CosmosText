extends Node
## Лор-архив — переживает permadeath (meta-слой). См. tech-spec-v1.md раздел 8
## и gdd-v1.md раздел 5.6 ("что переживает смерть").

var _unlocked: Dictionary = {}  # id -> true
var _lore_db: Dictionary = {}


func _ready() -> void:
	_lore_db = _load_res_json("res://data/lore.json")


func unlock_fragment(id: String) -> void:
	if id == "":
		return
	_unlocked[id] = true


func is_unlocked(id: String) -> bool:
	return _unlocked.has(id)


func get_unlocked() -> Array:
	return _unlocked.keys()


func get_title(id: String) -> String:
	return _lore_db.get(id, {}).get("title", id)


func get_text(id: String) -> String:
	return _lore_db.get(id, {}).get("text", "")


func to_save_data() -> Array:
	return _unlocked.keys()


func load_save_data(ids: Array) -> void:
	_unlocked.clear()
	for id in ids:
		_unlocked[str(id)] = true


func _load_res_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("ArchiveSystem: файл не найден %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
