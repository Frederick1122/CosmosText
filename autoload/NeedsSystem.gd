extends Node
## Дни, силы и голод. Каждое действие игрока (те же виды, что у кислорода:
## move, elevator, action, choice, combat_turn — ResourceSystem.action_taken)
## отнимает силы и прибавляет голода; цены — data/config.json → "needs".
##
##   Силы   — max_energy → 0. Ниже tired_energy игрок измотан: в бою штраф к
##            точности. На нуле вне боя игрок вырубается прямо там, где стоит:
##            без сознания уходит pass_out_o2 кислорода (в отсеке без воздуха
##            — дороже, на базе — ничего), просыпается с pass_out_energy сил и
##            голоднее на pass_out_hunger. В бою силы просто кончаются.
##   Голод  — 0 → max_hunger. От hungry_hunger силы тратятся быстрее
##            (hungry_energy_multiplier), на максимуме каждое действие отнимает
##            starving_hp здоровья. Голод снимает еда (эффект hunger_delta).
##   День   — растёт со сном на базе (GameState.end_day): силы до максимума,
##            +sleep_hp здоровья, +sleep_hunger голода, чекпойнт.
##
## Состояние забега: reset_for_new_run / to_save_data / load_save_data.

## Силы, голод или день изменились.
signal changed()
## Игрок вырубился от усталости (o2 — сколько кислорода ушло, пока лежал).
signal passed_out(o2: float)

const CONFIG_PATH := "res://data/config.json"
const DEFAULT_CONFIG := {
	"max_energy": 100,
	"max_hunger": 100,
	"energy_costs": {"move": 3, "elevator": 1, "action": 2, "choice": 1, "combat_turn": 2},
	"hunger_costs": {"move": 1, "elevator": 0.5, "action": 1, "choice": 0.5, "combat_turn": 0.5},
	"tired_energy": 25,
	"tired_hit_penalty": 0.15,
	"hungry_hunger": 75,
	"hungry_energy_multiplier": 1.5,
	"starving_hp": 3,
	"sleep_hunger": 15,
	"sleep_hp": 10,
	"pass_out_o2": 30,
	"pass_out_energy": 30,
	"pass_out_hunger": 10,
}

var day: int = 1
var energy: float = 100.0
var hunger: float = 0.0

var _config: Dictionary = DEFAULT_CONFIG.duplicate(true)


func _ready() -> void:
	_load_config()
	ResourceSystem.action_taken.connect(_on_action_taken)


func reset_for_new_run() -> void:
	day = 1
	energy = max_energy()
	hunger = 0.0
	changed.emit()


func max_energy() -> float:
	return float(_config["max_energy"])


func max_hunger() -> float:
	return float(_config["max_hunger"])


func is_tired() -> bool:
	return energy < float(_config["tired_energy"])


func is_hungry() -> bool:
	return hunger >= float(_config["hungry_hunger"])


func is_starving() -> bool:
	return hunger >= max_hunger()


## Штраф к шансу попадания в бою у измотанного игрока.
func hit_penalty() -> float:
	return float(_config["tired_hit_penalty"]) if is_tired() else 0.0


## Еда (отрицательное значение) или голод сверх обычного; возвращает
## фактическое изменение.
func apply_hunger_delta(value: float) -> float:
	var before := hunger
	hunger = clampf(hunger + value, 0.0, max_hunger())
	changed.emit()
	return hunger - before


## Сон на базе: новый день. Чекпойнт пишет GameState.end_day.
func sleep() -> void:
	day += 1
	energy = max_energy()
	NarrativeSystem.push("notice", "Вы забываетесь сном. Наступает день %d — силы вернулись." % day)
	EffectResolver.report_change("hunger", apply_hunger_delta(float(_config["sleep_hunger"])), "голода", true)
	var hp_before := ResourceSystem.hp
	ResourceSystem.apply_hp_delta(int(_config["sleep_hp"]))
	EffectResolver.report_change("hp", ResourceSystem.hp - hp_before, "HP")
	JournalSystem.add("rest", "Сон на базе. День %d" % day)


func to_save_data() -> Dictionary:
	return {"day": day, "energy": energy, "hunger": hunger}


func load_save_data(data: Dictionary) -> void:
	day = maxi(1, int(data.get("day", 1)))
	energy = clampf(float(data.get("energy", max_energy())), 0.0, max_energy())
	hunger = clampf(float(data.get("hunger", 0.0)), 0.0, max_hunger())
	changed.emit()


## Цена действия: силы и голод. Голод на максимуме бьёт по здоровью, силы на
## нуле вне боя — обморок.
func _on_action_taken(kind: String) -> void:
	var cost := float(_config["energy_costs"].get(kind, 0.0))
	if is_hungry():
		cost *= float(_config["hungry_energy_multiplier"])
	energy = maxf(0.0, energy - cost)
	hunger = minf(max_hunger(), hunger + float(_config["hunger_costs"].get(kind, 0.0)))
	changed.emit()
	if is_starving():
		var hp_before := ResourceSystem.hp
		ResourceSystem.apply_hp_delta(-int(_config["starving_hp"]))
		EffectResolver.report_change("hp", ResourceSystem.hp - hp_before, "HP — голод")
		if ResourceSystem.is_dead():
			return
	if energy <= 0.0 and not _in_combat():
		_pass_out()


func _pass_out() -> void:
	var o2 := float(_config["pass_out_o2"]) * ResourceSystem.environment_multiplier()
	energy = float(_config["pass_out_energy"])
	hunger = minf(max_hunger(), hunger + float(_config["pass_out_hunger"]))
	changed.emit()
	NarrativeSystem.push("notice", "Силы кончились: вы проваливаетесь в забытьё прямо здесь и приходите в себя не сразу.")
	JournalSystem.add("rest", "Обморок от усталости")
	var o2_before := ResourceSystem.o2
	ResourceSystem.apply_o2_delta(-o2)
	EffectResolver.report_change("o2", ResourceSystem.o2 - o2_before, "O2")
	passed_out.emit(o2_before - ResourceSystem.o2)


func _in_combat() -> bool:
	return CombatSystem.state == CombatSystem.State.PLAYER_TURN or CombatSystem.state == CombatSystem.State.RESOLVING


func _load_config() -> void:
	_config = DEFAULT_CONFIG.duplicate(true)
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not (parsed is Dictionary) or not (parsed.get("needs", {}) is Dictionary):
		return
	var section: Dictionary = parsed["needs"]
	for key in section.keys():
		if not DEFAULT_CONFIG.has(key):
			push_warning("NeedsSystem: неизвестный ключ needs.%s в config.json" % key)
			continue
		if DEFAULT_CONFIG[key] is Dictionary:
			var costs: Dictionary = (DEFAULT_CONFIG[key] as Dictionary).duplicate()
			if section[key] is Dictionary:
				for kind in section[key].keys():
					costs[str(kind)] = maxf(0.0, float(section[key][kind]))
			_config[key] = costs
		else:
			_config[key] = maxf(0.0, float(section[key]))
