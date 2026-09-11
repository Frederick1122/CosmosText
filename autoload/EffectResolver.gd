extends Node
## Единая точка применения effect- и requires-словарей из JSON-контента
## (ситуации, события локаций, предметы, рецепты, спецдействия в бою). Не описан
## отдельным автозагрузом в tech-spec-v1.md — добавлен, чтобы не дублировать
## switch по типу эффекта в нескольких системах. Справочник типов — docs/CONTENT.md.

func apply_effect(effect: Dictionary) -> void:
	match effect.get("type", ""):
		"hp_delta":
			ResourceSystem.apply_hp_delta(int(effect.get("value", 0)))
		"o2_delta":
			ResourceSystem.apply_o2_delta(float(effect.get("value", 0.0)))
		"ammo_delta":
			ResourceSystem.apply_ammo_delta(int(effect.get("value", 0)))
		"item_add":
			_add_item(str(effect.get("item", "")), int(effect.get("count", 1)))
		"item_remove":
			_remove_item(str(effect.get("item", "")), int(effect.get("count", 1)))
		"flag_set":
			SituationEngine.set_flag(effect.get("flag", ""), effect.get("value", true))
		"unlock_lore":
			ArchiveSystem.unlock_fragment(effect.get("id", ""))
		"open_map_node":
			MapSystem.unlock_node(effect.get("node", ""))
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
		_:
			push_warning("EffectResolver: неизвестный тип эффекта '%s'" % effect.get("type", ""))


func apply_effects(effects: Array) -> void:
	for e in effects:
		if e is Dictionary:
			apply_effect(e)


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
					current = ResourceSystem.o2_seconds
				"ammo":
					current = ResourceSystem.ammo
			return current >= float(req.get("value", 0))
		"skill_gte":
			return CharacterSystem.get_skill_level(str(req.get("skill", ""))) >= int(req.get("value", 1))
		"in_location":
			return LocationSystem.current_id == str(req.get("location", ""))
		"event_done":
			return LocationSystem.is_event_done(str(req.get("event", ""))) == bool(req.get("value", true))
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


## Лишнее, что не поместилось в сумку, остаётся на полу текущего модуля.
func _add_item(item_id: String, count: int) -> void:
	if InventorySystem.get_item_data(item_id).is_empty():
		push_warning("EffectResolver: неизвестный предмет '%s'" % item_id)
		return
	var added := 0
	while added < count and InventorySystem.add_item(item_id):
		added += 1
	var left := count - added
	if left <= 0:
		return
	var item_name := str(InventorySystem.get_item_data(item_id).get("name", item_id))
	if LocationSystem.is_active():
		LocationSystem.stash_add(item_id, left)
		LocationSystem.add_notice("Не поместилось в сумку: %s ×%d — осталось лежать здесь." % [item_name, left])
	else:
		push_warning("EffectResolver: '%s' ×%d не поместилось в сумку и потеряно" % [item_id, left])


## Сначала из сумки, затем — надетый экземпляр.
func _remove_item(item_id: String, count: int) -> void:
	for i in range(count):
		if InventorySystem.has_item(item_id):
			InventorySystem.remove_item(item_id)
		elif not CharacterSystem.remove_equipped(item_id):
			return


func _as_array(value) -> Array:
	return value if value is Array else []
