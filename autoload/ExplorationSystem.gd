extends Node
## Исследование модуля: одна кнопка «Исследовать» вместо россыпи действий.
##
## У ручного события модуля может быть "discover": true — такое событие
## спрятано, пока его не найдут исследованием (текст находки — "found").
## У локации — "explore": { "pool", "rolls" }: сколько раз в ней можно
## наткнуться на случайное событие из пула data/explore_pools.json (каждое
## событие пула — не больше раза за модуль). Всего исследований в модуле —
## спрятанные события плюс rolls плюс бонус навыка (stat explore_rolls).
##
## GameState запрашивает план находки заранее, затем показывает несколько
## тактов поиска и списывает кислород за каждый. Число тактов задаётся полем
## explore.duration: [min, max] у локации. После анимации resolve() раскрывает
## событие или разыгрывает находку. Предметы из пула с шансом stat find_chance
## выпадают на один больше. Когда искать нечего — кнопка неактивна; спрятанное
## событие, чьи triggers ещё не выполнены, станет находкой позже.
##
## Состояние забега: reset_for_new_run / to_save_data / load_save_data.

const POOLS_PATH := "res://data/explore_pools.json"

var _pools: Dictionary = {}  # pool_id -> [entry]
var _discovered: Dictionary = {}  # "location_id/event_id" -> true
var _drawn: Dictionary = {}  # location_id -> [entry_id]


func _ready() -> void:
	if not FileAccess.file_exists(POOLS_PATH):
		push_warning("ExplorationSystem: файл не найден %s" % POOLS_PATH)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(POOLS_PATH))
	_pools = parsed if parsed is Dictionary else {}


func reset_for_new_run() -> void:
	_discovered.clear()
	_drawn.clear()


func is_discovered(location_id: String, event_id: String) -> bool:
	return _discovered.has("%s/%s" % [location_id, event_id])


## Сколько ещё раз можно исследовать модуль: спрятанные события (в том числе
## пока недоступные) и оставшиеся броски пула.
func remaining(location_id: String) -> int:
	return LocationSystem.hidden_event_count(location_id) + rolls_left(location_id)


## Всего исследований в модуле — для счётчика «осталось N из M».
func total(location_id: String) -> int:
	return LocationSystem.discover_event_count(location_id) + _rolls_total(location_id)


## Броски пула, которые ещё можно сделать (не больше, чем осталось событий в пуле).
func rolls_left(location_id: String) -> int:
	var drawn: Array = _drawn.get(location_id, [])
	var unused := 0
	for entry in _pool(location_id):
		if not drawn.has(str(entry.get("id", ""))):
			unused += 1
	return clampi(_rolls_total(location_id) - drawn.size(), 0, unused)


## Есть ли что найти прямо сейчас в текущем модуле.
func can_explore() -> bool:
	var location_id := LocationSystem.current_id
	return location_id != "" and (not LocationSystem.findable_events().is_empty() or not _pool_candidates(location_id).is_empty())


## Выбирает результат и длительность, но пока не меняет состояние. План
## фиксируется на всё время анимации, чтобы итог не сменился между тактами.
func prepare() -> Dictionary:
	var location_id := LocationSystem.current_id
	var findable := LocationSystem.findable_events()
	var candidates := _pool_candidates(location_id)
	if findable.is_empty() and candidates.is_empty():
		return {}
	var steps := _duration_steps(location_id)
	var reveal_event := candidates.is_empty() or (not findable.is_empty()
		and randi_range(1, findable.size() + rolls_left(location_id)) <= findable.size())
	if reveal_event:
		return {
			"kind": "event",
			"event_id": str(findable[randi_range(0, findable.size() - 1)].get("id", "")),
			"steps": steps,
		}
	return {"kind": "pool", "entry": _pick(candidates), "steps": steps}


## Применяет заранее выбранный план после анимации исследования.
func resolve(plan: Dictionary) -> void:
	if str(plan.get("kind", "")) == "event":
		reveal(str(plan.get("event_id", "")))
		return
	if str(plan.get("kind", "")) != "pool":
		return
	var entry: Dictionary = plan.get("entry", {})
	var location_id := LocationSystem.current_id
	var drawn: Array = _drawn.get(location_id, [])
	drawn.append(str(entry.get("id", "")))
	_drawn[location_id] = drawn
	NarrativeSystem.push("text", str(entry.get("text", "")))
	EffectResolver.apply_effects(_with_find_bonus(entry.get("effects", [])))


## Спрятанное событие текущего модуля найдено: текст находки в ленту, событие
## появляется в меню. Вызывает explore(); смоук-тест так раскрывает нужное сразу.
func reveal(event_id: String) -> void:
	var ev := LocationSystem.find_event(event_id)
	var key := "%s/%s" % [LocationSystem.current_id, event_id]
	if ev.is_empty() or _discovered.has(key):
		return
	_discovered[key] = true
	NarrativeSystem.push("text", str(ev.get("found", "Здесь есть кое-что интересное.")))
	NarrativeSystem.push("notice", "[Найдено: %s]" % str(ev.get("label", "")))


func to_save_data() -> Dictionary:
	return {"discovered": _discovered.keys(), "drawn": _drawn.duplicate(true)}


func load_save_data(data: Dictionary) -> void:
	_discovered.clear()
	var keys = data.get("discovered", [])
	if keys is Array:
		for key in keys:
			_discovered[str(key)] = true
	var drawn = data.get("drawn", {})
	_drawn = drawn.duplicate(true) if drawn is Dictionary else {}


func _duration_steps(location_id: String) -> int:
	var duration = LocationSystem.get_explore(location_id).get("duration", [3, 3])
	if not (duration is Array) or duration.size() != 2:
		return 3
	var minimum := maxi(1, int(duration[0]))
	var maximum := maxi(minimum, int(duration[1]))
	return randi_range(minimum, maximum)


func _rolls_total(location_id: String) -> int:
	var explore := LocationSystem.get_explore(location_id)
	if explore.is_empty():
		return 0
	return maxi(0, int(explore.get("rolls", 0)) + int(CharacterSystem.get_stat("explore_rolls")))


func _pool(location_id: String) -> Array:
	var pool = _pools.get(str(LocationSystem.get_explore(location_id).get("pool", "")), [])
	return pool if pool is Array else []


## События пула, которые ещё не выпадали в модуле и чьи requires выполнены.
func _pool_candidates(location_id: String) -> Array:
	if rolls_left(location_id) <= 0:
		return []
	var drawn: Array = _drawn.get(location_id, [])
	var result: Array = []
	for entry in _pool(location_id):
		if entry is Dictionary and not drawn.has(str(entry.get("id", ""))) \
				and EffectResolver.check_requirements(entry.get("requires", [])):
			result.append(entry)
	return result


func _pick(entries: Array) -> Dictionary:
	var total_weight := 0
	for entry in entries:
		total_weight += maxi(1, int(entry.get("weight", 1)))
	var roll := randi_range(1, total_weight)
	for entry in entries:
		roll -= maxi(1, int(entry.get("weight", 1)))
		if roll <= 0:
			return entry
	return entries[entries.size() - 1]


## Навык «Поиск»: каждая находка предмета с шансом find_chance — на один больше.
func _with_find_bonus(effects: Array) -> Array:
	var chance := CharacterSystem.get_stat("find_chance")
	var result: Array = []
	for effect in effects:
		var copy: Dictionary = (effect as Dictionary).duplicate()
		if str(copy.get("type", "")) == "item_add" and chance > 0.0 and randf() < chance:
			copy["count"] = int(copy.get("count", 1)) + 1
		result.append(copy)
	return result
