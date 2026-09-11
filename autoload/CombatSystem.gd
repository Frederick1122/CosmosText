extends Node
## Текстовый бой — см. tech-spec-v1.md раздел 5.

signal combat_started(enemy_id: String)
signal turn_resolved(entry: Dictionary)
signal combat_ended(result: String)  # "won" | "fled" | "died"

enum State { IDLE, PLAYER_TURN, RESOLVING, ENDED }

var state: int = State.IDLE
var enemy_id: String = ""
var enemy_hp: int = 0
var enemy_data: Dictionary = {}
var log: Array = []
## Узел карты, из которого запущен этот бой (если есть) — заполняется из
## effect'а start_combat, чтобы GameState знал, какой узел пометить
## "пройдено"/"опасно" по итогу. См. GDD раздел 5.5, ситуация "требует оружие".
var clear_node_id: String = ""

var _enemy_db: Dictionary = {}
var _used_specials: Dictionary = {}


func _ready() -> void:
	_enemy_db = _load_res_json("res://data/enemies.json")


func reset_for_new_run() -> void:
	state = State.IDLE
	enemy_id = ""
	enemy_hp = 0
	enemy_data = {}
	clear_node_id = ""
	log.clear()
	_used_specials.clear()


func start_combat(id: String, clear_node: String = "") -> void:
	if not _enemy_db.has(id):
		push_error("CombatSystem: неизвестный враг '%s'" % id)
		return
	enemy_id = id
	enemy_data = _enemy_db[id]
	enemy_hp = int(enemy_data.get("hp", 10))
	clear_node_id = clear_node
	_used_specials.clear()
	log.clear()
	state = State.PLAYER_TURN
	combat_started.emit(id)


func get_state() -> Dictionary:
	return {
		"enemy_id": enemy_id,
		"enemy_name": enemy_data.get("name", ""),
		"enemy_hp": enemy_hp,
		"enemy_max_hp": int(enemy_data.get("hp", 1)),
		"player_hp": ResourceSystem.hp,
		"log": log.duplicate(),
		"available_specials": _available_specials(),
	}


func player_action(action: String, payload = null) -> void:
	if state != State.PLAYER_TURN:
		push_warning("CombatSystem: действие '%s' вне хода игрока" % action)
		return
	state = State.RESOLVING
	match action:
		"attack":
			_resolve_player_attack()
		"defend":
			_log("Игрок защищается.")
			_enemy_turn(0.5)
		"use_item":
			var item_id: String = payload if payload is String else ""
			if InventorySystem.use_item(item_id):
				_enemy_turn(1.0)
			else:
				state = State.PLAYER_TURN
				_log("Предмет нельзя использовать.")
		"flee":
			_resolve_flee()
		"special":
			_resolve_special(payload)
		_:
			push_warning("CombatSystem: неизвестное действие '%s'" % action)
			state = State.PLAYER_TURN


func _available_specials() -> Array:
	var result: Array = []
	for special in enemy_data.get("special_actions", []):
		var sid: String = special.get("id", "")
		if _used_specials.has(sid):
			continue
		if EffectResolver.check_requirements(special.get("requires", [])):
			result.append(special)
	return result


func _resolve_player_attack() -> void:
	var ranged: bool = ResourceSystem.ammo > 0
	var hit_chance: float = 0.75 if ranged else 0.5
	var dmg: int = 15 if ranged else 8
	if randf() <= hit_chance:
		enemy_hp = max(0, enemy_hp - dmg)
		if ranged:
			ResourceSystem.apply_ammo_delta(-1)
		_log("Попадание! Урон: %d" % dmg)
	else:
		_log("Промах.")
		if not ranged:
			ResourceSystem.apply_hp_delta(-10)  # неудачный ближний бой без патронов — риск GDD 5.2
	if enemy_hp <= 0:
		_end_combat("won")
		return
	_enemy_turn(1.0)


func _resolve_flee() -> void:
	var risk: float = float(enemy_data.get("flee_risk", 0.5))
	if randf() > risk:
		_log("Удалось отступить.")
		_end_combat("fled")
	else:
		_log("Побег не удался.")
		_enemy_turn(1.0)


func _resolve_special(payload) -> void:
	var sid: String = payload if payload is String else ""
	var special = null
	for s in enemy_data.get("special_actions", []):
		if s.get("id", "") == sid:
			special = s
			break
	if special == null or _used_specials.has(sid) or not EffectResolver.check_requirements(special.get("requires", [])):
		state = State.PLAYER_TURN
		return
	_used_specials[sid] = true
	var effect: Dictionary = special.get("effect", {})
	match effect.get("type", ""):
		"skip_enemy_turn_and_guarantee_hit":
			enemy_hp = max(0, enemy_hp - int(effect.get("value", 15)))
			_log("%s — враг теряет цель." % special.get("label", "Спецдействие"))
			if enemy_hp <= 0:
				_end_combat("won")
				return
			state = State.PLAYER_TURN
		_:
			push_warning("CombatSystem: неизвестный тип спецэффекта '%s'" % effect.get("type", ""))
			state = State.PLAYER_TURN


func _enemy_turn(multiplier: float) -> void:
	var atk: Dictionary = enemy_data.get("attack", {})
	if randf() <= float(atk.get("hit_chance", 0.5)):
		var dmg: int = int(randi_range(int(atk.get("min", 1)), int(atk.get("max", 5))) * multiplier)
		ResourceSystem.apply_hp_delta(-dmg)
		_log("Враг атакует. Урон: %d" % dmg)
	else:
		_log("Враг промахивается.")
	if ResourceSystem.hp <= 0:
		_end_combat("died")
	else:
		state = State.PLAYER_TURN


func _end_combat(result: String) -> void:
	state = State.ENDED
	if result == "won":
		for item_id in enemy_data.get("loot", []):
			InventorySystem.add_item(item_id)
	combat_ended.emit(result)


func _log(text: String) -> void:
	log.append(text)
	turn_resolved.emit({"text": text})


func _load_res_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("CombatSystem: файл не найден %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
