extends Node
## Сумка — слотовый инвентарь (см. tech-spec-v1.md раздел 3) и действия с
## предметами: использовать, выбросить, особые взаимодействия (interactions).
## Надетое снаряжение хранит CharacterSystem — слотов сумки оно не занимает.

signal item_added(item_id: String)
signal item_removed(item_id: String)
signal inventory_full(attempted_id: String)

var base_slots: int = 6
## Бонус от снаряжения и навыков (например рюкзак) — выставляет CharacterSystem.
var bonus_slots: int = 0
var max_slots: int:
	get:
		return base_slots + bonus_slots
var slots: Array = []  # [{ id: String, count: int, slot_cost: int }, ...]

var _item_db: Dictionary = {}


func _ready() -> void:
	_item_db = _load_res_json("res://data/items.json")


func reset_for_new_run(config: Dictionary) -> void:
	base_slots = int(config.get("inventory_slots", 6))
	bonus_slots = 0
	slots.clear()


func set_bonus_slots(value: int) -> void:
	bonus_slots = maxi(0, value)


func get_item_data(item_id: String) -> Dictionary:
	return _item_db.get(item_id, {})


func get_item_stats(item_id: String) -> Dictionary:
	var stats = get_item_data(item_id).get("stats", {})
	return stats if stats is Dictionary else {}


func used_slots() -> int:
	var used := 0
	for entry in slots:
		used += int(entry.get("slot_cost", 1))
	return used


func free_slots() -> int:
	return max_slots - used_slots()


func has_item(item_id: String) -> bool:
	return count_item(item_id) > 0


func count_item(item_id: String) -> int:
	for entry in slots:
		if entry.get("id", "") == item_id:
			return int(entry.get("count", 1))
	return 0


## Сколько слотов освободится, если убрать один экземпляр предмета.
func slots_freed_by_removing(item_id: String) -> int:
	for entry in slots:
		if entry.get("id", "") == item_id:
			return int(entry.get("slot_cost", 1)) if int(entry.get("count", 1)) <= 1 else 0
	return 0


## true, если добавлены все count экземпляров.
func add_item(item_id: String, count: int = 1) -> bool:
	for i in range(count):
		if not _add_one(item_id):
			return false
	return true


func remove_item(item_id: String, count: int = 1) -> void:
	for i in range(count):
		if not _remove_one(item_id):
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


func can_drop(item_id: String) -> bool:
	return has_item(item_id) and get_item_data(item_id).get("category", "") != "quest"


func drop_item(item_id: String) -> bool:
	if not can_drop(item_id):
		return false
	remove_item(item_id)
	if LocationSystem.is_active():
		LocationSystem.stash_add(item_id, 1)  # в модуле предмет остаётся лежать на полу
	return true


## Взаимодействия предмета, чьи requires сейчас выполнены.
func get_interactions(item_id: String) -> Array:
	var result: Array = []
	for inter in get_item_data(item_id).get("interactions", []):
		if inter is Dictionary and EffectResolver.check_requirements(inter.get("requires", [])):
			result.append(inter)
	return result


## Выполняет взаимодействие и возвращает его text ("" — если недоступно).
func interact(item_id: String, interaction_id: String) -> String:
	if not has_item(item_id) and not CharacterSystem.is_equipped(item_id):
		return ""
	for inter in get_interactions(item_id):
		if str(inter.get("id", "")) == interaction_id:
			EffectResolver.apply_effects(inter.get("effects", []))
			if bool(inter.get("consume", false)):
				remove_item(item_id)
			return str(inter.get("text", ""))
	push_warning("InventorySystem: взаимодействие '%s' с '%s' недоступно" % [interaction_id, item_id])
	return ""


func get_slots() -> Array:
	return slots.duplicate(true)


func to_save_data() -> Dictionary:
	return {
		"base_slots": base_slots,
		"slots": get_slots(),
	}


func load_save_data(data) -> void:
	bonus_slots = 0
	if data is Array:
		slots = data.duplicate(true)
		return
	if not (data is Dictionary):
		slots.clear()
		return
	base_slots = int(data.get("base_slots", data.get("max_slots", base_slots)))
	var loaded_slots = data.get("slots", [])
	slots = loaded_slots.duplicate(true) if loaded_slots is Array else []


func _add_one(item_id: String) -> bool:
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


func _remove_one(item_id: String) -> bool:
	for i in range(slots.size()):
		if slots[i].get("id", "") == item_id:
			if int(slots[i].get("count", 1)) > 1:
				slots[i]["count"] = int(slots[i]["count"]) - 1
			else:
				slots.remove_at(i)
			item_removed.emit(item_id)
			return true
	return false


func _load_res_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("InventorySystem: файл не найден %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
