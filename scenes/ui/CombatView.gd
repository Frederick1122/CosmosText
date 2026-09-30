extends VBoxContainer
## Экран боя в духе Neo Scavenger: сверху две карточки участников (состояние,
## оружие, последний манёвр), между ними — дистанция, ниже — сетка манёвров и
## журнал схватки. Логики боя не содержит: читает CombatSystem.get_state() и
## сообщает выбранный манёвр наружу.

signal move_selected(move_id: String, payload: Variant)

const UiKit = preload("res://scenes/ui/UiKit.gd")

const LOG_LINES := 7
const LOG_COLORS := {
	"hit": Color("#a7e3c4"),
	"damage": Color("#f0b0b9"),
	"move": Color("#9fd3e6"),
	"end": Color("#e0b153"),
}

var state: Dictionary = {}


func _init() -> void:
	name = "CombatView"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 14)


func setup(combat_state: Dictionary) -> void:
	state = combat_state.duplicate(true)
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var row := HBoxContainer.new()
	row.name = "CombatSides"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	row.add_child(_side_card(
		"Вы",
		int(state.get("player_hp", 0)),
		int(state.get("player_max_hp", 1)),
		str(state.get("player_weapon", "")),
		str(state.get("player_last_move", "")),
		state.get("player_conditions", []),
		Color("#5ea9c9"),
		UiKit.portrait("player", false, 128)
	))
	row.add_child(_side_card(
		str(state.get("enemy_name", "Противник")),
		int(state.get("enemy_hp", 0)),
		int(state.get("enemy_max_hp", 1)),
		str(state.get("enemy_weapon", "")),
		str(state.get("enemy_last_move", "")),
		state.get("enemy_conditions", []),
		Color("#b86d79"),
		UiKit.portrait(str(state.get("enemy_id", "")), true, 128)
	))
	add_child(row)

	add_child(_range_card())

	if int(CombatSystem.state) != CombatSystem.State.PLAYER_TURN:
		add_child(UiKit.text("…", 24, UiKit.MUTED_COLOR))
	else:
		_build_moves()
	_build_log()


## Карточка участника: полоса здоровья, оружие, последний манёвр, состояния.
func _side_card(
	title: String, hp: int, max_hp: int, weapon: String, last_move: String,
	conditions: Array, accent: Color, portrait: TextureRect = null
) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiKit.box(Color("#171d27"), Color("#2e3a4c"), 1, 12))
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	box.add_child(UiKit.text(title, 24, UiKit.TITLE_COLOR))
	if portrait != null:
		portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(portrait)
	box.add_child(_hp_bar(hp, max_hp, accent))
	box.add_child(UiKit.text("%d/%d HP" % [hp, max_hp], 20))
	if weapon != "":
		box.add_child(UiKit.text("Оружие: %s" % weapon, 19, UiKit.MUTED_COLOR))
	box.add_child(UiKit.text("Манёвр: %s" % (last_move if last_move != "" else "—"), 19, UiKit.MUTED_COLOR))
	for condition in conditions:
		box.add_child(UiKit.text("• %s" % str(condition), 19, UiKit.EXIT_COLOR))
	return panel


func _hp_bar(hp: int, max_hp: int, accent: Color) -> Control:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	bar.max_value = maxi(1, max_hp)
	bar.value = clampi(hp, 0, maxi(1, max_hp))
	bar.add_theme_stylebox_override("background", UiKit.box(Color("#10141b"), Color("#2e3a4c"), 1, 0))
	bar.add_theme_stylebox_override("fill", UiKit.box(accent, accent, 0, 0))
	return bar


## Дистанция: точками, как линейка расстояния в Neo Scavenger.
func _range_card() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiKit.box(Color("#141922"), Color("#2e3a4c"), 1, 12))
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var steps := int(state.get("range", 0))
	var max_steps := int(state.get("max_range", 5))
	var ruler := "Вы "
	for i in range(max_steps + 1):
		ruler += "◆" if i == steps else "·"
	ruler += " цель"
	var label := UiKit.text(ruler, 26, UiKit.ACCENT_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var hint := "вплотную" if steps <= 1 else "дистанция: %d шага(ов)" % steps
	var hint_label := UiKit.text(hint, 20, UiKit.MUTED_COLOR)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint_label)
	return panel


func _build_moves() -> void:
	add_child(UiKit.section("Манёвр этого хода"))
	var grid := GridContainer.new()
	grid.name = "CombatMoves"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	add_child(grid)

	for move in state.get("moves", []):
		var move_id := str(move.get("id", ""))
		var enabled := bool(move.get("enabled", false))
		var label := str(move.get("label", move_id))
		if not enabled and str(move.get("reason", "")) != "":
			label += " — " + str(move.get("reason", ""))
		var kind := "default"
		if move_id == "flee":
			kind = "exit"
		elif move_id == "defend" or move_id == "aim":
			kind = "quiet"
		var btn := UiKit.button(label, kind, 72)
		btn.name = "CombatMove_%s" % move_id
		btn.disabled = not enabled
		btn.add_theme_font_size_override("font_size", UiKit.fs(20))
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func() -> void: move_selected.emit(move_id, null))
		grid.add_child(btn)

	for special in state.get("available_specials", []):
		var sid := str(special.get("id", ""))
		var btn := UiKit.button(str(special.get("label", sid)), "default", 72)
		btn.name = "CombatSpecial_%s" % sid
		btn.add_theme_font_size_override("font_size", UiKit.fs(20))
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(func() -> void: move_selected.emit("special", sid))
		add_child(btn)

	var consumables := _consumables()
	if consumables.is_empty():
		return
	add_child(UiKit.section("Расходники (тратят ход)"))
	for item_id in consumables:
		var data := InventorySystem.get_item_data(item_id)
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		var icon := UiKit.item_icon(item_id, 44)
		if icon != null:
			row.add_child(icon)
		var btn := UiKit.button("Использовать: " + str(data.get("name", item_id)), "quiet", 64)
		btn.name = "CombatItem_%s" % item_id
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func() -> void: move_selected.emit("use_item", item_id))
		row.add_child(btn)
		add_child(row)


func _consumables() -> Array:
	var result: Array = []
	for entry in InventorySystem.get_slots():
		var item_id: String = entry.get("id", "")
		if InventorySystem.get_item_data(item_id).get("category", "") == "consumable":
			result.append(item_id)
	return result


func _build_log() -> void:
	var entries: Array = state.get("log", [])
	if entries.is_empty():
		return
	add_child(UiKit.section("Схватка"))
	var first := maxi(0, entries.size() - LOG_LINES)
	for i in range(first, entries.size()):
		var entry = entries[i]
		var text := str(entry.get("text", "")) if entry is Dictionary else str(entry)
		var kind := str(entry.get("kind", "info")) if entry is Dictionary else "info"
		add_child(UiKit.text("— " + text, 21, LOG_COLORS.get(kind, UiKit.TEXT_COLOR)))
