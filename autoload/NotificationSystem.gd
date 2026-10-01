extends Node
## Уведомления о новом содержимом персонажа и журнала.
## Состояние забега сохраняется вместе с run.json.
##
## Новые предметы и записи архива помечаются до просмотра. Очки навыков —
## не «новость», а долг: пока они не потрачены, кнопка «Персонаж» и вкладка
## «Навыки» показывают (!) и «(+N)».

signal changed()

var _new_items: Dictionary = {}  # item_id -> true
var _new_lore: bool = false


func _ready() -> void:
	InventorySystem.item_added.connect(_on_item_added)
	CharacterSystem.changed.connect(changed.emit)
	ArchiveSystem.fragment_unlocked.connect(_on_fragment_unlocked)


func reset_for_new_run() -> void:
	_new_items.clear()
	_new_lore = false
	changed.emit()


func is_item_new(item_id: String) -> bool:
	return _new_items.has(item_id)


func has_new_items() -> bool:
	return not _new_items.is_empty()


func unspent_skill_points() -> int:
	return CharacterSystem.skill_points


func has_character_alert() -> bool:
	return has_new_items() or unspent_skill_points() > 0


func has_new_lore() -> bool:
	return _new_lore


func mark_item_seen(item_id: String) -> void:
	if not _new_items.has(item_id):
		return
	_new_items.erase(item_id)
	changed.emit()


func mark_character_seen() -> void:
	if _new_items.is_empty():
		return
	_new_items.clear()
	changed.emit()


func mark_journal_seen() -> void:
	if not _new_lore:
		return
	_new_lore = false
	changed.emit()


func to_save_data() -> Dictionary:
	return {
		"new_items": _new_items.keys(),
		"new_lore": _new_lore,
	}


func load_save_data(data: Dictionary) -> void:
	_new_items.clear()
	var item_ids = data.get("new_items", [])
	if item_ids is Array:
		for item_id in item_ids:
			_new_items[str(item_id)] = true
	_new_lore = bool(data.get("new_lore", false))
	changed.emit()


func _on_item_added(item_id: String) -> void:
	if item_id == "":
		return
	_new_items[item_id] = true
	changed.emit()


func _on_fragment_unlocked(_id: String) -> void:
	_new_lore = true
	changed.emit()
