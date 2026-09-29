extends Control

const UiKit = preload("res://scenes/ui/UiKit.gd")
const SECTOR_MAP_VIEW_SCRIPT := preload("res://scenes/ui/SectorMapView.gd")
const CHARACTER_PANEL_SCRIPT := preload("res://scenes/ui/CharacterPanel.gd")
const COMBAT_VIEW_SCRIPT := preload("res://scenes/ui/CombatView.gd")

const CONTENT_MARGIN := 36
const BODY_GAP := 16
const BUTTON_HEIGHT := 68
## Сдвиг пальца/мыши (px), после которого нажатие считается прокруткой.
const DRAG_THRESHOLD := 14.0
## Ниже этого запаса кислорода счётчик в HUD становится тревожным.
const LOW_O2 := 60

var body: VBoxContainer
var hud: VBoxContainer
var content_scroll: ScrollContainer
var hp_label: Label
var o2_label: Label
var ammo_label: Label
var bag_label: Label
var map_button: Button
var character_button: Button
var journal_button: Button
var section_separator: HSeparator
var map_open: bool = false
var journal_open: bool = false
var character_open: bool = false
var character_tab: String = "items"
var journal_tab: String = "log"

var _drag_armed: bool = false
var _drag_scrolling: bool = false
var _drag_origin: Vector2 = Vector2.ZERO
var _drag_scroll_origin: int = 0
var _injecting: bool = false
## Сообщение карты (запертый узел без ключа) — живёт до следующего действия.
var _map_message: String = ""
## Ждём ответа рекламного провайдера по откату (защита от повторного нажатия).
var _ad_result_pending: bool = false
## Текст под причиной смерти (например, реклама не досмотрена).
var _death_message: String = ""


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

	hud = VBoxContainer.new()
	hud.name = "Hud"
	hud.add_theme_constant_override("separation", 10)
	root_vbox.add_child(hud)

	var stats_row := HBoxContainer.new()
	stats_row.name = "HudStats"
	stats_row.add_theme_constant_override("separation", 12)
	hud.add_child(stats_row)
	hp_label = _make_hud_label()
	o2_label = _make_hud_label()
	ammo_label = _make_hud_label()
	bag_label = _make_hud_label()
	bag_label.name = "BagLabel"
	for lbl in [hp_label, o2_label, ammo_label, bag_label]:
		stats_row.add_child(lbl)

	var nav_row := HBoxContainer.new()
	nav_row.name = "HudNav"
	nav_row.add_theme_constant_override("separation", 10)
	hud.add_child(nav_row)
	map_button = _make_nav_button("Карта", "MapButton", _toggle_map)
	character_button = _make_nav_button("Персонаж", "CharacterButton", _toggle_character)
	journal_button = _make_nav_button("Журнал", "JournalButton", _toggle_journal)
	for btn in [map_button, character_button, journal_button]:
		nav_row.add_child(btn)

	section_separator = HSeparator.new()
	section_separator.name = "SectionSeparator"
	root_vbox.add_child(section_separator)

	content_scroll = ScrollContainer.new()
	content_scroll.name = "ContentScroll"
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_scroll.follow_focus = true
	_style_scrollbar(content_scroll.get_v_scroll_bar())
	root_vbox.add_child(content_scroll)

	body = VBoxContainer.new()
	body.name = "ScreenBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", BODY_GAP)
	content_scroll.add_child(body)


func _connect_signals() -> void:
	GameState.screen_changed.connect(_on_screen_changed)
	ResourceSystem.hp_changed.connect(_on_resource_changed)
	ResourceSystem.o2_changed.connect(_on_resource_changed)
	ResourceSystem.ammo_changed.connect(_on_resource_changed)
	InventorySystem.item_added.connect(_on_inventory_changed)
	InventorySystem.item_removed.connect(_on_inventory_changed)
	CharacterSystem.changed.connect(_on_character_changed)
	NotificationSystem.changed.connect(_on_notification_changed)
	MapSystem.node_state_changed.connect(_on_map_node_state_changed)
	MapSystem.node_blocked.connect(_on_map_node_blocked)
	MapSystem.floor_changed.connect(_on_map_floor_changed)
	MapSystem.fog_changed.connect(_on_map_fog_changed)
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


func _make_nav_button(text: String, node_name: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.name = node_name
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 56)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 21)
	btn.pressed.connect(callback)
	_style_nav_button(btn, false)
	return btn


## Активная вкладка HUD (открытый экран или оверлей) подсвечивается.
func _style_nav_button(btn: Button, active: bool) -> void:
	if active:
		UiKit.style_button(btn, Color("#22415c"), Color("#2a577b"), Color("#1a324a"), Color("#8abce0"))
		btn.add_theme_stylebox_override("normal", _nav_box(Color("#22415c"), Color("#8abce0")))
	else:
		UiKit.style_button(btn, Color("#2b3546"), Color("#3d4c63"), Color("#1f2633"), Color("#4d6275"))


func _nav_box(bg: Color, border: Color) -> StyleBoxFlat:
	var box := UiKit.box(bg, border, 2)
	box.border_width_bottom = 5
	return box


func _style_scrollbar(bar: VScrollBar) -> void:
	bar.custom_minimum_size.x = 14
	bar.add_theme_stylebox_override("scroll", UiKit.box(Color("#161b24"), Color("#161b24"), 0, 0))
	bar.add_theme_stylebox_override("grabber", UiKit.box(Color("#3d4c63"), Color("#3d4c63"), 0, 0))
	bar.add_theme_stylebox_override("grabber_highlight", UiKit.box(Color("#4d6275"), Color("#4d6275"), 0, 0))
	bar.add_theme_stylebox_override("grabber_pressed", UiKit.box(Color("#5d91a8"), Color("#5d91a8"), 0, 0))


# --- Прокрутка перетаскиванием --------------------------------------------------
# Колесо мыши ScrollContainer обрабатывает сам. Перетаскивание (палец на
# телефоне или зажатая мышь) делаем здесь: жест может начаться на кнопке —
# тогда её нажатие отменяется, и после отпускания она не срабатывает.

func _input(event: InputEvent) -> void:
	if _injecting or content_scroll == null or not content_scroll.is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_armed = content_scroll.get_global_rect().has_point(event.position)
			_drag_scrolling = false
			_drag_origin = event.position
			_drag_scroll_origin = content_scroll.scroll_vertical
		else:
			if _drag_scrolling:
				get_viewport().set_input_as_handled()
			_drag_armed = false
			_drag_scrolling = false
	elif event is InputEventMouseMotion and _drag_armed:
		var dy: float = event.position.y - _drag_origin.y
		if not _drag_scrolling and absf(dy) >= DRAG_THRESHOLD:
			_drag_scrolling = true
			call_deferred("_cancel_gui_press")
		if _drag_scrolling:
			content_scroll.scroll_vertical = _drag_scroll_origin - int(dy)
			get_viewport().set_input_as_handled()


## Уводит «курсор» за пределы нажатой кнопки и отпускает там — кнопка
## не сработает и снимет подсветку нажатия.
func _cancel_gui_press() -> void:
	_injecting = true
	var away := Vector2(-10000, -10000)
	var motion := InputEventMouseMotion.new()
	motion.position = away
	motion.global_position = away
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = away
	release.global_position = away
	get_viewport().push_input(release, true)
	_injecting = false


func _scroll_to_top() -> void:
	content_scroll.scroll_vertical = 0


# --- Реакция на системы ---------------------------------------------------------

func _on_resource_changed(_value) -> void:
	_update_hud()


func _on_inventory_changed(_item_id: String) -> void:
	_update_hud()
	_update_nav_buttons()


func _on_character_changed() -> void:
	_update_hud()
	_update_nav_buttons()


func _on_notification_changed() -> void:
	_update_nav_buttons()


func _on_map_fog_changed() -> void:
	if (GameState.current_screen == GameState.Screen.SECTOR_MAP or map_open) and not journal_open and not character_open:
		_render_current_screen()


func _on_map_node_state_changed(_node_id: String, _state: String) -> void:
	if (GameState.current_screen == GameState.Screen.SECTOR_MAP or map_open) and not journal_open and not character_open:
		_render_current_screen()


## Узел заперт и ключа нет — показываем причину прямо над картой.
func _on_map_node_blocked(_node_id: String, message: String) -> void:
	_map_message = message
	if (GameState.current_screen == GameState.Screen.SECTOR_MAP or map_open) and not journal_open and not character_open:
		_render_current_screen()


func _on_map_floor_changed(_floor_id: String) -> void:
	if (GameState.current_screen == GameState.Screen.SECTOR_MAP or map_open) and not journal_open and not character_open:
		_render_current_screen()


func _on_combat_turn_resolved(_entry: Dictionary) -> void:
	if GameState.current_screen == GameState.Screen.COMBAT and not journal_open:
		_render_combat()


func _on_screen_changed(screen: int) -> void:
	if character_open:
		NotificationSystem.mark_character_seen()
	if journal_open:
		NotificationSystem.mark_journal_seen()
	map_open = false
	journal_open = false
	character_open = false
	if screen != GameState.Screen.DEATH:
		_death_message = ""
	_map_message = ""
	_scroll_to_top()
	_render_current_screen()


func _update_hud() -> void:
	hp_label.text = "HP: %d/%d" % [ResourceSystem.hp, ResourceSystem.max_hp]
	var o2i := int(ResourceSystem.o2)
	o2_label.text = "O2: %d" % o2i
	o2_label.add_theme_color_override("font_color", UiKit.BAD_COLOR if o2i <= LOW_O2 else Color("#eef3ff"))
	ammo_label.text = "Патроны: %d" % ResourceSystem.ammo
	bag_label.text = "Сумка: %d/%d" % [InventorySystem.used_slots(), InventorySystem.max_slots]


# --- HUD-вкладки ----------------------------------------------------------------

func _toggle_journal() -> void:
	if journal_button.disabled:
		return
	if journal_open:
		NotificationSystem.mark_journal_seen()
		journal_open = false
	else:
		if character_open:
			NotificationSystem.mark_character_seen()
		journal_open = true
		map_open = false
		character_open = false
	_scroll_to_top()
	_render_current_screen()


func _toggle_map() -> void:
	if map_button.disabled:
		return
	if journal_open:
		NotificationSystem.mark_journal_seen()
	if character_open:
		NotificationSystem.mark_character_seen()
	journal_open = false
	character_open = false
	if GameState.current_screen == GameState.Screen.SECTOR_MAP:
		map_open = false
	else:
		map_open = not map_open
	_scroll_to_top()
	_render_current_screen()


func _close_map_overlay() -> void:
	map_open = false
	_render_current_screen()


func _toggle_character() -> void:
	if character_button.disabled:
		return
	if character_open:
		_close_character()
		return
	if journal_open:
		NotificationSystem.mark_journal_seen()
	character_open = true
	map_open = false
	journal_open = false
	_scroll_to_top()
	_render_current_screen()


## Предметы могли измениться — в модуле перепроверяем его автособытия.
func _close_character() -> void:
	NotificationSystem.mark_character_seen()
	character_open = false
	_scroll_to_top()
	if GameState.current_screen == GameState.Screen.LOCATION:
		GameState.refresh_location()
	else:
		_render_current_screen()


func _render_current_screen() -> void:
	_update_hud()
	_set_chrome_visible(GameState.current_screen != GameState.Screen.MAIN_MENU)
	_update_nav_buttons()
	_clear_body()
	if journal_open:
		_render_journal()
		return
	if character_open:
		_render_character()
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
		GameState.Screen.LOCATION:
			_render_location()
		GameState.Screen.COMBAT:
			_render_combat()
		GameState.Screen.DEATH:
			_render_death()
		GameState.Screen.VICTORY:
			_render_victory()
		_:
			_add_text("Неизвестный экран: %d" % GameState.current_screen)


func _set_chrome_visible(is_visible: bool) -> void:
	hud.visible = is_visible
	section_separator.visible = is_visible


func _update_nav_buttons() -> void:
	if map_button == null:
		return
	var blocked := (
		MapSystem.current_sector_id == ""
		or GameState.current_screen == GameState.Screen.MAIN_MENU
		or GameState.current_screen == GameState.Screen.COMBAT
		or GameState.current_screen == GameState.Screen.VICTORY
		or GameState.current_screen == GameState.Screen.DEATH
	)
	map_button.disabled = blocked or not GameState.has_left_capsule
	character_button.disabled = blocked or not GameState.has_left_capsule
	journal_button.disabled = blocked
	_set_nav_label(map_button, "Карта", false)
	_set_nav_label(character_button, "Персонаж", NotificationSystem.has_character_alert())
	_set_nav_label(journal_button, "Журнал", NotificationSystem.has_new_lore())
	var map_active := not journal_open and not character_open and (
		map_open or GameState.current_screen == GameState.Screen.SECTOR_MAP
	)
	_style_nav_button(map_button, map_active)
	_style_nav_button(character_button, character_open)
	_style_nav_button(journal_button, journal_open)


func _set_nav_label(btn: Button, base: String, alert: bool) -> void:
	btn.text = base + ("  •" if alert else "")


func _clear_body() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()


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


## Пиксельная иллюстрация сцены; если картинки нет — просто пропускаем.
func _add_scene_image(image_name: String) -> void:
	var art := UiKit.scene_art(image_name, _body_width())
	if art != null:
		body.add_child(art)


## Ширина тела экрана: вьюпорт минус поля и полоса прокрутки.
func _body_width() -> float:
	var viewport_width := float(ProjectSettings.get_setting("display/window/size/viewport_width", 1080))
	return maxf(64.0, viewport_width - CONTENT_MARGIN * 2.0 - 14.0)


func _add_button(text: String, callback: Callable, kind: String = "default") -> Button:
	var btn := UiKit.button(text, kind, BUTTON_HEIGHT)
	btn.pressed.connect(callback)
	body.add_child(btn)
	return btn


func _add_section(text: String) -> void:
	body.add_child(UiKit.section(text))


func _count_suffix(count: int) -> String:
	return " ×%d" % count if count > 1 else ""


func _item_name(item_id: String) -> String:
	return str(InventorySystem.get_item_data(item_id).get("name", item_id))


# --- Экраны ---------------------------------------------------------------------

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
	if _map_message != "":
		var msg := _add_text(_map_message)
		msg.add_theme_color_override("font_color", UiKit.EXIT_COLOR)
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
		read_only,
		MapSystem.get_explored_floor_ids()
	)

	if read_only:
		_add_button("Закрыть карту", _close_map_overlay, "quiet")


func _on_map_node_selected(node_id: String) -> void:
	map_open = false
	_map_message = ""
	MapSystem.select_node(node_id)


func _render_situation() -> void:
	_add_scene_image(SituationEngine.get_current_image())
	var text := SituationEngine.get_current_text()
	_add_text(text if text != "" else "Ситуация не загружена.")

	var options := SituationEngine.get_available_options()
	if options.is_empty():
		# Некуда выбирать — единственная кнопка закрывает ситуацию.
		_add_button("Продолжить", func(): GameState.finish_situation(), "exit")
		return

	for opt in options:
		var opt_id: String = opt.get("id", "")
		# Завершающие варианты (выход на карту, конец события, финал) выделены цветом.
		var kind := "exit" if SituationEngine.is_closing_option(opt) else "default"
		_add_button(str(opt.get("label", opt_id)), _make_option_callback(opt_id), kind)


func _make_option_callback(opt_id: String) -> Callable:
	return func(): SituationEngine.select_option(opt_id)


func _render_location() -> void:
	_add_title(LocationSystem.get_title())
	# Иллюстрация сработавшего события важнее общей картинки модуля.
	var location_image := LocationSystem.event_image
	if location_image == "":
		location_image = LocationSystem.get_image()
	_add_scene_image(location_image)
	var description := LocationSystem.get_description()
	if description != "":
		_add_text(description)
	for notice in LocationSystem.notices:
		var lbl := _add_text(str(notice))
		lbl.add_theme_color_override("font_color", UiKit.ACCENT_COLOR)

	var events := LocationSystem.get_manual_events()
	if not events.is_empty():
		_add_section("Действия")
		for ev in events:
			var event_id := str(ev.get("id", ""))
			var label := str(ev.get("label", event_id))
			if LocationSystem.is_event_locked(ev):
				# Запертый ящик виден, но не нажимается: в подписи — нужный ключ.
				var locked_btn := UiKit.button(
					"%s — %s" % [label, EffectResolver.lock_hint(LocationSystem.get_event_lock(ev))],
					"quiet", BUTTON_HEIGHT + 28)
				locked_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				locked_btn.disabled = true
				body.add_child(locked_btn)
			else:
				_add_button(label, _make_location_event_callback(event_id))

	if LocationSystem.is_base():
		_render_base_section()

	var stash := LocationSystem.get_stash()
	if not stash.is_empty():
		_add_section("Склад" if LocationSystem.is_base() else "Здесь лежит")
		for item_id in stash.keys():
			_add_button("Взять: %s%s" % [_item_name(item_id), _count_suffix(int(stash[item_id]))], _make_stash_take_callback(item_id), "quiet")

	var usable: Array = []
	for entry in InventorySystem.get_slots():
		var item_id: String = entry.get("id", "")
		if InventorySystem.get_item_data(item_id).has("use_effect"):
			usable.append(item_id)
	if not usable.is_empty():
		_add_section("Инвентарь")
		for item_id in usable:
			_add_button("Использовать: " + _item_name(item_id), _make_location_item_callback(item_id), "quiet")

	_add_button("Выйти на карту", _leave_location, "exit")


## Модуль-база: ручное сохранение, верстак и разгрузка сумки на склад.
func _render_base_section() -> void:
	_add_section("База")
	_add_button("Сохранить забег", _base_save, "quiet")
	_add_button("Верстак: открыть крафт", _base_open_craft, "quiet")
	var droppable: Array = []
	for entry in InventorySystem.get_slots():
		var item_id: String = entry.get("id", "")
		if InventorySystem.can_drop(item_id):
			droppable.append(item_id)
	if droppable.is_empty():
		return
	_add_section("Разложить по складу")
	for item_id in droppable:
		_add_button("Положить: " + _item_name(item_id), _make_base_store_callback(item_id), "quiet")


func _base_save() -> void:
	LocationSystem.clear_notices()
	SaveManager.write_checkpoint()
	LocationSystem.add_notice("Забег сохранён: точка возврата — этот модуль.")
	_render_current_screen()


func _base_open_craft() -> void:
	character_tab = "craft"
	_toggle_character()


func _make_base_store_callback(item_id: String) -> Callable:
	return func():
		LocationSystem.clear_notices()
		if InventorySystem.drop_item(item_id):
			LocationSystem.add_notice("На складе: %s." % _item_name(item_id))
		_render_current_screen()


func _make_location_event_callback(event_id: String) -> Callable:
	return func(): GameState.start_location_event(event_id)


func _make_location_item_callback(item_id: String) -> Callable:
	return func():
		LocationSystem.clear_notices()
		if InventorySystem.use_item(item_id):
			LocationSystem.add_notice("Использовано: %s." % _item_name(item_id))
		GameState.refresh_location()


func _make_stash_take_callback(item_id: String) -> Callable:
	return func():
		LocationSystem.clear_notices()
		var total := int(LocationSystem.get_stash().get(item_id, 0))
		var taken := LocationSystem.stash_take(item_id)
		if taken == 0:
			LocationSystem.add_notice("В сумке нет места для «%s»." % _item_name(item_id))
		elif taken < total:
			LocationSystem.add_notice("Взято: %s ×%d. Остальное не поместилось." % [_item_name(item_id), taken])
		else:
			LocationSystem.add_notice("Взято: %s%s." % [_item_name(item_id), _count_suffix(taken)])
		GameState.refresh_location()


func _leave_location() -> void:
	GameState.leave_location()


func _render_character() -> void:
	var panel: VBoxContainer = CHARACTER_PANEL_SCRIPT.new()
	panel.tab = character_tab
	panel.tab_changed.connect(_on_character_tab_changed)
	panel.closed.connect(_close_character)
	body.add_child(panel)


func _on_character_tab_changed(new_tab: String) -> void:
	character_tab = new_tab
	_scroll_to_top()


func _render_combat() -> void:
	_clear_body()
	var st := CombatSystem.get_state()
	_add_title("Схватка: %s" % str(st.get("enemy_name", "")))
	var view: VBoxContainer = COMBAT_VIEW_SCRIPT.new()
	view.move_selected.connect(_combat_action)
	body.add_child(view)
	view.setup(st)


func _combat_action(move_id: String, payload = null) -> void:
	CombatSystem.player_action(move_id, payload)
	if GameState.current_screen == GameState.Screen.COMBAT:
		_render_combat()


func _render_death() -> void:
	var cause := GameState.last_death_cause
	var cause_text := "закончился кислород" if cause == "o2" else "здоровье упало до нуля"
	_add_title("Вы погибли")
	_add_text("Причина: %s." % cause_text)
	if _death_message != "":
		_add_text(_death_message)
	_add_button("Начать заново", _death_restart)

	if EconomyManager.can_use_rollback_today() and SaveManager.has_checkpoint():
		var hint := "" if EconomyManager.has_full_access else " (реклама)"
		_add_button("Вернуться к чекпойнту" + hint, _death_rollback, "quiet")


## Победа: текст финала, итоги забега и хроники, выход в меню или новый забег.
func _render_victory() -> void:
	var ending_id := GameState.last_ending_id
	_add_title("Забег завершён")
	_add_section(ChronicleSystem.get_ending_title(ending_id))
	_add_text(ChronicleSystem.get_ending_text(ending_id))

	var card := UiKit.card(body)
	card.add_child(UiKit.text("Итог", 26, UiKit.TITLE_COLOR))
	card.add_child(UiKit.text("HP на финише: %d/%d" % [ResourceSystem.hp, ResourceSystem.max_hp], 22))
	card.add_child(UiKit.text("Записей в журнале: %d" % ArchiveSystem.get_unlocked().size(), 22))
	card.add_child(UiKit.text("Финалов открыто: %d из %d" % [ChronicleSystem.endings_seen_count(), ChronicleSystem.endings_total()], 22))
	card.add_child(UiKit.text("Забегов: %d (побед: %d, смертей: %d)" % [
		ChronicleSystem.runs_finished, ChronicleSystem.victories, ChronicleSystem.deaths], 22))

	_add_button("Новый забег", _victory_restart)
	_add_button("В главное меню", _victory_menu, "quiet")


func _victory_restart() -> void:
	GameState.choose_restart()


func _victory_menu() -> void:
	GameState.go_to_main_menu()


func _death_restart() -> void:
	GameState.choose_restart()


## Откат за рекламу выполняется только если реклама действительно досмотрена.
func _death_rollback() -> void:
	if EconomyManager.has_full_access:
		EconomyManager.use_rollback()
		GameState.choose_rollback()
		return
	if _ad_result_pending:
		return
	_ad_result_pending = true
	EconomyManager.ad_completed.connect(_on_rollback_ad_completed, CONNECT_ONE_SHOT)
	EconomyManager.watch_rollback_ad()


func _on_rollback_ad_completed(success: bool) -> void:
	_ad_result_pending = false
	if success:
		GameState.choose_rollback()
	else:
		_death_message = "Реклама не досмотрена — откат недоступен."
		_render_current_screen()


## Журнал — две вкладки: «Хроника» (что уже произошло в забеге, JournalSystem)
## и «Архив» (найденные лор-фрагменты, ArchiveSystem).
const JOURNAL_TABS := [["log", "Хроника"], ["lore", "Архив"]]
const JOURNAL_COLORS := {
	"move": UiKit.ACCENT_COLOR,
	"combat": UiKit.BAD_COLOR,
	"death": UiKit.BAD_COLOR,
	"victory": UiKit.EXIT_COLOR,
	"lore": UiKit.TITLE_COLOR,
	"choice": UiKit.TITLE_COLOR,
	"loot": UiKit.MUTED_COLOR,
}


func _render_journal() -> void:
	_add_title("Журнал")
	var tabs := HBoxContainer.new()
	tabs.name = "JournalTabs"
	tabs.add_theme_constant_override("separation", 8)
	for entry in JOURNAL_TABS:
		var tab_id := str(entry[0])
		var label := str(entry[1])
		if tab_id == "lore" and NotificationSystem.has_new_lore():
			label += "  •"
		var btn := UiKit.button(label, "tab_active" if tab_id == journal_tab else "quiet", 58)
		btn.name = "JournalTab_%s" % tab_id
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(_select_journal_tab.bind(tab_id))
		tabs.add_child(btn)
	body.add_child(tabs)

	if journal_tab == "lore":
		_render_journal_archive()
	else:
		_render_journal_log()
	_add_button("Закрыть", _toggle_journal, "quiet")


func _select_journal_tab(tab_id: String) -> void:
	journal_tab = tab_id
	_scroll_to_top()
	_render_current_screen()


## Хроника забега: свежие записи сверху, у каждой — остаток кислорода.
func _render_journal_log() -> void:
	var entries := JournalSystem.get_entries()
	if entries.is_empty():
		_add_text("Пока ничего не произошло.")
		return
	_add_section("Записей: %d" % entries.size())
	for i in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[i]
		var count := int(entry.get("count", 1))
		var line := "O2 %d · %s%s" % [int(entry.get("o2", 0)), str(entry.get("text", "")), _count_suffix(count)]
		var lbl := _add_text(line)
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", JOURNAL_COLORS.get(str(entry.get("kind", "")), UiKit.TEXT_COLOR))


## Архив: открытые лор-фрагменты, каждая запись в рамке.
func _render_journal_archive() -> void:
	var ids := ArchiveSystem.get_unlocked()
	if ids.is_empty():
		_add_text("Записей пока нет. Их можно найти в планшетах, терминалах и бирках.")
		return
	_add_section("Записей: %d" % ids.size())
	for id in ids:
		var card := UiKit.card(body)
		card.add_child(UiKit.text(ArchiveSystem.get_title(str(id)), 26, UiKit.TITLE_COLOR))
		card.add_child(UiKit.text(ArchiveSystem.get_text(str(id)), 22))
