extends Node
## HP / O2 / патроны — см. tech-spec-v1.md раздел 4.
## max_hp = base_max_hp (из config) + бонус от снаряжения и навыков
## (выставляет CharacterSystem через set_max_hp_bonus).
##
## Кислород — не таймер, а расходник: запас в баллоне тратится на действия
## игрока. Цены лежат в data/config.json → o2_costs:
##   move        — переход в модуль с карты;
##   elevator    — поездка на лифте;
##   action      — запуск ручного события в модуле;
##   choice      — выбор варианта в ситуации;
##   combat_turn — ход в бою.
## В разгерметизированном модуле (узел карты с "sealed": false) любое действие
## стоит дороже — множитель config.o2_unsealed_multiplier, а в модуле с
## воздухом (локация с "breathable": true, например база) кислород не
## тратится вовсе. Использование предметов, подбор вещей с пола и крафт
## кислорода не стоят: это противовес расходу, а не действие на выживание.
##
## Каждое действие (даже бесплатное по кислороду) — сигнал action_taken:
## по нему NeedsSystem тратит силы и копит голод.

signal hp_changed(value: int)
signal o2_changed(value: float)
signal o2_spent(kind: String, amount: float)
signal action_taken(kind: String)
signal ammo_changed(value: int)
signal resource_depleted(kind: String)  # kind: "hp" | "o2"

const CONFIG_PATH := "res://data/config.json"
## Цены действий по умолчанию — используются, если в config.json нет o2_costs.
const DEFAULT_O2_COSTS := {
	"move": 6.0,
	"elevator": 4.0,
	"action": 4.0,
	"explore_tick": 1.0,
	"choice": 3.0,
	"combat_turn": 4.0,
}
const DEFAULT_UNSEALED_MULTIPLIER := 2.0
## Ниже этого запаса кислорода HUD краснеет, а SoundSystem подаёт сигнал тревоги.
const LOW_O2 := 60.0

var hp: int = 100
var max_hp: int = 100
var base_max_hp: int = 100
var max_hp_bonus: int = 0
var o2: float = 0.0
var ammo: int = 0

## Цены действий и множитель разгерметизации — контент, а не состояние забега:
## читаются один раз при старте и в сейв не попадают.
var o2_costs: Dictionary = DEFAULT_O2_COSTS.duplicate()
var o2_unsealed_multiplier: float = DEFAULT_UNSEALED_MULTIPLIER

var _died_this_run: bool = false


func _ready() -> void:
	_load_costs()


func reset_for_new_run(config: Dictionary) -> void:
	base_max_hp = int(config.get("start_hp", 100))
	max_hp_bonus = 0
	max_hp = base_max_hp
	hp = max_hp
	o2 = float(config.get("start_o2", 252.0))
	ammo = int(config.get("start_ammo", 0))
	_died_this_run = false
	hp_changed.emit(hp)
	o2_changed.emit(o2)
	ammo_changed.emit(ammo)


func set_max_hp_bonus(bonus: int) -> void:
	max_hp_bonus = bonus
	max_hp = maxi(1, base_max_hp + bonus)
	if hp > max_hp:
		hp = max_hp
	hp_changed.emit(hp)


func apply_hp_delta(v: int) -> void:
	if _died_this_run:
		return
	hp = clampi(hp + v, 0, max_hp)
	hp_changed.emit(hp)
	if hp <= 0:
		_trigger_death("hp")


func apply_o2_delta(v: float) -> void:
	if _died_this_run:
		return
	o2 = max(0.0, o2 + v)
	o2_changed.emit(o2)
	if o2 <= 0.0:
		_trigger_death("o2")


func apply_ammo_delta(v: int) -> void:
	ammo = max(0, ammo + v)
	ammo_changed.emit(ammo)


## Сколько кислорода стоит действие kind в узле node_id (пусто — текущий
## модуль игрока). Незагерметизированный узел дороже, модуль с воздухом —
## бесплатно. Узлы дерева «Точная стыковка» и «Переброс питания» срезают
## по одному пункту с переходов и действий соответственно.
func get_o2_cost(kind: String, node_id: String = "") -> float:
	var base := maxf(0.0, float(o2_costs.get(kind, 0.0)) - float(_tag_discount(kind)))
	return base * environment_multiplier(node_id)


func _tag_discount(kind: String) -> int:
	match kind:
		"move", "elevator":
			return 1 if SkillTreeSystem.has_tag("pilot:docking") else 0
		"action", "choice":
			return 1 if SkillTreeSystem.has_tag("eng:power_reroute") else 0
	return 0


## Списывает стоимость действия. count_action=false нужен для промежуточных
## тактов длительного действия: силы и голод списываются один раз в конце.
## Возвращает false, если кислород кончился и игрок уже мёртв.
func spend_o2(kind: String, node_id: String = "", count_action: bool = true) -> bool:
	if _died_this_run:
		return false
	var cost := get_o2_cost(kind, node_id)
	if cost > 0.0:
		apply_o2_delta(-cost)
		o2_spent.emit(kind, cost)
	if not _died_this_run and count_action:
		action_taken.emit(kind)
	return not _died_this_run


## Завершает длительное действие после всех кислородных тактов.
func finish_action(kind: String) -> bool:
	if _died_this_run:
		return false
	action_taken.emit(kind)
	return not _died_this_run


func is_dead() -> bool:
	return _died_this_run


func to_save_data() -> Dictionary:
	return {
		"hp": hp,
		"max_hp": max_hp,
		"base_max_hp": base_max_hp,
		"o2": o2,
		"ammo": ammo,
	}


func load_save_data(data: Dictionary) -> void:
	max_hp = int(data.get("max_hp", max_hp))
	base_max_hp = int(data.get("base_max_hp", max_hp))
	max_hp_bonus = max_hp - base_max_hp
	hp = clampi(int(data.get("hp", hp)), 0, max_hp)
	# "o2_seconds" — ключ сейвов версии 1, когда кислород шёл по таймеру.
	o2 = max(0.0, float(data.get("o2", data.get("o2_seconds", o2))))
	ammo = max(0, int(data.get("ammo", ammo)))
	_died_this_run = false
	hp_changed.emit(hp)
	o2_changed.emit(o2)
	ammo_changed.emit(ammo)


## Множитель среды узла (пусто — текущий модуль игрока): 0 в модуле с
## воздухом, o2_unsealed_multiplier без давления, иначе 1.
func environment_multiplier(node_id: String = "") -> float:
	var target := node_id if node_id != "" else LocationSystem.current_node_id
	if target == "":
		return 1.0
	if LocationSystem.is_breathable(str(MapSystem.nodes.get(target, {}).get("location_id", ""))):
		return 0.0
	if MapSystem.is_node_sealed(target):
		return 1.0
	return o2_unsealed_multiplier


func _load_costs() -> void:
	var config := _load_res_json(CONFIG_PATH)
	o2_costs = DEFAULT_O2_COSTS.duplicate()
	var costs = config.get("o2_costs", {})
	if costs is Dictionary:
		for kind in costs.keys():
			if not DEFAULT_O2_COSTS.has(kind):
				push_warning("ResourceSystem: неизвестное действие в o2_costs — '%s'" % kind)
				continue
			o2_costs[str(kind)] = max(0.0, float(costs[kind]))
	o2_unsealed_multiplier = max(1.0, float(config.get("o2_unsealed_multiplier", DEFAULT_UNSEALED_MULTIPLIER)))


func _load_res_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("ResourceSystem: файл не найден %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func _trigger_death(cause: String) -> void:
	if _died_this_run:
		return
	_died_this_run = true
	resource_depleted.emit(cause)
	EventBus.player_died.emit(cause)
