extends Node
## Узловая карта сектора — см. tech-spec-v1.md раздел 6.
## Не переключает экраны сама — просит GameState (единственный владелец
## переходов между экранами, см. ТЗ раздел 10).

signal node_state_changed(node_id: String, state: String)
signal sector_loaded(sector_id: String)
signal floor_changed(floor_id: String)

var current_sector_id: String = ""
var sector_title: String = ""
var hub_node_id: String = ""
var current_floor_id: String = ""
var map_config: Dictionary = {}
var nodes: Dictionary = {}  # node_id -> { title, location_id, connections, sealed, state, map }


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
	sector_loaded.emit(current_sector_id)
	return true


func get_visible_nodes() -> Array:
	var result: Array = []
	for node_id in nodes.keys():
		if not (nodes[node_id] is Dictionary):
			continue
		var data: Dictionary = nodes[node_id]
		if data.get("state", "locked") != "locked":
			var entry: Dictionary = data.duplicate()
			entry["id"] = node_id
			result.append(entry)
	return result


func get_sector_title() -> String:
	return sector_title if sector_title != "" else current_sector_id


func get_map_config() -> Dictionary:
	return map_config.duplicate(true)


func get_current_floor_id() -> String:
	return current_floor_id


func get_map_nodes(include_locked: bool = true) -> Array:
	var result: Array = []
	for node_id in nodes.keys():
		if not (nodes[node_id] is Dictionary):
			continue
		var data: Dictionary = nodes[node_id]
		if include_locked or data.get("state", "locked") != "locked":
			var entry: Dictionary = data.duplicate(true)
			entry["id"] = node_id
			result.append(entry)
	result.sort_custom(func(a, b): return _node_map_order(a) < _node_map_order(b))
	return result


func _node_map_order(node: Dictionary) -> int:
	var cfg = node.get("map", {})
	if cfg is Dictionary:
		return int(cfg.get("order", 0))
	return 0


func select_node(node_id: String) -> void:
	if not nodes.has(node_id):
		push_error("MapSystem: неизвестный узел '%s'" % node_id)
		return
	if not (nodes[node_id] is Dictionary):
		push_error("MapSystem: битый узел '%s'" % node_id)
		return
	var data: Dictionary = nodes[node_id]
	var state: String = data.get("state", "locked")
	if state == "locked":
		push_warning("MapSystem: узел '%s' закрыт" % node_id)
		return
	var node_floor_id := _node_floor_id(data)
	if current_floor_id != "" and node_floor_id != "" and node_floor_id != current_floor_id:
		push_warning("MapSystem: узел '%s' находится на другой палубе" % node_id)
		return
	if _is_elevator_node(data):
		_move_by_elevator(data)
		return
	var location_id := str(data.get("location_id", ""))
	if location_id == "":
		push_warning("MapSystem: у узла '%s' нет location_id" % node_id)
		return
	# В пройденные (cleared) и опасные модули можно возвращаться.
	ResourceSystem.set_o2_ticking(not bool(data.get("sealed", true)))
	GameState.enter_location(location_id, node_id)


func unlock_node(node_id: String) -> void:
	set_node_state(node_id, "available")


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
		"nodes": node_states,
	}


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
	return true


func _move_by_elevator(node: Dictionary) -> void:
	var cfg := _node_map(node)
	var target_floor_id := str(cfg.get("target_floor", ""))
	if target_floor_id == "":
		push_warning("MapSystem: у лифта нет target_floor")
		return
	if not _is_valid_floor_id(target_floor_id):
		push_warning("MapSystem: лифт ведет на неизвестную палубу '%s'" % target_floor_id)
		return
	ResourceSystem.set_o2_ticking(false)
	set_current_floor(target_floor_id)


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
