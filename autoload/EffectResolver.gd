extends Node
## Единая точка применения effect- и requires-словарей из JSON-контента
## (ситуации, события локаций, предметы, рецепты, спецдействия в бою). Не описан
## отдельным автозагрузом в tech-spec-v1.md — добавлен, чтобы не дублировать
## switch по типу эффекта в нескольких системах. Справочник типов — docs/CONTENT.md.

## Изменение показано в ленте. kind: "hp" | "o2" | "ammo" | "item" | "xp" | "hunger";
## amount — фактическое изменение (со знаком). Слушает SoundSystem.
signal change_reported(kind: String, amount: float)
## Замок открыт подходящим ключом (узел карты или событие-ящик).
signal lock_opened(lock_id: String)

## Изменения HP, кислорода, патронов и предметов сразу видны в ленте строкой
## в квадратных скобках (см. report_change).
func apply_effect(effect: Dictionary) -> void:
	match effect.get("type", ""):
		"hp_delta":
			var hp_before := ResourceSystem.hp
			ResourceSystem.apply_hp_delta(int(effect.get("value", 0)))
			report_change("hp", ResourceSystem.hp - hp_before, "HP")
		"o2_delta":
			var o2_before := ResourceSystem.o2
			ResourceSystem.apply_o2_delta(float(effect.get("value", 0.0)))
			report_change("o2", ResourceSystem.o2 - o2_before, "O2")
		"ammo_delta":
			var ammo_before := ResourceSystem.ammo
			ResourceSystem.apply_ammo_delta(int(effect.get("value", 0)))
			report_change("ammo", ResourceSystem.ammo - ammo_before, "Патроны")
		"hunger_delta":
			# Голод убывает — это хорошо: строка «[−40 голода]» зелёная.
			report_change("hunger", NeedsSystem.apply_hunger_delta(float(effect.get("value", 0.0))), "голода", true)
		"item_add":
			_add_item(str(effect.get("item", "")), int(effect.get("count", 1)))
		"item_remove":
			_remove_item(str(effect.get("item", "")), int(effect.get("count", 1)))
		"flag_set":
			SituationEngine.set_flag(effect.get("flag", ""), effect.get("value", true))
		"unlock_lore":
			ArchiveSystem.unlock_fragment(effect.get("id", ""))
			ProgressionSystem.lore_read(str(effect.get("id", "")))
		"reveal_map":
			MapSystem.reveal_map()
		"open_map_node":
			var location_name := MapSystem.unlock_node(str(effect.get("node", "")))
			if location_name != "":
				NarrativeSystem.push("notice", "[Открыта новая локация \"%s\"]" % location_name)
		"lock_map_node":
			MapSystem.set_node_state(effect.get("node", ""), effect.get("state", "dangerous"))
		"skill_points_add":
			CharacterSystem.add_skill_points(int(effect.get("value", 1)))
		"start_combat":
			CombatSystem.start_combat(
				effect.get("enemy", ""),
				effect.get("clear_node", ""),
				_as_array(effect.get("on_win", [])),
				_as_array(effect.get("on_flee", []))
			)
		"end_run":
			GameState.finish_run(str(effect.get("ending", "")))
		_:
			push_warning("EffectResolver: неизвестный тип эффекта '%s'" % effect.get("type", ""))


func apply_effects(effects: Array) -> void:
	for e in effects:
		if e is Dictionary:
			apply_effect(e)


## Что делает эффект предмета, коротко для UI: «+30 HP», «+90 O2».
## "" — эффект не про ресурсы (флаги, записи, бой).
func describe_effect(effect: Dictionary) -> String:
	var value := roundi(float(effect.get("value", 0)))
	match effect.get("type", ""):
		"hp_delta":
			return "%+d HP" % value
		"o2_delta":
			return "%+d O2" % value
		"ammo_delta":
			return "%+d патр." % value
		"hunger_delta":
			return "%+d голода" % value
		"skill_points_add":
			return "%+d очк. навыков" % value
	return ""


## Строка ленты вида «[−5 HP]» / «[+1 Аптечка]»: прибыль — kind ленты "gain",
## убыль — "loss". Нулевое изменение (лечение при полном HP) не показывается.
## kind — что изменилось ("hp" | "o2" | "ammo" | "item" | "xp" | "hunger"), what —
## подпись; less_is_better — убыль считается прибылью (голод).
func report_change(kind: String, amount: float, what: String, less_is_better: bool = false) -> void:
	if is_zero_approx(amount):
		return
	var shown := maxi(1, roundi(absf(amount)))
	var increased := amount > 0.0
	NarrativeSystem.push("gain" if increased != less_is_better else "loss",
		"[%s%d %s]" % ["+" if increased else "−", shown, what])
	change_reported.emit(kind, amount)


func check_requirement(req: Dictionary) -> bool:
	match req.get("type", ""):
		"has_item":
			var item_id := str(req.get("item", ""))
			var owned := InventorySystem.has_item(item_id) or CharacterSystem.is_equipped(item_id)
			return owned == bool(req.get("value", true))
		"flag":
			return SituationEngine.get_flag(req.get("flag", "")) == req.get("value", true)
		"stat_gte":
			var stat_name: String = req.get("stat", "hp")
			var current: float = 0.0
			match stat_name:
				"hp":
					current = ResourceSystem.hp
				"o2":
					current = ResourceSystem.o2
				"ammo":
					current = ResourceSystem.ammo
			return current >= float(req.get("value", 0))
		"skill_gte":
			return CharacterSystem.get_skill_level(str(req.get("skill", ""))) >= int(req.get("value", 1))
		"in_location":
			return LocationSystem.current_id == str(req.get("location", ""))
		"event_done":
			return LocationSystem.is_event_done(str(req.get("event", ""))) == bool(req.get("value", true))
		"has_key":
			var owned_key := InventorySystem.find_key(str(req.get("lock", ""))) != ""
			return owned_key == bool(req.get("value", true))
		"visits_gte":
			return LocationSystem.get_visits() >= int(req.get("value", 0))
		"visits_lte":
			return LocationSystem.get_visits() <= int(req.get("value", 0))
		_:
			push_warning("EffectResolver: неизвестный тип условия '%s'" % req.get("type", ""))
			return true


func check_requirements(reqs: Array) -> bool:
	for r in reqs:
		if r is Dictionary and not check_requirement(r):
			return false
	return true


# --- Замки и ключи --------------------------------------------------------------
# Замок в контенте (узел карты, событие-ящик) описан словарём:
#   { "key": "<id замка>", "consume": true, "text": "<что видно игроку>" }
# Ключ — предмет с "unlocks": ["<id замка>", ...].

func lock_id(lock: Dictionary) -> String:
	return str(lock.get("key", ""))


func can_open_lock(lock: Dictionary) -> bool:
	var id := lock_id(lock)
	return id == "" or InventorySystem.find_key(id) != ""


## Открывает замок подходящим ключом. Возвращает название ключа ("" — замка
## нет или ключ не тратится). Одноразовый ключ (consume) уходит из сумки.
func open_lock(lock: Dictionary) -> String:
	var id := lock_id(lock)
	if id == "":
		return ""
	var key_item := InventorySystem.find_key(id)
	if key_item == "":
		return ""
	var key_name := str(InventorySystem.get_item_data(key_item).get("name", key_item))
	lock_opened.emit(id)
	if bool(lock.get("consume", false)):
		_remove_item(key_item, 1)
	return key_name


## Подсказка для UI: «Заперто. Нужен: Ключ-карта пилота».
func lock_hint(lock: Dictionary) -> String:
	var id := lock_id(lock)
	if id == "":
		return ""
	var names: Array = []
	for item_id in InventorySystem.keys_for_lock(id):
		names.append(str(InventorySystem.get_item_data(item_id).get("name", item_id)))
	if names.is_empty():
		return "Заперто"
	return "Заперто. Нужен: %s" % ", ".join(names)


## Лишнее, что не поместилось в сумку, остаётся на полу текущего модуля.
func _add_item(item_id: String, count: int) -> void:
	if InventorySystem.get_item_data(item_id).is_empty():
		push_warning("EffectResolver: неизвестный предмет '%s'" % item_id)
		return
	var added := 0
	while added < count and InventorySystem.add_item(item_id):
		added += 1
	var item_name := str(InventorySystem.get_item_data(item_id).get("name", item_id))
	report_change("item", added, item_name)
	var left := count - added
	if left <= 0:
		return
	if LocationSystem.is_active():
		LocationSystem.stash_add(item_id, left)
		LocationSystem.add_notice("Не поместилось в сумку: %s ×%d — осталось лежать здесь." % [item_name, left])
	else:
		push_warning("EffectResolver: '%s' ×%d не поместилось в сумку и потеряно" % [item_id, left])


## Сначала из сумки, затем — надетый экземпляр.
func _remove_item(item_id: String, count: int) -> void:
	var removed := 0
	for i in range(count):
		if InventorySystem.has_item(item_id):
			InventorySystem.remove_item(item_id)
		elif not CharacterSystem.remove_equipped(item_id):
			break
		removed += 1
	report_change("item", -removed, str(InventorySystem.get_item_data(item_id).get("name", item_id)))


func _as_array(value) -> Array:
	return value if value is Array else []
