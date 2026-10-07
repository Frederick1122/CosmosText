extends Node
## Глобальная карта системы: узлы на гексагональной сетке (планеты, скопления
## астероидов, станции, обломки), топливо корабля и время перелёта.
##
## Данные — `data/galaxy.json` (схема в docs/CONTENT.md). Узел с `sector_id`
## ведёт в сектор карты отсеков; узел без него — точка интереса, к которой
## лететь некуда (панель объясняет почему).
##
## Сам ничего не переключает: перелёт заканчивается сигналом `arrived`, и только
## GameState грузит сектор. Топливо — состояние забега (run.json), время считает
## NeedsSystem по `advance_time`.
##
## Корабль появляется не сразу: флаг из `ship.unlock_flag` (контент, не код)
## означает, что герой уже сидит за штурвалом.

signal changed()
## Перелёт завершён: GameState грузит сектор узла node_id.
signal arrived(node_id: String)

const DATA_PATH := "res://data/galaxy.json"
const DEFAULT_SHIP := {
	"unlock_flag": "",
	"start_node": "",
	"start_fuel": 60.0,
	"max_fuel": 100.0,
	"fuel_per_hex": 4.0,
	"hours_per_hex": 3.0,
	"hunger_per_hour": 2.0,
}

var system_id: String = ""
var system_title: String = ""
var hex_size: float = 96.0
var nodes: Dictionary = {}  # node_id -> данные узла с q/r
var current_node_id: String = ""
var fuel: float = 0.0
var max_fuel: float = 100.0

var ship: Dictionary = DEFAULT_SHIP.duplicate(true)
## Узлы, где герой уже был — для подписи «вы здесь были» на карте.
var _visited: Dictionary = {}


func _ready() -> void:
	_load()
	# Единственная точка синхронизации: корабль стоит в узле загруженного сектора
	# (новая игра, загрузка сейва, отступление, прилёт — все пути идут через
	# MapSystem.load_sector).
	MapSystem.sector_loaded.connect(sync_node_for_sector)


func reset_for_new_run() -> void:
	system_id = ""
	system_title = ""
	hex_size = 96.0
	nodes.clear()
	current_node_id = ""
	fuel = 0.0
	max_fuel = 100.0
	ship = DEFAULT_SHIP.duplicate(true)
	_visited.clear()
	_load()
	changed.emit()


func get_title() -> String:
	return system_title


## Корабль есть: герой сел за штурвал (флаг из контента).
func has_ship() -> bool:
	var flag := str(ship.get("unlock_flag", ""))
	return flag != "" and SituationEngine.get_flag(flag)


func start_node_id() -> String:
	var configured := str(ship.get("start_node", ""))
	if configured != "" and nodes.has(configured):
		return configured
	return current_node_id


func is_visited(node_id: String) -> bool:
	return _visited.has(node_id)


## Узлы для экрана: координаты гекса уже переведены в пиксели, стоимость
## перелёта и доступность посчитаны.
func get_nodes() -> Array:
	var result: Array = []
	for node_id in nodes.keys():
		result.append(get_node_data(str(node_id)))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("title", "")) < str(b.get("title", "")))
	return result


func get_node_data(node_id: String) -> Dictionary:
	var data: Dictionary = nodes.get(node_id, {})
	if data.is_empty():
		return {}
	var distance := hex_distance(current_node_id, node_id)
	return {
		"id": node_id,
		"q": int(data.get("q", 0)),
		"r": int(data.get("r", 0)),
		"type": str(data.get("type", "planet")),
		"title": str(data.get("title", node_id)),
		"note": str(data.get("note", "")),
		"description": str(data.get("description", "")),
		"sector_id": str(data.get("sector_id", "")),
		"distance": distance,
		"fuel": travel_fuel(node_id),
		"hours": travel_hours(node_id),
		"available": is_available(node_id),
		"reachable": can_reach(node_id),
		"here": node_id == current_node_id,
		"visited": is_visited(node_id),
		"x": hex_to_pixel(int(data.get("q", 0)), int(data.get("r", 0))).x,
		"y": hex_to_pixel(int(data.get("q", 0)), int(data.get("r", 0))).y,
	}


## Узел существует для игрока: выполнены его `requires`.
func is_available(node_id: String) -> bool:
	var data: Dictionary = nodes.get(node_id, {})
	if data.is_empty():
		return false
	return EffectResolver.check_requirements(_as_array(data.get("requires", [])))


func is_travelable(node_id: String) -> bool:
	var data: Dictionary = nodes.get(node_id, {})
	return not data.is_empty() and str(data.get("sector_id", "")) != "" \
		and is_available(node_id) and node_id != current_node_id


func travel_fuel(node_id: String) -> float:
	var data: Dictionary = nodes.get(node_id, {})
	if data.has("fuel_cost"):
		return maxf(0.0, float(data["fuel_cost"]))
	return float(ship.get("fuel_per_hex", DEFAULT_SHIP["fuel_per_hex"])) \
		* float(maxi(1, hex_distance(current_node_id, node_id)))


func travel_hours(node_id: String) -> int:
	var data: Dictionary = nodes.get(node_id, {})
	if data.has("hours"):
		return maxi(1, int(data["hours"]))
	return maxi(1, int(round(float(ship.get("hours_per_hex", DEFAULT_SHIP["hours_per_hex"])) \
		* float(maxi(1, hex_distance(current_node_id, node_id))))))


func can_reach(node_id: String) -> bool:
	return is_travelable(node_id) and fuel + 0.001 >= travel_fuel(node_id)


## План перелёта для панели: { ok, message, ... } — по образцу MapSystem.plan_route.
func plan_travel(node_id: String) -> Dictionary:
	var plan := {"ok": false, "node": node_id, "message": "", "fuel": 0.0, "hours": 0, "distance": 0}
	var node := get_node_data(node_id)
	if node.is_empty():
		plan["message"] = "Такой точки на карте нет"
		return plan
	if not has_ship():
		plan["message"] = "Корабль недоступен"
		return plan
	if not is_available(node_id):
		plan["message"] = "Данных об этой точке нет — маршрут не рассчитан"
		return plan
	if not is_travelable(node_id):
		plan["message"] = "Сюда не летят: нет посадки"
		return plan
	plan["fuel"] = travel_fuel(node_id)
	plan["hours"] = travel_hours(node_id)
	plan["distance"] = int(node.get("distance", 0))
	if fuel + 0.001 < float(plan["fuel"]):
		plan["message"] = "Мало топлива: нужно %.0f, в баке %.0f" % [plan["fuel"], fuel]
		return plan
	plan["ok"] = true
	return plan


## Летим: топливо, часы и голод, затем сигнал arrived — сектор грузит GameState.
func travel_to(node_id: String) -> bool:
	var plan := plan_travel(node_id)
	if not bool(plan["ok"]):
		return false
	var node := get_node_data(node_id)
	var cost := float(plan["fuel"])
	var hours := int(plan["hours"])
	apply_fuel_delta(-cost)
	EffectResolver.report_change("fuel", -cost, "топлива", true)
	var hunger := float(hours) * float(ship.get("hunger_per_hour", DEFAULT_SHIP["hunger_per_hour"]))
	EffectResolver.report_change("hunger", NeedsSystem.apply_hunger_delta(hunger), "голода")
	NeedsSystem.advance_time(hours * 60)
	current_node_id = node_id
	_visited[node_id] = true
	JournalSystem.add("move", "Перелёт: %s — %d ч, %.0f топлива" % [str(node.get("title", node_id)), hours, cost])
	changed.emit()
	arrived.emit(node_id)
	return true


## Топливо корабля (эффект fuel_delta, баки в контенте).
func apply_fuel_delta(value: float) -> float:
	var before := fuel
	fuel = clampf(fuel + value, 0.0, max_fuel)
	if not is_equal_approx(fuel, before):
		changed.emit()
	return fuel - before


## Расстояние по гексам между двумя узлами (перелёт — всегда из текущего узла).
func hex_distance(from_id: String, to_id: String) -> int:
	if from_id == "" or not nodes.has(from_id) or not nodes.has(to_id):
		return 0
	var a: Dictionary = nodes[from_id]
	var b: Dictionary = nodes[to_id]
	var dq := int(b.get("q", 0)) - int(a.get("q", 0))
	var dr := int(b.get("r", 0)) - int(a.get("r", 0))
	return int((absi(dq) + absi(dr) + absi(dq + dr)) / 2)


## Гекс → пиксели: плоская раскладка (axial), шаг по X — 1.5 стороны.
func hex_to_pixel(q: int, r: int) -> Vector2:
	var width := hex_size * 1.5
	var height := hex_size * sqrt(3.0)
	return Vector2(width * float(q), height * (float(r) + float(q) * 0.5))


## Сектор загружен — корабль стоит в его узле: положение на карте системы не
## расходится с картой отсеков (новая игра, загрузка сейва, отступление).
func sync_node_for_sector(sector_id: String) -> void:
	if sector_id == "":
		return
	for node_id in nodes.keys():
		if str((nodes[node_id] as Dictionary).get("sector_id", "")) == sector_id:
			current_node_id = str(node_id)
			_visited[str(node_id)] = true
			changed.emit()
			return


func to_save_data() -> Dictionary:
	return {
		"system": system_id,
		"node": current_node_id,
		"fuel": fuel,
		"visited": _visited.keys(),
	}


func load_save_data(data: Dictionary) -> void:
	_visited.clear()
	for id in _as_array(data.get("visited", [])):
		_visited[str(id)] = true
	var saved_fuel = data.get("fuel", null)
	if saved_fuel != null:
		fuel = clampf(float(saved_fuel), 0.0, max_fuel)
	if str(data.get("system", "")) != "" and str(data["system"]) != system_id:
		_load(str(data["system"]))
	var node := str(data.get("node", ""))
	if node != "" and nodes.has(node):
		current_node_id = node
	elif current_node_id == "":
		current_node_id = start_node_id()
	changed.emit()


func _load(system_id_wanted: String = "") -> void:
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("GalaxySystem: файл не найден %s" % DATA_PATH)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not (parsed is Dictionary):
		push_warning("GalaxySystem: битый %s" % DATA_PATH)
		return
	var data: Dictionary = parsed
	if system_id_wanted != "" and str(data.get("id", "")) != system_id_wanted:
		push_warning("GalaxySystem: в %s нет системы '%s'" % [DATA_PATH, system_id_wanted])
	system_id = str(data.get("id", ""))
	system_title = str(data.get("title", system_id))
	hex_size = maxf(16.0, float(data.get("hex_size", 96.0)))
	var ship_data = data.get("ship", {})
	ship = DEFAULT_SHIP.duplicate(true)
	if ship_data is Dictionary:
		for key in ship_data.keys():
			if DEFAULT_SHIP.has(key):
				ship[key] = ship_data[key]
			else:
				push_warning("GalaxySystem: неизвестный ключ ship.%s" % key)
	max_fuel = maxf(1.0, float(ship.get("max_fuel", DEFAULT_SHIP["max_fuel"])))
	nodes.clear()
	var node_data = data.get("nodes", {})
	if node_data is Dictionary:
		for node_id in node_data.keys():
			var node = node_data[node_id]
			if not (node is Dictionary):
				push_warning("GalaxySystem: узел '%s' должен быть объектом" % node_id)
				continue
			nodes[str(node_id)] = node
	if fuel <= 0.0:
		fuel = clampf(float(ship.get("start_fuel", DEFAULT_SHIP["start_fuel"])), 0.0, max_fuel)
	if current_node_id == "" or not nodes.has(current_node_id):
		current_node_id = start_node_id()
	if current_node_id != "":
		_visited[current_node_id] = true
	changed.emit()


func _as_array(value) -> Array:
	return value if value is Array else []
