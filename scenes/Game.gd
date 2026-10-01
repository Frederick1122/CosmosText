extends Control

const UiKit = preload("res://scenes/ui/UiKit.gd")
const SECTOR_MAP_VIEW_SCRIPT := preload("res://scenes/ui/SectorMapView.gd")
const CHARACTER_PANEL_SCRIPT := preload("res://scenes/ui/CharacterPanel.gd")
const WORKBENCH_PANEL_SCRIPT := preload("res://scenes/ui/WorkbenchPanel.gd")
const COMBAT_VIEW_SCRIPT := preload("res://scenes/ui/CombatView.gd")
const XP_BAR_SCRIPT := preload("res://scenes/ui/XpBar.gd")

const CONTENT_MARGIN := 36
## Минимальный запас сверху под камеру/вырез, даже если система не сообщила
## безопасную зону (иммерсивный режим, эмуляторы, десктоп).
const SAFE_TOP_MIN := 56.0
const BODY_GAP := 16
const BUTTON_HEIGHT := 68
## Сдвиг пальца/мыши (px), после которого нажатие считается прокруткой.
const DRAG_THRESHOLD := 14.0
## Ширина столбца кнопок в главном меню (вьюпорт 1080).
const MENU_COLUMN_WIDTH := 620.0
## Шаг игрока по карте: переход фишки и пауза перед следующим отсеком, с.
const TRAVEL_STEP_TIME := 0.55
const TRAVEL_STEP_PAUSE := 0.2

var body: VBoxContainer
var content_margin: MarginContainer
var body_margin: MarginContainer
var hud: VBoxContainer
var content_scroll: ScrollContainer
var hp_label: Label
var o2_label: Label
## Оружие в руках; патроны — только при огнестреле.
var weapon_label: Label
var bag_label: Label
## Силы, голод и день (NeedsSystem).
var energy_label: Label
var hunger_label: Label
var day_label: Label
## Уровень и опыт — тонкая полоса над показателями HUD.
var xp_bar: HBoxContainer
var map_button: Button
var character_button: Button
var journal_button: Button
var settings_button: Button
var section_separator: HSeparator
var map_open: bool = false
var journal_open: bool = false
var character_open: bool = false
var settings_open: bool = false
## Верстак базы: оверлей с рецептами поверх экрана модуля.
var workbench_open: bool = false
var character_tab: String = "items"
var journal_tab: String = "goals"

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
## Сколько записей ленты уже показано: новые проявляются анимацией.
var _story_shown: int = 0
## Боковые вырезы экрана (слева + справа) — сужают тело экрана.
var _side_insets: float = 0.0
## Последний ход боя, чьи эффекты ударов уже показаны (0 — ни одного).
var _combat_fx_turn: int = 0
## Экран карты: сама карта, панель маршрута под ней и проложенный, но ещё
## не начатый маршрут (MapSystem.plan_route). Второй тап по цели — в путь.
var _map_view: Control
var _route_panel: VBoxContainer
var _route_panel_read_only: bool = false
var _route_plan: Dictionary = {}
var _travel_tick_id: int = 0
## Идёт перерисовка из-за смены настроек: экран не проявляется заново.
var _restyling: bool = false


func _ready() -> void:
	_fill_parent(self)
	_build_static_layout()
	_apply_hud_fonts()
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)
	_connect_signals()
	_render_current_screen()


func _build_static_layout() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.color = Color("#11141b")
	add_child(background)
	_fill_parent(background)

	content_margin = MarginContainer.new()
	content_margin.name = "ContentMargin"
	add_child(content_margin)
	_fill_parent(content_margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.name = "RootVBox"
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 14)
	content_margin.add_child(root_vbox)

	hud = VBoxContainer.new()
	hud.name = "Hud"
	hud.add_theme_constant_override("separation", 10)
	root_vbox.add_child(hud)

	xp_bar = XP_BAR_SCRIPT.new()
	hud.add_child(xp_bar)

	# При крупном шрифте показатели не помещаются в одну строку — переносятся.
	var stats_row := HFlowContainer.new()
	stats_row.name = "HudStats"
	stats_row.add_theme_constant_override("h_separation", 12)
	stats_row.add_theme_constant_override("v_separation", 4)
	hud.add_child(stats_row)
	hp_label = _make_hud_label()
	o2_label = _make_hud_label()
	weapon_label = _make_hud_label()
	weapon_label.name = "WeaponLabel"
	bag_label = _make_hud_label()
	bag_label.name = "BagLabel"
	energy_label = _make_hud_label()
	energy_label.name = "EnergyLabel"
	hunger_label = _make_hud_label()
	hunger_label.name = "HungerLabel"
	day_label = _make_hud_label()
	day_label.name = "DayLabel"
	for lbl in _hud_labels():
		stats_row.add_child(lbl)

	var nav_row := HBoxContainer.new()
	nav_row.name = "HudNav"
	nav_row.add_theme_constant_override("separation", 10)
	hud.add_child(nav_row)
	map_button = _make_nav_button("Карта", "MapButton", _toggle_map)
	character_button = _make_nav_button("Персонаж", "CharacterButton", _toggle_character)
	journal_button = _make_nav_button("Журнал", "JournalButton", _toggle_journal)
	settings_button = _make_nav_button("Настройки", "SettingsButton", _toggle_settings)
	for btn in [map_button, character_button, journal_button, settings_button]:
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

	# Полоса прокрутки не должна наезжать на текст и кнопки.
	body_margin = MarginContainer.new()
	body_margin.name = "BodyMargin"
	body_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_margin.add_theme_constant_override("margin_right", 18)
	content_scroll.add_child(body_margin)

	body = VBoxContainer.new()
	body.name = "ScreenBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", BODY_GAP)
	body_margin.add_child(body)

	# Основной контент занимает верх и середину экрана, HUD закреплён снизу.
	# Узлы создаются выше в удобном для инициализации порядке, затем переставляются.
	root_vbox.move_child(content_scroll, 0)
	root_vbox.move_child(section_separator, 1)


func _connect_signals() -> void:
	GameState.screen_changed.connect(_on_screen_changed)
	ResourceSystem.hp_changed.connect(_on_resource_changed)
	ResourceSystem.o2_changed.connect(_on_resource_changed)
	ResourceSystem.ammo_changed.connect(_on_resource_changed)
	InventorySystem.item_added.connect(_on_inventory_changed)
	InventorySystem.item_removed.connect(_on_inventory_changed)
	CharacterSystem.changed.connect(_on_character_changed)
	NotificationSystem.changed.connect(_on_notification_changed)
	MapSystem.node_state_changed.connect(func(_node_id: String, _state: String) -> void: _refresh_map())
	MapSystem.node_blocked.connect(_on_map_node_blocked)
	MapSystem.floor_changed.connect(func(_floor_id: String) -> void: _refresh_map())
	MapSystem.fog_changed.connect(_refresh_map)
	MapSystem.travel_changed.connect(_refresh_route_panel)
	SettingsSystem.changed.connect(_on_settings_changed)
	SituationEngine.option_resolved.connect(_on_situation_option_resolved)
	NarrativeSystem.entries_added.connect(_on_story_entries_added)
	ProgressionSystem.xp_gained.connect(_on_xp_gained)
	ProgressionSystem.changed.connect(_update_hud)
	NeedsSystem.changed.connect(_update_hud)
	NeedsSystem.passed_out.connect(_on_passed_out)

func _fill_parent(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	control.grow_vertical = Control.GROW_DIRECTION_BOTH


## Поля экрана с учётом выреза камеры, скруглений и системных панелей.
## DisplayServer отдаёт безопасную зону в пикселях экрана; переводим её в
## координаты вьюпорта (stretch canvas_items) относительно окна игры.
func _apply_safe_area() -> void:
	var left := 0.0
	var top := 0.0
	var right := 0.0
	var bottom := 0.0
	var window_size := DisplayServer.window_get_size()
	if window_size.x > 0 and window_size.y > 0:
		var window_rect := Rect2i(DisplayServer.window_get_position(), window_size)
		var safe := DisplayServer.get_display_safe_area().intersection(window_rect)
		if safe.has_area():
			var scale := get_viewport().get_visible_rect().size / Vector2(window_size)
			left = float(safe.position.x - window_rect.position.x) * scale.x
			top = float(safe.position.y - window_rect.position.y) * scale.y
			right = float(window_rect.end.x - safe.end.x) * scale.x
			bottom = float(window_rect.end.y - safe.end.y) * scale.y
	_side_insets = left + right
	content_margin.add_theme_constant_override("margin_left", CONTENT_MARGIN + roundi(left))
	content_margin.add_theme_constant_override("margin_top", CONTENT_MARGIN + roundi(maxf(top, SAFE_TOP_MIN)))
	content_margin.add_theme_constant_override("margin_right", CONTENT_MARGIN + roundi(right))
	content_margin.add_theme_constant_override("margin_bottom", CONTENT_MARGIN + roundi(bottom))


func _make_hud_label() -> Label:
	var lbl := Label.new()
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color("#eef3ff"))
	return lbl


func _make_nav_button(text: String, node_name: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.name = node_name
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.pressed.connect(SoundSystem.play.bind("ui_click"))
	btn.pressed.connect(callback)
	_style_nav_button(btn, false)
	return btn


## HUD строится один раз, поэтому размеры шрифта переприменяются при смене
## настройки «Размер шрифта», а не только при создании.
func _apply_hud_fonts() -> void:
	for lbl in _hud_labels():
		lbl.add_theme_font_size_override("font_size", UiKit.fs(22))
	for btn in [map_button, character_button, journal_button, settings_button]:
		btn.custom_minimum_size = Vector2(0, UiKit.fs(78))
		btn.add_theme_font_size_override("font_size", UiKit.fs(19))
	xp_bar.apply_fonts()


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
			# Карту перетаскивают как камеру — ленту под ней не прокручиваем.
			var on_map := _map_view_alive() and _map_view.get_global_rect().has_point(event.position)
			_drag_armed = content_scroll.get_global_rect().has_point(event.position) and not on_map
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


## Лента растёт вниз, поэтому после перерисовки показываем её конец —
## новые реплики и кнопки действий.
func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	if not is_instance_valid(content_scroll):
		return
	var bar := content_scroll.get_v_scroll_bar()
	var target := int(maxf(0.0, bar.max_value - bar.page))
	if SettingsSystem.animations:
		var tween := create_tween()
		tween.tween_property(content_scroll, "scroll_vertical", target, 0.22) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		content_scroll.scroll_vertical = target


## Экраны с лентой: модуль и ситуация.
func _is_story_screen() -> bool:
	return GameState.current_screen == GameState.Screen.LOCATION \
		or GameState.current_screen == GameState.Screen.SITUATION


func _any_overlay_open() -> bool:
	return map_open or journal_open or character_open or settings_open or workbench_open


## Плавное появление экрана целиком (карта, журнал, бой, смена сцены).
## Перерисовка того же экрана из-за смены настроек не мигает (_restyling).
func _animate_body() -> void:
	if not SettingsSystem.animations or _restyling:
		body.modulate.a = 1.0
		return
	body.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(body, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE)


## Плавное появление одной новой записи ленты.
func _fade_in(node: CanvasItem, delay: float) -> void:
	if not SettingsSystem.animations:
		return
	node.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_interval(minf(delay, 0.3))
	tween.tween_property(node, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE)


# --- Реакция на системы ---------------------------------------------------------

func _on_resource_changed(_value) -> void:
	_update_hud()


## Опыт набирается на глазах: полоса дотекает, всплывает «+N опыта». Победу
## в бою показывает экран победы — HUD под затемнением просто подтягивается.
func _on_xp_gained(amount: int, _levels: int) -> void:
	if GameState.current_screen == GameState.Screen.COMBAT:
		xp_bar.show_state(ProgressionSystem.level, ProgressionSystem.xp)
		return
	xp_bar.float_gain(amount)
	xp_bar.animate_to(ProgressionSystem.level, ProgressionSystem.xp)


func _on_inventory_changed(_item_id: String) -> void:
	_update_hud()
	_update_nav_buttons()


func _on_character_changed() -> void:
	_update_hud()
	_update_nav_buttons()


func _on_notification_changed() -> void:
	_update_nav_buttons()


## Узел заперт и ключа нет — причина видна под картой.
func _on_map_node_blocked(_node_id: String, message: String) -> void:
	_map_message = message
	_refresh_route_panel()


## Настройка изменилась — тот же экран перерисовывается под новый шрифт
## без анимации появления и на той же прокрутке: иначе каждый щелчок
## переключателя или отпущенный ползунок мигали бы всем экраном.
func _on_settings_changed() -> void:
	var scroll := content_scroll.scroll_vertical
	_apply_hud_fonts()
	_restyling = true
	_render_current_screen()
	_restyling = false
	_restore_scroll(scroll)


## Прокрутку возвращаем после раскладки: до неё новое тело ещё нулевой высоты.
func _restore_scroll(value: int) -> void:
	await get_tree().process_frame
	if is_instance_valid(content_scroll):
		content_scroll.scroll_vertical = value


## Выбор применён и его последствие уже в ленте — показываем «Продолжить».
func _on_situation_option_resolved(_option_id: String) -> void:
	if GameState.current_screen == GameState.Screen.SITUATION:
		_render_current_screen()


## Лента пополнилась, пока игрок на повествовательном экране — дорисовываем.
func _on_story_entries_added(_count: int) -> void:
	if _is_story_screen() and not _any_overlay_open():
		_render_current_screen()


func _on_screen_changed(screen: int) -> void:
	if character_open:
		NotificationSystem.mark_character_seen()
	if journal_open:
		NotificationSystem.mark_journal_seen()
	map_open = false
	journal_open = false
	character_open = false
	settings_open = false
	workbench_open = false
	if screen != GameState.Screen.DEATH:
		_death_message = ""
	_map_message = ""
	_route_plan = {}
	_combat_fx_turn = 0
	_render_current_screen()


func _update_hud() -> void:
	hp_label.text = "❤️ %d/%d" % [ResourceSystem.hp, ResourceSystem.max_hp]
	var o2i := int(ResourceSystem.o2)
	o2_label.text = "💨 O2 %d" % o2i
	o2_label.add_theme_color_override("font_color", UiKit.BAD_COLOR if o2i <= ResourceSystem.LOW_O2 else Color("#eef3ff"))
	weapon_label.text = _weapon_text()
	weapon_label.add_theme_color_override("font_color",
		UiKit.BAD_COLOR if CharacterSystem.has_firearm() and ResourceSystem.ammo <= 0 else Color("#eef3ff"))
	bag_label.text = "🧰 %d/%d" % [InventorySystem.used_slots(), InventorySystem.max_slots]
	energy_label.text = "⚡ %d" % roundi(NeedsSystem.energy)
	energy_label.add_theme_color_override("font_color", UiKit.BAD_COLOR if NeedsSystem.is_tired() else Color("#eef3ff"))
	hunger_label.text = "🍖 %d" % roundi(NeedsSystem.hunger)
	hunger_label.add_theme_color_override("font_color", UiKit.BAD_COLOR if NeedsSystem.is_hungry() else Color("#eef3ff"))
	day_label.text = "☀️ День %d" % NeedsSystem.day
	xp_bar.sync()


func _hud_labels() -> Array:
	return [hp_label, o2_label, weapon_label, bag_label, energy_label, hunger_label, day_label]


## «⚔️ Обломок трубы», «⚔️ Табельный пистолет · 💥 6», «✊ Без оружия»:
## патроны без огнестрела ни к чему, их не показываем.
func _weapon_text() -> String:
	var weapon := CharacterSystem.get_equipped_name("arms")
	if weapon == "":
		return "✊ Без оружия"
	if CharacterSystem.has_firearm():
		return "⚔️ %s · 💥 %d" % [weapon, ResourceSystem.ammo]
	return "⚔️ " + weapon


## Вырубился посреди карты — ленты там не видно, причина пишется под картой.
func _on_passed_out(o2: float) -> void:
	if GameState.current_screen == GameState.Screen.SECTOR_MAP:
		_map_message = "😵 Силы кончились — вы вырубились прямо в пути (−%d O2). Выспитесь на базе." % roundi(o2)
		_refresh_route_panel()


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
		settings_open = false
		workbench_open = false
	_scroll_to_top()
	_render_current_screen()


func _toggle_settings() -> void:
	if settings_open:
		settings_open = false
	else:
		if journal_open:
			NotificationSystem.mark_journal_seen()
		if character_open:
			NotificationSystem.mark_character_seen()
		settings_open = true
		map_open = false
		journal_open = false
		character_open = false
		workbench_open = false
	_scroll_to_top()
	_render_current_screen()


## Кнопка «Карта» в HUD: из модуля и ситуации открывает карту поверх экрана
## (повторное нажатие закрывает и возвращает в модуль). Из модуля по карте
## можно проложить маршрут — игрок выходит, только когда тронется в путь.
## Из ситуации карта только для просмотра. На самой карте кнопка закрывает
## открытый поверх неё журнал, персонажа или настройки.
func _toggle_map() -> void:
	if map_button.disabled:
		return
	if GameState.current_screen == GameState.Screen.SECTOR_MAP and not _any_overlay_open():
		return
	if journal_open:
		NotificationSystem.mark_journal_seen()
	if character_open:
		NotificationSystem.mark_character_seen()
	journal_open = false
	character_open = false
	settings_open = false
	workbench_open = false
	if GameState.current_screen == GameState.Screen.SECTOR_MAP:
		map_open = false
	else:
		map_open = not map_open
	if map_open or GameState.current_screen == GameState.Screen.SECTOR_MAP:
		SoundSystem.play("map_open")
	_route_plan = {}
	_map_message = ""
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
	settings_open = false
	workbench_open = false
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
	var story_before := _story_shown
	_set_body_stretch(false)
	_clear_body()
	if settings_open:
		_render_settings()
		_animate_body()
		return
	if journal_open:
		_render_journal()
		_animate_body()
		return
	if character_open:
		_render_character()
		_animate_body()
		return
	if workbench_open:
		_render_workbench()
		_animate_body()
		return
	if map_open:
		_render_map(GameState.current_screen != GameState.Screen.LOCATION)
		_animate_body()
		return
	if not _is_story_screen():
		_story_shown = 0
	elif story_before > NarrativeSystem.size():
		_story_shown = 0
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


## В пути HUD заперт: сначала «Стоп», потом журнал или персонаж.
func _update_nav_buttons() -> void:
	if map_button == null:
		return
	var blocked := (
		MapSystem.current_sector_id == ""
		or MapSystem.is_travelling()
		or GameState.current_screen == GameState.Screen.MAIN_MENU
		or GameState.current_screen == GameState.Screen.COMBAT
		or GameState.current_screen == GameState.Screen.VICTORY
		or GameState.current_screen == GameState.Screen.DEATH
	)
	map_button.disabled = blocked
	character_button.disabled = blocked
	journal_button.disabled = blocked
	settings_button.disabled = GameState.current_screen == GameState.Screen.COMBAT or MapSystem.is_travelling()
	_set_nav_label(map_button, "🗺️", "Карта", false)
	_set_nav_label(character_button, "🧑‍🚀", "Персонаж", NotificationSystem.has_character_alert())
	_set_nav_label(journal_button, "📓", "Журнал", NotificationSystem.has_journal_alert())
	_set_nav_label(settings_button, "⚙️", "Настройки", false)
	var map_active := not journal_open and not character_open and not settings_open and (
		map_open or GameState.current_screen == GameState.Screen.SECTOR_MAP
	)
	_style_nav_button(map_button, map_active)
	_style_nav_button(character_button, character_open)
	_style_nav_button(journal_button, journal_open)
	_style_nav_button(settings_button, settings_open)


## Значок сверху, подпись снизу: так «(!)» не обрезает название на узком экране.
func _set_nav_label(btn: Button, icon: String, title: String, alert: bool) -> void:
	btn.text = "%s%s\n%s" % [icon, " (!)" if alert else "", title]


func _clear_body() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()


func _add_title(text: String) -> Label:
	var lbl := _add_text(text)
	lbl.add_theme_font_size_override("font_size", UiKit.fs(34))
	lbl.add_theme_color_override("font_color", Color("#f5f8ff"))
	return lbl


## Ширина выставляется сразу: у переносимого Label без ширины минимальная
## высота на первом проходе раскладки считается «по букве на строку».
## Растянутое тело экрана (карта) успевало вырасти под эту высоту и не
## сжималось обратно — карта съезжала вниз после перерисовки.
func _add_text(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", UiKit.fs(24))
	lbl.add_theme_color_override("font_color", Color("#d7deee"))
	lbl.size.x = _body_width()
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
	return maxf(64.0, viewport_width - CONTENT_MARGIN * 2.0 - _side_insets - 32.0)


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

## Главное меню: заставка, название по центру и короткий столбец кнопок.
## Тело экрана на этом экране растягивается на всю высоту, поэтому блок
## держится по центру, а не липнет к верхней кромке.
func _render_main_menu() -> void:
	_set_body_stretch(true)
	_add_spacer(1.0)

	var art := UiKit.scene_art("title_screen", _body_width() * 0.92)
	if art != null:
		var art_row := CenterContainer.new()
		art_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		art_row.add_child(art)
		body.add_child(art_row)
		_pulse(art)

	var title := UiKit.text("CosmoTextGame", 58, UiKit.TITLE_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)

	var tagline := UiKit.text("Обломок «Персефона». Кислорода — на несколько решений.", 24, UiKit.ACCENT_COLOR)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(tagline)

	var menu := _add_centered_column(MENU_COLUMN_WIDTH)
	var has_run := FileAccess.file_exists(SaveManager.RUN_PATH)
	if has_run:
		menu.add_child(_menu_button("▶️ Продолжить", _continue_game, "default"))
		menu.add_child(_menu_button("✨ Новая игра", _start_new_game, "quiet"))
	else:
		menu.add_child(_menu_button("✨ Новая игра", _start_new_game, "default"))
	menu.add_child(_menu_button("⚙️ Настройки", _toggle_settings, "quiet"))

	var chronicle := "Забегов: %d · побед: %d · финалов открыто: %d из %d" % [
		ChronicleSystem.runs_finished, ChronicleSystem.victories,
		ChronicleSystem.endings_seen_count(), ChronicleSystem.endings_total()]
	var stats := UiKit.text(chronicle, 20, UiKit.MUTED_COLOR)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(stats)

	_add_spacer(1.0)
	var version := UiKit.text("Версия %s" % str(ProjectSettings.get_setting("application/config/version", "0.1.0")), 18, UiKit.MUTED_COLOR)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(version)


## Столбец по центру экрана с ограниченной шириной — кнопки меню не должны
## растягиваться на всю ширину планшета.
func _add_centered_column(width: float) -> VBoxContainer:
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(minf(width, _body_width()), 0)
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)
	return column


func _menu_button(text: String, callback: Callable, kind: String) -> Button:
	var btn := UiKit.button(text, kind, BUTTON_HEIGHT + 12)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.pressed.connect(callback)
	return btn


func _add_spacer(stretch: float) -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = stretch
	body.add_child(spacer)


## На экранах-лентах тело растёт вниз, в меню и на карте — занимает всю высоту.
func _set_body_stretch(stretch: bool) -> void:
	var flags := Control.SIZE_EXPAND_FILL if stretch else Control.SIZE_SHRINK_BEGIN
	body.size_flags_vertical = flags
	body_margin.size_flags_vertical = flags


## Медленное «дыхание» заставки: экран не выглядит статичной картинкой.
func _pulse(node: CanvasItem) -> void:
	if not SettingsSystem.animations:
		return
	var tween := node.create_tween().set_loops()
	tween.tween_property(node, "modulate", Color(1.08, 1.08, 1.08, 1.0), 2.2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(node, "modulate", Color(0.9, 0.9, 0.95, 1.0), 2.2).set_trans(Tween.TRANS_SINE)


func _start_new_game() -> void:
	GameState.start_new_game()


func _continue_game() -> void:
	GameState.continue_game()


## Карта: легенда, сама карта на всю высоту и панель маршрута под ней.
## read_only — карта из ситуации: только посмотреть.
func _render_map(read_only: bool = false) -> void:
	_set_body_stretch(true)
	_add_title("🗺️ " + MapSystem.get_sector_title())
	body.add_child(_map_legend())
	var nodes := MapSystem.get_map_nodes(true)
	_map_view = SECTOR_MAP_VIEW_SCRIPT.new()
	_map_view.name = "SectorMapView"
	body.add_child(_map_view)
	_map_view.node_selected.connect(_on_map_node_selected)
	_map_view.setup({
		"map_config": MapSystem.get_map_config(),
		"nodes": nodes,
		"hub_node_id": MapSystem.hub_node_id,
		"current_floor_id": MapSystem.get_current_floor_id(),
		"known_floors": MapSystem.get_known_floor_ids(),
		"player_node_id": MapSystem.player_node_id,
		"read_only": read_only,
	})
	_map_view.set_route(_current_route_path())
	_route_panel = VBoxContainer.new()
	_route_panel.name = "RoutePanel"
	_route_panel.add_theme_constant_override("separation", 10)
	body.add_child(_route_panel)
	_route_panel_read_only = read_only
	_refresh_route_panel()
	if MapSystem.is_travelling():
		# Экран карты вернулся посреди пути (прорыв после побега) — идём дальше.
		_map_view.focus_player(false)
		_schedule_travel_tick(TRAVEL_STEP_PAUSE * 2.0)


## Строка цветных значков: что значит цвет отсека.
func _map_legend() -> Control:
	var flow := HFlowContainer.new()
	flow.name = "MapLegend"
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 6)
	var styles: Dictionary = SECTOR_MAP_VIEW_SCRIPT.STATUS_STYLE
	var entries: Array = []
	for status in SECTOR_MAP_VIEW_SCRIPT.LEGEND_ORDER:
		var style: Dictionary = styles[status]
		entries.append([str(style["icon"]), style["fill"], style["border"], str(style["legend"])])
	entries.append([SECTOR_MAP_VIEW_SCRIPT.PLAYER_ICON, Color("#22415c"), Color("#f5f8ff"), "Ты"])
	entries.append([SECTOR_MAP_VIEW_SCRIPT.UNSEALED_BADGE, Color("#151a23"), Color("#34475e"), "Без давления: дороже по O2"])
	for entry in entries:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 6)
		var swatch := PanelContainer.new()
		swatch.custom_minimum_size = Vector2(UiKit.fs(30), UiKit.fs(30))
		swatch.add_theme_stylebox_override("panel", UiKit.box(entry[1], entry[2], 2, 0))
		var icon := UiKit.text(str(entry[0]), 16, Color.WHITE)
		icon.autowrap_mode = TextServer.AUTOWRAP_OFF
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		swatch.add_child(icon)
		chip.add_child(swatch)
		var caption := UiKit.text(str(entry[3]), 17, UiKit.MUTED_COLOR)
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		caption.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		chip.add_child(caption)
		flow.add_child(chip)
	return flow


## Первое нажатие на отсек — маршрут и цена, второе на ту же цель — в путь.
func _on_map_node_selected(node_id: String) -> void:
	if MapSystem.is_travelling():
		return
	if not _route_plan.is_empty() and str(_route_plan.get("target", "")) == node_id:
		_start_travel()
		return
	_route_plan = {}
	_map_message = ""
	if GameState.current_screen == GameState.Screen.LOCATION and node_id == MapSystem.player_node_id:
		_map_message = "Ты уже здесь."
	else:
		var plan := MapSystem.plan_route(node_id)
		if bool(plan["ok"]):
			_route_plan = plan
		else:
			_map_message = str(plan["message"])
	if _map_view_alive():
		_map_view.set_route(_current_route_path())
	_refresh_route_panel()


## В путь: из модуля игрок сначала выходит, камера едет к нему, дальше шаги.
func _start_travel() -> void:
	var target := str(_route_plan.get("target", ""))
	_route_plan = {}
	_map_message = ""
	if GameState.current_screen == GameState.Screen.LOCATION:
		GameState.leave_location()
	var plan := MapSystem.start_travel(target)
	if not bool(plan["ok"]):
		_map_message = str(plan["message"])
		_refresh_route_panel()
		return
	if _map_view_alive():
		_map_view.set_route(_current_route_path())
		_map_view.focus_player(true)
	_schedule_travel_tick(TRAVEL_STEP_PAUSE * 2.0)


## «Стоп» посреди перехода: шаг не сделан, фишка возвращается в свой отсек.
func _stop_travel() -> void:
	_travel_tick_id += 1
	MapSystem.cancel_travel()
	if _map_view_alive():
		_map_view.set_route([])
		_map_view.move_player(MapSystem.player_node_id, TRAVEL_STEP_PAUSE)


## Таймер шага: старый таймер после «Стоп» или перерисовки ничего не делает.
func _schedule_travel_tick(delay: float) -> void:
	_travel_tick_id += 1
	var tick_id := _travel_tick_id
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if tick_id == _travel_tick_id:
			_travel_tick())


## Шаг маршрута: фишка сначала доезжает до следующего отсека, потом шаг
## исполняется (кислород, перехват, вход). Поездка на лифте — сразу.
func _travel_tick() -> void:
	if not MapSystem.is_travelling() or GameState.current_screen != GameState.Screen.SECTOR_MAP or _any_overlay_open():
		return
	var next := MapSystem.peek_travel_step()
	var to := str(next.get("to", ""))
	var step_time := TRAVEL_STEP_TIME if SettingsSystem.animations else 0.0
	if to == "" or bool(next.get("ride", false)) or step_time <= 0.0 or not _map_view_alive():
		_travel_commit()
		return
	_map_view.move_player(to, step_time)
	_travel_tick_id += 1
	var tick_id := _travel_tick_id
	get_tree().create_timer(step_time).timeout.connect(func() -> void:
		if tick_id == _travel_tick_id:
			_travel_commit())


## Вход в модуль (цель или перехват) и смерть меняют экран сами — дальше
## шагать некуда.
func _travel_commit() -> void:
	if not MapSystem.is_travelling() or GameState.current_screen != GameState.Screen.SECTOR_MAP:
		return
	var result := MapSystem.travel_step()
	if result != "moved" and result != "arrived":
		return
	if _map_view_alive():
		_map_view.move_player(MapSystem.player_node_id, 0.0)
		_map_view.set_route(_current_route_path())
	if result == "moved":
		_schedule_travel_tick(TRAVEL_STEP_PAUSE)
	elif _map_view_alive():
		# Дошли (лифт): камера отпускает игрока и показывает палубу целиком.
		get_tree().create_timer(TRAVEL_STEP_PAUSE * 2.0).timeout.connect(func() -> void:
			if _map_view_alive() and not MapSystem.is_travelling():
				_map_view.overview(true))


## Узлы маршрута после игрока: оставшийся путь или проложенный план.
func _current_route_path() -> Array:
	var travel := MapSystem.get_travel()
	if not travel.is_empty():
		return (travel["path"] as Array).slice(int(travel["index"]))
	if not _route_plan.is_empty():
		return _route_plan["path"]
	return []


func _map_view_alive() -> bool:
	return _map_view != null and is_instance_valid(_map_view) and _map_view.is_inside_tree()


## Узлы и туман изменились (шаг, замок, лифт) — карта обновляется на месте,
## без перерисовки экрана: камера и фишка игрока не сбрасываются.
func _refresh_map() -> void:
	if not _map_view_alive():
		return
	_map_view.update_nodes(MapSystem.get_map_nodes(true), MapSystem.get_current_floor_id(),
		MapSystem.get_known_floor_ids(), MapSystem.player_node_id)
	_map_view.set_route(_current_route_path())


## Панель под картой: путь в дороге и «Стоп», проложенный маршрут с ценой и
## предупреждениями, причина отказа или подсказка.
func _refresh_route_panel() -> void:
	_update_nav_buttons()
	if _route_panel == null or not is_instance_valid(_route_panel) or not _route_panel.is_inside_tree():
		return
	for child in _route_panel.get_children():
		_route_panel.remove_child(child)
		child.queue_free()
	if _map_message != "":
		_route_panel.add_child(UiKit.text(_map_message, 22, UiKit.EXIT_COLOR))
	if _route_panel_read_only:
		_route_panel.add_child(UiKit.text("Карта только для просмотра — сначала закончи событие.", 20, UiKit.MUTED_COLOR))
		var close := UiKit.button("✖ Закрыть карту", "quiet", BUTTON_HEIGHT)
		close.pressed.connect(_close_map_overlay)
		_route_panel.add_child(close)
		return
	var travel := MapSystem.get_travel()
	if MapSystem.is_travelling():
		var path: Array = travel["path"]
		var left: Array = path.slice(int(travel["index"]))
		_route_panel.add_child(UiKit.text("🚶 Иду: %s · шаг %d из %d" % [
			_map_node_name(str(travel["target"])), int(travel["index"]) + 1, maxi(1, path.size())], 22, UiKit.TITLE_COLOR))
		_route_panel.add_child(UiKit.text("💨 До цели ≈ −%d O2" % roundi(MapSystem.path_cost(left)), 20, UiKit.ACCENT_COLOR))
		var stop := UiKit.button("⏹ Стоп", "danger", BUTTON_HEIGHT)
		stop.name = "TravelStop"
		stop.alignment = HORIZONTAL_ALIGNMENT_CENTER
		stop.pressed.connect(_stop_travel)
		_route_panel.add_child(stop)
		return
	if _route_plan.is_empty():
		if _map_message == "":
			_route_panel.add_child(UiKit.text("Нажми на отсек — проложу маршрут и посчитаю кислород.", 20, UiKit.MUTED_COLOR))
		return
	var plan_path: Array = _route_plan["path"]
	var names: Array = []
	var floor_before := MapSystem.get_current_floor_id()
	for node_id in plan_path:
		var floor_id := MapSystem.get_node_floor_id(str(node_id))
		if floor_id != floor_before:
			names.append("⇅ " + MapSystem.get_floor_title(floor_id))
			floor_before = floor_id
		else:
			names.append(_map_node_name(str(node_id)))
	var target := str(_route_plan["target"])
	var route_text := " → ".join(names) if not names.is_empty() else "войти в «%s»" % _map_node_name(target)
	_route_panel.add_child(UiKit.text("📍 " + route_text, 21, UiKit.TITLE_COLOR))
	var cost := float(_route_plan["cost"])
	var o2 := ResourceSystem.o2
	_route_panel.add_child(UiKit.text("💨 ≈ −%d O2 · останется ≈ %d" % [roundi(cost), maxi(0, roundi(o2 - cost))], 20, UiKit.ACCENT_COLOR))
	for warning in _route_warnings(plan_path, cost):
		_route_panel.add_child(UiKit.text(warning, 20, UiKit.BAD_COLOR))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var go := UiKit.button("▶️ Идти", "default", BUTTON_HEIGHT)
	go.name = "TravelGo"
	go.alignment = HORIZONTAL_ALIGNMENT_CENTER
	go.pressed.connect(_start_travel)
	row.add_child(go)
	var cancel := UiKit.button("✖ Отмена", "quiet", BUTTON_HEIGHT)
	cancel.alignment = HORIZONTAL_ALIGNMENT_CENTER
	cancel.pressed.connect(func() -> void:
		_route_plan = {}
		if _map_view_alive():
			_map_view.set_route([])
		_refresh_route_panel())
	row.add_child(cancel)
	_route_panel.add_child(row)


## Кислорода не хватит или станет мало; враг или неизвестные отсеки по пути.
func _route_warnings(path: Array, cost: float) -> Array:
	var warnings: Array = []
	var o2 := ResourceSystem.o2
	if cost >= o2:
		warnings.append("⛔ Кислорода не хватит: нужно ≈ %d, в баллоне %d." % [roundi(cost), int(o2)])
	elif o2 - cost <= ResourceSystem.LOW_O2:
		warnings.append("⚠️ После перехода останется ≈ %d O2 — это мало." % roundi(o2 - cost))
	if NeedsSystem.is_tired():
		warnings.append("😵 Сил ≈ %d — можно вырубиться в пути. Выспитесь на базе." % roundi(NeedsSystem.energy))
	var hostile: Array = []
	var unknown := false
	for i in range(path.size() - 1):
		match MapSystem.get_node_status(str(path[i])):
			"hostile":
				hostile.append(_map_node_name(str(path[i])))
			"unknown":
				unknown = true
	if not hostile.is_empty():
		warnings.append("☠ По пути враг: %s — не пропустит без боя." % ", ".join(hostile))
	if unknown:
		warnings.append("❔ По пути неизвестные отсеки — там могут остановить.")
	return warnings


## Подпись узла как на карте; неисследованный отсек не выдаёт своего имени.
func _map_node_name(node_id: String) -> String:
	if MapSystem.get_node_status(node_id) == "unknown":
		return "Неизвестно"
	var node: Dictionary = MapSystem.nodes.get(node_id, {})
	var cfg = node.get("map", {})
	if cfg is Dictionary and str(cfg.get("label", "")) != "":
		return str(cfg["label"])
	return str(node.get("title", node_id))


## Экран модуля и ситуация используют общий буфер, но при переходе старый
## контекст очищается: описание локации не остаётся под событием.
func _render_situation() -> void:
	_render_story()
	if SituationEngine.awaiting_continue:
		_add_button("▶️ Продолжить", _continue_situation, "exit")
		return
	var options := SituationEngine.get_available_options()
	if options.is_empty():
		# Некуда выбирать — единственная кнопка закрывает ситуацию.
		_add_button("▶️ Продолжить", _continue_situation, "exit")
		return
	for opt in options:
		var opt_id: String = opt.get("id", "")
		# Завершающие варианты (выход на карту, конец события, финал) выделены цветом.
		var kind := "exit" if SituationEngine.is_closing_option(opt) else "default"
		_add_button(str(opt.get("label", opt_id)), _make_option_callback(opt_id), kind)


func _continue_situation() -> void:
	GameState.finish_situation()


## Текущий контекст: новые записи проявляются и подматываются вниз.
func _render_story() -> void:
	var entries := NarrativeSystem.get_entries()
	var fresh_from := _story_shown if _story_shown <= entries.size() else 0
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		for node in _story_nodes(entry):
			body.add_child(node)
			if i >= fresh_from:
				_fade_in(node, 0.05 * float(i - fresh_from))
	_story_shown = entries.size()
	_scroll_to_bottom()


## Узлы одной записи ленты: картинка (если есть) и текст в своём стиле.
func _story_nodes(entry: Dictionary) -> Array:
	var nodes: Array = []
	var image := str(entry.get("image", ""))
	if image != "":
		var art := UiKit.scene_art(image, _body_width())
		if art != null:
			nodes.append(art)
	var text := str(entry.get("text", ""))
	if text == "":
		return nodes
	match str(entry.get("kind", "text")):
		"scene":
			nodes.append(UiKit.text(text, 32, UiKit.TITLE_COLOR))
		"choice":
			nodes.append(UiKit.text("— " + text, 24, UiKit.EXIT_COLOR))
		"result":
			nodes.append(UiKit.text(text, 24, UiKit.TEXT_COLOR))
		"notice":
			nodes.append(UiKit.text(text, 22, UiKit.ACCENT_COLOR))
		"gain":
			nodes.append(UiKit.text(text, 22, UiKit.GOOD_COLOR))
		"loss":
			nodes.append(UiKit.text(text, 22, UiKit.BAD_COLOR))
		"system":
			nodes.append(UiKit.text(text, 22, UiKit.MUTED_COLOR))
		_:
			nodes.append(UiKit.text(text, 24, UiKit.TEXT_COLOR))
	return nodes


func _make_option_callback(opt_id: String) -> Callable:
	return func(): SituationEngine.select_option(opt_id)


func _render_location() -> void:
	_render_story()

	var events := LocationSystem.get_manual_events()
	var explore_total := ExplorationSystem.total(LocationSystem.current_id)
	if not events.is_empty() or explore_total > 0:
		_add_section("Действия")
	if explore_total > 0:
		_add_explore_button(explore_total)
	if not events.is_empty():
		for ev in events:
			var event_id := str(ev.get("id", ""))
			var label := str(ev.get("label", event_id))
			if LocationSystem.is_event_locked(ev):
				# Запертый ящик виден, но не нажимается: в подписи — нужный ключ.
				var locked_btn := UiKit.button(
					"%s — %s" % [label, EffectResolver.lock_hint(LocationSystem.get_event_lock(ev))],
					"quiet", BUTTON_HEIGHT + 28)
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
			_add_button("✋ Взять: %s%s" % [_item_name(item_id), _count_suffix(int(stash[item_id]))], _make_stash_take_callback(item_id), "quiet")


## «Исследовать»: сколько ещё можно найти в отсеке. Искать нечего — кнопка
## неактивна; спрятанное, что откроется позже (нужен ключ, навык, событие),
## держит счётчик, но сейчас не находится.
func _add_explore_button(total: int) -> void:
	var left := ExplorationSystem.remaining(LocationSystem.current_id)
	var btn: Button
	if ExplorationSystem.can_explore():
		btn = _add_button("🔍 Исследовать отсек · осталось %d из %d" % [left, total], GameState.explore_location)
	else:
		var text := "🔍 Пока искать нечего · осталось %d из %d" % [left, total] if left > 0 else "🔍 Отсек исследован полностью"
		btn = UiKit.button(text, "quiet", BUTTON_HEIGHT)
		btn.disabled = true
		body.add_child(btn)
	btn.name = "ExploreButton"


## Модуль-база: ручное сохранение, верстак и разгрузка сумки на склад.
func _render_base_section() -> void:
	_add_section("База")
	_add_button("🛏️ Закончить день — сон и сохранение", GameState.end_day, "quiet")
	_add_button("🛠️ Верстак", _open_workbench, "quiet")
	var droppable: Array = []
	for entry in InventorySystem.get_slots():
		var item_id: String = entry.get("id", "")
		if InventorySystem.can_drop(item_id):
			droppable.append(item_id)
	if droppable.is_empty():
		return
	_add_section("Разложить по складу")
	for item_id in droppable:
		_add_button("📦 Положить: " + _item_name(item_id), _make_base_store_callback(item_id), "quiet")


func _open_workbench() -> void:
	workbench_open = true
	_scroll_to_top()
	_render_current_screen()


## Материалы и результат могли измениться — перепроверяем автособытия модуля.
func _close_workbench() -> void:
	workbench_open = false
	_scroll_to_top()
	GameState.refresh_location()


func _make_base_store_callback(item_id: String) -> Callable:
	return func():
		if InventorySystem.drop_item(item_id):
			LocationSystem.add_notice("На складе: %s." % _item_name(item_id))
		_render_current_screen()


func _make_location_event_callback(event_id: String) -> Callable:
	return func(): GameState.start_location_event(event_id)


func _make_stash_take_callback(item_id: String) -> Callable:
	return func():
		var total := int(LocationSystem.get_stash().get(item_id, 0))
		var taken := LocationSystem.stash_take(item_id)
		if taken == 0:
			LocationSystem.add_notice("В сумке нет места для «%s»." % _item_name(item_id))
		elif taken < total:
			LocationSystem.add_notice("Взято: %s ×%d. Остальное не поместилось." % [_item_name(item_id), taken])
		else:
			LocationSystem.add_notice("Взято: %s%s." % [_item_name(item_id), _count_suffix(taken)])
		GameState.refresh_location()


func _render_character() -> void:
	var panel: VBoxContainer = CHARACTER_PANEL_SCRIPT.new()
	panel.tab = character_tab
	panel.tab_changed.connect(_on_character_tab_changed)
	body.add_child(panel)


func _render_workbench() -> void:
	var panel: VBoxContainer = WORKBENCH_PANEL_SCRIPT.new()
	panel.closed.connect(_close_workbench)
	body.add_child(panel)


func _on_character_tab_changed(new_tab: String) -> void:
	character_tab = new_tab
	_scroll_to_top()


## Эффекты ударов проигрываются один раз на ход: повторная перерисовка того
## же хода (смена настроек) их не повторяет. Экран боя прижат к низу —
## манёвры под большим пальцем; не влез — прокручен к концу.
func _render_combat() -> void:
	_clear_body()
	_set_body_stretch(true)
	var st := CombatSystem.get_state()
	_add_title("Схватка: %s" % str(st.get("enemy_name", "")))
	var view: VBoxContainer = COMBAT_VIEW_SCRIPT.new()
	view.move_selected.connect(_combat_action)
	view.finished.connect(CombatSystem.finish)
	body.add_child(view)
	var turn := int(st.get("turn", 0))
	view.setup(st, turn > _combat_fx_turn)
	_combat_fx_turn = turn
	_scroll_to_bottom()


func _combat_action(move_id: String, payload = null) -> void:
	CombatSystem.player_action(move_id, payload)
	if GameState.current_screen == GameState.Screen.COMBAT:
		_render_combat()


const DEATH_TEXTS := {
	"o2": {
		"image": "death_o2",
		"cause": "Кислород закончился",
		"epitaph": "Последний вдох ушёл в пустой баллон. Визор затянуло инеем, и шум в шлеме стих.",
	},
	"hp": {
		"image": "death_hp",
		"cause": "Раны оказались смертельными",
		"epitaph": "Скафандр держал давление дольше, чем тело. Над тем, кто не дошёл, мигает аварийная лампа.",
	},
}
## Сколько последних записей журнала показать в «Последних минутах».
const DEATH_RECAP_ENTRIES := 3
## Длинные тексты событий в сводке режутся — это напоминание, а не пересказ.
const DEATH_RECAP_LENGTH := 80
## Иллюстрация уже экрана: заголовок и кнопки должны помещаться без прокрутки.
const DEATH_ART_SCALE := 0.8


## Экран смерти: иллюстрация причины, крупный заголовок, эпитафия, смертельный
## удар (если погиб в бою), выбор — откат или новый забег, ниже — последние
## записи журнала и счётчики хроники. Блоки проявляются по очереди.
func _render_death() -> void:
	_set_body_stretch(true)
	var texts: Dictionary = DEATH_TEXTS.get(GameState.last_death_cause, DEATH_TEXTS["hp"])
	var blocks: Array = []
	_add_spacer(1.0)

	var art := UiKit.scene_art(str(texts["image"]), _body_width() * DEATH_ART_SCALE)
	if art != null:
		var art_row := CenterContainer.new()
		art_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		art_row.add_child(art)
		body.add_child(art_row)
		blocks.append(art_row)
	blocks.append(_add_centered_text("ВЫ ПОГИБЛИ", 58, UiKit.BAD_COLOR))
	blocks.append(_add_centered_text(str(texts["cause"]), 28, UiKit.TITLE_COLOR))
	blocks.append(_add_centered_text(str(texts["epitaph"]), 22, UiKit.MUTED_COLOR))
	if GameState.last_death_blow != "":
		blocks.append(_add_centered_text("Последний удар: %s" % GameState.last_death_blow, 22, UiKit.BAD_COLOR))

	# Выбор — сразу под причиной, чтобы не прокручивать; сводка — ниже.
	var menu := _add_centered_column(MENU_COLUMN_WIDTH)
	var can_rollback := EconomyManager.can_use_rollback_today() and SaveManager.has_checkpoint()
	if can_rollback:
		var hint := "" if EconomyManager.has_full_access else " (реклама)"
		menu.add_child(_menu_button("⏪ Вернуться к чекпойнту" + hint, _death_rollback, "default"))
	menu.add_child(_menu_button("🔄 Начать заново", _death_restart, "quiet" if can_rollback else "default"))
	blocks.append(menu.get_parent())
	if _death_message != "":
		blocks.append(_add_centered_text(_death_message, 22, UiKit.EXIT_COLOR))

	var recap := _death_recap()
	if not recap.is_empty():
		var card := UiKit.card(body)
		card.add_child(UiKit.section("Последние минуты"))
		for line in recap:
			var lbl := UiKit.text(line, 21, UiKit.TEXT_COLOR)
			lbl.size.x = _body_width() - 40.0  # см. _add_text: ширина до раскладки
			card.add_child(lbl)
		blocks.append(card.get_parent())

	blocks.append(_add_centered_text("Забегов: %d · смертей: %d · записей в архиве: %d" % [
		ChronicleSystem.runs_finished, ChronicleSystem.deaths, ArchiveSystem.get_unlocked().size()],
		19, UiKit.MUTED_COLOR))
	_add_spacer(1.0)

	for i in range(blocks.size()):
		_fade_in(blocks[i], 0.06 * float(i))


## Строки «O2 120 · Бой: Дрон» — что было перед смертью, от старых к новым.
func _death_recap() -> Array:
	var entries := JournalSystem.get_entries()
	var lines: Array = []
	for i in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[i]
		if str(entry.get("kind", "")) == "death":
			continue
		var text := str(entry.get("text", ""))
		if text.length() > DEATH_RECAP_LENGTH:
			text = text.substr(0, DEATH_RECAP_LENGTH - 1).strip_edges() + "…"
		lines.push_front("O2 %d · %s%s" % [int(entry.get("o2", 0)), text, _count_suffix(int(entry.get("count", 1)))])
		if lines.size() >= DEATH_RECAP_ENTRIES:
			break
	return lines


## Надпись по центру тела экрана; ширина — сразу, как в _add_text.
func _add_centered_text(value: String, font_size: int, color: Color) -> Label:
	var lbl := UiKit.text(value, font_size, color)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size.x = _body_width()
	body.add_child(lbl)
	return lbl


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

	_add_button("🔄 Новый забег", _victory_restart)
	_add_button("🏠 В главное меню", _victory_menu, "quiet")


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


## Журнал — три вкладки: «Цели» (мысли героя и задачи, QuestSystem),
## «Хроника» (что уже произошло в забеге, JournalSystem) и «Архив»
## (найденные лор-фрагменты, ArchiveSystem). Закрывает журнал кнопка HUD.
const JOURNAL_TABS := [["goals", "🎯 Цели"], ["log", "📜 Хроника"], ["lore", "🗄️ Архив"]]
const JOURNAL_COLORS := {
	"move": UiKit.ACCENT_COLOR,
	"combat": UiKit.BAD_COLOR,
	"death": UiKit.BAD_COLOR,
	"victory": UiKit.EXIT_COLOR,
	"lore": UiKit.TITLE_COLOR,
	"choice": UiKit.TITLE_COLOR,
	"loot": UiKit.MUTED_COLOR,
	"rest": UiKit.GOOD_COLOR,
	"goal": UiKit.EXIT_COLOR,
}


func _render_journal() -> void:
	_add_title("Журнал")
	var tabs := HBoxContainer.new()
	tabs.name = "JournalTabs"
	tabs.add_theme_constant_override("separation", 8)
	for entry in JOURNAL_TABS:
		var tab_id := str(entry[0])
		var label := str(entry[1])
		if (tab_id == "lore" and NotificationSystem.has_new_lore()) or (tab_id == "goals" and NotificationSystem.has_new_goals()):
			label += " (!)"
		var btn := UiKit.button(label, "tab_active" if tab_id == journal_tab else "quiet", 58)
		btn.name = "JournalTab_%s" % tab_id
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_font_size_override("font_size", UiKit.fs(20))
		btn.pressed.connect(_select_journal_tab.bind(tab_id))
		tabs.add_child(btn)
	body.add_child(tabs)

	match journal_tab:
		"lore":
			_render_journal_archive()
		"log":
			_render_journal_log()
		_:
			_render_journal_goals()


## Цели: сверху мысли героя о происходящем, ниже начатые цели — текущие с
## шагами (засчитанные ✓, текущий ▸), под ними выполненные.
func _render_journal_goals() -> void:
	var thoughts := QuestSystem.get_thoughts()
	if thoughts != "":
		var thoughts_card := UiKit.card(body)
		thoughts_card.add_child(UiKit.text("💭 Мысли", 24, UiKit.ACCENT_COLOR))
		thoughts_card.add_child(UiKit.text(thoughts, 22))
	var quests := QuestSystem.get_quests()
	var active := quests.filter(func(q: Dictionary) -> bool: return not bool(q["completed"]))
	var completed := quests.filter(func(q: Dictionary) -> bool: return bool(q["completed"]))
	_add_section("Цели" if not active.is_empty() else "Текущих целей нет")
	for quest in active:
		var card := UiKit.card(body)
		card.add_child(UiKit.text("🎯 " + str(quest["title"]), 26, UiKit.TITLE_COLOR))
		if str(quest["description"]) != "":
			card.add_child(UiKit.text(str(quest["description"]), 21, UiKit.MUTED_COLOR))
		for step in quest["steps"]:
			var done := bool(step["done"])
			card.add_child(UiKit.text(("✓ " if done else "▸ ") + str(step["text"]), 22,
				UiKit.MUTED_COLOR if done else UiKit.TEXT_COLOR))
	if completed.is_empty():
		return
	_add_section("Выполнено")
	for quest in completed:
		var card := UiKit.card(body)
		card.add_child(UiKit.text("✓ " + str(quest["title"]), 24, UiKit.GOOD_COLOR))
		for step in quest["steps"]:
			card.add_child(UiKit.text("✓ " + str(step["text"]), 20, UiKit.MUTED_COLOR))


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
		lbl.add_theme_font_size_override("font_size", UiKit.fs(22))
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


## Настройки интерфейса: размер шрифта и громкость — ползунки, плавные
## переходы и звук — переключатели. В игре настройки закрывает кнопка HUD;
## в главном меню HUD нет, поэтому там внизу «В меню».
func _render_settings() -> void:
	_add_title("Настройки")
	var font_caption := UiKit.section("")
	body.add_child(font_caption)
	var font_slider := UiKit.slider(SettingsSystem.FONT_SCALE_MIN, SettingsSystem.FONT_SCALE_MAX, 0.05,
		SettingsSystem.font_scale())
	font_slider.name = "FontScaleSlider"
	font_slider.tick_count = SettingsSystem.FONT_SCALE_ANCHORS.size()
	font_slider.ticks_on_borders = true
	body.add_child(font_slider)
	_bind_settings_slider(font_slider, font_caption,
		func(value: float) -> String: return "Размер шрифта: %s×" % _scale_text(SettingsSystem.snap_font_scale(value)),
		func(value: float) -> void: SettingsSystem.set_font_scale(value))
	var anchors := HBoxContainer.new()
	for i in range(SettingsSystem.FONT_SCALE_ANCHORS.size()):
		var anchor := UiKit.text("%s×" % _scale_text(float(SettingsSystem.FONT_SCALE_ANCHORS[i])), 20, UiKit.MUTED_COLOR)
		anchor.horizontal_alignment = [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_RIGHT][mini(i, 2)]
		anchors.add_child(anchor)
	body.add_child(anchors)

	_add_section("Плавные переходы")
	var anim_btn := UiKit.button(
		"Анимации: включены" if SettingsSystem.animations else "Анимации: выключены",
		"tab_active" if SettingsSystem.animations else "quiet")
	anim_btn.name = "AnimationsToggle"
	anim_btn.pressed.connect(func(): SettingsSystem.set_animations(not SettingsSystem.animations))
	body.add_child(anim_btn)
	_add_section("Звук")
	var sound_btn := UiKit.button(
		"Звук: включён" if SettingsSystem.sound_enabled else "Звук: выключен",
		"tab_active" if SettingsSystem.sound_enabled else "quiet")
	sound_btn.name = "SoundToggle"
	sound_btn.pressed.connect(_toggle_sound)
	body.add_child(sound_btn)
	if SettingsSystem.sound_enabled:
		var volume_caption := UiKit.section("")
		body.add_child(volume_caption)
		var volume_slider := UiKit.slider(0, 100, 1, SettingsSystem.sound_volume_percent)
		volume_slider.name = "SoundVolumeSlider"
		body.add_child(volume_slider)
		_bind_settings_slider(volume_slider, volume_caption,
			func(value: float) -> String: return "Громкость: %d" % roundi(value),
			_set_sound_volume)
	_add_text("Настройки меняют интерфейс сразу и сохраняются между запусками.")
	if GameState.current_screen == GameState.Screen.MAIN_MENU:
		_add_button("← В меню", _toggle_settings, "quiet")


## Подпись ползунка следует за пальцем, а значение применяется, когда палец
## отпущен (или по нажатию на дорожку): настройка перерисовывает экран, и
## ползунок под пальцем не должен пересоздаваться посреди движения.
func _bind_settings_slider(slider: HSlider, caption: Label, describe: Callable, commit: Callable) -> void:
	caption.text = describe.call(slider.value)
	var dragging := [false]
	slider.drag_started.connect(func() -> void: dragging[0] = true)
	slider.drag_ended.connect(func(_changed: bool) -> void:
		dragging[0] = false
		commit.call_deferred(slider.value))
	slider.value_changed.connect(func(value: float) -> void:
		caption.text = describe.call(value)
		if not dragging[0]:
			commit.call_deferred(value))


func _scale_text(value: float) -> String:
	return str(snappedf(value, 0.05)).trim_suffix(".0")


## После смены громкости или включения звука — образец на новой громкости.
func _set_sound_volume(value: float) -> void:
	SettingsSystem.set_sound_volume(roundi(value))
	SoundSystem.play("pickup")


func _toggle_sound() -> void:
	SettingsSystem.set_sound_enabled(not SettingsSystem.sound_enabled)
	SoundSystem.play("pickup")
