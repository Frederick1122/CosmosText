extends VBoxContainer
## Экран развития: кольцевая карта дерева навыков, карточка выбранного узла,
## карта известного мира и легенда секторов. Игровой логики не содержит:
## читает SkillTreeSystem и вызывает только buy(); перерисовывается по сигналу
## changed. Строится из кода, как CharacterPanel / WorkbenchPanel.

const UiKit = preload("res://scenes/ui/UiKit.gd")

var selected_id: String = ""


func _init() -> void:
	name = "SkillTreePanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 14)


func _ready() -> void:
	if not SkillTreeSystem.changed.is_connected(_rebuild):
		SkillTreeSystem.changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_build_header()
	_build_map()
	_build_detail()
	_build_knowledge()
	_build_legend()


# --- Заголовок -----------------------------------------------------------------

func _build_header() -> void:
	var progress := SkillTreeSystem.progress()
	add_child(UiKit.section("Очки развития: %d · Куплено %d из %d" % [
		CharacterSystem.skill_points, int(progress.get("owned", 0)), int(progress.get("known", 0))]))
	var origin_id := SkillTreeSystem.get_origin_id()
	if origin_id == "":
		return
	var origin := SkillTreeSystem.get_origin()
	add_child(UiKit.text("Происхождение: %s" % str(origin.get("name", origin_id)), 24, UiKit.ACCENT_COLOR))
	var debuff := str(origin.get("debuff", ""))
	if debuff != "":
		add_child(UiKit.text("Слабость: " + debuff, 20, UiKit.BAD_COLOR))


# --- Карта ---------------------------------------------------------------------

func _build_map() -> void:
	var view := RingView.new()
	view.node_selected = _on_node_selected
	view.setup(SkillTreeSystem.get_nodes(), SkillTreeSystem.get_sectors(), selected_id)
	add_child(view)


func _on_node_selected(node_id: String) -> void:
	selected_id = node_id
	_rebuild()


# --- Карточка узла -------------------------------------------------------------

func _build_detail() -> void:
	var card := UiKit.card(self)
	var data := SkillTreeSystem.get_node_data(selected_id)
	if selected_id == "" or data.is_empty():
		card.add_child(UiKit.text("Выбери узел на кольце.", 22, UiKit.MUTED_COLOR))
		return
	var state := SkillTreeSystem.node_state(selected_id)
	var cost := SkillTreeSystem.node_cost(selected_id)
	if state == SkillTreeSystem.NodeState.UNKNOWN:
		card.add_child(UiKit.text("???", 26, UiKit.MUTED_COLOR))
		card.add_child(UiKit.text("Узел ещё не открыт — нужны знание или практика.", 21, UiKit.MUTED_COLOR))
		return

	card.add_child(UiKit.text(str(data.get("name", selected_id)), 26, UiKit.TITLE_COLOR))
	var type_id := str(data.get("type", "small"))
	card.add_child(UiKit.text("%s · %s · %d очк." % [
		str(SkillTreeSystem.TYPE_TITLES.get(type_id, type_id)),
		str(SkillTreeSystem.RING_TITLES.get(str(data.get("ring", "inner")), "")),
		cost], 21, SkillTreeSystem.TYPE_COLORS.get(type_id, UiKit.ACCENT_COLOR)))

	var description := str(data.get("description", ""))
	if description != "":
		card.add_child(UiKit.text(description, 21))
	var stats = data.get("stats", {})
	if stats is Dictionary:
		var stats_text := CharacterSystem.describe_stats(stats)
		if stats_text != "":
			card.add_child(UiKit.text(stats_text, 21, UiKit.ACCENT_COLOR))
	var tags = data.get("tags", [])
	if tags is Array and not tags.is_empty():
		card.add_child(UiKit.text("Метки: " + ", ".join(PackedStringArray(tags)), 19, UiKit.MUTED_COLOR))

	if state == SkillTreeSystem.NodeState.OWNED:
		card.add_child(UiKit.text("✔ Изучено", 24, UiKit.GOOD_COLOR))
		return
	var reason := SkillTreeSystem.lock_reason(selected_id)
	if reason != "":
		card.add_child(UiKit.text(reason, 20, UiKit.BAD_COLOR))
	var btn := UiKit.button("⭐ Взять (%d очк.)" % cost, "default", 60)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.disabled = not SkillTreeSystem.can_buy(selected_id)
	btn.pressed.connect(_buy.bind(selected_id))
	card.add_child(btn)


func _buy(node_id: String) -> void:
	SkillTreeSystem.buy(node_id)


# --- Знание и легенда ----------------------------------------------------------

func _build_knowledge() -> void:
	add_child(UiKit.section("Карта известного мира"))
	var entries := SkillTreeSystem.all_knowledge()
	if entries.is_empty():
		add_child(UiKit.text("Знание пока не открыто.", 21, UiKit.MUTED_COLOR))
		return
	for entry in entries:
		var data: Dictionary = entry
		if bool(data.get("known", false)):
			var source := str(data.get("source", ""))
			var line := str(data.get("name", ""))
			if source != "":
				line += " — " + source
			add_child(UiKit.text(line, 21, UiKit.TEXT_COLOR))
		else:
			add_child(UiKit.text("??? — направление не открыто", 21, UiKit.MUTED_COLOR))


func _build_legend() -> void:
	add_child(UiKit.section("Сектора дерева"))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 14)
	row.add_theme_constant_override("v_separation", 6)
	for sector in SkillTreeSystem.get_sectors():
		var data: Dictionary = sector
		var known := bool(data.get("known", false))
		var color := UiKit.MUTED_COLOR
		if known:
			color = Color.from_string(str(data.get("color", "")), UiKit.ACCENT_COLOR)
		var label := UiKit.text(("● " if known else "○ ") + str(data.get("name", "")), 18, color)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		row.add_child(label)
	add_child(row)


## Кольцевая карта дерева. Только отрисовка и выбор узла: вокруг внешнего
## кольца оставлен отдельный пояс для названий секторов, поэтому разделители
## и ветки не заходят на текст даже при увеличенном шрифте.
class RingView extends Control:
	const UiKit = preload("res://scenes/ui/UiKit.gd")
	const RING_R := {"inner": 0.36, "middle": 0.66, "outer": 0.95}
	const NODE_R := 16.0
	const HIT_R := 28.0
	const BRIDGE_COLOR := Color("#7fc8a8")
	const GRID_COLOR := Color("#2e3a4c")

	var selected_id: String = ""
	var node_selected: Callable = Callable()

	var _nodes: Array = []
	var _sectors: Array = []
	var _index: Dictionary = {}
	var _center := Vector2.ZERO
	var _r := 0.0
	var _hit: Dictionary = {}

	func _init() -> void:
		name = "SkillRingMap"
		custom_minimum_size = Vector2(0, 800)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP

	func setup(nodes: Array, sector_list: Array, selected: String) -> void:
		_nodes = nodes
		_sectors = sector_list
		selected_id = selected
		_index.clear()
		for i in range(_sectors.size()):
			_index[str((_sectors[i] as Dictionary).get("id", ""))] = i
		queue_redraw()

	func _dir(angle: float) -> Vector2:
		return Vector2(cos(angle), sin(angle))

	func _angle_of(sector_id: String) -> float:
		return -PI * 0.5 + float(int(_index.get(sector_id, 0))) * TAU / 8.0

	func _color_of(sector_id: String) -> Color:
		var i := int(_index.get(sector_id, -1))
		if i < 0:
			return UiKit.ACCENT_COLOR
		return Color.from_string(str((_sectors[i] as Dictionary).get("color", "")), UiKit.ACCENT_COLOR)

	func _draw() -> void:
		var side := minf(size.x, size.y)
		if side <= 0.0:
			return
		_center = size * 0.5
		_r = side * 0.40
		_hit.clear()
		_draw_frame()
		_draw_bridges()
		_draw_nodes()

	## Сектор-клин, кольца, разделители и подписи. Неоткрытые сектора не рисуются.
	func _draw_frame() -> void:
		var slice := TAU / 8.0
		for sector in _sectors:
			var data: Dictionary = sector
			if not bool(data.get("known", false)):
				continue
			var a := _angle_of(str(data.get("id", "")))
			_wedge(a - slice * 0.42, a + slice * 0.42, _r * 0.30, _r, Color(_color_of(str(data.get("id", ""))), 0.10))
		for ratio in [0.36, 0.66, 0.95]:
			draw_arc(_center, _r * float(ratio), 0.0, TAU, 96, GRID_COLOR, 1.5, true)
		var font := ThemeDB.fallback_font
		var label_size := int(UiKit.fs(17))
		for sector in _sectors:
			var data: Dictionary = sector
			if not bool(data.get("known", false)):
				continue
			var a := _angle_of(str(data.get("id", "")))
			for border in [a - slice * 0.5, a + slice * 0.5]:
				draw_line(_center + _dir(border) * (_r * 0.30), _center + _dir(border) * _r,
					Color(GRID_COLOR, 0.9), 1.5, true)
			var label := str(data.get("name", ""))
			var sz := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size)
			draw_string(font, _center + _dir(a) * (_r * 1.14) - Vector2(sz.x * 0.5, sz.y * 0.35),
				label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, _color_of(str(data.get("id", ""))))

	func _wedge(a0: float, a1: float, r_in: float, r_out: float, color: Color) -> void:
		var pts := PackedVector2Array()
		var steps := 10
		for k in range(steps + 1):
			pts.append(_center + _dir(lerpf(a0, a1, float(k) / float(steps))) * r_out)
		for k in range(steps, -1, -1):
			pts.append(_center + _dir(lerpf(a0, a1, float(k) / float(steps))) * r_in)
		draw_colored_polygon(pts, color)

	## Перемычки: тонкая дуга между сектором узла-моста и сектором его предка.
	func _draw_bridges() -> void:
		for node in _nodes:
			var data: Dictionary = node
			if str(data.get("type", "")) != "bridge":
				continue
			var sector_id := str(data.get("sector", ""))
			if not _index.has(sector_id):
				continue
			var sectors: Array = [sector_id]
			var requires = SkillTreeSystem.get_node_data(str(data.get("id", ""))).get("requires", {})
			var prevs = requires.get("nodes", []) if requires is Dictionary else []
			if prevs is Array:
				for prev in prevs:
					var prev_sector := str(SkillTreeSystem.get_node_data(str(prev)).get("sector", ""))
					if _index.has(prev_sector) and not sectors.has(prev_sector):
						sectors.append(prev_sector)
			if sectors.size() < 2:
				continue
			var rr := _r * float(RING_R.get(str(data.get("ring", "inner")), 0.36))
			var a1 := _angle_of(str(sectors[0]))
			var a2 := _angle_of(str(sectors[1]))
			var sweep := fposmod(a2 - a1, TAU)
			if sweep > PI:
				a1 = a2
				sweep = TAU - sweep
			draw_arc(_center, rr, a1, a1 + sweep, 24, Color(BRIDGE_COLOR, 0.45), 2.0, true)

	func _draw_nodes() -> void:
		var font := ThemeDB.fallback_font
		var q_size := int(UiKit.fs(18))
		for node in _nodes:
			var data: Dictionary = node
			var sector_id := str(data.get("sector", ""))
			if not _index.has(sector_id):
				continue
			if not bool((_sectors[int(_index[sector_id])] as Dictionary).get("known", false)):
				continue  # скрытый сектор не рисует и своих узлов
			var id := str(data.get("id", ""))
			var pos := _center + _dir(_angle_of(sector_id)) \
				* (_r * float(RING_R.get(str(data.get("ring", "inner")), 0.36)))
			_hit[id] = pos
			var col := _color_of(sector_id)
			match int(data.get("state", 0)):
				0:  # UNKNOWN — размытый знак вопроса
					draw_circle(pos, 12.0, Color("#232a35"))
					draw_arc(pos, 12.0, 0.0, TAU, 28, Color("#4a5568"), 2.0, true)
					var sz := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, q_size)
					draw_string(font, pos + Vector2(-sz.x * 0.5, q_size * 0.36), "?",
						HORIZONTAL_ALIGNMENT_LEFT, -1, q_size, UiKit.MUTED_COLOR)
				1:  # LOCKED — тёмный кружок в цвете сектора
					draw_circle(pos, NODE_R, Color("#1b222c"))
					draw_arc(pos, NODE_R, 0.0, TAU, 32, col.darkened(0.15), 2.5, true)
				2:  # AVAILABLE — заливка цветом сектора
					draw_circle(pos, NODE_R, col)
					draw_arc(pos, NODE_R, 0.0, TAU, 32, col.lightened(0.35), 2.0, true)
				_:  # OWNED — ярче и с жирным кольцом
					draw_circle(pos, NODE_R, col.lightened(0.3))
					draw_arc(pos, NODE_R + 3.0, 0.0, TAU, 36, UiKit.TITLE_COLOR, 3.5, true)
			if id == selected_id:
				draw_arc(pos, NODE_R + 6.0, 0.0, TAU, 40, Color("#ffffff"), 2.5, true)

	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton) or not event.pressed \
				or event.button_index != MOUSE_BUTTON_LEFT:
			return
		var best := ""
		var best_dist := HIT_R
		for id in _hit.keys():
			var dist: float = (event.position as Vector2).distance_to(_hit[id])
			if dist <= best_dist:
				best_dist = dist
				best = str(id)
		if best == "":
			return
		selected_id = best
		if node_selected.is_valid():
			node_selected.call(best)
		queue_redraw()
		accept_event()
