extends Node
## Слотовый инвентарь — см. tech-spec-v1.md раздел 3.

signal item_added(item_id: String)
signal item_removed(item_id: String)
signal inventory_full(attempted_id: String)

var max_slots: int = 6
var slots: Array = []  # [{ id: String, count: int, slot_cost: int }, ...]

var _item_db: Dictionary = {}


func _ready() -> void:
	_item_db = _load_res_json("res://data/items.json")


func reset_for_new_run(config: Dictionary) -> void:
	max_slots = int(config.get("inventory_slots", 6))
	slots.clear()


func get_item_data(item_id: String) -> Dictionary:
	return _item_db.get(item_id, {})


func free_slots() -> int:
	var used := 0
	for entry in slots:
		used += int(entry.get("slot_cost", 1))
	return max_slots - used


func has_item(item_id: String) -> bool:
	for entry in slots:
		if entry.get("id", "") == item_id:
			return true
	return false


func add_item(item_id: String) -> bool:
	var data := get_item_data(item_id)
	if data.is_empty():
		push_warning("InventorySystem: неизвестный предмет '%s'" % item_id)
		return false

	if data.get("stackable", false) and has_item(item_id):
		for entry in slots:
			if entry.get("id", "") == item_id:
				entry["count"] = int(entry.get("count", 1)) + 1
				item_added.emit(item_id)
				return true

	var cost: int = int(data.get("slot_cost", 1))
	if free_slots() < cost:
		inventory_full.emit(item_id)
		return false

	slots.append({"id": item_id, "count": 1, "slot_cost": cost})
	item_added.emit(item_id)
	return true


func remove_item(item_id: String) -> void:
	for i in range(slots.size()):
		if slots[i].get("id", "") == item_id:
			if int(slots[i].get("count", 1)) > 1:
				slots[i]["count"] = int(slots[i]["count"]) - 1
			else:
				slots.remove_at(i)
			item_removed.emit(item_id)
			return


func use_item(item_id: String) -> bool:
	if item_id == "" or not has_item(item_id):
		push_warning("InventorySystem: попытка использовать отсутствующий предмет '%s'" % item_id)
		return false
	var data := get_item_data(item_id)
	if data.is_empty():
		return false
	if data.has("use_effect"):
		EffectResolver.apply_effect(data["use_effect"])
	if data.get("category", "") == "consumable":
		remove_item(item_id)
	return true


func get_slots() -> Array:
	return slots.duplicate(true)


func to_save_data() -> Dictionary:
	return {
		"max_slots": max_slots,
		"slots": get_slots(),
	}


func load_save_data(data) -> void:
	if data is Array:
		slots = data.duplicate(true)
		return
	if not (data is Dictionary):
		slots.clear()
		return
	max_slots = int(data.get("max_slots", max_slots))
	var loaded_slots = data.get("slots", [])
	slots = loaded_slots.duplicate(true) if loaded_slots is Array else []


func _load_res_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("InventorySystem: файл не найден %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
