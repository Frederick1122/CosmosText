extends Node
## Уведомления о новом содержимом персонажа и журнала.
## Состояние забега сохраняется вместе с run.json.
##
## Новые предметы, записи архива, справочника и цели (новая или засчитанный
## шаг) помечаются до просмотра. Очки навыков — не «новость», а долг: пока
## они не потрачены, кнопка «Развитие» показывает (!).

signal changed()

var _new_items: Dictionary = {}  # item_id -> true
var _new_lore_entries: Dictionary = {}  # archive_id -> true
var _new_codex_entries: Dictionary = {}  # codex_id -> true
var _new_goals: bool = false


func _ready() -> void:
	InventorySystem.item_added.connect(_on_item_added)
	CharacterSystem.changed.connect(changed.emit)
	SkillTreeSystem.changed.connect(changed.emit)
	ArchiveSystem.fragment_unlocked.connect(_on_fragment_unlocked)
	CodexSystem.entry_unlocked.connect(_on_codex_entry_unlocked)


func reset_for_new_run() -> void:
	_new_items.clear()
	_new_lore_entries.clear()
	_new_codex_entries.clear()
	_new_goals = false
	changed.emit()


func is_item_new(item_id: String) -> bool:
	return _new_items.has(item_id)


func has_new_items() -> bool:
	return not _new_items.is_empty()

func new_item_ids() -> Array:
	return _new_items.keys()


func has_new_items_in_info() -> bool:
	for item_id in _new_items.keys():
		if InventorySystem.is_info_item(str(item_id)):
			return true
	return false


func has_new_items_in_bag() -> bool:
	for item_id in _new_items.keys():
		if not InventorySystem.is_info_item(str(item_id)):
			return true
	return false



func unspent_skill_points() -> int:
	return CharacterSystem.skill_points


func has_character_alert() -> bool:
	return has_new_items()


func has_development_alert() -> bool:
	if unspent_skill_points() <= 0:
		return false
	if SkillTreeSystem.has_available():
		return true
	for skill in CharacterSystem.get_skills():
		if CharacterSystem.can_learn(str(skill.get("id", ""))):
			return true
	return false


func has_new_lore() -> bool:
	return not _new_lore_entries.is_empty()


func has_new_codex() -> bool:
	return not _new_codex_entries.is_empty()


func has_new_goals() -> bool:
	return _new_goals

func has_new_codex_category(category: String) -> bool:
	for id in _new_codex_entries.keys():
		if CodexSystem.get_category(str(id)) == category:
			return true
	return false



## Кнопка «Журнал»: новая запись архива, справочника или новость по целям.
func has_journal_alert() -> bool:
	return has_new_lore() or has_new_codex() or _new_goals


## Цель началась или засчитан шаг (QuestSystem.refresh).
func mark_goals_new() -> void:
	if _new_goals:
		return
	_new_goals = true
	changed.emit()


func mark_item_seen(item_id: String) -> void:
	if not _new_items.has(item_id):
		return
	_new_items.erase(item_id)
	changed.emit()


func mark_character_seen() -> void:
	mark_character_items_seen("")


func mark_character_items_seen(item_tab: String = "") -> void:
	var changed_any := false
	for item_id in _new_items.keys():
		var is_info := InventorySystem.is_info_item(str(item_id))
		if item_tab == "" or (item_tab == "info" and is_info) or (item_tab == "bag" and not is_info):
			_new_items.erase(item_id)
			changed_any = true
	if changed_any:
		changed.emit()


func mark_journal_seen() -> void:
	mark_goals_seen()
	mark_lore_seen()
	mark_codex_seen()


func mark_goals_seen() -> void:
	if not _new_goals:
		return
	_new_goals = false
	changed.emit()


func mark_lore_seen() -> void:
	if _new_lore_entries.is_empty():
		return
	_new_lore_entries.clear()
	changed.emit()


func mark_codex_seen(category: String = "") -> void:
	if _new_codex_entries.is_empty():
		return
	var changed_any := false
	for id in _new_codex_entries.keys():
		if category == "" or CodexSystem.get_category(str(id)) == category:
			_new_codex_entries.erase(id)
			changed_any = true
	if changed_any:
		changed.emit()


func to_save_data() -> Dictionary:
	return {
		"new_items": _new_items.keys(),
		"new_lore": has_new_lore(),
		"new_lore_entries": _new_lore_entries.keys(),
		"new_codex": has_new_codex(),
		"new_codex_entries": _new_codex_entries.keys(),
		"new_goals": _new_goals,
	}


func load_save_data(data: Dictionary) -> void:
	_new_items.clear()
	_new_lore_entries.clear()
	_new_codex_entries.clear()
	var item_ids = data.get("new_items", [])
	if item_ids is Array:
		for item_id in item_ids:
			_new_items[str(item_id)] = true
	for id in _as_array(data.get("new_lore_entries", [])):
		_new_lore_entries[str(id)] = true
	if bool(data.get("new_lore", false)) and _new_lore_entries.is_empty():
		_new_lore_entries[""] = true
	for id in _as_array(data.get("new_codex_entries", [])):
		_new_codex_entries[str(id)] = true
	if bool(data.get("new_codex", false)) and _new_codex_entries.is_empty():
		_new_codex_entries[""] = true
	_new_goals = bool(data.get("new_goals", false))
	changed.emit()


func _on_item_added(item_id: String) -> void:
	if item_id == "":
		return
	_new_items[item_id] = true
	changed.emit()


func _on_fragment_unlocked(id: String) -> void:
	_new_lore_entries[str(id)] = true
	changed.emit()


func _on_codex_entry_unlocked(id: String) -> void:
	_new_codex_entries[str(id)] = true
	changed.emit()


func _as_array(value) -> Array:
	return value if value is Array else []
