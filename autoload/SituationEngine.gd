extends Node
## Ситуации — см. tech-spec-v1.md раздел 2 и gdd-v1.md раздел 5.1.
## Не переключает экраны сама: применяет effects текущего выбора и сообщает
## GameState, что дальше (next) — см. ТЗ раздел 10, единственный владелец экранов.

signal situation_started(id: String)
signal option_selected(id: String)
## next: "" (сцена сама переключит экран, например start_combat),
##       "map:<sector_id>" (открыть карту сектора) или id следующей ситуации.
signal situation_ended(id: String, next: String)

var current_id: String = ""
var flags: Dictionary = {}

var _situations: Dictionary = {}  # id -> data
var _current_data: Dictionary = {}


func _ready() -> void:
	_load_all_situations()


func _load_all_situations() -> void:
	_situations.clear()
	var dir := DirAccess.open("res://data/situations")
	if dir == null:
		push_warning("SituationEngine: res://data/situations не найден")
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var path := "res://data/situations/%s" % file_name
			var f := FileAccess.open(path, FileAccess.READ)
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary and parsed.has("id"):
				_situations[parsed["id"]] = parsed
			else:
				push_warning("SituationEngine: битый файл ситуации %s" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


func reset_for_new_run() -> void:
	flags.clear()
	current_id = ""
	_current_data = {}


func set_flag(flag: String, value) -> void:
	if flag != "":
		flags[flag] = value


func get_flag(flag: String):
	return flags.get(flag, false)


func load_situation(id: String) -> bool:
	if not _situations.has(id):
		push_error("SituationEngine: неизвестная ситуация '%s'" % id)
		return false
	_current_data = _situations[id]
	current_id = id
	situation_started.emit(id)
	return true


func get_current_text() -> String:
	return _current_data.get("text", "")


func get_available_options() -> Array:
	var result: Array = []
	for opt in _current_data.get("options", []):
		if EffectResolver.check_requirements(opt.get("requires", [])):
			result.append(opt)
	return result


func select_option(option_id: String) -> void:
	var chosen = _find_option(option_id)
	if chosen == null:
		push_error("SituationEngine: опция '%s' не найдена в '%s'" % [option_id, current_id])
		return
	EffectResolver.apply_effects(chosen.get("effects", []))
	option_selected.emit(option_id)
	if ResourceSystem.is_dead():
		return
	var ended_id := current_id
	var next_id: String = chosen.get("next", "")
	situation_ended.emit(ended_id, next_id)


func _find_option(option_id: String):
	for opt in _current_data.get("options", []):
		if opt.get("id", "") == option_id:
			return opt
	return null


func to_save_data() -> Dictionary:
	return {
		"flags": flags.duplicate(true),
		"current_id": current_id,
	}


func load_save_data(data: Dictionary) -> void:
	flags = data.get("flags", {}).duplicate(true)
	current_id = str(data.get("current_id", ""))
	_current_data = _situations.get(current_id, {}) if current_id != "" else {}
