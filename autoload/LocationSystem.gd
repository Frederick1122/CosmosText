extends Node
## Локации (модули корабля). Узел карты с location_id ведёт в локацию:
## базовое описание (+ варианты по условиям), набор событий и функции
## инвентаря. В локацию можно возвращаться сколько угодно раз.
##
## Событие:
##   start: "auto"   — стартует само при входе/возврате в локацию, если
##                     выполнены triggers (не чаще раза за визит);
##          "manual" — пункт меню модуля, игрок запускает его сам.
##   repeatable: false — одноразовое (после запуска больше не доступно),
##               true  — повторяемое.
##   Тело: situation (ситуация с выбором) и/или text + effects (мгновенно).
##
## «Здесь лежит» (stash) — предметы на полу модуля: то, что не поместилось
## в сумку при получении, и то, что игрок оставил сам. Их можно забрать позже.
##
## Экраны не переключает — это делает GameState (см. docs/ARCHITECTURE.md).

signal location_entered(id: String)
signal location_left(id: String)
signal event_started(location_id: String, event_id: String)
signal stash_changed(location_id: String)

var current_id: String = ""
var current_node_id: String = ""
## Тексты мгновенных событий, сработавших с последнего действия игрока.
var notices: Array = []

var _locations: Dictionary = {}  # id -> data
var _visits: Dictionary = {}  # location_id -> int
var _done: Dictionary = {}  # "location_id/event_id" -> сколько раз запускалось
var _fired_this_visit: Dictionary = {}  # event_key -> true
var _stash: Dictionary = {}  # location_id -> { item_id: count }


func _ready() -> void:
	_load_all_locations()


func _load_all_locations() -> void:
	_locations.clear()
	var dir := DirAccess.open("res://data/locations")
	if dir == null:
		push_warning("LocationSystem: res://data/locations не найден")
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var f := FileAccess.open("res://data/locations/%s" % file_name, FileAccess.READ)
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary and parsed.has("id"):
				_locations[parsed["id"]] = parsed
			else:
				push_warning("LocationSystem: битый файл локации %s" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


func reset_for_new_run() -> void:
	current_id = ""
	current_node_id = ""
	notices.clear()
	_visits.clear()
	_done.clear()
	_fired_this_visit.clear()
	_stash.clear()


func has_location(id: String) -> bool:
	return _locations.has(id)


func is_active() -> bool:
	return current_id != ""


func enter(location_id: String, node_id: String = "") -> bool:
	if not _locations.has(location_id):
		push_error("LocationSystem: неизвестная локация '%s'" % location_id)
		return false
	current_id = location_id
	current_node_id = node_id
	_visits[location_id] = int(_visits.get(location_id, 0)) + 1
	_fired_this_visit.clear()
	notices.clear()
	location_entered.emit(location_id)
	return true


func leave() -> void:
	if current_id == "":
		return
	var left_id := current_id
	current_id = ""
	current_node_id = ""
	notices.clear()
	_fired_this_visit.clear()
	location_left.emit(left_id)


func get_location_title(location_id: String) -> String:
	return str(_locations.get(location_id, {}).get("title", location_id))


func get_title() -> String:
	var title := str(_current().get("title", ""))
	if title == "" and MapSystem.nodes.has(current_node_id):
		title = str(MapSystem.nodes[current_node_id].get("title", ""))
	return title if title != "" else current_id


## Первый вариант из descriptions, чьи requires выполнены, иначе description.
func get_description() -> String:
	var data := _current()
	for variant in data.get("descriptions", []):
		if variant is Dictionary and EffectResolver.check_requirements(variant.get("requires", [])):
			return str(variant.get("text", ""))
	return str(data.get("description", ""))


func get_visits(location_id: String = "") -> int:
	if location_id == "":
		location_id = current_id
	return int(_visits.get(location_id, 0))


## ref — "локация/событие" или короткий id события текущей локации.
func is_event_done(ref: String) -> bool:
	return int(_done.get(_resolve_key(ref), 0)) > 0


func next_auto_event() -> Dictionary:
	for ev in _current().get("events", []):
		if ev is Dictionary and str(ev.get("start", "manual")) == "auto" and _is_available(ev):
			return ev
	return {}


func get_manual_events() -> Array:
	var result: Array = []
	for ev in _current().get("events", []):
		if ev is Dictionary and str(ev.get("start", "manual")) == "manual" and _is_available(ev):
			result.append(ev)
	return result


func find_event(event_id: String) -> Dictionary:
	for ev in _current().get("events", []):
		if ev is Dictionary and str(ev.get("id", "")) == event_id:
			return ev
	return {}


func is_event_available(event_id: String) -> bool:
	var ev := find_event(event_id)
	return not ev.is_empty() and _is_available(ev)


func mark_started(ev: Dictionary) -> void:
	var key := _event_key(ev)
	_done[key] = int(_done.get(key, 0)) + 1
	_fired_this_visit[key] = true
	event_started.emit(current_id, str(ev.get("id", "")))


func add_notice(text: String) -> void:
	if text != "":
		notices.append(text)


func clear_notices() -> void:
	notices.clear()


# --- Предметы на полу модуля ----------------------------------------------------

## { item_id: count } для локации (по умолчанию — текущей).
func get_stash(location_id: String = "") -> Dictionary:
	if location_id == "":
		location_id = current_id
	var stash = _stash.get(location_id, {})
	return stash.duplicate() if stash is Dictionary else {}


func stash_add(item_id: String, count: int = 1, location_id: String = "") -> void:
	if location_id == "":
		location_id = current_id
	if location_id == "" or item_id == "" or count <= 0:
		return
	var stash: Dictionary = get_stash(location_id)
	stash[item_id] = int(stash.get(item_id, 0)) + count
	_stash[location_id] = stash
	stash_changed.emit(location_id)


## Переносит предмет с пола в сумку — столько, сколько поместится.
## Возвращает число взятых экземпляров.
func stash_take(item_id: String, location_id: String = "") -> int:
	if location_id == "":
		location_id = current_id
	var stash: Dictionary = get_stash(location_id)
	var available := int(stash.get(item_id, 0))
	var taken := 0
	while taken < available and InventorySystem.add_item(item_id):
		taken += 1
	if taken >= available:
		stash.erase(item_id)
	else:
		stash[item_id] = available - taken
	if stash.is_empty():
		_stash.erase(location_id)
	else:
		_stash[location_id] = stash
	if taken > 0:
		stash_changed.emit(location_id)
	return taken


# --- Сохранение -----------------------------------------------------------------

func to_save_data() -> Dictionary:
	return {
		"visits": _visits.duplicate(),
		"done": _done.duplicate(),
		"stash": _stash.duplicate(true),
	}


func load_save_data(data: Dictionary) -> void:
	reset_for_new_run()
	var visits = data.get("visits", {})
	if visits is Dictionary:
		_visits = visits.duplicate()
	var done = data.get("done", {})
	if done is Dictionary:
		_done = done.duplicate()
	var stash = data.get("stash", {})
	if stash is Dictionary:
		_stash = stash.duplicate(true)


func _is_available(ev: Dictionary) -> bool:
	var key := _event_key(ev)
	if not bool(ev.get("repeatable", false)) and int(_done.get(key, 0)) > 0:
		return false
	if str(ev.get("start", "manual")) == "auto" and _fired_this_visit.has(key):
		return false
	return EffectResolver.check_requirements(ev.get("triggers", []))


func _event_key(ev: Dictionary) -> String:
	return "%s/%s" % [current_id, str(ev.get("id", ""))]


func _resolve_key(ref: String) -> String:
	if ref.contains("/"):
		return ref
	return "%s/%s" % [current_id, ref]


func _current() -> Dictionary:
	return _locations.get(current_id, {})
