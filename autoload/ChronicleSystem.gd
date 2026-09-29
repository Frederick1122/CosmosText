extends Node
## Хроника забегов — meta-слой, переживает permadeath вместе с архивом лора.
## Хранит счётчики завершённых забегов и то, какие финалы игрок уже видел.
## Тексты финалов лежат в data/endings.json и сюда только читаются.

signal changed()

var runs_finished: int = 0
var victories: int = 0
var deaths: int = 0
var last_ending_id: String = ""
var last_death_cause: String = ""

var _endings_db: Dictionary = {}
var _endings_seen: Dictionary = {}  # ending_id -> сколько раз получен


func _ready() -> void:
	_endings_db = _load_res_json("res://data/endings.json")
	EventBus.player_died.connect(_on_player_died)


func has_ending(ending_id: String) -> bool:
	return _endings_db.has(ending_id)


func get_ending(ending_id: String) -> Dictionary:
	var data = _endings_db.get(ending_id, {})
	return data if data is Dictionary else {}


func get_ending_title(ending_id: String) -> String:
	return str(get_ending(ending_id).get("title", ending_id))


func get_ending_text(ending_id: String) -> String:
	return str(get_ending(ending_id).get("text", ""))


func is_ending_seen(ending_id: String) -> bool:
	return _endings_seen.has(ending_id)


## Сколько всего финалов есть в контенте — для строки «открыто X из Y».
func endings_total() -> int:
	return _endings_db.size()


func endings_seen_count() -> int:
	return _endings_seen.size()


func record_victory(ending_id: String) -> void:
	runs_finished += 1
	victories += 1
	last_ending_id = ending_id
	last_death_cause = ""
	if ending_id != "":
		_endings_seen[ending_id] = int(_endings_seen.get(ending_id, 0)) + 1
	changed.emit()


func to_save_data() -> Dictionary:
	return {
		"runs_finished": runs_finished,
		"victories": victories,
		"deaths": deaths,
		"last_ending_id": last_ending_id,
		"last_death_cause": last_death_cause,
		"endings_seen": _endings_seen.duplicate(),
	}


func load_save_data(data: Dictionary) -> void:
	runs_finished = int(data.get("runs_finished", 0))
	victories = int(data.get("victories", 0))
	deaths = int(data.get("deaths", 0))
	last_ending_id = str(data.get("last_ending_id", ""))
	last_death_cause = str(data.get("last_death_cause", ""))
	_endings_seen.clear()
	var seen = data.get("endings_seen", {})
	if seen is Dictionary:
		for ending_id in seen.keys():
			_endings_seen[str(ending_id)] = int(seen[ending_id])
	changed.emit()


func _on_player_died(cause: String) -> void:
	runs_finished += 1
	deaths += 1
	last_death_cause = cause
	changed.emit()


func _load_res_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("ChronicleSystem: файл не найден %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
