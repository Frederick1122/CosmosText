extends Node
## Время, силы, голод и отдых. Каждое действие игрока (те же виды, что у
## кислорода: move, elevator, action, choice, combat_turn —
## ResourceSystem.action_taken) продвигает часы с шагом пять минут, отнимает
## силы и прибавляет голода; цены — data/config.json → "needs".
##
##   Время  — день и минуты суток. Переход через 24:00 увеличивает день.
##   Силы   — max_energy → 0. Ниже tired_energy игрок измотан: в бою штраф к
##            точности. На нуле вне боя игрок вырубается прямо там, где стоит:
##            теряет кислород, четыре часа и получает плохой сон.
##   Голод  — 0 → max_hunger. От hungry_hunger силы тратятся быстрее
##            (hungry_energy_multiplier), на максимуме каждое действие отнимает
##            starving_hp здоровья. Голод снимает еда (эффект hunger_delta).
##   Сон    — 4 / 8 / 12 часов. Качество задаёт место: база даёт нормальное,
##            обморок — плохое; хорошие уровни оставлены для будущих модулей.
##
## Состояние забега: reset_for_new_run / to_save_data / load_save_data.

## Время, силы или голод изменились.
signal changed()
## Игрок вырубился от усталости (o2 — сколько кислорода ушло, пока лежал).
signal passed_out(o2: float)
## Сон или обморок завершён; результат нужен итоговой плашке UI.
signal rest_completed(result: Dictionary)

const CONFIG_PATH := "res://data/config.json"
const DEFAULT_CONFIG := {
	"max_energy": 100,
	"max_hunger": 100,
	"start_time_minutes": 480,
	"time_costs": {"move": 10, "elevator": 5, "action": 15, "choice": 5, "combat_turn": 5},
	"energy_costs": {"move": 3, "elevator": 1, "action": 2, "choice": 1, "combat_turn": 2},
	"hunger_costs": {"move": 1, "elevator": 0.5, "action": 1, "choice": 0.5, "combat_turn": 0.5},
	"tired_energy": 25,
	"tired_hit_penalty": 0.15,
	"hungry_hunger": 75,
	"hungry_energy_multiplier": 1.5,
	"starving_hp": 3,
	"sleep_energy_per_hour": 12.5,
	"sleep_hunger_per_hour": 2,
	"sleep_hp_per_hour": 1.25,
	"pass_out_hours": 4,
	"pass_out_o2": 30,
	"pass_out_hunger": 10,
}
const SLEEP_QUALITIES := {
	"poor": {"title": "Плохое", "energy": 0.6, "hp": 0.1},
	"normal": {"title": "Нормальное", "energy": 1.0, "hp": 1.0},
	"good": {"title": "Хорошее", "energy": 1.15, "hp": 1.25},
	"excellent": {"title": "Превосходное", "energy": 1.3, "hp": 1.5},
}

var day: int = 1
var time_minutes: int = 480
var energy: float = 100.0
var hunger: float = 0.0

var _config: Dictionary = DEFAULT_CONFIG.duplicate(true)


func _ready() -> void:
	_load_config()
	ResourceSystem.action_taken.connect(_on_action_taken)


func reset_for_new_run() -> void:
	day = 1
	time_minutes = _snap_minutes(int(_config["start_time_minutes"]))
	energy = max_energy()
	hunger = 0.0
	changed.emit()


func max_energy() -> float:
	return float(_config["max_energy"])


func max_hunger() -> float:
	return float(_config["max_hunger"])


## Текущее время в формате 08:05.
func clock_text() -> String:
	return "%02d:%02d" % [floori(float(time_minutes) / 60.0), time_minutes % 60]


## Цена действия во внутриигровых минутах. Любое значение округляется к шагу 5.
func action_minutes(kind: String) -> int:
	return _snap_minutes(int(_config["time_costs"].get(kind, 0)))

func pass_out_hours() -> int:
	return maxi(1, int(_config["pass_out_hours"]))

func sleep_quality_title(quality: String) -> String:
	return str(SLEEP_QUALITIES.get(quality, SLEEP_QUALITIES["normal"])["title"])


## Публичный переход времени для сценарных систем.
func advance_time(minutes: int) -> void:
	_advance_time(minutes)
	changed.emit()

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


## Сон с качеством места. Возвращает фактическое восстановление ресурсов для
## итоговой плашки; чекпойнт после сна пишет GameState.sleep.
func sleep(hours: int, quality: String = "normal") -> Dictionary:
	hours = maxi(1, hours)
	if not SLEEP_QUALITIES.has(quality):
		quality = "normal"
	var quality_data: Dictionary = SLEEP_QUALITIES[quality]
	var start_day := day
	var start_time := time_minutes
	var energy_before := energy
	var hunger_before := hunger
	var hp_before := ResourceSystem.hp
	_advance_time(hours * 60)
	energy = minf(max_energy(), energy + float(hours) * float(_config["sleep_energy_per_hour"]) \
		* float(quality_data["energy"]))
	var hunger_delta := apply_hunger_delta(float(hours) * float(_config["sleep_hunger_per_hour"]))
	var hp_gain := roundi(float(hours) * float(_config["sleep_hp_per_hour"]) * float(quality_data["hp"]))
	ResourceSystem.apply_hp_delta(hp_gain)
	changed.emit()
	var result := _rest_result(start_day, start_time, hours, quality, false,
		energy - energy_before, hunger - hunger_before, ResourceSystem.hp - hp_before)
	NarrativeSystem.push("notice", "Сон: %d ч. Качество — %s. Сейчас день %d, %s." % [
		hours, str(quality_data["title"]).to_lower(), day, clock_text()])
	EffectResolver.report_change("hunger", hunger_delta, "голода", true)
	EffectResolver.report_change("hp", ResourceSystem.hp - hp_before, "HP")
	JournalSystem.add("rest", "Сон %d ч. (%s). День %d, %s" % [
		hours, str(quality_data["title"]).to_lower(), day, clock_text()])
	rest_completed.emit(result)
	return result


func to_save_data() -> Dictionary:
	return {"day": day, "time_minutes": time_minutes, "energy": energy, "hunger": hunger}


func load_save_data(data: Dictionary) -> void:
	day = maxi(1, int(data.get("day", 1)))
	time_minutes = _snap_minutes(int(data.get("time_minutes", _config["start_time_minutes"])))
	energy = clampf(float(data.get("energy", max_energy())), 0.0, max_energy())
	hunger = clampf(float(data.get("hunger", 0.0)), 0.0, max_hunger())
	changed.emit()


## Цена действия: силы и голод. Голод на максимуме бьёт по здоровью, силы на
## нуле вне боя — обморок.
func _on_action_taken(kind: String) -> void:
	_advance_time(action_minutes(kind))
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


## Силы на нуле вне боя: игрок вырубается и спит pass_out_hours часов плохим
## сном (SLEEP_QUALITIES.poor) — силы почти не возвращаются, здоровья он
## получает крохи. Сверх сна он тратит кислород и просыпается голоднее.
func _pass_out() -> void:
	var hours := pass_out_hours()
	var poor: Dictionary = SLEEP_QUALITIES["poor"]
	var start_day := day
	var start_time := time_minutes
	var energy_before := energy
	var hunger_before := hunger
	var hp_before := ResourceSystem.hp
	_advance_time(hours * 60)
	energy = minf(max_energy(), energy + float(hours) * float(_config["sleep_energy_per_hour"]) \
		* float(poor["energy"]))
	hunger = minf(max_hunger(), hunger + float(_config["pass_out_hunger"]))
	ResourceSystem.apply_hp_delta(roundi(float(hours) * float(_config["sleep_hp_per_hour"]) * float(poor["hp"])))
	changed.emit()
	NarrativeSystem.push("notice", "Силы кончились: вы проваливаетесь в плохой сон прямо здесь и приходите в себя через %d ч." % hours)
	EffectResolver.report_change("hunger", hunger - hunger_before, "голода", true)
	EffectResolver.report_change("hp", ResourceSystem.hp - hp_before, "HP")
	JournalSystem.add("rest", "Обморок от усталости: плохой сон %d ч. День %d, %s" % [hours, day, clock_text()])
	var o2 := float(_config["pass_out_o2"]) * ResourceSystem.environment_multiplier()
	var o2_before := ResourceSystem.o2
	ResourceSystem.apply_o2_delta(-o2)
	EffectResolver.report_change("o2", ResourceSystem.o2 - o2_before, "O2")
	if not ResourceSystem.is_dead():
		rest_completed.emit(_rest_result(start_day, start_time, hours, "poor", true,
			energy - energy_before, hunger - hunger_before, ResourceSystem.hp - hp_before))
	passed_out.emit(o2_before - ResourceSystem.o2)


func _in_combat() -> bool:
	return CombatSystem.state == CombatSystem.State.PLAYER_TURN or CombatSystem.state == CombatSystem.State.RESOLVING

func _advance_time(minutes: int) -> void:
	var elapsed := _snap_minutes(minutes)
	if elapsed <= 0:
		return
	var total := time_minutes + elapsed
	day += floori(float(total) / 1440.0)
	time_minutes = total % 1440


func _snap_minutes(minutes: int) -> int:
	return clampi(int(round(float(maxi(0, minutes)) / 5.0)) * 5, 0, 1435)


func _rest_result(start_day: int, start_time: int, hours: int, quality: String,
		forced: bool, energy_restored: float, nutrition_spent: float, hp_restored: int) -> Dictionary:
	var quality_data: Dictionary = SLEEP_QUALITIES.get(quality, SLEEP_QUALITIES["normal"])
	return {
		"start_day": start_day,
		"start_time": start_time,
		"hours": hours,
		"quality": quality,
		"quality_title": str(quality_data["title"]),
		"forced": forced,
		"energy_restored": maxf(0.0, energy_restored),
		"nutrition_spent": maxf(0.0, nutrition_spent),
		"hp_restored": maxi(0, hp_restored),
		"end_day": day,
		"end_time": time_minutes,
	}


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
