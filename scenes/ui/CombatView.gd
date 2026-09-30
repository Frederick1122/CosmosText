extends VBoxContainer
## Экран боя в духе Neo Scavenger: сверху две карточки участников (состояние,
## оружие, последний манёвр), между ними — дистанция, ниже — сетка манёвров и
## журнал схватки. Логики боя не содержит: читает CombatSystem.get_state() и
## сообщает выбранный манёвр наружу.
##
## Эффекты ударов: записи журнала текущего хода несут fx (кто получил удар и
## сколько, 0 — промах). По очереди записей карточка цели вздрагивает и
## вспыхивает, над портретом всплывает урон или «мимо», полоса HP стекает
## до нового значения; удар по игроку ещё и окрашивает экран красным.
## Проигрываются только при включённых анимациях (SettingsSystem).

signal move_selected(move_id: String, payload: Variant)
## «Продолжить» под итогом схватки (победа или побег).
signal finished()

const UiKit = preload("res://scenes/ui/UiKit.gd")

const LOG_LINES := 7
const LOG_COLORS := {
	"hit": UiKit.GOOD_COLOR,
	"damage": UiKit.BAD_COLOR,
	"move": UiKit.ACCENT_COLOR,
	"end": UiKit.EXIT_COLOR,
}
## Пауза между ударами одного хода: сначала манёвр игрока, затем ответ врага.
const FX_STEP := 0.5
const FX_START := 0.12
const FLOAT_RISE := 90.0
const FLOAT_TIME := 0.95
## Сила встряски карточки (поворот в четвертях градуса, сжатие): удар в упор
## трясёт сильнее выстрела.
const SHAKE := {"melee": 16.0, "ranged": 9.0}
const PLAYER_ACCENT := Color("#5ea9c9")
const ENEMY_ACCENT := Color("#b86d79")
## Счётчик HP в карточке; во время эффекта стекает вместе с полосой.
const HP_TEXT := "%d/%d HP"

var state: Dictionary = {}
var _animate: bool = false
## side ("player" | "enemy") -> { panel, portrait, bar, hp_label, hp, max_hp }
var _sides: Dictionary = {}


func _init() -> void:
	name = "CombatView"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 14)


## animate — ход новый, его удары ещё не показаны.
func setup(combat_state: Dictionary, animate: bool = false) -> void:
	state = combat_state.duplicate(true)
	_animate = animate and SettingsSystem.animations
	_rebuild()
	if _animate:
		_play_turn_fx()
	elif str(state.get("outcome", "")) == "won":
		_sides["enemy"]["panel"].modulate = _defeated_tint()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_sides.clear()

	var row := HBoxContainer.new()
	row.name = "CombatSides"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	row.add_child(_side_card(
		"player",
		"Вы",
		int(state.get("player_hp", 0)),
		int(state.get("player_max_hp", 1)),
		str(state.get("player_weapon", "")),
		str(state.get("player_last_move", "")),
		state.get("player_conditions", []),
		PLAYER_ACCENT,
		UiKit.portrait("player", false, 128)
	))
	row.add_child(_side_card(
		"enemy",
		str(state.get("enemy_name", "Противник")),
		int(state.get("enemy_hp", 0)),
		int(state.get("enemy_max_hp", 1)),
		str(state.get("enemy_weapon", "")),
		str(state.get("enemy_last_move", "")),
		state.get("enemy_conditions", []),
		ENEMY_ACCENT,
		UiKit.portrait(str(state.get("enemy_id", "")), true, 128)
	))
	add_child(row)

	add_child(_range_card())

	var outcome := str(state.get("outcome", ""))
	if outcome != "":
		_build_outcome(outcome)
	elif int(CombatSystem.state) != CombatSystem.State.PLAYER_TURN:
		add_child(UiKit.text("…", 24, UiKit.MUTED_COLOR))
	else:
		_build_moves()
	_build_log()


## Карточка участника: полоса здоровья, оружие, последний манёвр, состояния.
func _side_card(
	side: String, title: String, hp: int, max_hp: int, weapon: String, last_move: String,
	conditions: Array, accent: Color, portrait: TextureRect = null
) -> Control:
	var panel := PanelContainer.new()
	panel.name = "CombatSide_%s" % side
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
	var bar := _hp_bar(hp, max_hp, accent)
	box.add_child(bar)
	var hp_label := UiKit.text(HP_TEXT % [hp, max_hp], 20)
	box.add_child(hp_label)
	if weapon != "":
		box.add_child(UiKit.text("Оружие: %s" % weapon, 19, UiKit.MUTED_COLOR))
	box.add_child(UiKit.text("Манёвр: %s" % (last_move if last_move != "" else "—"), 19, UiKit.MUTED_COLOR))
	for condition in conditions:
		box.add_child(UiKit.text("• %s" % str(condition), 19, UiKit.EXIT_COLOR))
	_sides[side] = {
		"panel": panel,
		"portrait": portrait,
		"bar": bar,
		"hp_label": hp_label,
		"hp": hp,
		"max_hp": max_hp,
	}
	return panel


func _hp_bar(hp: int, max_hp: int, accent: Color) -> ProgressBar:
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


## Схватка решена: итог и «Продолжить» вместо манёвров.
func _build_outcome(outcome: String) -> void:
	var won := outcome == "won"
	var panel := PanelContainer.new()
	panel.name = "CombatOutcome"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var accent := UiKit.GOOD_COLOR if won else UiKit.EXIT_COLOR
	panel.add_theme_stylebox_override("panel", UiKit.box(Color("#161d22") if won else Color("#211c12"), accent, 2, 18))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title := UiKit.text("Победа" if won else "Вы ушли от схватки", 34, accent)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var note := "%s больше не угрожает." % str(state.get("enemy_name", "Противник")) if won \
		else "Противник остался в отсеке — модуль опасен."
	var note_label := UiKit.text(note, 21, UiKit.MUTED_COLOR)
	note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note_label)
	add_child(panel)
	if _animate:
		_pop_in(panel, FX_START + FX_STEP * float(_fresh_fx().size()))

	var btn := UiKit.button("Продолжить", "exit", 72)
	btn.name = "CombatContinue"
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.pressed.connect(func() -> void: finished.emit())
	add_child(btn)


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


## Записи текущего хода — яркие, прошлых ходов — приглушены.
func _build_log() -> void:
	var entries: Array = state.get("log", [])
	if entries.is_empty():
		return
	add_child(UiKit.section("Схватка"))
	var current_turn := int(state.get("turn", 0))
	var first := maxi(0, entries.size() - LOG_LINES)
	var fresh_index := 0
	for i in range(first, entries.size()):
		var entry = entries[i]
		var text := str(entry.get("text", "")) if entry is Dictionary else str(entry)
		var kind := str(entry.get("kind", "info")) if entry is Dictionary else "info"
		var fresh: bool = entry is Dictionary and int(entry.get("turn", -1)) == current_turn
		var line := UiKit.text("— " + text, 21, LOG_COLORS.get(kind, UiKit.TEXT_COLOR))
		if not fresh:
			line.modulate.a = 0.55
		add_child(line)
		if fresh and _animate:
			line.modulate.a = 0.0
			var tween := create_tween()
			tween.tween_interval(FX_STEP * 0.5 * float(fresh_index))
			tween.tween_property(line, "modulate:a", 1.0, 0.25)
			fresh_index += 1


# --- Эффекты ударов -------------------------------------------------------------

## Удары текущего хода по порядку журнала: [{ target, amount, style }].
func _fresh_fx() -> Array:
	var result: Array = []
	var current_turn := int(state.get("turn", 0))
	for entry in state.get("log", []):
		if not (entry is Dictionary) or int(entry.get("turn", -1)) != current_turn:
			continue
		for fx in entry.get("fx", []):
			if fx is Dictionary and _sides.has(str(fx.get("target", ""))):
				result.append(fx)
	return result


## Кадр ждём, чтобы раскладка закончилась: всплывающим числам нужны готовые
## позиции карточек, а встряске — их размер (центр вращения).
func _play_turn_fx() -> void:
	var fx_list := _fresh_fx()
	if fx_list.is_empty():
		return
	# Полосы HP начинают с того, что было до ударов, и стекают по одному удару.
	var shown := {}
	for side in _sides.keys():
		var info: Dictionary = _sides[side]
		var taken := 0
		for fx in fx_list:
			if str(fx.get("target", "")) == side:
				taken += int(fx.get("amount", 0))
		shown[side] = mini(int(info["hp"]) + taken, int(info["max_hp"]))
		_set_hp_shown(float(shown[side]), side)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	for i in range(fx_list.size()):
		var fx: Dictionary = fx_list[i]
		var side := str(fx.get("target", ""))
		var amount := int(fx.get("amount", 0))
		var delay := FX_START + FX_STEP * float(i)
		if amount > 0:
			var from := float(shown[side])
			shown[side] = maxi(0, int(shown[side]) - amount)
			_hit_fx(side, amount, str(fx.get("style", "melee")), delay, from, float(shown[side]))
		else:
			_miss_fx(side, delay)
	if str(state.get("outcome", "")) == "won":
		var tween := create_tween()
		tween.tween_interval(FX_START + FX_STEP * float(fx_list.size()))
		tween.tween_property(_sides["enemy"]["panel"], "modulate", _defeated_tint(), 0.4)


## Позицию карточки раскладывает HBoxContainer, поэтому встряска — поворот и
## «сжатие» вокруг центра: их контейнер не трогает.
func _hit_fx(side: String, amount: int, style: String, delay: float, hp_from: float, hp_to: float) -> void:
	var info: Dictionary = _sides[side]
	var panel: Control = info["panel"]
	var strength: float = SHAKE.get(style, SHAKE["melee"])
	panel.pivot_offset = panel.size * 0.5

	var shake := create_tween()
	shake.tween_interval(delay)
	for k in range(5):
		var angle := deg_to_rad(strength * 0.25) * (1.0 - float(k) / 5.0) * (1.0 if k % 2 == 0 else -1.0)
		shake.tween_property(panel, "rotation", angle, 0.045)
	shake.tween_property(panel, "rotation", 0.0, 0.05)

	var punch := create_tween()
	punch.tween_interval(delay)
	punch.tween_property(panel, "scale", Vector2.ONE * (1.0 - strength * 0.004), 0.05)
	punch.tween_property(panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Вспышка карточки: красная у игрока, белая у врага.
	var flash_color := Color(1.9, 0.55, 0.55) if side == "player" else Color(2.2, 2.2, 2.2)
	var flash := create_tween()
	flash.tween_interval(delay)
	flash.tween_property(panel, "modulate", flash_color, 0.05)
	flash.tween_property(panel, "modulate", Color.WHITE, 0.3).set_trans(Tween.TRANS_SINE)

	var bar_tween := create_tween()
	bar_tween.tween_interval(delay + 0.05)
	bar_tween.tween_method(_set_hp_shown.bind(side), hp_from, hp_to, 0.35) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	var color := UiKit.BAD_COLOR if side == "player" else UiKit.EXIT_COLOR
	_float_text(side, "−%d" % amount, color, 46, delay)
	if side == "player":
		_screen_flash(delay)


## Промах: цель уклоняется наклоном, над ней — «мимо».
func _miss_fx(side: String, delay: float) -> void:
	var panel: Control = _sides[side]["panel"]
	panel.pivot_offset = panel.size * 0.5
	var lean := deg_to_rad(3.5 if side == "enemy" else -3.5)
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(panel, "rotation", lean, 0.08).set_trans(Tween.TRANS_SINE)
	tween.tween_property(panel, "rotation", 0.0, 0.2).set_trans(Tween.TRANS_SINE)
	_float_text(side, "мимо", UiKit.MUTED_COLOR, 30, delay)


## Всплывающая надпись над портретом (или серединой карточки): поднимается
## и тает. top_level — контейнеры её не раскладывают.
func _float_text(side: String, value: String, color: Color, font_size: int, delay: float) -> void:
	var info: Dictionary = _sides[side]
	var anchor: Control = info["portrait"] if info["portrait"] != null else info["panel"]
	var label := Label.new()
	label.text = value
	label.top_level = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", UiKit.fs(font_size))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("#0b0e14"))
	label.add_theme_constant_override("outline_size", UiKit.fs(10))
	label.modulate.a = 0.0
	add_child(label)
	var text_size := label.get_combined_minimum_size()
	var anchor_rect := anchor.get_global_rect()
	var start := Vector2(anchor_rect.get_center().x, anchor_rect.position.y + anchor_rect.size.y * 0.3) - text_size * 0.5
	label.size = text_size
	label.global_position = start
	label.pivot_offset = text_size * 0.5
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(label, "modulate:a", 1.0, 0.06)
	tween.parallel().tween_property(label, "scale", Vector2(1.25, 1.25), 0.08).from(Vector2(0.6, 0.6))
	tween.tween_property(label, "scale", Vector2.ONE, 0.12)
	tween.parallel().tween_property(label, "global_position:y", start.y - FLOAT_RISE, FLOAT_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, FLOAT_TIME * 0.6).set_delay(FLOAT_TIME * 0.4)
	tween.tween_callback(label.queue_free)


## Удар по игроку: экран на мгновение краснеет.
func _screen_flash(delay: float) -> void:
	var overlay := ColorRect.new()
	overlay.top_level = true
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.color = Color(0.85, 0.1, 0.12, 0.0)
	add_child(overlay)
	overlay.global_position = Vector2.ZERO
	overlay.size = get_viewport_rect().size
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(overlay, "color:a", 0.28, 0.05)
	tween.tween_property(overlay, "color:a", 0.0, 0.35).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(overlay.queue_free)


## Итог «Победа» появляется после последнего удара.
func _pop_in(node: Control, delay: float) -> void:
	node.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(node, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE)


func _set_hp_shown(value: float, side: String) -> void:
	var info: Dictionary = _sides[side]
	var bar: ProgressBar = info["bar"]
	bar.value = value
	var label: Label = info["hp_label"]
	label.text = HP_TEXT % [roundi(value), int(info["max_hp"])]


func _defeated_tint() -> Color:
	return Color(0.5, 0.5, 0.56, 0.85)
