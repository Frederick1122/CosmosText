extends Node
## Пошаговый бой в духе Neo Scavenger. Ход — это выбор одного «манёвра»
## из списка доступных; ход игрока и ход противника разыгрываются
## одновременно:
##   1. обе стороны выбирают манёвр (противник — по своему типу ИИ);
##   2. применяются перемещения, дистанция меняется на сумму сдвигов;
##   3. по новой дистанции разыгрываются атаки и их последствия.
##
## Дистанция (0…MAX_RANGE шагов) решает, чем можно бить: вплотную — руками
## или оружием ближнего боя, издалека — только огнестрелом. Побег возможен
## только с безопасного расстояния.
##
## Обломок с палубы есть в любой схватке: «Подобрать» тратит ход, «Бросить» —
## ещё один; попадание ранит немного, но противник теряет следующий ход.
##
## Характеристики персонажа берутся из CharacterSystem, формулы — в
## docs/ARCHITECTURE.md.

signal combat_started(enemy_id: String)
## Схватка решена ("won" | "fled") и игрок нажал «Продолжить» (finish), либо
## игрок погиб ("died") — тогда сразу: экран смерти выставляет EventBus.
signal combat_ended(result: String)

enum State { IDLE, PLAYER_TURN, RESOLVING, ENDED }

const MAX_RANGE := 5
const DEFAULT_START_RANGE := 3
const MELEE_RANGE := 1

const RANGED_HIT_CHANCE := 0.75
const RANGED_DAMAGE := 15
const MELEE_HIT_CHANCE := 0.6
const MELEE_DAMAGE := 8
const MELEE_MISS_PENALTY := 6
const MAX_HIT_CHANCE := 0.95
const MIN_FLEE_RISK := 0.05
## Прицеливание: прибавка к шансу попадания следующей атаки.
const AIM_BONUS := 0.25
## Защита: множитель входящего урона и штраф к шансу попадания врага.
const DEFEND_DAMAGE_MULTIPLIER := 0.5
const DEFEND_HIT_PENALTY := 0.2
## Дистанция, с которой побег удаётся без броска.
const SAFE_FLEE_RANGE := 4
## Обломок с палубы: подобрать — ход, бросить — ещё ход. Попадание ранит
## немного, зато сбивает противника с толку: следующий ход он теряет.
const THROW_HIT_CHANCE := 0.7
const THROW_DAMAGE := 5
const THROW_STAGGER_TURNS := 1

var state: int = State.IDLE
var enemy_id: String = ""
var enemy_hp: int = 0
var enemy_data: Dictionary = {}
## Журнал схватки: [{ text, kind, turn, fx }].
##   kind — "info" | "move" | "hit" | "damage" | "heal" | "end";
##   turn — номер хода, в котором появилась запись (0 — начало боя);
##   fx   — удары и лечение этой записи для эффектов экрана боя:
##          [{ "target": "enemy"|"player", "amount": урон или лечение (0 — промах),
##             "style": "melee" | "ranged" | "heal" }].
var log: Array = []
## Номер текущего хода: экран боя проигрывает эффекты только свежих записей.
var turn: int = 0
## Итог решённой схватки, ждущий «Продолжить»: "won" | "fled" ("" — нет).
var outcome: String = ""
## Дистанция между игроком и противником в шагах.
var range_steps: int = DEFAULT_START_RANGE
var player_last_move: String = ""
var enemy_last_move: String = ""
## Узел карты, из которого запущен этот бой (если есть) — заполняется из
## effect'а start_combat, чтобы GameState знал, какой узел пометить
## "пройдено"/"опасно" по итогу. См. GDD раздел 5.5.
var clear_node_id: String = ""
## Эффекты из start_combat.on_win / on_flee — применяет GameState по итогу боя.
var on_win_effects: Array = []
var on_flee_effects: Array = []
## Награда за победу (пусто — схватка не выиграна): { xp, level_before,
## xp_before, loot } — опыт уже начислен, трофеи выдаст GameState по «Продолжить».
var reward: Dictionary = {}

var _enemy_db: Dictionary = {}
var _used_specials: Dictionary = {}
var _player_aiming: bool = false
var _player_defending: bool = false
var _enemy_defending: bool = false
## Сколько ходов противник потерял цель (спецдействие-отвлечение).
var _enemy_distracted_turns: int = 0
## Следующая атака игрока попадает без броска — противник его не видит.
var _guaranteed_hit: bool = false
## В руке подобранный обломок — следующим ходом его можно бросить.
var _holding_debris: bool = false
## «Хладнокровный выстрел»: бонус первого выстрела боя ещё не потрачен.
var _first_shot_ready: bool = false

const MOVE_TITLES := {
	"approach": "Сблизиться",
	"retreat": "Разорвать дистанцию",
	"shoot": "Выстрелить",
	"strike": "Удар",
	"aim": "Прицелиться",
	"defend": "Уклоняться",
	"flee": "Бежать",
	"use_item": "Использовать предмет",
	"special": "Спецдействие",
	"hold": "Выжидать",
	"grab": "Подобрать обломок",
	"throw": "Бросить обломок",
	"distracted": "Потерял цель",
}


func _ready() -> void:
	_enemy_db = _load_res_json("res://data/enemies.json")


func reset_for_new_run() -> void:
	state = State.IDLE
	enemy_id = ""
	enemy_hp = 0
	enemy_data = {}
	clear_node_id = ""
	on_win_effects = []
	on_flee_effects = []
	range_steps = DEFAULT_START_RANGE
	player_last_move = ""
	enemy_last_move = ""
	_player_aiming = false
	_player_defending = false
	_enemy_defending = false
	_enemy_distracted_turns = 0
	_guaranteed_hit = false
	_holding_debris = false
	reward = {}
	turn = 0
	outcome = ""
	log.clear()
	_used_specials.clear()


func start_combat(id: String, clear_node: String = "", on_win: Array = [], on_flee: Array = []) -> void:
	if not _enemy_db.has(id):
		push_error("CombatSystem: неизвестный враг '%s'" % id)
		return
	enemy_id = id
	enemy_data = _enemy_db[id]
	enemy_hp = int(enemy_data.get("hp", 10))
	clear_node_id = clear_node
	on_win_effects = on_win.duplicate(true)
	on_flee_effects = on_flee.duplicate(true)
	range_steps = clampi(int(enemy_data.get("start_range", DEFAULT_START_RANGE)), 0, MAX_RANGE)
	player_last_move = ""
	enemy_last_move = ""
	_player_aiming = false
	_player_defending = false
	_enemy_defending = false
	_enemy_distracted_turns = 0
	_guaranteed_hit = false
	_holding_debris = false
	_first_shot_ready = SkillTreeSystem.has_tag("combat:first_shot")
	reward = {}
	turn = 0
	outcome = ""
	_used_specials.clear()
	log.clear()
	state = State.PLAYER_TURN
	_log("%s замечает вас. Дистанция: %d." % [str(enemy_data.get("name", id)), range_steps], "info")
	combat_started.emit(id)


func get_state() -> Dictionary:
	return {
		"enemy_id": enemy_id,
		"enemy_name": enemy_data.get("name", ""),
		"enemy_hp": enemy_hp,
		"enemy_max_hp": int(enemy_data.get("hp", 1)),
		"enemy_weapon": str(enemy_data.get("weapon", "")),
		"enemy_last_move": move_title(enemy_last_move),
		"enemy_conditions": _enemy_conditions(),
		"player_hp": ResourceSystem.hp,
		"player_max_hp": ResourceSystem.max_hp,
		"player_weapon": _player_weapon_name(),
		"player_last_move": move_title(player_last_move),
		"player_conditions": _player_conditions(),
		"range": range_steps,
		"max_range": MAX_RANGE,
		"log": log.duplicate(true),
		"turn": turn,
		"outcome": outcome,
		"moves": get_available_moves(),
		"available_specials": _available_specials(),
		"reward": reward.duplicate(true),
	}


func move_title(move_id: String) -> String:
	return str(MOVE_TITLES.get(move_id, ""))


## Манёвры этого хода: [{ id, label, hint, enabled, reason }]. Порядок — сетка
## экрана боя по две кнопки: отход слева, сближение справа.
func get_available_moves() -> Array:
	var moves: Array = []
	# Стрелять можно только из огнестрела в руках (предмет с "firearm": true) и при патронах.
	var firearm := CharacterSystem.has_firearm()
	var shoot_reason := "Нет патронов" if firearm else "Нет огнестрела в руках"
	moves.append(_move_entry("shoot", "Выстрелить (патронов: %d)" % ResourceSystem.ammo,
		firearm and ResourceSystem.ammo > 0, shoot_reason))
	var melee_name := CharacterSystem.get_equipped_name("arms")
	var melee_label := "Удар: %s" % melee_name if melee_name != "" else "Удар голыми руками"
	moves.append(_move_entry("strike", melee_label, range_steps <= MELEE_RANGE,
		"Слишком далеко (нужно ≤ %d)" % MELEE_RANGE))
	moves.append(_move_entry("retreat", "Разорвать дистанцию", range_steps < MAX_RANGE, "Дальше отходить некуда"))
	moves.append(_move_entry("approach", "Сблизиться", range_steps > 0, "Уже вплотную"))
	moves.append(_move_entry("aim", "Прицелиться (+%d%% к попаданию)" % int(AIM_BONUS * 100.0), true, ""))
	moves.append(_move_entry("defend", "Уклоняться", true, ""))
	if _holding_debris:
		moves.append(_move_entry("throw", "Бросить обломок (%d%%, сбивает с толку)" % int(_throw_chance() * 100.0), true, ""))
	else:
		moves.append(_move_entry("grab", "Подобрать обломок", true, ""))
	var flee_label := "Бежать (уверенно)" if range_steps >= SAFE_FLEE_RANGE else "Бежать (риск: %d%%)" % int(_flee_risk() * 100.0)
	moves.append(_move_entry("flee", flee_label, true, ""))
	return moves


func player_action(move_id: String, payload = null) -> void:
	if state != State.PLAYER_TURN:
		push_warning("CombatSystem: манёвр '%s' вне хода игрока" % move_id)
		return
	if not _is_move_allowed(move_id):
		push_warning("CombatSystem: манёвр '%s' сейчас недоступен" % move_id)
		return
	# Ход в бою — тяжёлая работа: дыхание расходует запас баллона.
	if not ResourceSystem.spend_o2("combat_turn"):
		_log("Баллон пуст.", "damage")
		_end_combat("died")
		return
	turn += 1
	state = State.RESOLVING
	player_last_move = move_id
	_player_defending = move_id == "defend"
	_enemy_defending = false

	# Спецдействие живёт по своим правилам: враг теряет ход.
	if move_id == "special":
		_resolve_special(payload)
		return

	var enemy_move := _choose_enemy_move()
	enemy_last_move = enemy_move
	_enemy_defending = enemy_move == "defend"
	_apply_movement(move_id, enemy_move)

	if move_id == "flee":
		_resolve_flee(enemy_move)
		return

	_resolve_player_move(move_id, payload)
	if state == State.ENDED:
		return
	_resolve_enemy_move(enemy_move)
	if state == State.ENDED:
		return
	state = State.PLAYER_TURN


# --- Разрешение манёвров --------------------------------------------------------

func _resolve_player_move(move_id: String, payload) -> void:
	match move_id:
		"approach":
			_log("Вы сокращаете дистанцию. Шагов до цели: %d." % range_steps, "move")
		"retreat":
			_log("Вы разрываете дистанцию. Шагов до цели: %d." % range_steps, "move")
		"aim":
			_player_aiming = true
			_log("Вы ловите цель в прицел.", "move")
		"defend":
			_log("Вы уходите в защиту и следите за движением.", "move")
		"shoot":
			_resolve_shot()
		"strike":
			_resolve_strike()
		"use_item":
			_resolve_use_item(payload if payload is String else "")
		"grab":
			_holding_debris = true
			_log("Вы подхватываете с палубы увесистый обломок.", "move")
		"throw":
			_resolve_throw()
		_:
			_log("Вы выжидаете.", "move")


## Расходник в бою: в журнале — что он на самом деле дал. Лечение всплывает
## над карточкой игрока (fx со style "heal").
func _resolve_use_item(item_id: String) -> void:
	var item_name := str(InventorySystem.get_item_data(item_id).get("name", item_id))
	var hp_before := ResourceSystem.hp
	var o2_before := ResourceSystem.o2
	var ammo_before := ResourceSystem.ammo
	var hunger_before := NeedsSystem.hunger
	if not InventorySystem.use_item(item_id):
		_log("Предмет нельзя использовать.", "info")
		return
	var healed := ResourceSystem.hp - hp_before
	var gains := PackedStringArray()
	if healed != 0:
		gains.append("%+d HP" % healed)
	var o2_gain := roundi(ResourceSystem.o2 - o2_before)
	if o2_gain != 0:
		gains.append("%+d O2" % o2_gain)
	if ResourceSystem.ammo != ammo_before:
		gains.append("%+d патр." % (ResourceSystem.ammo - ammo_before))
	var hunger_change := roundi(NeedsSystem.hunger - hunger_before)
	if hunger_change != 0:
		gains.append("%+d голода" % hunger_change)
	if gains.is_empty():
		_log("Вы используете: %s — ничего не изменилось." % item_name, "move")
		return
	_log("Вы используете: %s (%s)." % [item_name, ", ".join(gains)], "heal",
		[_fx("player", healed, "heal")] if healed > 0 else [])


## Брошенный обломок: на попадание — немного урона и потерянный врагом ход.
func _resolve_throw() -> void:
	_holding_debris = false
	var chance := _throw_chance()
	_consume_aim()
	if _take_guaranteed_hit() or randf() <= chance:
		_enemy_distracted_turns = maxi(_enemy_distracted_turns, THROW_STAGGER_TURNS)
		_damage_enemy(THROW_DAMAGE, "Обломок попадает в цель. Урон: %d — %s сбит с толку." % [
			THROW_DAMAGE, str(enemy_data.get("name", "Противник"))], "thrown")
	else:
		_log("Обломок пролетает мимо и гремит по палубе.", "info", [_fx("enemy", 0, "thrown")])


func _throw_chance() -> float:
	var chance := THROW_HIT_CHANCE + _accuracy_bonus()
	chance -= 0.08 * float(maxi(0, range_steps - 2))
	if _enemy_defending:
		chance -= DEFEND_HIT_PENALTY
	return clampf(chance, 0.05, MAX_HIT_CHANCE)


func _resolve_shot() -> void:
	if ResourceSystem.ammo <= 0:
		_log("Осечка: патронов нет.", "info")
		return
	ResourceSystem.apply_ammo_delta(-1)
	# «Хладнокровный выстрел»: первый выстрел боя бьёт точнее и больнее.
	var cold_shot := _first_shot_ready
	_first_shot_ready = false
	var chance := RANGED_HIT_CHANCE + _accuracy_bonus()
	if cold_shot:
		chance += 0.15
	# На вытянутой руке стрелять неудобно, на большой дистанции — тем более.
	chance -= 0.08 * float(maxi(0, range_steps - 2))
	if range_steps == 0:
		chance -= 0.15
	if _enemy_defending:
		chance -= DEFEND_HIT_PENALTY
	_consume_aim()
	if _take_guaranteed_hit() or randf() <= minf(chance, MAX_HIT_CHANCE):
		var dmg := maxi(1, RANGED_DAMAGE + int(CharacterSystem.get_stat("ranged_damage")))
		if cold_shot:
			dmg = maxi(1, roundi(dmg * 1.25))
		_damage_enemy(dmg, "Попадание! Урон: %d." % dmg, "ranged")
	else:
		_log("Выстрел уходит мимо.", "info", [_fx("enemy", 0, "ranged")])


func _resolve_strike() -> void:
	if range_steps > MELEE_RANGE:
		_log("Противник слишком далеко — удар рассекает пустоту.", "info")
		return
	var chance := MELEE_HIT_CHANCE + _accuracy_bonus()
	if _enemy_defending:
		chance -= DEFEND_HIT_PENALTY
	_consume_aim()
	if _take_guaranteed_hit() or randf() <= minf(chance, MAX_HIT_CHANCE):
		var dmg := maxi(1, MELEE_DAMAGE + int(CharacterSystem.get_stat("melee_damage")))
		_damage_enemy(dmg, "Вы бьёте в упор. Урон: %d." % dmg, "melee")
	else:
		_log("Вы промахиваетесь и открываетесь. Урон: %d." % MELEE_MISS_PENALTY, "damage",
			[_fx("enemy", 0, "melee"), _fx("player", MELEE_MISS_PENALTY, "melee")])
		ResourceSystem.apply_hp_delta(-MELEE_MISS_PENALTY)
		if ResourceSystem.hp <= 0:
			_end_combat("died")


## Отвлечённый противник не видит цели: следующий удар проходит наверняка.
func _take_guaranteed_hit() -> bool:
	if not _guaranteed_hit:
		return false
	_guaranteed_hit = false
	return true


func _resolve_flee(enemy_move: String) -> void:
	if range_steps >= SAFE_FLEE_RANGE or enemy_move == "defend":
		_log("Вы разрываете контакт и уходите.", "end")
		_end_combat("fled")
		return
	if randf() > _flee_risk():
		_log("Вы отрываетесь от преследования.", "end")
		_end_combat("fled")
		return
	_log("Уйти не вышло — вы подставляетесь.", "info")
	_resolve_enemy_move(enemy_move, 1.5)
	if state != State.ENDED:
		state = State.PLAYER_TURN


func _resolve_enemy_move(enemy_move: String, damage_multiplier: float = 1.0) -> void:
	var name := str(enemy_data.get("name", "Противник"))
	match enemy_move:
		"approach":
			_log("%s сокращает дистанцию (%d)." % [name, range_steps], "move")
		"retreat":
			_log("%s отходит (%d)." % [name, range_steps], "move")
		"defend":
			_log("%s уходит в глухую оборону." % name, "move")
		"distracted":
			_log("%s шарит по отсеку: цель потеряна." % name, "move")
		"attack":
			_enemy_attack(damage_multiplier)
		_:
			_log("%s выжидает." % name, "move")


func _enemy_attack(damage_multiplier: float) -> void:
	var name := str(enemy_data.get("name", "Противник"))
	var atk: Dictionary = enemy_data.get("attack", {})
	var style := "melee" if int(atk.get("range", MELEE_RANGE)) <= MELEE_RANGE else "ranged"
	var chance := float(atk.get("hit_chance", 0.5))
	if _player_defending:
		chance -= DEFEND_HIT_PENALTY
	if randf() > chance:
		_log("%s промахивается." % name, "info", [_fx("player", 0, style)])
		return
	var raw := int(randi_range(int(atk.get("min", 1)), int(atk.get("max", 5))) * damage_multiplier)
	if _player_defending:
		raw = int(raw * DEFEND_DAMAGE_MULTIPLIER)
	var armor := int(CharacterSystem.get_stat("armor"))
	var dmg: int = maxi(1, raw - armor)
	_player_aiming = false  # попадание сбивает прицел
	# Запись в журнал — до урона: смертельный удар должен успеть в журнал
	# раньше, чем EventBus переключит экран на смерть.
	if armor > 0 and raw > dmg:
		_log("%s попадает. Урон: %d (броня поглотила %d)." % [name, dmg, raw - dmg], "damage", [_fx("player", dmg, style)])
	else:
		_log("%s попадает. Урон: %d." % [name, dmg], "damage", [_fx("player", dmg, style)])
	ResourceSystem.apply_hp_delta(-dmg)
	if ResourceSystem.hp <= 0:
		_end_combat("died")


func _resolve_special(payload) -> void:
	var sid: String = payload if payload is String else ""
	var special = null
	for s in enemy_data.get("special_actions", []):
		if s.get("id", "") == sid:
			special = s
			break
	if special == null:
		for s in _available_specials():  # синтетические спецдействия узлов дерева
			if s.get("id", "") == sid:
				special = s
				break
	if special == null or _used_specials.has(sid) or not EffectResolver.check_requirements(special.get("requires", [])):
		state = State.PLAYER_TURN
		return
	_used_specials[sid] = true
	enemy_last_move = "distracted"
	var effect: Dictionary = special.get("effect", {})
	match effect.get("type", ""):
		"distract":
			# Отвлечение не наносит урона: противник теряет цель на несколько
			# ходов, а первый удар по нему проходит наверняка.
			_enemy_distracted_turns = maxi(1, int(effect.get("value", 1))) - 1
			_guaranteed_hit = true
			_log("%s. %s теряет цель." % [
				str(special.get("label", "Отвлекающий манёвр")),
				str(enemy_data.get("name", "Противник"))], "move")
			state = State.PLAYER_TURN
		_:
			push_warning("CombatSystem: неизвестный тип спецэффекта '%s'" % effect.get("type", ""))
			state = State.PLAYER_TURN


# --- Дистанция и ИИ -------------------------------------------------------------

## Перемещения обеих сторон складываются: отход под наступление врага
## оставляет дистанцию прежней — как в Neo Scavenger. «Контроль дистанции»
## двигает игрока на два шага за ход вместо одного.
func _apply_movement(player_move: String, enemy_move: String) -> void:
	var player_steps := 2 if SkillTreeSystem.has_tag("combat:range_control") else 1
	var delta := 0
	if player_move == "approach":
		delta -= player_steps
	elif player_move == "retreat" or player_move == "flee":
		delta += player_steps
	if enemy_move == "approach":
		delta -= 1
	elif enemy_move == "retreat":
		delta += 1
	range_steps = clampi(range_steps + delta, 0, MAX_RANGE)


func _choose_enemy_move() -> String:
	if _enemy_distracted_turns > 0:
		_enemy_distracted_turns -= 1
		return "distracted"
	var reach := int(enemy_data.get("attack", {}).get("range", MELEE_RANGE))
	var preferred := int(enemy_data.get("preferred_range", reach))
	match str(enemy_data.get("ai", "brawler")):
		"turret":
			# Турель прикручена к палубе: только стреляет и ждёт.
			return "attack" if range_steps <= reach else "hold"
		"shooter":
			if range_steps < preferred:
				return "retreat"
			if range_steps > reach:
				return "approach"
			return "attack"
		_:
			if enemy_hp * 4 <= int(enemy_data.get("hp", 1)) and randf() < 0.3:
				return "defend"  # подранок огрызается осторожнее
			if range_steps > reach:
				return "approach"
			return "attack"


func _flee_risk() -> float:
	var risk := float(enemy_data.get("flee_risk", 0.5)) - CharacterSystem.get_stat("flee_chance")
	risk -= 0.08 * float(range_steps)
	return maxf(risk, MIN_FLEE_RISK)


# --- Служебное ------------------------------------------------------------------

func _is_move_allowed(move_id: String) -> bool:
	if move_id == "special" or move_id == "use_item":
		return true
	for move in get_available_moves():
		if str(move.get("id", "")) == move_id:
			return bool(move.get("enabled", false))
	return false


func _move_entry(id: String, label: String, enabled: bool, reason: String) -> Dictionary:
	return {
		"id": id,
		"label": label,
		"enabled": enabled,
		"reason": "" if enabled else reason,
	}


func _aim_bonus() -> float:
	return AIM_BONUS if _player_aiming else 0.0


## Прибавка к шансу попадания: точность снаряжения и навыков, прицел, минус
## усталость (NeedsSystem).
func _accuracy_bonus() -> float:
	return CharacterSystem.get_stat("hit_chance") + _aim_bonus() - NeedsSystem.hit_penalty()


func _consume_aim() -> void:
	_player_aiming = false


func _damage_enemy(amount: int, text: String, style: String) -> void:
	enemy_hp = max(0, enemy_hp - amount)
	_log(text, "hit", [_fx("enemy", amount, style)])
	if enemy_hp <= 0:
		_end_combat("won")


func _player_conditions() -> Array:
	var result: Array = []
	if _guaranteed_hit:
		result.append("Верный удар")
	if _player_aiming:
		result.append("На прицеле")
	if _player_defending:
		result.append("В защите")
	if ResourceSystem.hp * 4 <= ResourceSystem.max_hp:
		result.append("Тяжело ранен")
	if CharacterSystem.has_firearm() and ResourceSystem.ammo <= 0:
		result.append("Без патронов")
	if _holding_debris:
		result.append("Обломок в руке")
	if _first_shot_ready:
		result.append("Хладнокровный выстрел")
	if NeedsSystem.is_tired():
		result.append("Измотан: −%d%% к попаданию" % roundi(NeedsSystem.hit_penalty() * 100.0))
	if NeedsSystem.is_hungry():
		result.append("Голоден")
	return result


func _enemy_conditions() -> Array:
	var result: Array = []
	if _enemy_distracted_turns > 0 or enemy_last_move == "distracted":
		result.append("Потерял цель")
	if _enemy_defending:
		result.append("В защите")
	if enemy_hp * 4 <= int(enemy_data.get("hp", 1)):
		result.append("Повреждён")
	if range_steps <= MELEE_RANGE:
		result.append("Вплотную")
	return result


func _player_weapon_name() -> String:
	var weapon := CharacterSystem.get_equipped_name("arms")
	return weapon if weapon != "" else "голые руки"


func _available_specials() -> Array:
	var result: Array = []
	# «Подавление»: узел дерева даёт один подавляющий залп за бой — враг теряет
	# цель, не получая урона. Собственные спецдействия врага идут следом.
	if SkillTreeSystem.has_tag("combat:suppression") and not _used_specials.has("skill_suppression"):
		result.append({
			"id": "skill_suppression",
			"label": "Подавить огнём (враг теряет цель)",
			"effect": {"type": "distract", "value": 2},
		})
	for special in enemy_data.get("special_actions", []):
		var sid: String = special.get("id", "")
		if _used_specials.has(sid):
			continue
		if EffectResolver.check_requirements(special.get("requires", [])):
			result.append(special)
	return result


## Победа и побег не уводят с экрана боя сразу: игрок видит последний удар
## и итог, а combat_ended уходит по «Продолжить» (finish). Смерть — сразу.
func _end_combat(result: String) -> void:
	state = State.ENDED
	if result == "died":
		outcome = ""
		combat_ended.emit(result)
		return
	outcome = result
	if result == "won":
		_log("%s обезврежен." % str(enemy_data.get("name", "Противник")), "end")
		# Опыт — сразу: экран победы показывает, как он набирается.
		var xp := ProgressionSystem.kill_reward(enemy_data)
		reward = {
			"xp": xp,
			"level_before": ProgressionSystem.level,
			"xp_before": ProgressionSystem.xp,
			"loot": (enemy_data.get("loot", []) as Array).duplicate(),
		}
		ProgressionSystem.add_xp(xp)


## «Продолжить» под итогом схватки: только теперь бой заканчивается.
func finish() -> void:
	if state != State.ENDED or outcome == "":
		return
	var result := outcome
	outcome = ""
	combat_ended.emit(result)


## Текст последнего удара по игроку ("" — игрока не задели) — для экрана смерти.
func last_hit_on_player() -> String:
	for i in range(log.size() - 1, -1, -1):
		for fx in log[i].get("fx", []):
			if str(fx.get("target", "")) == "player" and int(fx.get("amount", 0)) > 0:
				return str(log[i].get("text", ""))
	return ""


## Трофеи побеждённого врага — эффекты item_add; применяет GameState.
func loot_effects() -> Array:
	var effects: Array = []
	for item_id in enemy_data.get("loot", []):
		effects.append({"type": "item_add", "item": str(item_id)})
	return effects


func _fx(target: String, amount: int, style: String) -> Dictionary:
	return {"target": target, "amount": amount, "style": style}


func _log(text: String, kind: String = "info", fx: Array = []) -> void:
	log.append({"text": text, "kind": kind, "turn": turn, "fx": fx})


func _load_res_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("CombatSystem: файл не найден %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
