extends Control
## Карта сектора: сетка палубы, связи, узлы-отсеки, игрок и маршрут.
## Логики перемещения не содержит — только показывает то, что дали MapSystem
## и Game, и сообщает о нажатии на узел (node_selected).
##
## Узел красится по статусу (MapSystem.get_node_status): база, есть дела,
## под ключ, пусто, враг, лифт, не исследовано. Подпись, которая не влезает,
## едет бегущей строкой (MarqueeLabel). Видны только палубы, где игрок был.
##
## Камера: по умолчанию палуба вписана целиком (zoom 1). Её можно двигать
## перетаскиванием, приближать колесом, щипком или кнопками «＋/－», а «◎»
## возвращает к игроку. В пути (focus_player) камера приближается к игроку и
## ведёт его от отсека к отсеку.

signal node_selected(node_id: String)

const UiKit = preload("res://scenes/ui/UiKit.gd")
const MARQUEE_SCRIPT := preload("res://scenes/ui/MarqueeLabel.gd")

const DEFAULT_VIRTUAL_SIZE := Vector2(900, 620)
const DEFAULT_GRID_COLUMNS := 7
const DEFAULT_GRID_ROWS := 5
const DEFAULT_CELL_SIZE := Vector2(118, 112)
const DEFAULT_MODULE_SIZE := Vector2(74, 74)
const MIN_MODULE_SIDE := 56.0
const MAX_MODULE_SIDE := 150.0
## Потолок увеличения при вписывании: карта из пары узлов не раздувается на весь экран.
const MAX_VIEW_SCALE := 2.2
const MAP_PADDING := 28.0
const FLOOR_RAIL_WIDTH := 104.0
const FLOOR_RAIL_GAP := 16.0
const ZOOM_MAX := 2.6
const ZOOM_STEP := 1.35
## Приближение камеры, когда она ведёт игрока по маршруту.
const FOLLOW_ZOOM := 1.7
const CAMERA_TIME := 0.35
const DRAG_THRESHOLD := 10.0
const TOKEN_SIDE := 54.0
const ROUTE_COLOR := Color("#ffd166")

## Статус узла → заливка, рамка, значок, цвет подписи и строка легенды.
const STATUS_STYLE := {
	"base": {"fill": Color("#174c3c"), "border": Color("#70d1a0"), "icon": "🏠", "text": Color("#b6f0d0"), "legend": "База: сон, сохранение и склад"},
	"events": {"fill": Color("#4d3c12"), "border": Color("#f0c24b"), "icon": "❗", "text": Color("#ffe08a"), "legend": "Есть что сделать"},
	"locked": {"fill": Color("#1c3358"), "border": Color("#6f9cf0"), "icon": "🔒", "text": Color("#bcd2ff"), "legend": "Нужен ключ: дверь, ящик"},
	"door": {"fill": Color("#1c3358"), "border": Color("#6f9cf0"), "icon": "🔒", "text": Color("#bcd2ff"), "legend": ""},
	"empty": {"fill": Color("#2a2f38"), "border": Color("#646d7c"), "icon": "✓", "text": Color("#9aa3b2"), "legend": "Больше ничего нет"},
	"hostile": {"fill": Color("#5b2530"), "border": Color("#e0707e"), "icon": "☠", "text": Color("#ffb3bd"), "legend": "Враг"},
	"elevator": {"fill": Color("#174a5c"), "border": Color("#7fdcf5"), "icon": "🛗", "text": Color("#c8f2ff"), "legend": "Лифт на другую палубу"},
	"unknown": {"fill": Color("#1b2029"), "border": Color("#4a5363"), "icon": "?", "text": Color("#9aa4b6"), "legend": "Ещё не исследован"},
}
## Порядок строк легенды над картой.
const LEGEND_ORDER := ["base", "events", "locked", "empty", "hostile", "elevator", "unknown"]
const UNSEALED_BADGE := "💨"
const PLAYER_ICON := "🧑‍🚀"


## Фишка игрока: кружок с космонавтом поверх узла.
class PlayerToken extends Control:
	var _label: Label

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label = Label.new()
		_label.text = "🧑‍🚀"
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", 30)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_label.size = size
			queue_redraw()

	func set_side(side: float) -> void:
		if is_equal_approx(size.x, side):
			return
		size = Vector2(side, side)
		_label.add_theme_font_size_override("font_size", int(side * 0.52))

	func _draw() -> void:
		var radius := minf(size.x, size.y) * 0.5
		draw_circle(size * 0.5, radius, Color("#0b0e14"))
		draw_circle(size * 0.5, radius - 3.0, Color("#f5f8ff"))
		draw_circle(size * 0.5, radius - 6.0, Color("#22415c"))


var _map_config: Dictionary = {}
var _nodes: Array = []
var _node_lookup: Dictionary = {}
var _node_order: Dictionary = {}
var _node_controls: Dictionary = {}
var _floor_buttons: Dictionary = {}
var _floors: Array = []
var _known_floor_ids: Array = []
var _hub_node_id: String = ""
var _current_floor_id: String = ""
var _active_floor_id: String = ""
var _player_node_id: String = ""
var _read_only: bool = false
var _virtual_size: Vector2 = DEFAULT_VIRTUAL_SIZE
var _grid_columns: int = DEFAULT_GRID_COLUMNS
var _grid_rows: int = DEFAULT_GRID_ROWS
var _cell_size: Vector2 = DEFAULT_CELL_SIZE
var _module_size: Vector2 = DEFAULT_MODULE_SIZE
var _uses_grid_layout: bool = false
## Занятая часть сетки активной палубы (в виртуальных координатах).
var _view_origin: Vector2 = Vector2.ZERO
var _view_span: Vector2 = DEFAULT_VIRTUAL_SIZE
## Камера: центр (виртуальные координаты) и приближение поверх вписывания.
var _cam: Vector2 = Vector2.ZERO
var _zoom: float = 1.0
var _follow_player: bool = false
var _camera_tween: Tween
## Маршрут: узлы от игрока до цели включительно.
var _route_ids: Array = []
var _token: PlayerToken
## Холст карты внутри рамки (обрезает отсеки и линии за краем).
var _canvas: Control
var _token_virtual: Vector2 = Vector2.ZERO
## Палуба, на которой сейчас стоит фишка (поездка на лифте — прыжок, не скольжение).
var _token_floor: String = ""
var _token_tween: Tween
var _zoom_buttons: Array = []
var _drag_armed: bool = false
var _dragging: bool = false
var _drag_origin: Vector2 = Vector2.ZERO
var _drag_cam_origin: Vector2 = Vector2.ZERO


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(0, 420.0)


## data: map_config, nodes, hub_node_id, current_floor_id, known_floors,
## player_node_id, read_only.
func setup(data: Dictionary) -> void:
	_map_config = (data.get("map_config", {}) as Dictionary).duplicate(true)
	_hub_node_id = str(data.get("hub_node_id", ""))
	_read_only = bool(data.get("read_only", false))
	_read_layout_config()
	_apply_state(data.get("nodes", []), str(data.get("current_floor_id", "")),
		data.get("known_floors", []), str(data.get("player_node_id", "")))
	_active_floor_id = _valid_floor_or_default(_current_floor_id)
	_recompute_view_bounds()
	_reset_camera()
	_token_virtual = _player_virtual()
	_token_floor = _node_floor_id(_node_lookup[_player_node_id]) if _node_lookup.has(_player_node_id) else ""
	_rebuild()


## Обновить узлы на месте (шаг маршрута, туман, замок): камера и активная
## палуба сохраняются, а после поездки на лифте карта переходит на новую палубу.
func update_nodes(nodes: Array, current_floor_id: String, known_floors: Array, player_node_id: String) -> void:
	var floor_before := _current_floor_id
	_apply_state(nodes, current_floor_id, known_floors, player_node_id)
	if _current_floor_id != floor_before or not _is_known_floor(_active_floor_id):
		_active_floor_id = _valid_floor_or_default(_current_floor_id)
	_recompute_view_bounds()
	_clamp_camera()
	_rebuild()


## Подсветить маршрут: path — узлы после игрока (как MapSystem.plan_route).
func set_route(path: Array) -> void:
	_route_ids = [_player_node_id] + path if not path.is_empty() else []
	_redraw()


## Шаг игрока: фишка едет к to_id; камера, если ведёт игрока, — следом.
## Поездка на лифте (другая палуба) — карта переключается, фишка переставляется.
func move_player(to_id: String, duration: float) -> void:
	if not _node_lookup.has(to_id):
		return
	_player_node_id = to_id
	var to_floor := _node_floor_id(_node_lookup[to_id])
	var from_floor := _token_floor
	_token_floor = to_floor
	var target := _node_position(_node_lookup[to_id])
	if _token_tween != null:
		_token_tween.kill()
	if to_floor != _active_floor_id:
		_active_floor_id = to_floor
		_recompute_view_bounds()
		_rebuild()
	if from_floor != to_floor or duration <= 0.0:
		_set_token_virtual(target)
		return
	_token_tween = create_tween()
	_token_tween.tween_method(_set_token_virtual, _token_virtual, target, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Камера к игроку: приблизиться и вести его по маршруту.
func focus_player(animated: bool = true) -> void:
	_follow_player = true
	if _node_lookup.has(_player_node_id):
		var player_floor := _node_floor_id(_node_lookup[_player_node_id])
		if player_floor != _active_floor_id:
			_active_floor_id = player_floor
			_recompute_view_bounds()
			_rebuild()
	_move_camera(_token_virtual, maxf(_zoom, FOLLOW_ZOOM), animated)


## Камера отпускает игрока и показывает палубу целиком (путь окончен).
func overview(animated: bool = true) -> void:
	_follow_player = false
	_move_camera(_view_origin + _view_span * 0.5, 1.0, animated)


func _apply_state(nodes: Array, current_floor_id: String, known_floors: Array, player_node_id: String) -> void:
	_nodes = nodes.duplicate(true)
	_current_floor_id = current_floor_id
	_known_floor_ids = known_floors.duplicate()
	_player_node_id = player_node_id
	_floors = _read_floors()
	_node_lookup.clear()
	_node_order.clear()
	for i in range(_nodes.size()):
		if not (_nodes[i] is Dictionary):
			continue
		var node_id := str(_nodes[i].get("id", ""))
		if node_id == "":
			continue
		_node_lookup[node_id] = _nodes[i]
		_node_order[node_id] = i


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_clamp_camera()
		_layout_controls()
		_redraw()


func _draw() -> void:
	_draw_floor_rail()


## Карта рисуется на холсте, обрезанном рамкой: при приближении линии и
## отсеки за краем не залезают на кнопки палуб.
func _draw_canvas() -> void:
	var rect := _map_rect()
	_canvas.draw_set_transform(-rect.position)
	_canvas.draw_rect(rect, Color("#151a23"), true)
	_draw_grid(rect)
	_draw_connections()
	_draw_route()
	_draw_node_halos()
	_canvas.draw_rect(rect.grow(-1.0), Color("#34475e"), false, 2.0)


func _redraw() -> void:
	queue_redraw()
	if _canvas != null:
		_canvas.queue_redraw()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_node_controls.clear()
	_floor_buttons.clear()
	_zoom_buttons.clear()
	_canvas = Control.new()
	_canvas.name = "MapCanvas"
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_canvas)
	add_child(_canvas)
	_build_node_controls()
	_build_floor_buttons()
	_build_zoom_buttons()
	_token = PlayerToken.new()
	_token.name = "PlayerToken"
	_canvas.add_child(_token)
	_layout_controls()
	_redraw()


func _build_floor_buttons() -> void:
	if _floors.size() <= 1:
		return
	for floor in _floors:
		var floor_id: String = str(floor.get("id", ""))
		var btn := Button.new()
		btn.name = "MapFloor_%s" % floor_id
		btn.text = _floor_button_text(floor)
		btn.tooltip_text = _floor_tooltip(floor)
		btn.add_theme_font_size_override("font_size", UiKit.fs(20))
		_apply_floor_style(btn, floor_id)
		btn.pressed.connect(SoundSystem.play.bind("ui_click"))
		btn.pressed.connect(_select_floor_filter.bind(floor_id))
		add_child(btn)
		_floor_buttons[floor_id] = btn


func _build_zoom_buttons() -> void:
	for entry in [["＋", "MapZoomIn", _zoom_in], ["－", "MapZoomOut", _zoom_out], ["◎", "MapFocusPlayer", focus_player.bind(true)]]:
		var btn := UiKit.button(str(entry[0]), "quiet", 52)
		btn.name = str(entry[1])
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.custom_minimum_size = Vector2(UiKit.fs(52), UiKit.fs(52))
		btn.add_theme_font_size_override("font_size", UiKit.fs(24))
		btn.pressed.connect(entry[2])
		add_child(btn)
		_zoom_buttons.append(btn)


func _build_node_controls() -> void:
	for node_id in _node_lookup.keys():
		var node: Dictionary = _node_lookup[node_id]
		if not _is_node_visible_on_active_floor(node):
			continue
		var btn := Button.new()
		btn.name = "MapNode_%s" % node_id
		btn.text = _node_icon_text(node)
		btn.tooltip_text = _node_tooltip(node)
		btn.disabled = _read_only or not _is_node_targetable(node)
		btn.add_theme_font_size_override("font_size", UiKit.fs(28))
		_apply_node_style(btn, node)
		btn.pressed.connect(func() -> void: node_selected.emit(str(node_id)))
		_canvas.add_child(btn)

		var label: Control = MARQUEE_SCRIPT.new()
		label.name = "MapNodeLabel_%s" % node_id
		_canvas.add_child(label)
		label.setup(_node_label(node), 20, _node_text_color(node))

		var badge: Label = null
		if not bool(node.get("sealed", true)) and not _is_unknown_room(node):
			badge = Label.new()
			badge.text = UNSEALED_BADGE
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.add_theme_font_size_override("font_size", UiKit.fs(20))
			_canvas.add_child(badge)
		_node_controls[node_id] = {"button": btn, "label": label, "badge": badge}


func _select_floor_filter(floor_id: String) -> void:
	if floor_id == _active_floor_id:
		return
	_active_floor_id = floor_id
	_follow_player = false
	_recompute_view_bounds()
	_reset_camera()
	_rebuild()


# --- Камера и ввод ----------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_drag_armed = true
					_dragging = false
					_drag_origin = event.position
					_drag_cam_origin = _cam
				else:
					_drag_armed = false
					_dragging = false
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_in()
					accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_out()
					accept_event()
	elif event is InputEventMouseMotion and _drag_armed:
		var delta: Vector2 = event.position - _drag_origin
		if not _dragging and delta.length() >= DRAG_THRESHOLD:
			_dragging = true
			_follow_player = false
		if _dragging:
			_cam = _drag_cam_origin - delta / _current_scale()
			_clamp_camera()
			_layout_controls()
			_redraw()
			accept_event()
	elif event is InputEventMagnifyGesture:
		_set_zoom(_zoom * event.factor, false)
		accept_event()


func _zoom_in() -> void:
	_set_zoom(_zoom * ZOOM_STEP, true)


func _zoom_out() -> void:
	_set_zoom(_zoom / ZOOM_STEP, true)


func _set_zoom(value: float, animated: bool) -> void:
	_move_camera(_cam, value, animated)


func _move_camera(center: Vector2, zoom: float, animated: bool) -> void:
	if _camera_tween != null:
		_camera_tween.kill()
	zoom = clampf(zoom, 1.0, ZOOM_MAX)
	if not animated or not SettingsSystem.animations:
		_apply_camera(center, zoom)
		return
	var from_cam := _cam
	var from_zoom := _zoom
	_camera_tween = create_tween()
	_camera_tween.tween_method(func(t: float) -> void:
		_apply_camera(from_cam.lerp(center, t), lerpf(from_zoom, zoom, t)), 0.0, 1.0, CAMERA_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _apply_camera(center: Vector2, zoom: float) -> void:
	_cam = center
	_zoom = zoom
	_clamp_camera()
	_layout_controls()
	_redraw()


func _reset_camera() -> void:
	_zoom = 1.0
	_cam = _view_origin + _view_span * 0.5


## Камера не уходит за край занятой части палубы; вписанная палуба стоит по центру.
func _clamp_camera() -> void:
	var rect := _map_rect()
	var half_visible := rect.size / (_current_scale() * 2.0)
	var lo := _view_origin + half_visible
	var hi := _view_origin + _view_span - half_visible
	var center := _view_origin + _view_span * 0.5
	_cam.x = clampf(_cam.x, lo.x, hi.x) if lo.x <= hi.x else center.x
	_cam.y = clampf(_cam.y, lo.y, hi.y) if lo.y <= hi.y else center.y


func _set_token_virtual(value: Vector2) -> void:
	_token_virtual = value
	if _follow_player:
		_cam = value
		_clamp_camera()
	_layout_controls()
	_redraw()


func _player_virtual() -> Vector2:
	if _node_lookup.has(_player_node_id):
		return _node_position(_node_lookup[_player_node_id])
	return _view_origin + _view_span * 0.5


# --- Раскладка ----------------------------------------------------------------------

func _layout_controls() -> void:
	if _canvas != null:
		var rect := _map_rect()
		_canvas.position = rect.position
		_canvas.size = rect.size
	_layout_floor_buttons()
	_layout_node_controls()
	_layout_zoom_buttons()
	_layout_token()


func _layout_floor_buttons() -> void:
	if _floor_buttons.is_empty():
		return
	var rail := _floor_rail_rect()
	var button_height := 58.0
	var gap := 10.0
	var total_height := float(_floor_buttons.size()) * button_height + float(maxi(0, _floor_buttons.size() - 1)) * gap
	var y := rail.position.y + maxf(0.0, (rail.size.y - total_height) * 0.5)
	for floor in _floors:
		var floor_id: String = str(floor.get("id", ""))
		if not _floor_buttons.has(floor_id):
			continue
		var btn: Button = _floor_buttons[floor_id]
		btn.position = Vector2(rail.position.x, y).round()
		btn.size = Vector2(rail.size.x, button_height).round()
		y += button_height + gap


func _layout_zoom_buttons() -> void:
	var rect := _map_rect()
	var x := rect.position.x + 10.0
	for btn in _zoom_buttons:
		var side := float(UiKit.fs(52))
		btn.size = Vector2(side, side)
		btn.position = Vector2(x, rect.position.y + 10.0).round()
		x += side + 8.0


## Отсеки — дети холста: координаты считаются от угла рамки карты.
func _layout_node_controls() -> void:
	var rect := _map_rect()
	var origin := rect.position
	var icon_size := _scaled_module_size()
	var label_gap := 6.0
	var label_width := clampf(_cell_size.x * _current_scale() - 8.0, icon_size.x + 20.0, 280.0)
	var label_height := roundf(float(UiKit.fs(20)) * 1.5)
	for node_id in _node_controls.keys():
		var controls: Dictionary = _node_controls[node_id]
		var btn: Button = controls["button"]
		var label: Control = controls["label"]
		var center := _node_center(_node_lookup[node_id]) - origin
		var inside := Rect2(Vector2.ZERO, rect.size).grow(icon_size.x * 0.5).has_point(center)
		btn.visible = inside
		label.visible = inside
		btn.position = (center - icon_size * 0.5).round()
		btn.size = icon_size.round()
		label.position = Vector2(center.x - label_width * 0.5, center.y + icon_size.y * 0.5 + label_gap).round()
		label.size = Vector2(label_width, label_height).round()
		var badge: Label = controls["badge"]
		if badge != null:
			badge.visible = inside
			badge.position = (center + Vector2(icon_size.x * 0.5 - 14.0, -icon_size.y * 0.5 - 12.0)).round()


## Фишка игрока в углу отсека; её размер растёт вместе с приближением камеры.
func _layout_token() -> void:
	if _token == null:
		return
	var on_floor := _node_lookup.has(_player_node_id) \
		and _node_floor_id(_node_lookup[_player_node_id]) == _active_floor_id
	_token.visible = on_floor
	var icon_size := _scaled_module_size()
	var side := maxf(TOKEN_SIDE, icon_size.x * 0.62)
	var corner := _virtual_to_local(_token_virtual) - _map_rect().position - icon_size * 0.5
	_token.set_side(side)
	_token.position = (corner - Vector2(side * 0.35, side * 0.35)).round()


# --- Рисование ----------------------------------------------------------------------

func _draw_floor_rail() -> void:
	if _floor_buttons.is_empty():
		return
	var rail := _floor_rail_rect()
	draw_rect(rail, Color("#111722"), true)
	draw_rect(rail, Color(0.33, 0.43, 0.55, 0.55), false, 1.0)


## Сетка рисуется только внутри рамки карты.
func _draw_grid(rect: Rect2) -> void:
	if not bool(_map_config.get("grid", true)):
		return
	var color := Color(0.36, 0.46, 0.6, 0.16)
	var step := _cell_size
	if not _uses_grid_layout:
		var raw_step := float(_map_config.get("grid_step", 90))
		if raw_step <= 0.0:
			return
		step = Vector2(raw_step, raw_step)
	var visible := _visible_virtual_rect(rect)
	for col in range(int(floor(visible.position.x / step.x)), int(ceil(visible.end.x / step.x)) + 1):
		var x := _virtual_to_local(Vector2(float(col) * step.x, 0.0)).x
		if x >= rect.position.x and x <= rect.end.x:
			_canvas.draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), color, 2.0)
	for row in range(int(floor(visible.position.y / step.y)), int(ceil(visible.end.y / step.y)) + 1):
		var y := _virtual_to_local(Vector2(0.0, float(row) * step.y)).y
		if y >= rect.position.y and y <= rect.end.y:
			_canvas.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), color, 2.0)


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
			var target_id := str(target_raw)
			if not _node_lookup.has(target_id):
				continue
			var target: Dictionary = _node_lookup[target_id]
			if not _is_node_visible_on_active_floor(target):
				continue
			var edge_key := "%s|%s" % ([node_id, target_id] if node_id < target_id else [target_id, node_id])
			if drawn.has(edge_key):
				continue
			drawn[edge_key] = true
			_canvas.draw_line(_node_center(node), _node_center(target), Color(0.03, 0.04, 0.06, 0.75), 8.0, true)
			_canvas.draw_line(_node_center(node), _node_center(target), _connection_color(node, target), 3.0, true)


## Маршрут: жёлтая линия по отсекам активной палубы и кольцо у цели.
func _draw_route() -> void:
	if _route_ids.size() < 2:
		return
	var width := maxf(6.0, 5.0 * _zoom)
	var last_on_floor := ""
	for i in range(_route_ids.size() - 1):
		var a := str(_route_ids[i])
		var b := str(_route_ids[i + 1])
		if not _node_lookup.has(a) or not _node_lookup.has(b):
			continue
		var a_node: Dictionary = _node_lookup[a]
		var b_node: Dictionary = _node_lookup[b]
		if _node_floor_id(b_node) == _active_floor_id:
			last_on_floor = b
		if _node_floor_id(a_node) != _active_floor_id or _node_floor_id(b_node) != _active_floor_id:
			continue
		var from := _node_center(a_node)
		var to := _node_center(b_node)
		_canvas.draw_line(from, to, Color(0.05, 0.04, 0.0, 0.85), width + 6.0, true)
		_canvas.draw_line(from, to, ROUTE_COLOR, width, true)
		_canvas.draw_circle(to, width * 0.9, ROUTE_COLOR)
	if last_on_floor != "":
		var center := _node_center(_node_lookup[last_on_floor])
		var radius := maxf(_scaled_module_size().x, _scaled_module_size().y) * 0.78
		_canvas.draw_arc(center, radius, 0.0, TAU, 48, ROUTE_COLOR, 4.0, true)


func _draw_node_halos() -> void:
	var icon_size := _scaled_module_size()
	for node in _nodes:
		if not (node is Dictionary) or not _is_node_visible_on_active_floor(node):
			continue
		var border: Color = _style(node)["border"]
		_canvas.draw_circle(_node_center(node), maxf(icon_size.x, icon_size.y) * 0.72, Color(border, 0.16))


# --- Геометрия ------------------------------------------------------------------------

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
		return Vector2(maxf(1.0, float(raw.get("x", fallback.x))), maxf(1.0, float(raw.get("y", fallback.y))))
	if raw is int or raw is float:
		var side := maxf(1.0, float(raw))
		return Vector2(side, side)
	return fallback


func _map_rect() -> Rect2:
	var area := _content_rect()
	if _floor_buttons.size() > 0 or _floors.size() > 1:
		var reserved := FLOOR_RAIL_WIDTH + FLOOR_RAIL_GAP
		if _floor_side() == "left":
			area.position.x += reserved
		area.size.x -= reserved
	area.size = area.size.max(Vector2.ONE)
	return area


func _visible_virtual_rect(rect: Rect2) -> Rect2:
	var visible_span := rect.size / _current_scale()
	return Rect2(_cam - visible_span * 0.5, visible_span)


## Занятые клетки активной палубы (в виртуальных координатах).
func _recompute_view_bounds() -> void:
	var min_point := Vector2.INF
	var max_point := -Vector2.INF
	for node in _nodes:
		if not (node is Dictionary) or not _is_node_visible_on_active_floor(node):
			continue
		var point := _node_position(node)
		min_point = min_point.min(point)
		max_point = max_point.max(point)
	if min_point.x > max_point.x:
		_view_origin = Vector2.ZERO
		_view_span = _virtual_size
		return
	var pad := _cell_size * 0.6
	_view_origin = min_point - pad
	_view_span = Vector2(
		maxf(_cell_size.x, max_point.x - min_point.x + pad.x * 2.0),
		maxf(_cell_size.y, max_point.y - min_point.y + pad.y * 2.0)
	)


func _floor_rail_rect() -> Rect2:
	var area := _content_rect()
	var x := area.position.x
	if _floor_side() != "left":
		x = area.position.x + area.size.x - FLOOR_RAIL_WIDTH
	return Rect2(Vector2(x, area.position.y), Vector2(FLOOR_RAIL_WIDTH, area.size.y))


func _content_rect() -> Rect2:
	var available := size
	if available.x <= 0.0 or available.y <= 0.0:
		available = custom_minimum_size.max(Vector2.ONE)
	return Rect2(Vector2(MAP_PADDING, MAP_PADDING), (available - Vector2(MAP_PADDING, MAP_PADDING) * 2.0).max(Vector2.ONE))


func _floor_side() -> String:
	return "left" if str(_map_config.get("floor_buttons_side", "right")) == "left" else "right"


func _virtual_to_local(point: Vector2) -> Vector2:
	return _map_rect().get_center() + (point - _cam) * _current_scale()


func _fit_scale() -> float:
	var rect := _map_rect()
	return minf(minf(rect.size.x / _view_span.x, rect.size.y / _view_span.y), MAX_VIEW_SCALE)


func _current_scale() -> float:
	return _fit_scale() * _zoom


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
	var idx := int(_node_order.get(str(node.get("id", "")), 0))
	var count: int = maxi(1, _nodes.size())
	var angle := TAU * float(idx) / float(count) - PI * 0.5
	var radius: float = minf(_virtual_size.x, _virtual_size.y) * 0.32
	return _virtual_size * 0.5 + Vector2(cos(angle), sin(angle)) * radius


func _scaled_module_size() -> Vector2:
	var raw_size := _module_size * _current_scale()
	var side := clampf(minf(raw_size.x, raw_size.y), MIN_MODULE_SIDE, MAX_MODULE_SIDE)
	return Vector2(side, side)


func _node_map(node: Dictionary) -> Dictionary:
	var cfg = node.get("map", {})
	return cfg if cfg is Dictionary else {}


# --- Палубы -----------------------------------------------------------------------

## Только палубы, где игрок уже был.
func _read_floors() -> Array:
	var result: Array = []
	var raw_floors = _map_config.get("floors", [])
	if not (raw_floors is Array):
		return result
	for floor in raw_floors:
		if not (floor is Dictionary):
			continue
		var floor_id := str(floor.get("id", ""))
		if floor_id != "" and _known_floor_ids.has(floor_id):
			result.append(floor.duplicate(true))
	return result


func _valid_floor_or_default(floor_id: String) -> String:
	if _is_known_floor(floor_id):
		return floor_id
	if _floors.size() > 0:
		return str(_floors[0].get("id", ""))
	return ""


func _is_known_floor(floor_id: String) -> bool:
	if _floors.is_empty():
		return true
	for floor in _floors:
		if str(floor.get("id", "")) == floor_id:
			return true
	return false


func _node_floor_id(node: Dictionary) -> String:
	var floor_id := str(_node_map(node).get("floor", ""))
	if floor_id != "":
		return floor_id
	var configured := str(_map_config.get("default_floor", ""))
	return configured if configured != "" else _current_floor_id


## Короткая метка палубы с кнопки справа от карты: «02», «B».
func _floor_label(floor_id: String) -> String:
	for floor in _map_config.get("floors", []):
		if floor is Dictionary and str(floor.get("id", "")) == floor_id:
			return str(floor.get("label", floor_id))
	return floor_id


func _floor_title(floor_id: String) -> String:
	for floor in _map_config.get("floors", []):
		if floor is Dictionary and str(floor.get("id", "")) == floor_id:
			return str(floor.get("title", floor_id))
	return floor_id


func _floor_button_text(floor: Dictionary) -> String:
	var label := str(floor.get("label", floor.get("id", "?")))
	return label + (" " + PLAYER_ICON if str(floor.get("id", "")) == _current_floor_id else "")


func _floor_tooltip(floor: Dictionary) -> String:
	var floor_id := str(floor.get("id", ""))
	var lines := [str(floor.get("title", floor_id))]
	if floor_id == _current_floor_id:
		lines.append("Ты здесь")
	return "\n".join(lines)


# --- Узлы ---------------------------------------------------------------------------

func _is_node_visible_on_active_floor(node: Dictionary) -> bool:
	if not bool(node.get("fog_visible", true)):
		return false
	return _active_floor_id == "" or _node_floor_id(node) == _active_floor_id


## Узел можно выбрать целью маршрута: он не заперт наглухо (без замка).
func _is_node_targetable(node: Dictionary) -> bool:
	if str(node.get("state", "locked")) != "locked":
		return true
	var lock = node.get("lock", {})
	return lock is Dictionary and not lock.is_empty()


func _is_elevator_node(node: Dictionary) -> bool:
	return str(_node_map(node).get("kind", "")) == "elevator"


func _is_unknown_room(node: Dictionary) -> bool:
	return str(node.get("status", "")) == "unknown"


func _style(node: Dictionary) -> Dictionary:
	return STATUS_STYLE.get(str(node.get("status", "unknown")), STATUS_STYLE["unknown"])


## Подпись под узлом. Лифт подписан палубой, куда ведёт: «Лифт к 02» —
## та же метка, что на кнопке палубы.
func _node_label(node: Dictionary) -> String:
	var cfg := _node_map(node)
	if _is_unknown_room(node):
		return "Неизвестно"
	if str(node.get("state", "locked")) == "locked" and not bool(cfg.get("reveal_title_when_locked", true)):
		return "Неизвестно"
	if _is_elevator_node(node) and str(cfg.get("target_floor", "")) != "":
		return "Лифт к %s" % _floor_label(str(cfg["target_floor"]))
	return str(cfg.get("label", node.get("title", node.get("id", ""))))


func _node_icon_text(node: Dictionary) -> String:
	if str(node.get("status", "")) == "door" and bool(node.get("unlockable", false)):
		return "🔑"
	return str(_style(node)["icon"])


func _node_text_color(node: Dictionary) -> Color:
	return _style(node)["text"]


func _node_tooltip(node: Dictionary) -> String:
	var status := str(node.get("status", "unknown"))
	if _is_unknown_room(node):
		return "Неизвестный отсек\nПалуба: " + _floor_title(_node_floor_id(node))
	var cfg := _node_map(node)
	var lines := [
		str(node.get("title", node.get("id", ""))),
		str(STATUS_STYLE["locked"]["legend"]) if status == "door" else str(_style(node)["legend"]),
		"Палуба: " + _floor_title(_node_floor_id(node)),
		"Герметично" if bool(node.get("sealed", true)) else "Без давления — дороже по O2",
	]
	if str(node.get("id", "")) == _player_node_id:
		lines.append("Ты здесь")
	if _is_elevator_node(node):
		var target_floor_id := str(cfg.get("target_floor", ""))
		if target_floor_id != "":
			lines.append("Ведёт: " + _floor_title(target_floor_id))
	if status == "door":
		var lock = node.get("lock", {})
		if lock is Dictionary and not lock.is_empty():
			lines.append("Ключ подходит" if bool(node.get("unlockable", false)) else EffectResolver.lock_hint(lock))
	var note := str(cfg.get("note", ""))
	if note != "":
		lines.append(note)
	return "\n".join(lines)


func _connection_color(a: Dictionary, b: Dictionary) -> Color:
	var a_state: String = str(a.get("state", "locked"))
	var b_state: String = str(b.get("state", "locked"))
	if a_state == "locked" or b_state == "locked":
		return Color(0.42, 0.48, 0.57, 0.34)
	if a_state == "dangerous" or b_state == "dangerous":
		return Color("#a95b67")
	return Color("#5ea9c9")


func _apply_floor_style(btn: Button, floor_id: String) -> void:
	var is_active := floor_id == _active_floor_id
	var normal := Color("#22415c") if is_active else Color("#1a2230")
	var border := Color("#8abce0") if is_active else Color("#3b4c61")
	btn.add_theme_color_override("font_color", Color("#ffffff") if is_active else Color("#c9d3e4"))
	btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
	btn.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	btn.add_theme_stylebox_override("normal", _box(normal, border, 1))
	btn.add_theme_stylebox_override("hover", _box(normal.lightened(0.12), border.lightened(0.18), 1))
	btn.add_theme_stylebox_override("pressed", _box(normal.darkened(0.2), border.lightened(0.26), 2))
	btn.add_theme_stylebox_override("focus", _box(normal.lightened(0.12), Color("#d6f2ff"), 2))


func _apply_node_style(btn: Button, node: Dictionary) -> void:
	var style := _style(node)
	var normal: Color = style["fill"]
	var border: Color = style["border"]
	if str(node.get("status", "")) == "door" and bool(node.get("unlockable", false)):
		border = Color("#f0c24b")
	if str(node.get("id", "")) == _player_node_id:
		border = Color("#f5f8ff")
	btn.add_theme_color_override("font_color", Color("#f4f7fb"))
	btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
	btn.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	btn.add_theme_color_override("font_disabled_color", Color("#c3cad6"))
	btn.add_theme_stylebox_override("normal", _box(normal, border, 2))
	btn.add_theme_stylebox_override("hover", _box(normal.lightened(0.15), border.lightened(0.15), 3))
	btn.add_theme_stylebox_override("pressed", _box(normal.darkened(0.2), border.lightened(0.25), 3))
	btn.add_theme_stylebox_override("disabled", _box(normal.darkened(0.1), border.darkened(0.15), 2))
	btn.add_theme_stylebox_override("focus", _box(normal.lightened(0.15), Color("#d6f2ff"), 3))


func _box(bg: Color, border: Color, border_width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(10)
	box.content_margin_left = 0
	box.content_margin_right = 0
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	return box
