extends Node
## Персонаж: снаряжение по слотам (шлем, тело, руки, ноги, спина), навыки
## и итоговые характеристики — сумма бонусов надетых предметов и навыков.
## Слоты сумки и макс. HP применяются сразу (InventorySystem / ResourceSystem),
## боевые характеристики читает CombatSystem. Справочник — docs/CONTENT.md.
signal changed()
signal skill_points_added(value: int)
const SLOTS := ["head", "body", "arms", "legs", "back"]
const SLOT_TITLES := {
	"head": "Шлем",
	"body": "Тело",
	"arms": "Руки",
	"legs": "Ноги",
	"back": "Спина",
}
const STAT_TITLES := {
	"armor": "Броня",
	"melee_damage": "Урон в ближнем бою",
	"ranged_damage": "Урон в дальнем бою",
	"hit_chance": "Точность",
	"flee_chance": "Шанс побега",
	"max_hp": "Макс. HP",
	"inventory_slots": "Слоты сумки",
}
const PERCENT_STATS := ["hit_chance", "flee_chance"]

var equipment: Dictionary = {}  # slot -> item_id
var skill_levels: Dictionary = {}  # skill_id -> level
var skill_points: int = 0

var _skill_db: Dictionary = {}
var _stats: Dictionary = {}


func _ready() -> void:
	_skill_db = _load_res_json("res://data/skills.json")


func reset_for_new_run(config: Dictionary) -> void:
	equipment.clear()
	skill_levels.clear()
	skill_points = int(config.get("start_skill_points", 0))
	var start_equipment = config.get("start_equipment", {})
	if start_equipment is Dictionary:
		for slot in start_equipment.keys():
			var item_id := str(start_equipment[slot])
			if get_item_slot(item_id) == slot:
				equipment[slot] = item_id
			else:
				push_warning("CharacterSystem: '%s' нельзя надеть в слот '%s'" % [item_id, slot])
	_recalculate()


# --- Снаряжение ---------------------------------------------------------------

func get_item_slot(item_id: String) -> String:
	return str(InventorySystem.get_item_data(item_id).get("equip_slot", ""))


func get_equipped(slot: String) -> String:
	return str(equipment.get(slot, ""))


func get_equipped_name(slot: String) -> String:
	var item_id := get_equipped(slot)
	return _item_name(item_id) if item_id != "" else ""


func is_equipped(item_id: String) -> bool:
	return item_id != "" and equipment.values().has(item_id)


## Надеть предмет из сумки; прежний предмет слота уходит в сумку.
## Возвращает текст ошибки или "" при успехе.
func equip(item_id: String) -> String:
	var slot := get_item_slot(item_id)
	if not SLOTS.has(slot):
		return "Этот предмет нельзя надеть."
	if not InventorySystem.has_item(item_id):
		return "Предмета нет в сумке."
	var old_id := get_equipped(slot)
	var free_after := InventorySystem.free_slots() + InventorySystem.slots_freed_by_removing(item_id)
	free_after += _slot_bonus(item_id) - _slot_bonus(old_id)
	if old_id != "":
		free_after -= _slot_cost(old_id)
	if free_after < 0:
		return "В сумке не хватит места для «%s»." % _item_name(old_id)
	InventorySystem.remove_item(item_id)
	equipment[slot] = item_id
	_recalculate()
	if old_id != "":
		InventorySystem.add_item(old_id)
	return ""


## Снять предмет в сумку. Возвращает текст ошибки или "" при успехе.
func unequip(slot: String) -> String:
	var item_id := get_equipped(slot)
	if item_id == "":
		return "Слот пуст."
	if InventorySystem.free_slots() - _slot_bonus(item_id) - _slot_cost(item_id) < 0:
		return "В сумке не хватит места."
	equipment.erase(slot)
	_recalculate()
	InventorySystem.add_item(item_id)
	return ""


## Уничтожить надетый предмет (эффект item_remove, когда в сумке его нет).
func remove_equipped(item_id: String) -> bool:
	for slot in equipment.keys():
		if equipment[slot] == item_id:
			equipment.erase(slot)
			_recalculate()
			return true
	return false


# --- Характеристики -----------------------------------------------------------

func get_stat(stat: String) -> float:
	return float(_stats.get(stat, 0.0))


func get_stats() -> Dictionary:
	return _stats.duplicate()


## "Броня +1, Точность +5%" — для UI.
func describe_stats(stats: Dictionary) -> String:
	var parts := PackedStringArray()
	for stat in STAT_TITLES.keys():
		if not stats.has(stat):
			continue
		var value := float(stats[stat])
		if is_zero_approx(value):
			continue
		parts.append("%s %s" % [STAT_TITLES[stat], format_stat(stat, value)])
	return ", ".join(parts)


func format_stat(stat: String, value: float) -> String:
	if PERCENT_STATS.has(stat):
		return "%+d%%" % roundi(value * 100.0)
	return "%+d" % roundi(value)


# --- Навыки -------------------------------------------------------------------

func get_skills() -> Array:
	var result: Array = []
	for skill_id in _skill_db.keys():
		if _skill_db[skill_id] is Dictionary:
			var entry: Dictionary = _skill_db[skill_id].duplicate(true)
			entry["id"] = skill_id
			entry["level"] = get_skill_level(skill_id)
			result.append(entry)
	return result


func get_skill_level(skill_id: String) -> int:
	return int(skill_levels.get(skill_id, 0))


func get_skill_name(skill_id: String) -> String:
	return str(_skill_db.get(skill_id, {}).get("name", skill_id))


func get_skill_cost(skill_id: String) -> int:
	return maxi(1, int(_skill_db.get(skill_id, {}).get("cost", 1)))


func get_skill_max_level(skill_id: String) -> int:
	return int(_skill_db.get(skill_id, {}).get("max_level", 1))


func can_learn(skill_id: String) -> bool:
	return (
		_skill_db.has(skill_id)
		and get_skill_level(skill_id) < get_skill_max_level(skill_id)
		and skill_points >= get_skill_cost(skill_id)
	)


func learn(skill_id: String) -> bool:
	if not can_learn(skill_id):
		return false
	skill_points -= get_skill_cost(skill_id)
	skill_levels[skill_id] = get_skill_level(skill_id) + 1
	_recalculate()
	return true


func add_skill_points(value: int) -> void:
	skill_points = maxi(0, skill_points + value)
	if value > 0:
		skill_points_added.emit(value)
	changed.emit()

# --- Сохранение ---------------------------------------------------------------

func to_save_data() -> Dictionary:
	return {
		"equipment": equipment.duplicate(),
		"skills": skill_levels.duplicate(),
		"skill_points": skill_points,
	}


func load_save_data(data: Dictionary) -> void:
	var saved_equipment = data.get("equipment", {})
	equipment = saved_equipment.duplicate() if saved_equipment is Dictionary else {}
	var saved_skills = data.get("skills", {})
	skill_levels = saved_skills.duplicate() if saved_skills is Dictionary else {}
	skill_points = int(data.get("skill_points", 0))
	_recalculate()


# --- Внутреннее ---------------------------------------------------------------

func _recalculate() -> void:
	_stats = {}
	for slot in equipment.keys():
		_add_stats(InventorySystem.get_item_stats(str(equipment[slot])), 1)
	for skill_id in skill_levels.keys():
		var per_level = _skill_db.get(skill_id, {}).get("per_level", {})
		if per_level is Dictionary:
			_add_stats(per_level, int(skill_levels[skill_id]))
	InventorySystem.set_bonus_slots(int(get_stat("inventory_slots")))
	ResourceSystem.set_max_hp_bonus(int(get_stat("max_hp")))
	changed.emit()


func _add_stats(stats: Dictionary, multiplier: int) -> void:
	for stat in stats.keys():
		_stats[stat] = float(_stats.get(stat, 0.0)) + float(stats[stat]) * multiplier


func _slot_bonus(item_id: String) -> int:
	if item_id == "":
		return 0
	return int(InventorySystem.get_item_stats(item_id).get("inventory_slots", 0))


func _slot_cost(item_id: String) -> int:
	return int(InventorySystem.get_item_data(item_id).get("slot_cost", 1))


func _item_name(item_id: String) -> String:
	return str(InventorySystem.get_item_data(item_id).get("name", item_id))


func _load_res_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("CharacterSystem: файл не найден %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
