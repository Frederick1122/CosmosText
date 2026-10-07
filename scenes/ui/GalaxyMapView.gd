extends Control
## Глобальная карта системы: гексагональная сетка, узлы-точки интереса
## (планеты, астероиды, станции, обломки) нарисованы иконками из
## `assets/art/galaxy/<тип>.png`. Логики перелёта не содержит: показывает то,
## что дал `GalaxySystem`, и сообщает о нажатии (`node_selected`).
##
## Камера: один палец или зажатая мышь двигает карту, щипок двумя пальцами
## масштабирует вокруг их середины, работают колесо и «＋/－/◎». Касание,
## перешедшее в жест, точку не выбирает. Сетка рисуется целиком: пустые гексы
## дают карте масштаб, занятые — несут иконку, подпись и состояние.

signal node_selected(node_id: String)

const UiKit = preload("res://scenes/ui/UiKit.gd")

const MIN_ZOOM := 0.4
const MAX_ZOOM := 2.4
const ZOOM_STEP := 1.35
const TAP_SLOP := 16.0
const GRID_COLOR := Color("#232b38")
const GRID_EDGE := Color("#334153")
const ROUTE_COLOR := Color("#e0b153")
const HERE_COLOR := Color("#a7e3c4")
const SELECT_COLOR := Color("#ffffff")
const UNAVAILABLE_COLOR := Color(0.55, 0.58, 0.66, 0.45)

## Узлы из GalaxySystem.get_nodes(): q/r, тип, подписи, доступность.
var _nodes: Array = []
var _by_id: Dictionary = {}
var _current_id: String = ""
var _selected_id: String = ""

var _hex_size: float = 96.0
var _cam: Vector2 = Vector2.ZERO
var _zoom: float = 1.0
var _bounds := Rect2()
var _camera_tween: Tween

var _pointers: Dictionary = {}
var _gesture_moved: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _cam_origin: Vector2 = Vector2.ZERO
var _pinch_distance: float = 0.0
var _pinch_zoom: float = 1.0
var _pinch_anchor: Vector2 = Vector2.ZERO
## Камеру вписываем один раз, когда у карты появился настоящий размер: до первой
## раскладки size ещё нулевой, а дальше это уже выбор игрока.
var _fitted: bool = false
var _zoom_buttons: Array = []


func _init() -> void:
	name = "GalaxyMapView"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(0, 640.0)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	resized.connect(_on_resized)
	_build_zoom_buttons()
	queue_redraw()


## data: { nodes, current_id, hex_size, selected_id }.
func setup(data: Dictionary) -> void:
	_hex_size = maxf(24.0, float(data.get("hex_size", 96.0)))
	_current_id = str(data.get("current_id", ""))
	_selected_id = str(data.get("selected_id", ""))
	_apply_nodes(data.get("nodes", []))
	_refit_camera()
	queue_redraw()


## Узлы изменились (перелёт, топливо, флаги) — камера остаётся на месте.
func update_nodes(nodes: Array, current_id: String) -> void:
	_current_id = current_id
	_apply_nodes(nodes)
	queue_redraw()


func set_selected(node_id: String) -> void:
	_selected_id = node_id
	queue_redraw()


func focus_node(node_id: String, animated: bool = true) -> void:
	if not _by_id.has(node_id):
		return
	_move_camera(_virtual_of(_by_id[node_id]), _zoom, animated)


func focus_current(animated: bool = true) -> void:
	if _current_id == "":
		return
	_move_camera(_virtual_of(_by_id[_current_id]), maxf(_zoom, 0.9), animated)


# --- Отрисовка -----------------------------------------------------------------

func _draw() -> void:
	if _nodes.is_empty():
		return
	_draw_grid()
	_draw_route()
	for node in _nodes:
		_draw_node(node)
	_draw_here()


## Пустые гексы вокруг занятых: карта читается как сетка, а не как россыпь иконок.
func _draw_grid() -> void:
	var step_x := _hex_size * 1.5
	var step_y := _hex_size * sqrt(3.0)
	var margin := _hex_size * 2.0
	var visible := Rect2(_to_virtual(Vector2.ZERO), size / _zoom)
	visible = visible.grow(margin)
	var q_from := floori((visible.position.x - margin) / step_x)
	var q_to := ceili((visible.end.x + margin) / step_x)
	for q in range(q_from, q_to + 1):
		var r_from := floori((visible.position.y - margin) / step_y - float(q) * 0.5)
		var r_to := ceili((visible.end.y + margin) / step_y - float(q) * 0.5)
		for r in range(r_from, r_to + 1):
			var center := _to_screen(Vector2(step_x * float(q), step_y * (float(r) + float(q) * 0.5)))
			_draw_hexagon(center, _hex_size * _zoom, GRID_COLOR, true)


func _draw_hexagon(center: Vector2, radius: float, color: Color, filled: bool) -> void:
	var points := PackedVector2Array()
	for i in range(6):
		var angle := TAU * float(i) / 6.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	if filled:
		draw_polyline(points + PackedVector2Array([points[0]]), color, 1.0, true)
	else:
		draw_colored_polygon(points, color)


## Пунктирная линия от корабля к выбранной точке: видно, что перелёт возможен
## и насколько точка далеко.
func _draw_route() -> void:
	if _selected_id == "" or _current_id == "" or _selected_id == _current_id:
		return
	if not _by_id.has(_selected_id) or not _by_id.has(_current_id):
		return
	var from := _to_screen(_virtual_of(_by_id[_current_id]))
	var to := _to_screen(_virtual_of(_by_id[_selected_id]))
	var length := from.distance_to(to)
	if length < 1.0:
		return
	var direction := (to - from) / length
	var dash := 14.0 * _zoom
	var gap := 10.0 * _zoom
	var offset := 0.0
	while offset < length:
		var start := from + direction * offset
		var finish := from + direction * minf(offset + dash, length)
		draw_line(start, finish, Color(ROUTE_COLOR, 0.8), 2.0, true)
		offset += dash + gap
	# Стрелка у цели: направление перелёта.
	var arrow := 12.0 * _zoom
	var left := to - direction * arrow + Vector2(-direction.y, direction.x) * arrow * 0.5
	var right := to - direction * arrow - Vector2(-direction.y, direction.x) * arrow * 0.5
	draw_colored_polygon(PackedVector2Array([to, left, right]), Color(ROUTE_COLOR, 0.9))


func _draw_node(node: Dictionary) -> void:
	var node_id := str(node.get("id", ""))
	var center := _to_screen(_virtual_of(node))
	var available := bool(node.get("available", true))
	var texture := UiKit.galaxy_texture(str(node.get("type", "planet")))
	var icon_side := _hex_size * 0.92 * _zoom
	var tint := Color.WHITE if available else UNAVAILABLE_COLOR
	if texture != null:
		var rect := Rect2(center - Vector2(icon_side, icon_side) * 0.5, Vector2(icon_side, icon_side))
		draw_texture_rect(texture, rect, false, tint)
	else:
		# Иконки нет — круг с первой буквой типа: карта должна читаться и без арта.
		draw_circle(center, icon_side * 0.45, Color(tint.r, tint.g, tint.b, 0.5))
	if node_id == _selected_id:
		draw_arc(center, icon_side * 0.62, 0.0, TAU, 44, SELECT_COLOR, 2.5, true)
	var font := ThemeDB.fallback_font
	var font_size := int(UiKit.fs(16))
	var title := str(node.get("title", node_id))
	if not bool(node.get("here", false)):
		title += " · %d ч" % int(node.get("hours", 0))
	var text_size := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var text_color := UiKit.TITLE_COLOR if available else UiKit.MUTED_COLOR
	if node_id == _selected_id:
		text_color = UiKit.ACCENT_COLOR
	draw_string(font, center + Vector2(-text_size.x * 0.5, icon_side * 0.5 + font_size + 6.0),
		title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)


## Корабль: кольцо и шеврон над текущим узлом — «вы здесь».
func _draw_here() -> void:
	if _current_id == "" or not _by_id.has(_current_id):
		return
	var center := _to_screen(_virtual_of(_by_id[_current_id]))
	var radius := _hex_size * 0.6 * _zoom
	draw_arc(center, radius, 0.0, TAU, 48, HERE_COLOR, 2.5, true)
	var arrow := 9.0 * _zoom
	var tip := center + Vector2(0.0, -radius - 4.0 * _zoom)
	draw_colored_polygon(PackedVector2Array([
		tip,
		tip + Vector2(-arrow, arrow * 1.2),
		tip + Vector2(arrow, arrow * 1.2),
	]), HERE_COLOR)


# --- Камера и жесты ------------------------------------------------------------

func _on_resized() -> void:
	_place_zoom_buttons()
	if not _fitted and size.x > 0.0 and size.y > 0.0 and not _nodes.is_empty():
		_fitted = true
		_refit_camera()
	queue_redraw()


func _build_zoom_buttons() -> void:
	_zoom_buttons = [
		["＋", _zoom_in], ["－", _zoom_out], ["◎", focus_current],
	]
	for entry in _zoom_buttons:
		var btn := UiKit.button(str(entry[0]), "quiet", 52)
		btn.name = "GalaxyZoom%s" % str(entry[0])
		btn.size_flags_horizontal = Control.SIZE_SHRINK_END
		btn.custom_minimum_size = Vector2(UiKit.fs(76), UiKit.fs(56))
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.pressed.connect(entry[1])
		add_child(btn)
	_place_zoom_buttons()


func _place_zoom_buttons() -> void:
	var side := UiKit.fs(76)
	var height := UiKit.fs(56)
	var gap := 8.0
	var x := size.x - side - 10.0
	var y := size.y - height - 10.0
	for i in range(_zoom_buttons.size()):
		var btn: Button = get_child(i)
		btn.size = Vector2(side, height)
		btn.position = Vector2(x, y - float(i) * (height + gap))


func _apply_nodes(nodes: Array) -> void:
	_nodes = []
	_by_id.clear()
	for node in nodes:
		if not (node is Dictionary):
			continue
		var data: Dictionary = node
		_nodes.append(data)
		_by_id[str(data.get("id", ""))] = data
	_bounds = _nodes_bounds()


func _nodes_bounds() -> Rect2:
	if _nodes.is_empty():
		return Rect2()
	var first := _virtual_of(_nodes[0])
	var rect := Rect2(first, Vector2.ZERO)
	for node in _nodes:
		rect = rect.expand(_virtual_of(node))
	return rect


func _virtual_of(node: Dictionary) -> Vector2:
	var step_x := _hex_size * 1.5
	var step_y := _hex_size * sqrt(3.0)
	var q := float(int(node.get("q", 0)))
	var r := float(int(node.get("r", 0)))
	return Vector2(step_x * q, step_y * (r + q * 0.5))


func _to_screen(value: Vector2) -> Vector2:
	return (value - _cam) * _zoom + size * 0.5


func _to_virtual(point: Vector2) -> Vector2:
	return (point - size * 0.5) / _zoom + _cam


## Вписать все узлы в рамку: на старте карта видна целиком.
func _refit_camera() -> void:
	if _nodes.is_empty() or size.x <= 0.0 or size.y <= 0.0:
		_cam = Vector2.ZERO
		_zoom = 1.0
		return
	var margin := _hex_size * 2.4
	var span := Vector2(maxf(1.0, _bounds.size.x + margin), maxf(1.0, _bounds.size.y + margin))
	_zoom = clampf(minf(size.x / span.x, size.y / span.y), MIN_ZOOM, MAX_ZOOM)
	_cam = _bounds.get_center()


func _move_camera(target: Vector2, zoom: float, animated: bool) -> void:
	var wanted := clampf(zoom, MIN_ZOOM, MAX_ZOOM)
	if _camera_tween != null:
		_camera_tween.kill()
	if not animated:
		_cam = target
		_zoom = wanted
		queue_redraw()
		return
	_camera_tween = create_tween().set_parallel(true)
	_camera_tween.tween_method(_set_cam, _cam, target, 0.25).set_trans(Tween.TRANS_SINE)
	_camera_tween.tween_method(_set_zoom_value, _zoom, wanted, 0.25).set_trans(Tween.TRANS_SINE)


func _set_cam(value: Vector2) -> void:
	_cam = value
	queue_redraw()


func _set_zoom_value(value: float) -> void:
	_zoom = value
	queue_redraw()


func _zoom_in() -> void:
	_move_camera(_cam, _zoom * ZOOM_STEP, true)


func _zoom_out() -> void:
	_move_camera(_cam, _zoom / ZOOM_STEP, true)


## Пальцы ловятся до GUI: касание, начатое на кнопке, тоже двигает карту.
## Мышь, эмулированная из касания, пропускается — палец уже учтён.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_pointer_down(event.index, event.position)
		else:
			_pointer_up(event.index)
	elif event is InputEventScreenDrag:
		_pointer_move(event.index, event.position)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pointer_down(0, event.position)
			else:
				_pointer_up(0)
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if get_global_rect().has_point(event.position):
				_zoom_at(event.position, ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_pointer_move(0, event.position)


func _pointer_down(index: int, global_point: Vector2) -> void:
	if not get_global_rect().has_point(global_point):
		return
	if _pointers.is_empty():
		_gesture_moved = false
	var local := _to_local_point(global_point)
	_pointers[index] = local
	if _pointers.size() == 1:
		_press_pos = local
		_cam_origin = _cam
	elif _pointers.size() == 2:
		_begin_pinch()


func _pointer_move(index: int, global_point: Vector2) -> void:
	if not _pointers.has(index):
		return
	_pointers[index] = _to_local_point(global_point)
	if _pointers.size() >= 2:
		_update_pinch()
		get_viewport().set_input_as_handled()
		return
	var delta: Vector2 = _pointers[index] - _press_pos
	if not _gesture_moved and delta.length() >= TAP_SLOP:
		_start_gesture()
	if _gesture_moved:
		_cam = _cam_origin - delta / _zoom
		queue_redraw()
		get_viewport().set_input_as_handled()


func _pointer_up(index: int) -> void:
	if not _pointers.has(index):
		return
	var was_tap := not _gesture_moved and _pointers.size() == 1
	var point: Vector2 = _pointers[index]
	_pointers.erase(index)
	if _pointers.size() == 1:
		_press_pos = _pointers.values()[0]
		_cam_origin = _cam
	elif _pointers.size() >= 2:
		_begin_pinch()
	if was_tap:
		_select_at(point)


func _begin_pinch() -> void:
	_start_gesture()
	var points: Array = _pointers.values()
	var a: Vector2 = points[0]
	var b: Vector2 = points[1]
	_pinch_distance = maxf(1.0, a.distance_to(b))
	_pinch_zoom = _zoom
	_pinch_anchor = _to_virtual((a + b) * 0.5)


func _update_pinch() -> void:
	var points: Array = _pointers.values()
	var a: Vector2 = points[0]
	var b: Vector2 = points[1]
	var wanted := clampf(_pinch_zoom * a.distance_to(b) / _pinch_distance, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(wanted, _zoom):
		return
	_cam = _pinch_anchor - ((a + b) * 0.5 - size * 0.5) / wanted
	_zoom = wanted
	queue_redraw()


func _start_gesture() -> void:
	_gesture_moved = true
	if _camera_tween != null:
		_camera_tween.kill()


func _zoom_at(point: Vector2, factor: float) -> void:
	var anchor := _to_virtual(point)
	var wanted := clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	_cam = anchor - (point - size * 0.5) / wanted
	_zoom = wanted
	queue_redraw()


## Ближайшая точка в пределах гекса; пустое место снимает выбор. Под кнопками
## «＋/－/◎» выбор не срабатывает: там своё нажатие.
func _select_at(point: Vector2) -> void:
	if _over_zoom_button(point):
		return
	var best := ""
	var best_distance := _hex_size * _zoom
	for node in _nodes:
		var distance := _to_screen(_virtual_of(node)).distance_to(point)
		if distance <= best_distance:
			best_distance = distance
			best = str(node.get("id", ""))
	_selected_id = best
	queue_redraw()
	node_selected.emit(best)


func _over_zoom_button(point: Vector2) -> bool:
	for child in get_children():
		var btn := child as Button
		if btn != null and btn.get_rect().has_point(point):
			return true
	return false


func _to_local_point(global_point: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * global_point
