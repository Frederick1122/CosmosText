extends Node
## Единая точка применения effect- и requires-словарей из JSON-контента
## (ситуации, предметы, спецдействия в бою). Не описан отдельным автозагрузом
## в tech-spec-v1.md — добавлен, чтобы не дублировать switch по типу эффекта
## в SituationEngine и InventorySystem. Прикладной отход от документа, не архитектурный.

func apply_effect(effect: Dictionary) -> void:
	match effect.get("type", ""):
		"hp_delta":
			ResourceSystem.apply_hp_delta(int(effect.get("value", 0)))
		"o2_delta":
			ResourceSystem.apply_o2_delta(float(effect.get("value", 0.0)))
		"ammo_delta":
			ResourceSystem.apply_ammo_delta(int(effect.get("value", 0)))
		"item_add":
			InventorySystem.add_item(effect.get("item", ""))
		"item_remove":
			InventorySystem.remove_item(effect.get("item", ""))
		"flag_set":
			SituationEngine.set_flag(effect.get("flag", ""), effect.get("value", true))
		"unlock_lore":
			ArchiveSystem.unlock_fragment(effect.get("id", ""))
		"open_map_node":
			MapSystem.unlock_node(effect.get("node", ""))
		"lock_map_node":
			MapSystem.set_node_state(effect.get("node", ""), effect.get("state", "dangerous"))
		"start_combat":
			CombatSystem.start_combat(effect.get("enemy", ""), effect.get("clear_node", ""))
		_:
			push_warning("EffectResolver: неизвестный тип эффекта '%s'" % effect.get("type", ""))


func apply_effects(effects: Array) -> void:
	for e in effects:
		if e is Dictionary:
			apply_effect(e)


func check_requirement(req: Dictionary) -> bool:
	match req.get("type", ""):
		"has_item":
			return InventorySystem.has_item(req.get("item", ""))
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
		_:
			push_warning("EffectResolver: неизвестный тип условия '%s'" % req.get("type", ""))
			return true


func check_requirements(reqs: Array) -> bool:
	for r in reqs:
		if r is Dictionary and not check_requirement(r):
			return false
	return true
