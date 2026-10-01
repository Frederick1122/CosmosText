extends Node
## Узловая карта сектора — см. tech-spec-v1.md раздел 6.
## Не переключает экраны сама — просит GameState (единственный владелец
## переходов между экранами, см. ТЗ раздел 10).
##
## Игрок стоит в узле (player_node_id) и ходит по связям узлов. Клик по
## отсеку на карте — это маршрут (plan_route): кратчайший по кислороду путь
## через разведанные незапертые узлы. Путь проходится шагами (travel_step):
## каждый шаг тратит кислород. Транзитный модуль останавливает игрока, только
## если при входе в него начнётся бой (враг в отсеке): игрок входит в модуль,
## и маршрут прерывается. Прочие автособытия по пути не срабатывают — они
## ждут, когда игрок войдёт сам. Побег из такого боя — прорыв: путь
## продолжается (resume_travel_after_flee). Отступление возвращает в
## предыдущий узел.

signal node_state_changed(node_id: String, state: String)
signal sector_loaded(sector_id: String)
signal floor_changed(floor_id: String)
signal fog_changed()
## Узел отказал в проходе (заперт, нет ключа) — UI показывает текст на карте.
signal node_blocked(node_id: String, message: String)
## Игрок проехал на лифте на палубу floor_id (смена палубы при загрузке сектора
## или сейва сюда не относится).
signal elevator_used(floor_id: String)
## Игрок перешёл из узла в узел (шаг маршрута, лифт, отступление).
signal player_moved(from_id: String, to_id: String)
## Маршрут начат, продвинулся, прерван или закончен.
signal travel_changed()

var current_sector_id: String = ""
var sector_title: String = ""
var hub_node_id: String = ""
var current_floor_id: String = ""
var map_config: Dictionary = {}
var nodes: Dictionary = {}  # node_id -> { title, location_id, connections, sealed, state, map }
var map_revealed: bool = false
## Узел, в котором стоит игрок, и откуда он туда пришёл (для отступления).
var player_node_id: String = ""
var _previous_node_id: String = ""
var _explored_nodes: Dictionary = {}  # node_id -> true
## Палубы, на которых игрок уже был: остальные на карте не показываются.
var _known_floors: Dictionary = {}  # floor_id -> true
## Маршрут: { target, path: [узлы без стартового], index — следующий шаг }.
var _travel: Dictionary = {}
## Маршрут прерван перехватом в модуле: ждёт, чем кончится встреча.
var _travel_suspended: bool = false

func load_sector(id: String) -> bool:
	var path := "res://data/sectors/%s.json" % id
	if not FileAccess.file_exists(path):
		push_error("MapSystem: файл сектора не найден '%s'" % id)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		push_error("MapSystem: битый файл сектора '%s'" % id)
		return false
	current_sector_id = parsed.get("id", id)
	sector_title = str(parsed.get("title", current_sector_id))
	hub_node_id = parsed.get("hub_node", "")
	var parsed_map = parsed.get("map", {})
	map_config = parsed_map if parsed_map is Dictionary else {}
	current_floor_id = _default_floor_id()
	var parsed_nodes = parsed.get("nodes", {})
	nodes = parsed_nodes if parsed_nodes is Dictionary else {}
	map_revealed = false
	_explored_nodes.clear()
	_known_floors.clear()
	_travel.clear()
	_travel_suspended = false
	_place_player(_start_node_id())
	sector_loaded.emit(current_sector_id)
	return true


## Новый сектор начинается в хабе (или в первом узле стартовой палубы).
func _start_node_id() -> String:
	if hub_node_id != "" and nodes.has(hub_node_id):
		return hub_node_id
	for node_id in nodes.keys():
		if nodes[node_id] is Dictionary and _node_floor_id(nodes[node_id]) == current_floor_id:
			return str(node_id)
	return ""


## Ставит игрока в узел без шага: старт сектора, загрузка сейва.
func _place_player(node_id: String) -> void:
	player_node_id = node_id
	_previous_node_id = ""
	if nodes.has(node_id) and nodes[node_id] is Dictionary:
		current_floor_id = _node_floor_id(nodes[node_id])
		_explored_nodes[node_id] = true
	if current_floor_id != "":
		_known_floors[current_floor_id] = true


func get_sector_title() -> String:
	return sector_title if sector_title != "" else current_sector_id


func get_map_config() -> Dictionary:
	return map_config.duplicate(true)


func get_current_floor_id() -> String:
	return current_floor_id


## Узлы для UI: данные контента + explored, unlockable, fog_visible и status
## (см. get_node_status).
func get_map_nodes(include_locked: bool = true) -> Array:
	var result: Array = []
	for node_id in nodes.keys():
		if not (nodes[node_id] is Dictionary):
			continue
		var data: Dictionary = nodes[node_id]
		if not include_locked and data.get("state", "locked") == "locked":
			continue
		var entry: Dictionary = data.duplicate(true)
		entry["id"] = node_id
		entry["explored"] = is_node_explored(str(node_id))
		entry["unlockable"] = can_unlock_node(str(node_id))
		entry["fog_visible"] = is_node_fog_visible(str(node_id))
		entry["status"] = get_node_status(str(node_id))
		result.append(entry)
	result.sort_custom(func(a, b): return _node_map_order(a) < _node_map_order(b))
	return result


func _node_map_order(node: Dictionary) -> int:
	var cfg = node.get("map", {})
	if cfg is Dictionary:
		return int(cfg.get("order", 0))
	return 0


## Что игрок знает об отсеке — по этому карта красит узел:
##   elevator — лифт; door — запертый узел (дверь под ключ);
##   unknown — ещё не был внутри; base — модуль-база (сохранение, склад);
##   hostile — встречен враг (узел dangerous); events — есть доступные
##   действия, что исследовать, ждущее событие или вещи на полу; locked — остались только
##   действия под ключ; empty — больше ничего нет.
func get_node_status(node_id: String) -> String:
	if not nodes.has(node_id) or not (nodes[node_id] is Dictionary):
		return "unknown"
	var node: Dictionary = nodes[node_id]
	var state := str(node.get("state", "locked"))
	if _is_elevator_node(node):
		return "elevator"
	if state == "locked":
		return "door"
	if not is_node_explored(node_id):
		return "unknown"
	var location_id := str(node.get("location_id", ""))
	if location_id != "" and LocationSystem.is_base(location_id):
		return "base"
	if state == "dangerous":
		return "hostile"
	if location_id == "":
		return "empty"
	var left := LocationSystem.peek(location_id)
	if int(left["open"]) > 0 or bool(left["auto"]) or bool(left["explore"]) or bool(left["stash"]):
		return "events"
	if int(left["locked"]) > 0:
		return "locked"
	return "empty"


# --- Маршруты и перемещение -----------------------------------------------------

## Маршрут из узла игрока в target_id, ничего не меняя:
##   { ok, target, path: [узлы без стартового], cost — кислород на весь путь,
##     message — почему пути нет }.
## Путь идёт только через разведанные и незапертые узлы; запертый узел может
## быть только целью, и только если ключ уже в сумке. Цель-лифт — это поездка:
## путь заканчивается в парном лифте на другой палубе. Цель — узел игрока —
## войти в модуль, где стоишь (путь пустой).
func plan_route(target_id: String) -> Dictionary:
	var plan := {"ok": false, "target": target_id, "path": [], "cost": 0.0, "message": ""}
	if not nodes.has(target_id) or not (nodes[target_id] is Dictionary):
		plan["message"] = "Такого отсека нет на схеме"
		return plan
	if not is_node_fog_visible(target_id):
		plan["message"] = "Дороги туда не знаешь"
		return plan
	var data: Dictionary = nodes[target_id]
	if str(data.get("state", "locked")) == "locked":
		var lock := get_node_lock(target_id)
		if lock.is_empty():
			plan["message"] = "%s: закрыто" % _node_title(target_id)
			return plan
		if not EffectResolver.can_open_lock(lock):
			# Незнакомый отсек не выдаёт, какой ключ ему нужен.
			var title := _node_title(target_id) if is_node_explored(target_id) else "Отсек"
			var hint := EffectResolver.lock_hint(lock) if is_node_explored(target_id) else "Заперто"
			plan["message"] = "%s: %s" % [title, hint]
			node_blocked.emit(target_id, plan["message"])
			return plan
	var path: Array = []
	if target_id != player_node_id:
		path = _shortest_path(player_node_id, target_id)
		if path.is_empty():
			plan["message"] = "Дороги к отсеку «%s» не знаешь" % _node_title(target_id)
			return plan
	elif str(data.get("location_id", "")) == "" and not _is_elevator_node(data):
		plan["message"] = "Ты уже здесь"
		return plan
	# Цель-лифт — значит, ехать: если к нему не приехали, добавляем поездку.
	var last_from := player_node_id if path.size() < 2 else str(path[path.size() - 2])
	if _is_elevator_node(data) and not _is_ride(last_from, target_id):
		var pair := _lift_pair(target_id)
		if pair == "":
			plan["message"] = "Лифт не отвечает"
			return plan
		if target_id == player_node_id:
			path = [pair]
		else:
			path.append(pair)
	var cost := path_cost(path)
	if path.is_empty():
		cost = _step_cost(player_node_id, player_node_id)
	plan["ok"] = true
	plan["path"] = path
	plan["cost"] = cost
	return plan


## Начинает маршрут (шаги делает travel_step). Возвращает план.
func start_travel(target_id: String) -> Dictionary:
	var plan := plan_route(target_id)
	if not bool(plan["ok"]):
		return plan
	_travel = {"target": target_id, "path": plan["path"], "index": 0}
	_travel_suspended = false
	travel_changed.emit()
	return plan


## Идти сразу до конца (без анимации): старт игры, смоук-тест.
func travel_to(target_id: String) -> Dictionary:
	var plan := start_travel(target_id)
	while is_travelling():
		travel_step()
	return plan


func is_travelling() -> bool:
	return not _travel.is_empty() and not _travel_suspended


## Копия маршрута для UI: { target, path, index } или пустой словарь.
func get_travel() -> Dictionary:
	return _travel.duplicate(true)


func cancel_travel() -> void:
	if _travel.is_empty() and not _travel_suspended:
		return
	_travel.clear()
	_travel_suspended = false
	travel_changed.emit()


## Один шаг маршрута. Итог:
##   moved   — прошли транзитный узел, путь продолжается;
##   arrived — дошли до цели вне модуля (лифт), путь окончен;
##   entered — вошли в модуль: цель или перехват в пути (экран уже сменил GameState);
##   dead    — кислород кончился в пути; idle — маршрута нет.
func travel_step() -> String:
	if not is_travelling():
		return "idle"
	var path: Array = _travel["path"]
	var index := int(_travel["index"])
	if path.is_empty():
		# Войти в модуль, где стоишь.
		_travel.clear()
		travel_changed.emit()
		return _enter_here(player_node_id)
	var from := player_node_id
	var to := str(path[index])
	var is_last := index == path.size() - 1
	var ride := _is_ride(from, to)
	if str(nodes[to].get("state", "locked")) == "locked" and not _open_node_lock(to):
		cancel_travel()
		return "idle"
	var paid := true
	if ride:
		paid = ResourceSystem.spend_o2("elevator", from)
	elif _has_location(to):
		paid = ResourceSystem.spend_o2("move", to)
	if not paid:
		cancel_travel()
		return "dead"
	_travel["index"] = index + 1
	_step_player(to)
	if ride:
		set_current_floor(_node_floor_id(nodes[to]))
		elevator_used.emit(current_floor_id)
	if _has_location(to) and (is_last or _would_intercept(to)):
		if is_last:
			_travel.clear()
		else:
			_travel_suspended = true
		travel_changed.emit()
		GameState.enter_location(str(nodes[to].get("location_id", "")), to)
		return "entered"
	if is_last:
		_travel.clear()
		travel_changed.emit()
		SaveManager.autosave()
		return "arrived"
	travel_changed.emit()
	return "moved"


## Бой, начатый перехватом в пути, кончился побегом: путь продолжается
## дальше от этого узла. false — продолжать нечего.
func resume_travel_after_flee() -> bool:
	if not _travel_suspended or _travel.is_empty() or int(_travel["index"]) >= _travel["path"].size():
		cancel_travel()
		return false
	_travel_suspended = false
	travel_changed.emit()
	return true


## Отступление: игрок не вошёл в отсек и стоит там, откуда пришёл.
func retreat() -> void:
	cancel_travel()
	if _previous_node_id == "" or not nodes.has(_previous_node_id):
		return
	var from := player_node_id
	player_node_id = _previous_node_id
	_previous_node_id = ""
	set_current_floor(_node_floor_id(nodes[player_node_id]))
	player_moved.emit(from, player_node_id)


## Кислород на путь path от узла игрока (оставшийся маршрут в UI).
func path_cost(path: Array) -> float:
	var cost := 0.0
	var from := player_node_id
	for step in path:
		cost += _step_cost(from, str(step))
		from = str(step)
	return cost


## Следующий шаг маршрута без исполнения — UI сначала ведёт фишку, потом
## делает шаг: { to — узел ("" — войти, где стоишь), ride — поездка на лифте }.
func peek_travel_step() -> Dictionary:
	if not is_travelling():
		return {}
	var path: Array = _travel["path"]
	var index := int(_travel["index"])
	if index >= path.size():
		return {"to": "", "ride": false}
	var to := str(path[index])
	return {"to": to, "ride": _is_ride(player_node_id, to)}


## Цена шага from → to: поездка на лифте — цена elevator по лифту отправления,
## вход в модуль — цена move по модулю (без давления дороже), лифты и
## переходы без модуля бесплатны.
func _step_cost(from: String, to: String) -> float:
	if _is_ride(from, to):
		return ResourceSystem.get_o2_cost("elevator", from)
	if _has_location(to):
		return ResourceSystem.get_o2_cost("move", to)
	return 0.0


## Дейкстра по кислороду (при равной цене — меньше шагов).
func _shortest_path(start_id: String, target_id: String) -> Array:
	if not nodes.has(start_id):
		return []
	var best := {start_id: [0.0, 0]}
	var came_from := {}
	var open := [start_id]
	while not open.is_empty():
		var current: String = open[0]
		for candidate in open:
			if _route_better(best[candidate], best[current]):
				current = candidate
		open.erase(current)
		if current == target_id:
			break
		for next_id in _neighbors(current):
			if next_id != target_id and not _is_passable(next_id):
				continue
			var score := [float(best[current][0]) + _step_cost(current, next_id), int(best[current][1]) + 1]
			if not best.has(next_id) or _route_better(score, best[next_id]):
				best[next_id] = score
				came_from[next_id] = current
				if not open.has(next_id):
					open.append(next_id)
	if not came_from.has(target_id):
		return []
	var path: Array = []
	var node_id := target_id
	while node_id != start_id:
		path.push_front(node_id)
		node_id = came_from[node_id]
	return path


func _route_better(a: Array, b: Array) -> bool:
	if not is_equal_approx(float(a[0]), float(b[0])):
		return float(a[0]) < float(b[0])
	return int(a[1]) < int(b[1])


func _neighbors(node_id: String) -> Array:
	var result: Array = []
	for other_id in nodes.keys():
		if str(other_id) != node_id and _nodes_are_adjacent(node_id, str(other_id)):
			result.append(str(other_id))
	return result


## Через узел можно пройти: он на схеме и не заперт.
func _is_passable(node_id: String) -> bool:
	return is_node_fog_visible(node_id) and str(nodes[node_id].get("state", "locked")) != "locked"


## Шаг между двумя лифтами разных палуб — поездка.
func _is_ride(from: String, to: String) -> bool:
	if not nodes.has(from) or not nodes.has(to):
		return false
	return _is_elevator_node(nodes[from]) and _is_elevator_node(nodes[to]) \
		and _node_floor_id(nodes[from]) != _node_floor_id(nodes[to])


## Парный лифт: связанный лифт на палубе target_floor.
func _lift_pair(lift_id: String) -> String:
	var target_floor := str(_node_map(nodes[lift_id]).get("target_floor", ""))
	for other_id in _neighbors(lift_id):
		var other: Dictionary = nodes[other_id]
		if _is_elevator_node(other) and _node_floor_id(other) == target_floor:
			return other_id
	return ""


func _has_location(node_id: String) -> bool:
	return nodes.has(node_id) and str(nodes[node_id].get("location_id", "")) != ""


func _node_title(node_id: String) -> String:
	return str(nodes[node_id].get("title", node_id))


func _step_player(node_id: String) -> void:
	var from := player_node_id
	_previous_node_id = from
	player_node_id = node_id
	mark_explored(node_id)
	player_moved.emit(from, node_id)


## Транзитный модуль перехватывает игрока, только если при входе в него
## начнётся бой. Находки и сообщения подождут, пока игрок войдёт сам.
func _would_intercept(node_id: String) -> bool:
	return bool(LocationSystem.peek(str(nodes[node_id].get("location_id", "")), true)["combat"])


## Вход в модуль, в котором игрок уже стоит, — по цене перехода.
func _enter_here(node_id: String) -> String:
	if not _has_location(node_id):
		return "idle"
	if not ResourceSystem.spend_o2("move", node_id):
		return "dead"
	GameState.enter_location(str(nodes[node_id].get("location_id", "")), node_id)
	return "entered"


## Запертый узел на пути открывается ключом из сумки (план это проверил).
func _open_node_lock(node_id: String) -> bool:
	var lock := get_node_lock(node_id)
	if lock.is_empty() or not EffectResolver.can_open_lock(lock):
		return false
	var key_name := EffectResolver.open_lock(lock)
	unlock_node(node_id)
	var opened := str(lock.get("text", "Замок поддался."))
	if key_name != "":
		opened += " (%s)" % key_name
	JournalSystem.add("event", "%s: %s" % [_node_title(node_id), opened])
	return true

## Загерметизирован ли узел: в разгерметизированном действия дороже по O2.
func is_node_sealed(node_id: String) -> bool:
	if not nodes.has(node_id) or not (nodes[node_id] is Dictionary):
		return true
	return bool(nodes[node_id].get("sealed", true))


## Замок узла: { "key": "<id замка>", "consume": bool, "text": "..." }.
func get_node_lock(node_id: String) -> Dictionary:
	if not nodes.has(node_id) or not (nodes[node_id] is Dictionary):
		return {}
	var lock = nodes[node_id].get("lock", {})
	return lock if lock is Dictionary else {}


## Заперт, но подходящий ключ уже в сумке — карта подсвечивает такой узел.
func can_unlock_node(node_id: String) -> bool:
	if not nodes.has(node_id) or str(nodes[node_id].get("state", "locked")) != "locked":
		return false
	var lock := get_node_lock(node_id)
	return not lock.is_empty() and EffectResolver.can_open_lock(lock)


## Открывает узел и возвращает его название. Пустая строка означает, что
## узел не существовал или уже был открыт.
func unlock_node(node_id: String) -> String:
	if not nodes.has(node_id) or not (nodes[node_id] is Dictionary):
		push_warning("MapSystem: неизвестный узел '%s'" % node_id)
		return ""
	if str(nodes[node_id].get("state", "locked")) != "locked":
		return ""
	var title := str(nodes[node_id].get("title", node_id))
	set_node_state(node_id, "available")
	return title


func set_node_state(node_id: String, state: String) -> void:
	if not nodes.has(node_id):
		push_warning("MapSystem: неизвестный узел '%s'" % node_id)
		return
	nodes[node_id]["state"] = state
	node_state_changed.emit(node_id, state)


func mark_cleared(node_id: String) -> void:
	set_node_state(node_id, "cleared")


func set_current_floor(floor_id: String) -> void:
	if floor_id == "":
		return
	if not _is_valid_floor_id(floor_id):
		push_warning("MapSystem: неизвестная палуба '%s'" % floor_id)
		return
	if current_floor_id == floor_id:
		return
	current_floor_id = floor_id
	_known_floors[floor_id] = true
	_explore_floor_elevators(floor_id)
	floor_changed.emit(current_floor_id)


func to_save_data() -> Dictionary:
	var node_states := {}
	for node_id in nodes.keys():
		if not (nodes[node_id] is Dictionary):
			continue
		node_states[node_id] = {
			"state": nodes[node_id].get("state", "locked"),
		}
	return {
		"sector_id": current_sector_id,
		"current_floor_id": current_floor_id,
		"player_node": player_node_id,
		"previous_node": _previous_node_id,
		"known_floors": _known_floors.keys(),
		"nodes": node_states,
		"explored_nodes": _explored_nodes.keys(),
		"map_revealed": map_revealed,
	}


## Маршрут в сейв не пишется: после загрузки игрок стоит в своём узле.
func load_save_data(data: Dictionary, fallback_sector_id: String = "wreck_01") -> bool:
	var sector_id: String = data.get("sector_id", fallback_sector_id)
	if sector_id == "":
		sector_id = fallback_sector_id
	if not load_sector(sector_id):
		return false
	var saved_floor_id := str(data.get("current_floor_id", current_floor_id))
	if _is_valid_floor_id(saved_floor_id):
		current_floor_id = saved_floor_id

	var saved_nodes = data.get("nodes", {})
	if saved_nodes is Dictionary:
		for node_id in saved_nodes.keys():
			if nodes.has(node_id) and saved_nodes[node_id] is Dictionary:
				var saved_node: Dictionary = saved_nodes[node_id]
				if saved_node.has("state"):
					nodes[node_id]["state"] = saved_node["state"]

	map_revealed = bool(data.get("map_revealed", false))
	_explored_nodes.clear()
	var saved_explored = data.get("explored_nodes", null)
	if saved_explored is Array:
		for node_id in saved_explored:
			if nodes.has(str(node_id)):
				_explored_nodes[str(node_id)] = true
	elif saved_explored is Dictionary:
		for node_id in saved_explored.keys():
			if bool(saved_explored[node_id]) and nodes.has(str(node_id)):
				_explored_nodes[str(node_id)] = true
	else:
		# Старые сохранения не знали о тумане: восстановим посещённые узлы
		# по состоянию и всегда оставим стартовую капсулу видимой.
		for node_id in nodes.keys():
			if str(node_id) == hub_node_id or str(nodes[node_id].get("state", "locked")) != "locked":
				_explored_nodes[str(node_id)] = true
	if hub_node_id != "" and nodes.has(hub_node_id):
		_explored_nodes[hub_node_id] = true

	# Сейвы без положения игрока: он у хаба своей палубы или у её лифта.
	var saved_player := str(data.get("player_node", ""))
	if not nodes.has(saved_player):
		saved_player = _fallback_player_node()
	_known_floors.clear()
	_place_player(saved_player)
	var saved_previous := str(data.get("previous_node", ""))
	_previous_node_id = saved_previous if nodes.has(saved_previous) else ""
	var saved_floors = data.get("known_floors", null)
	if saved_floors is Array:
		for floor_id in saved_floors:
			if _is_valid_floor_id(str(floor_id)):
				_known_floors[str(floor_id)] = true
	else:
		for node_id in _explored_nodes.keys():
			_known_floors[_node_floor_id(nodes[node_id])] = true
	return true


func _fallback_player_node() -> String:
	if hub_node_id != "" and nodes.has(hub_node_id) and _node_floor_id(nodes[hub_node_id]) == current_floor_id:
		return hub_node_id
	for node_id in nodes.keys():
		var node: Dictionary = nodes[node_id]
		if _node_floor_id(node) == current_floor_id and _is_elevator_node(node) and is_node_explored(str(node_id)):
			return str(node_id)
	return _start_node_id()


func is_node_explored(node_id: String) -> bool:
	return _explored_nodes.has(node_id)


func mark_explored(node_id: String) -> void:
	if node_id == "" or not nodes.has(node_id) or _explored_nodes.has(node_id):
		return
	_explored_nodes[node_id] = true
	fog_changed.emit()


func reveal_map() -> void:
	if map_revealed:
		return
	map_revealed = true
	fog_changed.emit()


func get_node_floor_id(node_id: String) -> String:
	return _node_floor_id(nodes[node_id]) if nodes.has(node_id) and nodes[node_id] is Dictionary else ""


func get_floor_title(floor_id: String) -> String:
	for floor in map_config.get("floors", []):
		if floor is Dictionary and str(floor.get("id", "")) == floor_id:
			return str(floor.get("title", floor_id))
	return floor_id


## Палубы, на которых игрок уже побывал, в порядке из конфига сектора.
func get_known_floor_ids() -> Array:
	var result: Array = []
	for floor_id in _all_floor_ids():
		if _known_floors.has(floor_id):
			result.append(floor_id)
	if result.is_empty() and current_floor_id != "":
		result.append(current_floor_id)
	return result


## Видно узел, если в нём были, или он на знакомой палубе и найдена схема,
## или он соседний с разведанным. Палубы, где игрок не был, скрыты целиком.
func is_node_fog_visible(node_id: String) -> bool:
	if not nodes.has(node_id) or not (nodes[node_id] is Dictionary):
		return false
	var node: Dictionary = nodes[node_id]
	var node_map := _node_map(node)
	# Секретные отсеки не выдаёт ни соседство, ни найденная схема:
	# их впервые показывает только действие с open_map_node.
	if (
		bool(node_map.get("hidden_until_open", false))
		and str(node.get("state", "locked")) == "locked"
		and not is_node_explored(node_id)
	):
		return false
	if is_node_explored(node_id):
		return true
	if not _known_floors.has(_node_floor_id(node)):
		return false
	if map_revealed:
		return true
	for explored_id in _explored_nodes.keys():
		if _nodes_are_adjacent(str(explored_id), node_id):
			return true
	return false


func _nodes_are_adjacent(first_id: String, second_id: String) -> bool:
	if not nodes.has(first_id) or not nodes.has(second_id):
		return false
	var first_connections = nodes[first_id].get("connections", [])
	if first_connections is Array and first_connections.has(second_id):
		return true
	var second_connections = nodes[second_id].get("connections", [])
	return second_connections is Array and second_connections.has(first_id)


func _explore_floor_elevators(floor_id: String) -> void:
	var changed := false
	for node_id in nodes.keys():
		if not (nodes[node_id] is Dictionary):
			continue
		var node: Dictionary = nodes[node_id]
		if _node_floor_id(node) == floor_id and _is_elevator_node(node) and not is_node_explored(str(node_id)):
			_explored_nodes[str(node_id)] = true
			changed = true
	if changed:
		fog_changed.emit()


func _all_floor_ids() -> Array:
	var result: Array = []
	var floors = map_config.get("floors", [])
	if floors is Array:
		for floor in floors:
			if floor is Dictionary:
				var floor_id := str(floor.get("id", ""))
				if floor_id != "":
					result.append(floor_id)
	return result


func _is_elevator_node(node: Dictionary) -> bool:
	return str(_node_map(node).get("kind", "")) == "elevator"


func _node_map(node: Dictionary) -> Dictionary:
	var cfg = node.get("map", {})
	return cfg if cfg is Dictionary else {}


func _node_floor_id(node: Dictionary) -> String:
	var floor_id := str(_node_map(node).get("floor", ""))
	if floor_id == "":
		return _default_floor_id()
	return floor_id


func _default_floor_id() -> String:
	var configured := str(map_config.get("default_floor", ""))
	if configured != "":
		return configured
	var floors = map_config.get("floors", [])
	if floors is Array:
		for floor in floors:
			if floor is Dictionary:
				var floor_id := str(floor.get("id", ""))
				if floor_id != "":
					return floor_id
	return ""


func _is_valid_floor_id(floor_id: String) -> bool:
	var floors = map_config.get("floors", [])
	if not (floors is Array) or floors.is_empty():
		return true
	for floor in floors:
		if floor is Dictionary and str(floor.get("id", "")) == floor_id:
			return true
	return false
