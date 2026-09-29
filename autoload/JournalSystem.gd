extends Node
## Общий журнал забега: хронология того, что уже произошло — переходы между
## модулями, события, выборы в ситуациях, бои, находки, записи лора, финал.
##
## Ничего не решает: только слушает сигналы остальных систем и копит записи.
## Состояние забега — лежит в run.json, сбрасывается новой игрой и
## восстанавливается откатом к чекпойнту. Лор (ArchiveSystem) и хроника
## забегов (ChronicleSystem) — другие, meta-слои; журнал живёт один забег.

signal changed()

## Потолок записей: старые вытесняются, чтобы сейв не рос бесконечно.
const MAX_ENTRIES := 200
## Длинные тексты ситуаций режутся — журнал это сводка, а не пересказ.
const MAX_TEXT_LENGTH := 180

var _entries: Array = []  # [{ kind, text, o2, count }]


func _ready() -> void:
	LocationSystem.location_entered.connect(_on_location_entered)
	LocationSystem.event_started.connect(_on_event_started)
	SituationEngine.situation_started.connect(_on_situation_started)
	SituationEngine.option_selected.connect(_on_option_selected)
	CombatSystem.combat_started.connect(_on_combat_started)
	CombatSystem.combat_ended.connect(_on_combat_ended)
	InventorySystem.item_added.connect(_on_item_added)
	ArchiveSystem.fragment_unlocked.connect(_on_fragment_unlocked)
	EventBus.player_died.connect(_on_player_died)


func reset_for_new_run() -> void:
	_entries.clear()
	changed.emit()


## kind: "move" | "event" | "situation" | "choice" | "combat" | "loot" |
##       "lore" | "death" | "victory"
func add(kind: String, text: String) -> void:
	var trimmed := _trim(text)
	if trimmed == "":
		return
	if not _entries.is_empty():
		var last: Dictionary = _entries[_entries.size() - 1]
		if last.get("kind", "") == kind and last.get("text", "") == trimmed:
			last["count"] = int(last.get("count", 1)) + 1
			last["o2"] = int(ResourceSystem.o2)
			changed.emit()
			return
	_entries.append({"kind": kind, "text": trimmed, "o2": int(ResourceSystem.o2), "count": 1})
	if _entries.size() > MAX_ENTRIES:
		_entries = _entries.slice(_entries.size() - MAX_ENTRIES)
	changed.emit()


## Записи от старых к новым.
func get_entries() -> Array:
	return _entries.duplicate(true)


func entry_count() -> int:
	return _entries.size()


func to_save_data() -> Array:
	return _entries.duplicate(true)


func load_save_data(data: Array) -> void:
	_entries.clear()
	for entry in data:
		if not (entry is Dictionary):
			continue
		_entries.append({
			"kind": str(entry.get("kind", "event")),
			"text": str(entry.get("text", "")),
			"o2": int(entry.get("o2", 0)),
			"count": maxi(1, int(entry.get("count", 1))),
		})
	changed.emit()


func _on_location_entered(location_id: String) -> void:
	add("move", "Переход: %s" % LocationSystem.get_location_title(location_id))


func _on_event_started(_location_id: String, event_id: String) -> void:
	var ev := LocationSystem.find_event(event_id)
	var text := str(ev.get("text", ""))
	if text == "":
		text = str(ev.get("label", ""))
	add("event", text)


func _on_situation_started(_id: String) -> void:
	add("situation", SituationEngine.get_current_text())


func _on_option_selected(option_id: String) -> void:
	add("choice", "Выбрано: %s" % SituationEngine.get_option_label(option_id))


func _on_combat_started(_enemy_id: String) -> void:
	add("combat", "Бой: %s" % str(CombatSystem.enemy_data.get("name", "противник")))


func _on_combat_ended(result: String) -> void:
	match result:
		"won":
			add("combat", "Победа в бою.")
		"fled":
			add("combat", "Отступление из боя.")
		"died":
			pass  # смерть пишет _on_player_died


func _on_item_added(item_id: String) -> void:
	var item_name := str(InventorySystem.get_item_data(item_id).get("name", item_id))
	add("loot", "Получено: %s" % item_name)


func _on_fragment_unlocked(id: String) -> void:
	add("lore", "Запись в архиве: %s" % ArchiveSystem.get_title(id))


func _on_player_died(cause: String) -> void:
	add("death", "Смерть: %s." % ("закончился кислород" if cause == "o2" else "здоровье упало до нуля"))


func _trim(text: String) -> String:
	var value := text.strip_edges()
	if value.length() <= MAX_TEXT_LENGTH:
		return value
	return value.substr(0, MAX_TEXT_LENGTH - 1).strip_edges() + "…"
