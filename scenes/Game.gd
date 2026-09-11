extends Control

const SECTOR_MAP_VIEW_SCRIPT := preload("res://scenes/ui/SectorMapView.gd")

const CONTENT_MARGIN := 36
const BODY_GAP := 16
const BUTTON_HEIGHT := 68

var body: VBoxContainer
var hud_bar: HBoxContainer
var hp_label: Label
var o2_label: Label
var ammo_label: Label
var map_button: Button
var inventory_label: Label
var section_separator: HSeparator
var map_open: bool = false
var archive_open: bool = false


func _ready() -> void:
	_fill_parent(self)
	_build_static_layout()
	_connect_signals()
	_render_current_screen()


func _build_static_layout() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.color = Color("#11141b")
	add_child(background)
	_fill_parent(background)

	var margin := MarginContainer.new()
	margin.name = "ContentMargin"
	margin.add_theme_constant_override("margin_left", CONTENT_MARGIN)
	margin.add_theme_constant_override("margin_top", CONTENT_MARGIN)
	margin.add_theme_constant_override("margin_right", CONTENT_MARGIN)
	margin.add_theme_constant_override("margin_bottom", CONTENT_MARGIN)
	add_child(margin)
	_fill_parent(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.name = "RootVBox"
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 14)
	margin.add_child(root_vbox)

	hud_bar = HBoxContainer.new()
	hud_bar.name = "HudBar"
	hud_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud_bar.add_theme_constant_override("separation", 12)
	root_vbox.add_child(hud_bar)

	hp_label = _make_hud_label()
	o2_label = _make_hud_label()
	ammo_label = _make_hud_label()
	hud_bar.add_child(hp_label)
	hud_bar.add_child(o2_label)
	hud_bar.add_child(ammo_label)

	map_button = _make_chrome_button("Карта")
	map_button.name = "MapButton"
	map_button.pressed.connect(_toggle_map)
	hud_bar.add_child(map_button)

	var archive_btn := _make_chrome_button("Архив")
	archive_btn.name = "ArchiveButton"
	archive_btn.pressed.connect(_toggle_archive)
	hud_bar.add_child(archive_btn)

	inventory_label = Label.new()
	inventory_label.name = "InventoryLabel"
	inventory_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory_label.add_theme_font_size_override("font_size", 22)
	inventory_label.add_theme_color_override("font_color", Color("#b8c2d6"))
	root_vbox.add_child(inventory_label)

	section_separator = HSeparator.new()
	section_separator.name = "SectionSeparator"
	root_vbox.add_child(section_separator)

	var scroll := ScrollContainer.new()
	scroll.name = "ContentScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	root_vbox.add_child(scroll)

	body = VBoxContainer.new()
	body.name = "ScreenBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", BODY_GAP)
	scroll.add_child(body)


func _connect_signals() -> void:
	GameState.screen_changed.connect(_on_screen_changed)
	ResourceSystem.hp_changed.connect(_on_resource_changed)
	ResourceSystem.o2_changed.connect(_on_resource_changed)
	ResourceSystem.ammo_changed.connect(_on_resource_changed)
	InventorySystem.item_added.connect(_on_inventory_changed)
	InventorySystem.item_removed.connect(_on_inventory_changed)
	MapSystem.node_state_changed.connect(_on_map_node_state_changed)
	MapSystem.floor_changed.connect(_on_map_floor_changed)
	CombatSystem.turn_resolved.connect(_on_combat_turn_resolved)


func _fill_parent(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	control.grow_vertical = Control.GROW_DIRECTION_BOTH


func _make_hud_label() -> Label:
	var lbl := Label.new()
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color("#eef3ff"))
	return lbl


func _make_chrome_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(142, 54)
	btn.add_theme_font_size_override("font_size", 21)
	_apply_button_style(btn, Color("#2b3546"), Color("#3d4c63"), Color("#1f2633"))
	return btn


func _on_resource_changed(_value) -> void:
	_update_hud()


func _on_inventory_changed(_item_id: String) -> void:
	_update_hud()


func _on_map_node_state_changed(_node_id: String, _state: String) -> void:
	if (GameState.current_screen == GameState.Screen.SECTOR_MAP or map_open) and not archive_open:
		_render_current_screen()


func _on_map_floor_changed(_floor_id: String) -> void:
	if (GameState.current_screen == GameState.Screen.SECTOR_MAP or map_open) and not archive_open:
		_render_current_screen()


func _on_combat_turn_resolved(_entry: Dictionary) -> void:
	if GameState.current_screen == GameState.Screen.COMBAT and not archive_open:
		_render_combat()


func _on_screen_changed(_screen: int) -> void:
	map_open = false
	archive_open = false
	_render_current_screen()


func _update_hud() -> void:
	hp_label.text = "HP: %d" % ResourceSystem.hp
	var o2i := int(ResourceSystem.o2_seconds)
	o2_label.text = "O2: %02d:%02d" % [o2i / 60, o2i % 60]
	ammo_label.text = "Патроны: %d" % ResourceSystem.ammo

	var names: Array = []
	for entry in InventorySystem.get_slots():
		var data := InventorySystem.get_item_data(entry.get("id", ""))
		var item_name: String = data.get("name", str(entry.get("id", "?")))
		var count: int = int(entry.get("count", 1))
		if count > 1:
			names.append("%s x%d" % [item_name, count])
		else:
			names.append(item_name)

	var inv_text := "пусто" if names.is_empty() else _join_strings(names, ", ")
	var used := InventorySystem.max_slots - InventorySystem.free_slots()
	inventory_label.text = "Инвентарь (%d/%d): %s" % [used, InventorySystem.max_slots, inv_text]


func _toggle_archive() -> void:
	archive_open = not archive_open
	if archive_open:
		map_open = false
		_render_archive()
	else:
		_render_current_screen()


func _toggle_map() -> void:
	if GameState.current_screen == GameState.Screen.MAIN_MENU:
		return
	archive_open = false
	if GameState.current_screen == GameState.Screen.SECTOR_MAP:
		map_open = false
	else:
		map_open = not map_open
	_render_current_screen()


func _close_map_overlay() -> void:
	map_open = false
	_render_current_screen()


func _render_current_screen() -> void:
	_update_hud()
	_set_chrome_visible(GameState.current_screen != GameState.Screen.MAIN_MENU)
	_update_nav_buttons()
	_clear_body()
	if archive_open:
		_render_archive()
		return
	if map_open:
		_render_map(true)
		return
	match GameState.current_screen:
		GameState.Screen.MAIN_MENU:
			_render_main_menu()
		GameState.Screen.SECTOR_MAP:
			_render_map()
		GameState.Screen.SITUATION:
			_render_situation()
		GameState.Screen.COMBAT:
			_render_combat()
		GameState.Screen.DEATH:
			_render_death()
		_:
			_add_text("Неизвестный экран: %d" % GameState.current_screen)


func _set_chrome_visible(is_visible: bool) -> void:
	hud_bar.visible = is_visible
	inventory_label.visible = is_visible
	section_separator.visible = is_visible


func _update_nav_buttons() -> void:
	if map_button == null:
		return
	map_button.disabled = (
		MapSystem.current_sector_id == ""
		or GameState.current_screen == GameState.Screen.COMBAT
		or GameState.current_screen == GameState.Screen.DEATH
	)


func _clear_body() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()


func _join_strings(parts: Array, separator: String) -> String:
	var text := ""
	for i in range(parts.size()):
		if i > 0:
			text += separator
		text += str(parts[i])
	return text


func _add_title(text: String) -> Label:
	var lbl := _add_text(text)
	lbl.add_theme_font_size_override("font_size", 34)
	lbl.add_theme_color_override("font_color", Color("#f5f8ff"))
	return lbl


func _add_text(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color("#d7deee"))
	body.add_child(lbl)
	return lbl


func _add_button(text: String, callback: Callable, kind: String = "default") -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 23)
	btn.pressed.connect(callback)

	match kind:
		"danger":
			_apply_button_style(btn, Color("#5b2530"), Color("#7e3443"), Color("#3b1c24"))
		"quiet":
			_apply_button_style(btn, Color("#202733"), Color("#323d4e"), Color("#171d27"))
		_:
			_apply_button_style(btn, Color("#173f55"), Color("#1f6989"), Color("#102c3d"))

	body.add_child(btn)
	return btn


func _apply_button_style(btn: Button, normal_color: Color, hover_color: Color, pressed_color: Color) -> void:
	btn.add_theme_color_override("font_color", Color("#f4f7fb"))
	btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
	btn.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	btn.add_theme_color_override("font_disabled_color", Color("#798294"))
	btn.add_theme_stylebox_override("normal", _button_box(normal_color, Color("#4d6275")))
	btn.add_theme_stylebox_override("hover", _button_box(hover_color, Color("#7faec6")))
	btn.add_theme_stylebox_override("pressed", _button_box(pressed_color, Color("#a9d8ea")))
	btn.add_theme_stylebox_override("disabled", _button_box(Color("#1a1f29"), Color("#2a3240")))
	btn.add_theme_stylebox_override("focus", _button_box(hover_color, Color("#d6f2ff"), 2))


func _button_box(bg: Color, border: Color, border_width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(8)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box


func _render_main_menu() -> void:
	_add_title("CosmoTextGame")
	_add_text("Текстовая survival-RPG на борту обломка «Персефона».")
	_add_button("Новая игра", _start_new_game)
	if FileAccess.file_exists(SaveManager.RUN_PATH):
		_add_button("Продолжить", _continue_game, "quiet")


func _start_new_game() -> void:
	GameState.start_new_game()


func _continue_game() -> void:
	GameState.continue_game()


func _render_map(read_only: bool = false) -> void:
	_add_title("Карта: " + MapSystem.get_sector_title())
	var nodes := MapSystem.get_map_nodes(true)
	if nodes.is_empty():
		_add_text("Видимых узлов нет.")
		return

	var map_view: Control = SECTOR_MAP_VIEW_SCRIPT.new()
	map_view.name = "SectorMapView"
	map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(map_view)
	map_view.node_selected.connect(_on_map_node_selected)
	map_view.setup(
		MapSystem.current_sector_id,
		MapSystem.get_sector_title(),
		MapSystem.get_map_config(),
		nodes,
		MapSystem.hub_node_id,
		MapSystem.get_current_floor_id(),
		read_only
	)

	if read_only:
		_add_button("Закрыть карту", _close_map_overlay, "quiet")


func _on_map_node_selected(node_id: String) -> void:
	map_open = false
	MapSystem.select_node(node_id)


func _render_situation() -> void:
	var text := SituationEngine.get_current_text()
	_add_text(text if text != "" else "Ситуация не загружена.")

	var options := SituationEngine.get_available_options()
	if options.is_empty():
		_add_button("Вернуться к карте", func(): GameState.return_to_hub(), "quiet")
		return

	for opt in options:
		var opt_id: String = opt.get("id", "")
		_add_button(str(opt.get("label", opt_id)), _make_option_callback(opt_id))


func _make_option_callback(opt_id: String) -> Callable:
	return func(): SituationEngine.select_option(opt_id)


func _render_combat() -> void:
	_clear_body()
	var st := CombatSystem.get_state()
	_add_title("%s - HP врага: %d/%d" % [str(st.get("enemy_name", "")), int(st.get("enemy_hp", 0)), int(st.get("enemy_max_hp", 1))])
	_add_text("Ваше HP: %d" % ResourceSystem.hp)

	var log_lines: Array = st.get("log", [])
	if not log_lines.is_empty():
		var log_text := ""
		var first_log_index = max(0, log_lines.size() - 5)
		for i in range(first_log_index, log_lines.size()):
			log_text += "- %s\n" % str(log_lines[i])
		_add_text(log_text)

	if CombatSystem.state != CombatSystem.State.PLAYER_TURN:
		_add_text("...")
		return

	var ammo_hint := " (дальний бой)" if ResourceSystem.ammo > 0 else " (ближний бой, патронов нет)"
	_add_button("Атаковать" + ammo_hint, _combat_attack)
	_add_button("Защититься", _combat_defend, "quiet")
	_add_button("Бежать", _combat_flee, "danger")

	for special in st.get("available_specials", []):
		var sid: String = special.get("id", "")
		_add_button(str(special.get("label", sid)), _make_special_callback(sid))

	for entry in InventorySystem.get_slots():
		var item_id: String = entry.get("id", "")
		var data := InventorySystem.get_item_data(item_id)
		if data.get("category", "") == "consumable":
			_add_button("Использовать: " + str(data.get("name", item_id)), _make_item_callback(item_id), "quiet")


func _make_special_callback(sid: String) -> Callable:
	return func(): _combat_action("special", sid)


func _make_item_callback(item_id: String) -> Callable:
	return func(): _combat_action("use_item", item_id)


func _combat_attack() -> void:
	_combat_action("attack")


func _combat_defend() -> void:
	_combat_action("defend")


func _combat_flee() -> void:
	_combat_action("flee")


func _combat_action(action: String, payload = null) -> void:
	CombatSystem.player_action(action, payload)
	if GameState.current_screen == GameState.Screen.COMBAT:
		_render_combat()


func _render_death() -> void:
	var cause := GameState.last_death_cause
	var cause_text := "закончился кислород" if cause == "o2" else "здоровье упало до нуля"
	_add_title("Вы погибли")
	_add_text("Причина: %s." % cause_text)
	_add_button("Начать заново", _death_restart)

	if EconomyManager.can_use_rollback_today() and SaveManager.has_checkpoint():
		var hint := "" if EconomyManager.has_full_access else " (реклама)"
		_add_button("Вернуться к чекпойнту" + hint, _death_rollback, "quiet")


func _death_restart() -> void:
	GameState.choose_restart()


func _death_rollback() -> void:
	if EconomyManager.has_full_access:
		EconomyManager.use_rollback()
		GameState.choose_rollback()
	else:
		EconomyManager.watch_rollback_ad()
		GameState.choose_rollback()


func _render_archive() -> void:
	_clear_body()
	_add_title("Архив")
	var ids := ArchiveSystem.get_unlocked()
	if ids.is_empty():
		_add_text("Пока пусто.")
	for id in ids:
		_add_text("- %s -\n%s" % [ArchiveSystem.get_title(str(id)), ArchiveSystem.get_text(str(id))])
	_add_button("Закрыть", _toggle_archive, "quiet")
