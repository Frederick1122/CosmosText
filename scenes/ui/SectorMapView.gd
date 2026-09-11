extends Control

signal node_selected(node_id: String)

const DEFAULT_VIRTUAL_SIZE := Vector2(900, 620)
const DEFAULT_GRID_COLUMNS := 7
const DEFAULT_GRID_ROWS := 5
const DEFAULT_CELL_SIZE := Vector2(118, 112)
const DEFAULT_MODULE_SIZE := Vector2(74, 74)
const MIN_MODULE_SIDE := 48.0
const MAX_MODULE_SIDE := 84.0
const LABEL_HEIGHT := 30.0
const MAP_PADDING := 28.0
const FLOOR_RAIL_WIDTH := 104.0
const FLOOR_RAIL_GAP := 16.0

var _sector_id: String = ""
var _sector_title: String = ""
var _map_config: Dictionary = {}
var _nodes: Array = []
var _node_lookup: Dictionary = {}
var _node_order: Dictionary = {}
var _node_controls: Dictionary = {}
var _floor_buttons: Dictionary = {}
var _floors: Array = []
var _hub_node_id: String = ""
var _current_floor_id: String = ""
var _active_floor_id: String = ""
var _read_only: bool = false
var _virtual_size: Vector2 = DEFAULT_VIRTUAL_SIZE
var _grid_columns: int = DEFAULT_GRID_COLUMNS
var _grid_rows: int = DEFAULT_GRID_ROWS
var _cell_size: Vector2 = DEFAULT_CELL_SIZE
var _module_size: Vector2 = DEFAULT_MODULE_SIZE
var _uses_grid_layout: bool = false


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_PASS


func setup(
	sector_id: String,
	sector_title: String,
	map_config: Dictionary,
	nodes: Array,
	hub_node_id: String,
	current_floor_id: String,
	read_only: bool = false
) -> void:
	_sector_id = sector_id
	_sector_title = sector_title
	_map_config = map_config.duplicate(true)
	_nodes = nodes.duplicate(true)
	_hub_node_id = hub_node_id
	_current_floor_id = current_floor_id
	_read_only = read_only
	_read_layout_config()
	_floors = _read_floors()
	_active_floor_id = _valid_floor_or_default(_current_floor_id)
	custom_minimum_size = Vector2(0, maxf(560.0, float(_map_config.get("viewport_height", _virtual_size.y))))
	_rebuild()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_controls()
		queue_redraw()


func _draw() -> void:
	var rect := _map_rect()
	_draw_floor_rail()
	draw_rect(rect, Color("#151a23"), true)
	draw_rect(rect, Color("#34475e"), false, 2.0)
	_draw_grid(rect)
	_draw_connections()
	_draw_node_halos()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_node_lookup.clear()
	_node_order.clear()
	_node_controls.clear()
	_floor_buttons.clear()

	for i in range(_nodes.size()):
		if not (_nodes[i] is Dictionary):
			continue
		var node: Dictionary = _nodes[i]
		var node_id: String = str(node.get("id", ""))
		if node_id == "":
			continue
		_node_lookup[node_id] = node
		_node_order[node_id] = i

	_build_floor_buttons()
	_build_node_controls()
	call_deferred("_layout_controls")
	queue_redraw()


func _build_floor_buttons() -> void:
	if _floors.size() <= 1:
		return

	for floor in _floors:
		if not (floor is Dictionary):
			continue
		var floor_id: String = str(floor.get("id", ""))
		if floor_id == "":
			continue
		var btn := Button.new()
		btn.name = "MapFloor_%s" % floor_id
		btn.text = _floor_button_text(floor)
		btn.tooltip_text = _floor_tooltip(floor)
		btn.custom_minimum_size = Vector2(FLOOR_RAIL_WIDTH, 58)
		btn.add_theme_font_size_override("font_size", 20)
		_apply_floor_style(btn, floor_id)
		var selected_floor_id := floor_id
		btn.pressed.connect(func() -> void: _select_floor_filter(selected_floor_id))
		add_child(btn)
		_floor_buttons[floor_id] = btn


func _build_node_controls() -> void:
	for node_id in _node_lookup.keys():
		var node: Dictionary = _node_lookup[node_id]
		if not _is_node_visible_on_active_floor(node):
			continue

		var btn := Button.new()
		btn.name = "MapNode_%s" % node_id
		btn.text = _node_icon_text(node)
		btn.tooltip_text = _node_tooltip(node)
		btn.disabled = _read_only or not _is_node_interactive(node)
		btn.add_theme_font_size_override("font_size", 25)
		_apply_node_style(btn, node)
		var selected_id: String = str(node_id)
		btn.pressed.connect(func() -> void: node_selected.emit(selected_id))
		add_child(btn)

		var label := Label.new()
		label.name = "MapNodeLabel_%s" % node_id
		label.text = _node_label(node)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 16)
		_apply_node_label_style(label, node)
		add_child(label)

		_node_controls[node_id] = {
			"button": btn,
			"label": label,
		}


func _select_floor_filter(floor_id: String) -> void:
	if floor_id == _active_floor_id:
		return
	_active_floor_id = floor_id
	_rebuild()


func _layout_controls() -> void:
	_layout_floor_buttons()
	_layout_node_controls()


func _layout_floor_buttons() -> void:
	if _floor_buttons.is_empty():
		return
	var rail := _floor_rail_rect()
	var button_height := 58.0
	var gap := 10.0
	var total_height := float(_floor_buttons.size()) * button_height + float(maxi(0, _floor_buttons.size() - 1)) * gap
	var y := rail.position.y + maxf(0.0, (rail.size.y - total_height) * 0.5)

	for floor in _floors:
		if not (floor is Dictionary):
			continue
		var floor_id: String = str(floor.get("id", ""))
		if not _floor_buttons.has(floor_id):
			continue
		var btn: Button = _floor_buttons[floor_id]
		btn.position = Vector2(rail.position.x, y).round()
		btn.size = Vector2(rail.size.x, button_height).round()
		y += button_height + gap


func _layout_node_controls() -> void:
	var icon_size := _scaled_module_size()
	var label_gap := 7.0
	var label_width := clampf(_cell_size.x * _current_scale() - 6.0, icon_size.x + 26.0, 150.0)
	for node_id in _node_controls.keys():
		var controls: Dictionary = _node_controls[node_id]
		var btn := controls.get("button", null) as Button
		var label := controls.get("label", null) as Label
		if btn == null or label == null:
			continue
		var node: Dictionary = _node_lookup[node_id]
		var center := _node_center(node)
		btn.position = (center - icon_size * 0.5).round()
		btn.size = icon_size.round()
		label.position = Vector2(center.x - label_width * 0.5, center.y + icon_size.y * 0.5 + label_gap).round()
		label.size = Vector2(label_width, LABEL_HEIGHT).round()


func _draw_floor_rail() -> void:
	if _floor_buttons.is_empty():
		return
	var rail := _floor_rail_rect()
	draw_rect(rail, Color("#111722"), true)
	draw_rect(rail, Color(0.33, 0.43, 0.55, 0.55), false, 1.0)


func _draw_grid(rect: Rect2) -> void:
	if not bool(_map_config.get("grid", true)):
		return

	var color := Color(0.36, 0.46, 0.6, 0.16)
	if _uses_grid_layout:
		for col in range(_grid_columns + 1):
			var x := float(col) * _cell_size.x
			var a := _virtual_to_local(Vector2(x, 0.0))
			var b := _virtual_to_local(Vector2(x, _virtual_size.y))
			draw_line(a, b, color, 1.0)

		for row in range(_grid_rows + 1):
			var y := float(row) * _cell_size.y
			var a := _virtual_to_local(Vector2(0.0, y))
			var b := _virtual_to_local(Vector2(_virtual_size.x, y))
			draw_line(a, b, color, 1.0)
		return

	var step := float(_map_config.get("grid_step", 90))
	if step <= 0.0:
		return

	var x := 0.0
	while x <= _virtual_size.x:
		var a := _virtual_to_local(Vector2(x, 0.0))
		var b := _virtual_to_local(Vector2(x, _virtual_size.y))
		draw_line(a, b, color, 1.0)
		x += step

	var y := 0.0
	while y <= _virtual_size.y:
		var a := _virtual_to_local(Vector2(0.0, y))
		var b := _virtual_to_local(Vector2(_virtual_size.x, y))
		draw_line(a, b, color, 1.0)
		y += step


func _draw_connections() -> void:
	var drawn := {}
	for node in _nodes:
		if not (node is Dictionary) or not _is_node_visible_on_active_floor(node):
			continue

		var node_id: String = str(node.get("id", ""))
		var connections = node.get("connections", [])
		if not (connections is Array):
			continue

		for target_raw in connections:
			var target_id: String = str(target_raw)
			if not _node_lookup.has(target_id):
				continue
			var target: Dictionary = _node_lookup[target_id]
			if not _is_node_visible_on_active_floor(target):
				continue

			var first_id: String = node_id
			var second_id: String = target_id
			if first_id > second_id:
				first_id = target_id
				second_id = node_id
			var edge_key := "%s|%s" % [first_id, second_id]
			if drawn.has(edge_key):
				continue
			drawn[edge_key] = true

			var color := _connection_color(node, target)
			draw_line(_node_center(node), _node_center(target), Color(0.03, 0.04, 0.06, 0.75), 8.0, true)
			draw_line(_node_center(node), _node_center(target), color, 3.0, true)


func _draw_node_halos() -> void:
	var icon_size := _scaled_module_size()
	for node in _nodes:
		if not (node is Dictionary) or not _is_node_visible_on_active_floor(node):
			continue
		var center: Vector2 = _node_center(node)
		var radius: float = maxf(icon_size.x, icon_size.y) * 0.72
		draw_circle(center, radius, _node_halo_color(node))


func _read_layout_config() -> void:
	_uses_grid_layout = (
		_map_config.has("grid_columns")
		or _map_config.has("grid_rows")
		or _map_config.has("cell_size")
	)
	_grid_columns = maxi(1, int(_map_config.get("grid_columns", DEFAULT_GRID_COLUMNS)))
	_grid_rows = maxi(1, int(_map_config.get("grid_rows", DEFAULT_GRID_ROWS)))
	_cell_size = _read_vec2(_map_config.get("cell_size", {}), DEFAULT_CELL_SIZE)
	_module_size = _read_vec2(_map_config.get("module_size", {}), DEFAULT_MODULE_SIZE)

	if _uses_grid_layout:
		_virtual_size = Vector2(float(_grid_columns) * _cell_size.x, float(_grid_rows) * _cell_size.y)
		return

	_virtual_size = _read_vec2(_map_config.get("size", {}), DEFAULT_VIRTUAL_SIZE)


func _read_vec2(raw, fallback: Vector2) -> Vector2:
	if raw is Dictionary:
		return Vector2(
			maxf(1.0, float(raw.get("x", fallback.x))),
			maxf(1.0, float(raw.get("y", fallback.y)))
		)
	if raw is int or raw is float:
		var side := maxf(1.0, float(raw))
		return Vector2(side, side)
	return fallback


func _map_rect() -> Rect2:
	var area := _content_rect()
	if _floor_buttons.size() > 0:
		var reserved := FLOOR_RAIL_WIDTH + FLOOR_RAIL_GAP
		if _floor_side() == "left":
			area.position.x += reserved
		area.size.x -= reserved
	area.size.x = maxf(1.0, area.size.x)
	area.size.y = maxf(1.0, area.size.y)

	var scale: float = minf(area.size.x / _virtual_size.x, area.size.y / _virtual_size.y)
	var map_size: Vector2 = _virtual_size * scale
	return Rect2(area.position + (area.size - map_size) * 0.5, map_size)


func _floor_rail_rect() -> Rect2:
	var area := _content_rect()
	var x := area.position.x
	if _floor_side() != "left":
		x = area.position.x + area.size.x - FLOOR_RAIL_WIDTH
	return Rect2(Vector2(x, area.position.y), Vector2(FLOOR_RAIL_WIDTH, area.size.y))


func _content_rect() -> Rect2:
	var available := size
	if available.x <= 0.0 or available.y <= 0.0:
		available = Vector2(maxf(custom_minimum_size.x, 1.0), maxf(custom_minimum_size.y, 1.0))
	return Rect2(Vector2(MAP_PADDING, MAP_PADDING), Vector2(
		maxf(1.0, available.x - MAP_PADDING * 2.0),
		maxf(1.0, available.y - MAP_PADDING * 2.0)
	))


func _floor_side() -> String:
	var side := str(_map_config.get("floor_buttons_side", "right"))
	return "left" if side == "left" else "right"


func _virtual_to_local(point: Vector2) -> Vector2:
	var rect := _map_rect()
	var scale: float = minf(rect.size.x / _virtual_size.x, rect.size.y / _virtual_size.y)
	return rect.position + point * scale


func _current_scale() -> float:
	var rect := _map_rect()
	return minf(rect.size.x / _virtual_size.x, rect.size.y / _virtual_size.y)


func _node_center(node: Dictionary) -> Vector2:
	return _virtual_to_local(_node_position(node))


func _node_position(node: Dictionary) -> Vector2:
	var cfg := _node_map(node)
	var raw_cell = cfg.get("cell", {})
	if raw_cell is Dictionary:
		var cell_x := clampf(float(raw_cell.get("x", 1.0)) - 1.0, 0.0, float(_grid_columns - 1))
		var cell_y := clampf(float(raw_cell.get("y", 1.0)) - 1.0, 0.0, float(_grid_rows - 1))
		return Vector2((cell_x + 0.5) * _cell_size.x, (cell_y + 0.5) * _cell_size.y)

	var raw_position = cfg.get("position", {})
	if raw_position is Dictionary:
		return Vector2(float(raw_position.get("x", 0.0)), float(raw_position.get("y", 0.0)))

	var node_id: String = str(node.get("id", ""))
	var idx := int(_node_order.get(node_id, 0))
	var count: int = maxi(1, _nodes.size())
	var angle := TAU * float(idx) / float(count) - PI * 0.5
	var radius: float = minf(_virtual_size.x, _virtual_size.y) * 0.32
	return _virtual_size * 0.5 + Vector2(cos(angle), sin(angle)) * radius


func _scaled_module_size() -> Vector2:
	var scale := _current_scale()
	var raw_size := _module_size * scale
	var side := clampf(minf(raw_size.x, raw_size.y), MIN_MODULE_SIDE, MAX_MODULE_SIDE)
	return Vector2(side, side)


func _node_map(node: Dictionary) -> Dictionary:
	var cfg = node.get("map", {})
	return cfg if cfg is Dictionary else {}


func _read_floors() -> Array:
	var result: Array = []
	var raw_floors = _map_config.get("floors", [])
	if not (raw_floors is Array):
		return result
	for floor in raw_floors:
		if not (floor is Dictionary):
			continue
		var floor_id := str(floor.get("id", ""))
		if floor_id == "":
			continue
		result.append(floor.duplicate(true))
	return result


func _valid_floor_or_default(floor_id: String) -> String:
	if _is_known_floor(floor_id):
		return floor_id
	var configured := str(_map_config.get("default_floor", ""))
	if _is_known_floor(configured):
		return configured
	if _floors.size() > 0 and _floors[0] is Dictionary:
		return str(_floors[0].get("id", ""))
	return ""


func _is_known_floor(floor_id: String) -> bool:
	if floor_id == "":
		return false
	if _floors.is_empty():
		return true
	for floor in _floors:
		if floor is Dictionary and str(floor.get("id", "")) == floor_id:
			return true
	return false


func _node_floor_id(node: Dictionary) -> String:
	var floor_id := str(_node_map(node).get("floor", ""))
	return _valid_floor_or_default(floor_id) if floor_id == "" else floor_id


func _is_node_visible_on_active_floor(node: Dictionary) -> bool:
	if not _is_node_visible(node):
		return false
	if _active_floor_id == "":
		return true
	return _node_floor_id(node) == _active_floor_id


func _is_node_visible(node: Dictionary) -> bool:
	var state: String = str(node.get("state", "locked"))
	if state != "locked":
		return true
	return bool(_node_map(node).get("visible_when_locked", false))


func _is_node_interactive(node: Dictionary) -> bool:
	var state: String = str(node.get("state", "locked"))
	if state == "locked":
		return false
	var node_floor_id := _node_floor_id(node)
	if _current_floor_id != "" and node_floor_id != "" and node_floor_id != _current_floor_id:
		return false
	return true


func _is_elevator_node(node: Dictionary) -> bool:
	return str(_node_map(node).get("kind", "")) == "elevator"


func _node_label(node: Dictionary) -> String:
	var cfg := _node_map(node)
	var label: String = str(cfg.get("label", node.get("title", node.get("id", ""))))
	if str(node.get("state", "locked")) == "locked" and not bool(cfg.get("reveal_title_when_locked", true)):
		label = "Неизвестно"
	return label


func _node_icon_text(node: Dictionary) -> String:
	var state: String = str(node.get("state", "locked"))
	if str(node.get("id", "")) == _hub_node_id:
		return "H"
	if _is_elevator_node(node):
		return "⇅"
	match state:
		"dangerous":
			return "!"
		"cleared":
			return "✓"
		"locked":
			return "?"
		_:
			return "•"


func _floor_button_text(floor: Dictionary) -> String:
	return str(floor.get("label", floor.get("id", "?")))


func _floor_tooltip(floor: Dictionary) -> String:
	var floor_id := str(floor.get("id", ""))
	var lines := [
		str(floor.get("title", floor_id)),
	]
	if floor_id == _current_floor_id:
		lines.append("Текущая палуба")
	if floor_id == _active_floor_id:
		lines.append("Открыта на карте")
	return _join_strings(lines, "\n")


func _floor_title(floor_id: String) -> String:
	for floor in _floors:
		if floor is Dictionary and str(floor.get("id", "")) == floor_id:
			return str(floor.get("title", floor_id))
	return floor_id


func _node_tooltip(node: Dictionary) -> String:
	var cfg := _node_map(node)
	var state: String = str(node.get("state", "locked"))
	var lines := [
		str(node.get("title", node.get("id", ""))),
		_state_text(state),
		"Палуба: " + _floor_title(_node_floor_id(node)),
		"Герметично" if bool(node.get("sealed", true)) else "Расходует O2",
	]
	if _is_elevator_node(node):
		var target_floor_id := str(cfg.get("target_floor", ""))
		if target_floor_id != "":
			lines.append("Ведет: " + _floor_title(target_floor_id))
	var note := str(cfg.get("note", ""))
	if note != "":
		lines.append(note)
	return _join_strings(lines, "\n")


func _join_strings(parts: Array, separator: String) -> String:
	var text := ""
	for i in range(parts.size()):
		if i > 0:
			text += separator
		text += str(parts[i])
	return text


func _state_text(state: String) -> String:
	match state:
		"available":
			return "Доступно"
		"dangerous":
			return "Опасно"
		"cleared":
			return "Пройдено"
		"locked":
			return "Закрыто"
		_:
			return state


func _connection_color(a: Dictionary, b: Dictionary) -> Color:
	var a_state: String = str(a.get("state", "locked"))
	var b_state: String = str(b.get("state", "locked"))
	if a_state == "locked" or b_state == "locked":
		return Color(0.42, 0.48, 0.57, 0.34)
	if a_state == "dangerous" or b_state == "dangerous":
		return Color("#a95b67")
	if a_state == "cleared" and b_state == "cleared":
		return Color("#5c9475")
	return Color("#5ea9c9")


func _node_halo_color(node: Dictionary) -> Color:
	var state: String = str(node.get("state", "locked"))
	if not _is_node_interactive(node) and state != "locked":
		return Color(0.36, 0.41, 0.50, 0.11)
	if str(node.get("id", "")) == _hub_node_id:
		return Color(0.28, 0.65, 0.48, 0.17)
	if _is_elevator_node(node):
		return Color(0.53, 0.68, 0.90, 0.18)
	match state:
		"dangerous":
			return Color(0.78, 0.23, 0.31, 0.17)
		"cleared":
			return Color(0.42, 0.58, 0.72, 0.13)
		"locked":
			return Color(0.44, 0.48, 0.56, 0.09)
		_:
			return Color(0.18, 0.56, 0.74, 0.16)


func _apply_node_label_style(label: Label, node: Dictionary) -> void:
	var state: String = str(node.get("state", "locked"))
	var color := Color("#d7deee")
	if state == "locked":
		color = Color("#858e9f")
	elif state == "dangerous":
		color = Color("#f0b0b9")
	elif str(node.get("id", "")) == _hub_node_id:
		color = Color("#a7e3c4")
	elif _is_elevator_node(node):
		color = Color("#bfd8ff")
	if not _is_node_interactive(node):
		color = color.darkened(0.2)
	label.add_theme_color_override("font_color", color)


func _apply_floor_style(btn: Button, floor_id: String) -> void:
	var is_active := floor_id == _active_floor_id
	var is_current := floor_id == _current_floor_id
	var normal := Color("#1a2230")
	var hover := Color("#263549")
	var pressed := Color("#131b27")
	var border := Color("#3b4c61")
	var font := Color("#c9d3e4")
	if is_current:
		normal = Color("#173b37")
		hover = Color("#1e564f")
		border = Color("#66b59c")
		font = Color("#e6fff4")
	if is_active:
		normal = Color("#22415c")
		hover = Color("#2a577b")
		border = Color("#8abce0")
		font = Color("#ffffff")
	btn.add_theme_color_override("font_color", font)
	btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
	btn.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	btn.add_theme_stylebox_override("normal", _box(normal, border, 1))
	btn.add_theme_stylebox_override("hover", _box(hover, border.lightened(0.18), 1))
	btn.add_theme_stylebox_override("pressed", _box(pressed, border.lightened(0.26), 2))
	btn.add_theme_stylebox_override("focus", _box(hover, Color("#d6f2ff"), 2))


func _apply_node_style(btn: Button, node: Dictionary) -> void:
	var state: String = str(node.get("state", "locked"))
	var normal := Color("#173f55")
	var hover := Color("#1f6989")
	var pressed := Color("#102c3d")
	var border := Color("#5d91a8")

	if str(node.get("id", "")) == _hub_node_id:
		normal = Color("#174c3c")
		hover = Color("#1e6a53")
		pressed = Color("#103429")
		border = Color("#70b997")
	elif _is_elevator_node(node):
		normal = Color("#243f63")
		hover = Color("#315988")
		pressed = Color("#1a2c45")
		border = Color("#89b7e6")
	elif state == "dangerous":
		normal = Color("#5b2530")
		hover = Color("#7e3443")
		pressed = Color("#3b1c24")
		border = Color("#b86d79")
	elif state == "cleared":
		normal = Color("#232c38")
		hover = Color("#2d3847")
		pressed = Color("#1a212b")
		border = Color("#566477")
	elif state == "locked":
		normal = Color("#171c25")
		hover = Color("#171c25")
		pressed = Color("#171c25")
		border = Color("#303847")

	if not _is_node_interactive(node) and state != "locked":
		normal = normal.darkened(0.25)
		hover = normal
		pressed = normal
		border = border.darkened(0.18)

	btn.add_theme_color_override("font_color", Color("#f4f7fb"))
	btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
	btn.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	btn.add_theme_color_override("font_disabled_color", Color("#8791a4"))
	btn.add_theme_stylebox_override("normal", _box(normal, border, 1))
	btn.add_theme_stylebox_override("hover", _box(hover, border.lightened(0.15), 2))
	btn.add_theme_stylebox_override("pressed", _box(pressed, border.lightened(0.25), 2))
	btn.add_theme_stylebox_override("disabled", _box(normal.darkened(0.08), border.darkened(0.25), 1))
	btn.add_theme_stylebox_override("focus", _box(hover, Color("#d6f2ff"), 2))


func _box(bg: Color, border: Color, border_width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(8)
	box.content_margin_left = 0
	box.content_margin_right = 0
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	return box
