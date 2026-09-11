extends Node
## Уведомления о новом содержимом персонажа и журнала.
## Состояние забега сохраняется вместе с run.json.

signal changed()

var _new_items: Dictionary = {}  # item_id -> true
var _new_skill_points: bool = false
var _new_lore: bool = false


func _ready() -> void:
	InventorySystem.item_added.connect(_on_item_added)
	CharacterSystem.skill_points_added.connect(_on_skill_points_added)
	ArchiveSystem.fragment_unlocked.connect(_on_fragment_unlocked)


func reset_for_new_run() -> void:
	_new_items.clear()
	_new_skill_points = false
	_new_lore = false
	changed.emit()


func is_item_new(item_id: String) -> bool:
	return _new_items.has(item_id)


func has_new_items() -> bool:
	return not _new_items.is_empty()


func has_new_skill_points() -> bool:
	return _new_skill_points


func has_character_alert() -> bool:
	return has_new_items() or has_new_skill_points()


func has_new_lore() -> bool:
	return _new_lore


func mark_item_seen(item_id: String) -> void:
	if not _new_items.has(item_id):
		return
	_new_items.erase(item_id)
	changed.emit()


func mark_skill_points_seen() -> void:
	if not _new_skill_points:
		return
	_new_skill_points = false
	changed.emit()


func mark_character_seen() -> void:
	if _new_items.is_empty() and not _new_skill_points:
		return
	_new_items.clear()
	_new_skill_points = false
	changed.emit()


func mark_journal_seen() -> void:
	if not _new_lore:
		return
	_new_lore = false
	changed.emit()


func to_save_data() -> Dictionary:
	return {
		"new_items": _new_items.keys(),
		"new_skill_points": _new_skill_points,
		"new_lore": _new_lore,
	}


func load_save_data(data: Dictionary) -> void:
	_new_items.clear()
	var item_ids = data.get("new_items", [])
	if item_ids is Array:
		for item_id in item_ids:
			_new_items[str(item_id)] = true
	_new_skill_points = bool(data.get("new_skill_points", false))
	_new_lore = bool(data.get("new_lore", false))
	changed.emit()


func _on_item_added(item_id: String) -> void:
	if item_id == "":
		return
	_new_items[item_id] = true
	changed.emit()


func _on_skill_points_added(value: int) -> void:
	if value <= 0:
		return
	_new_skill_points = true
	changed.emit()


func _on_fragment_unlocked(_id: String) -> void:
	_new_lore = true
	changed.emit()
