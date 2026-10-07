extends Control

const UiKit = preload("res://scenes/ui/UiKit.gd")
const SECTOR_MAP_VIEW_SCRIPT := preload("res://scenes/ui/SectorMapView.gd")
const CHARACTER_PANEL_SCRIPT := preload("res://scenes/ui/CharacterPanel.gd")
const SKILL_TREE_PANEL_SCRIPT := preload("res://scenes/ui/SkillTreePanel.gd")
const GALAXY_MAP_VIEW_SCRIPT := preload("res://scenes/ui/GalaxyMapView.gd")
const DIALOGUE_VIEW_SCRIPT := preload("res://scenes/ui/DialogueView.gd")
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
## Появление кнопок ситуации: пауза перед первой, шаг между кнопками и время
## всплытия одной кнопки, с.
const BUTTON_REVEAL_DELAY := 0.05
const BUTTON_REVEAL_STEP := 0.07
const BUTTON_REVEAL_TIME := 0.18
## Один экранный такт анимации сна соответствует одному игровому часу.
const REST_STEP_SECONDS := 0.18

var body: VBoxContainer
var content_margin: MarginContainer
var body_margin: MarginContainer
var hud: VBoxContainer
var content_scroll: ScrollContainer
var pinned_header: VBoxContainer
var hp_label: Label
var hp_bar: ProgressBar
var hp_icon: Label
var o2_label: Label
## Оружие в руках; патроны — только при огнестреле.
var weapon_label: Label
var bag_label: Label
## Силы и питание показываются остатком 0…max; NeedsSystem.hunger внутри
## хранит обратную величину — накопленный голод.
var energy_label: Label
var energy_bar: ProgressBar
var energy_icon: Label
var hunger_label: Label
var hunger_bar: ProgressBar
var hunger_icon: Label
var day_label: Label
## Уровень и опыт — тонкая полоса над показателями HUD.
var xp_bar: HBoxContainer
var map_button: Button
var galaxy_button: Button
var character_button: Button
var skill_button: Button
var journal_button: Button
var settings_button: Button
var section_separator: HSeparator
var map_open: bool = false
var journal_open: bool = false
var character_open: bool = false
## Общее развитие: кольцевое дерево и базовые навыки.
var skill_open: bool = false
var skill_tab: String = "tree"
## Экран создания героя: одна листаемая анкета за раз.
var origin_picker_open: bool = false
var origin_index: int = 0
var settings_open: bool = false
## Верстак базы: оверлей с рецептами поверх экрана модуля.
var workbench_open: bool = false
var character_tab: String = "items"
var character_items_tab: String = "bag"
var journal_tab: String = "goals"
var codex_tab: String = "terms"

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
var _story_render_queued: bool = false
## Время (с), когда кнопки ситуации станут доступны: считается от конца печати
## текста и не сдвигается назад перерисовками.
var _buttons_ready_at: float = 0.0
## Боковые вырезы экрана (слева + справа) — сужают тело экрана.
var _side_insets: float = 0.0
## Последний ход боя, чьи эффекты ударов уже показаны (0 — ни одного).
var _combat_fx_turn: int = 0
## Экран карты: сама карта, панель маршрута под ней и проложенный, но ещё
## не начатый маршрут (MapSystem.plan_route). Второй тап по цели — в путь.
var _map_view: Control
## Глобальная карта системы: карта, панель выбранной точки и выбор игрока.
var _galaxy_view: Control
var _galaxy_panel: VBoxContainer
var _galaxy_selected: String = ""
## Оверлей разговора: живёт, пока идёт диалог, и убирается по сигналу closed.
var _dialogue_view: Control
var _route_panel: VBoxContainer
var _route_panel_read_only: bool = false
var _route_plan: Dictionary = {}
var _travel_tick_id: int = 0
## Идёт перерисовка из-за смены настроек: экран не проявляется заново.
var _restyling: bool = false
## Плашка поиска по центру экрана (только пока идёт исследование с анимациями).
var _explore_overlay: Control
var _explore_card: PanelContainer
var _explore_caption: Label
var _explore_bar: ProgressBar
var _explore_total: int = 1
## Итог сна/обморока: отдельная блокирующая плашка с почасовым прогрессом.
var _rest_overlay: Control
var _rest_card: PanelContainer
var _rest_caption: Label
var _rest_stats: Label
var _rest_bar: ProgressBar
var _rest_animation_serial: int = 0
var _energy_alert_tween: Tween
var _hunger_alert_tween: Tween
var _energy_alert_active: bool = false
var _hunger_alert_active: bool = false
## Уведомление о новом узле и отложенный фокус карты.
var _map_reveal_overlay: Control
var _map_reveal_card: PanelContainer
var _map_reveal_serial: int = 0
var _pending_map_focus_node: String = ""
## Открытый узел, чью плашку ждём показать до конца печати ленты: { node, title }.
var _pending_map_reveal: Dictionary = {}
var _map_reveal_scheduled: bool = false


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

	# Три главных состояния читаются как доля от максимума, а не как три
	# разрозненных числа среди служебных показателей.
	var resource_grid := GridContainer.new()
	resource_grid.name = "HudResources"
	resource_grid.columns = 3
	resource_grid.add_theme_constant_override("h_separation", 12)
	hud.add_child(resource_grid)
	var hp_meter := _make_resource_meter(resource_grid, "Здоровье", "❤️", Color("#55b884"))
	hp_icon = hp_meter["icon"]
	hp_label = hp_meter["value"]
	hp_bar = hp_meter["bar"]
	var energy_meter := _make_resource_meter(resource_grid, "Силы", "⚡", Color("#e0b153"))
	energy_icon = energy_meter["icon"]
	energy_label = energy_meter["value"]
	energy_bar = energy_meter["bar"]
	var hunger_meter := _make_resource_meter(resource_grid, "Питание", "🍖", Color("#cf8f58"))
	hunger_icon = hunger_meter["icon"]
	hunger_label = hunger_meter["value"]
	hunger_bar = hunger_meter["bar"]

	# Остальные показатели компактны и при крупном шрифте переносятся.
	var stats_row := HFlowContainer.new()
	stats_row.name = "HudStats"
	stats_row.add_theme_constant_override("h_separation", 12)
	stats_row.add_theme_constant_override("v_separation", 4)
	hud.add_child(stats_row)
	o2_label = _make_hud_label()
	weapon_label = _make_hud_label()
	weapon_label.name = "WeaponLabel"
	bag_label = _make_hud_label()
	bag_label.name = "BagLabel"
	day_label = _make_hud_label()
	day_label.name = "DayLabel"
	for lbl in [o2_label, weapon_label, bag_label, day_label]:
		stats_row.add_child(lbl)

	var nav_row := HBoxContainer.new()
	nav_row.name = "HudNav"
	nav_row.add_theme_constant_override("separation", 10)
	hud.add_child(nav_row)
	map_button = _make_nav_button("Карта", "MapButton", _toggle_map)
	galaxy_button = _make_nav_button("Космос", "GalaxyButton", _toggle_galaxy)
	character_button = _make_nav_button("Персонаж", "CharacterButton", _toggle_character)
	skill_button = _make_nav_button("Развитие", "SkillButton", _toggle_skills)
	journal_button = _make_nav_button("Журнал", "JournalButton", _toggle_journal)
	settings_button = _make_nav_button("Настройки", "SettingsButton", _toggle_settings)
	for btn in [map_button, galaxy_button, character_button, skill_button, journal_button, settings_button]:
		nav_row.add_child(btn)

	section_separator = HSeparator.new()
	section_separator.name = "SectionSeparator"
	root_vbox.add_child(section_separator)
	pinned_header = VBoxContainer.new()
	pinned_header.name = "PinnedHeader"
	pinned_header.visible = false
	pinned_header.add_theme_constant_override("separation", 10)
	root_vbox.add_child(pinned_header)


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
	# Заголовки и вкладки журналов/персонажа стоят над ScrollContainer.
	root_vbox.move_child(pinned_header, 0)
	root_vbox.move_child(content_scroll, 1)
	root_vbox.move_child(section_separator, 2)


func _connect_signals() -> void:
	GameState.screen_changed.connect(_on_screen_changed)
	GameState.exploration_progressed.connect(_on_exploration_progressed)
	GameState.exploration_finished.connect(_hide_explore_overlay)
	ResourceSystem.hp_changed.connect(_on_resource_changed)
	ResourceSystem.o2_changed.connect(_on_resource_changed)
	ResourceSystem.ammo_changed.connect(_on_resource_changed)
	InventorySystem.item_added.connect(_on_inventory_changed)
	InventorySystem.item_removed.connect(_on_inventory_changed)
	CharacterSystem.changed.connect(_on_character_changed)
	NotificationSystem.changed.connect(_on_notification_changed)
	MapSystem.node_state_changed.connect(func(_node_id: String, _state: String) -> void: _refresh_map())
	MapSystem.node_unlocked.connect(_on_map_node_unlocked)
	MapSystem.node_blocked.connect(_on_map_node_blocked)
	MapSystem.floor_changed.connect(func(_floor_id: String) -> void: _refresh_map())
	MapSystem.fog_changed.connect(_refresh_map)
	MapSystem.travel_changed.connect(_refresh_route_panel)
	SettingsSystem.changed.connect(_on_settings_changed)
	SituationEngine.option_resolved.connect(_on_situation_option_resolved)
	NarrativeSystem.entries_added.connect(_on_story_entries_added)
	NarrativeSystem.cleared.connect(_on_story_cleared)
	ProgressionSystem.xp_gained.connect(_on_xp_gained)
	ProgressionSystem.changed.connect(_update_hud)
	NeedsSystem.changed.connect(_update_hud)
	NeedsSystem.passed_out.connect(_on_passed_out)
	NeedsSystem.rest_completed.connect(_on_rest_completed)

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


## Компактный бар HUD: подпись и число сверху, заполнение снизу.
func _make_resource_meter(parent: Control, title: String, emoji: String, fill: Color) -> Dictionary:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 3)
	parent.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	column.add_child(row)
	var icon := Label.new()
	icon.text = emoji
	icon.tooltip_text = title
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.resized.connect(func() -> void: icon.pivot_offset = icon.size * 0.5)
	row.add_child(icon)
	var title_label := Label.new()
	title_label.text = title
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	title_label.tooltip_text = title
	row.add_child(title_label)
	var value_label := Label.new()
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = UiKit.fs(16)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_stylebox_override("background", UiKit.box(Color("#10141b"), Color("#2e3a4c"), 1, 0))
	bar.add_theme_stylebox_override("fill", UiKit.box(fill, fill.lightened(0.16), 1, 0))
	column.add_child(bar)
	for lbl in [icon, title_label, value_label]:
		lbl.add_theme_font_size_override("font_size", UiKit.fs(18))
		lbl.add_theme_color_override("font_color", Color("#eef3ff"))
	return {"icon": icon, "value": value_label, "bar": bar}


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
	for lbl in [hp_icon, energy_icon, hunger_icon, hp_label, energy_label, hunger_label]:
		lbl.add_theme_font_size_override("font_size", UiKit.fs(18))
	for bar in [hp_bar, energy_bar, hunger_bar]:
		bar.custom_minimum_size.y = UiKit.fs(16)
	for btn in [map_button, character_button, skill_button, journal_button, settings_button]:
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
# Карта и ползунки ведут палец сами: отмена нажатия увела бы бегунок ползунка
# за левый край, и значение упало бы в минимум.

func _input(event: InputEvent) -> void:
	if _injecting or content_scroll == null or not content_scroll.is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Карту перетаскивают как камеру, ползунок — как бегунок: ленту под ними не прокручиваем.
			var on_map := _map_view_alive() and _map_view.get_global_rect().has_point(event.position)
			_drag_armed = content_scroll.get_global_rect().has_point(event.position) and not on_map \
				and not _slider_at(event.position)
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


## Ползунок под пальцем: его перетаскивание не превращается в прокрутку ленты.
func _slider_at(point: Vector2) -> bool:
	for node in body.find_children("*", "Slider", true, false):
		var slider := node as Slider
		if slider.is_visible_in_tree() and slider.get_global_rect().has_point(point):
			return true
	return false


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
	return map_open or journal_open or character_open or skill_open or settings_open or workbench_open \
		or _dialogue_view != null


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

## Новая запись печатается с постоянной скоростью. Картинка той же записи
## проявляется параллельно, а привязанный звук запускается с первым знаком.
## Возвращает время начала следующей записи, чтобы строки шли по очереди.
func _reveal_story_entry(entry: Dictionary, nodes: Array, start: float) -> float:
	var sound_id := str(entry.get("sound", ""))
	if not SettingsSystem.animations:
		if sound_id != "":
			SoundSystem.play(sound_id)
		return start
	var text := str(entry.get("text", ""))
	var duration := maxf(0.08, float(text.length()) / float(SettingsSystem.text_speed_cps))
	for node in nodes:
		if node is RichTextLabel:
			var rich := node as RichTextLabel
			# Строки раскладываются по всему тексту заранее: слово, которое не
			# влезет, сразу начинает печататься с новой строки.
			rich.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
			rich.visible_ratio = 0.0
			var text_tween := rich.create_tween()
			text_tween.tween_interval(start)
			text_tween.tween_property(rich, "visible_ratio", 1.0, duration).set_trans(Tween.TRANS_LINEAR)
		elif node is Label:
			var label := node as Label
			label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
			label.visible_ratio = 0.0
			var text_tween := label.create_tween()
			text_tween.tween_interval(start)
			text_tween.tween_property(label, "visible_ratio", 1.0, duration).set_trans(Tween.TRANS_LINEAR)
		else:
			node.modulate.a = 0.0
			var fade: Tween = (node as Node).create_tween()
			fade.tween_interval(start)
			fade.tween_property(node, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE)
	if sound_id != "" and not nodes.is_empty():
		var sound_tween: Tween = (nodes[0] as Node).create_tween()
		sound_tween.tween_interval(maxf(0.01, start))
		sound_tween.tween_callback(SoundSystem.play.bind(sound_id))
	return start + duration + 0.08




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
	_restart_need_alerts()
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

## Лента пополнилась — откладываем перерисовку до конца кадра. Событие часто
## добавляет текст и несколько находок подряд; одна общая раскладка не обрывает
## анимацию предыдущей строки и сохраняет последовательный ритм.
func _on_story_entries_added(_count: int) -> void:
	if not _is_story_screen() or _any_overlay_open() or _story_render_queued:
		return
	_story_render_queued = true
	_render_story_deferred.call_deferred()


func _render_story_deferred() -> void:
	_story_render_queued = false
	if _is_story_screen() and not _any_overlay_open() and _story_shown != NarrativeSystem.size():
		_render_current_screen()


func _on_story_cleared() -> void:
	_story_shown = 0
	_buttons_ready_at = 0.0


func _on_exploration_progressed(step: int, total: int, o2_spent: float) -> void:
	if step == 0:
		_show_explore_overlay(total)
	_update_explore_overlay(step, total, o2_spent)
	if GameState.current_screen == GameState.Screen.LOCATION and not _any_overlay_open():
		_render_current_screen()


## Плашка по центру: затемнение, карточка с подписью и шкалой. Шкала плавно
## идёт к концу поиска весь его срок, а не прыгает по тактам. Касания
## затемнение съедает — пока идёт поиск, остальное не нажать.
func _show_explore_overlay(total: int) -> void:
	_drop_explore_overlay()
	if not SettingsSystem.animations:
		return
	_explore_total = maxi(1, total)
	_explore_overlay = Control.new()
	_explore_overlay.name = "ExplorationOverlay"
	_explore_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_explore_overlay)
	_fill_parent(_explore_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.07, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_explore_overlay.add_child(dim)
	_fill_parent(dim)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_explore_overlay.add_child(center)
	_fill_parent(center)
	_explore_card = PanelContainer.new()
	_explore_card.name = "ExplorationProgress"
	_explore_card.custom_minimum_size.x = 720.0
	_explore_card.add_theme_stylebox_override("panel", UiKit.box(Color("#171d27"), Color("#5d91a8"), 2, 30))
	center.add_child(_explore_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	_explore_card.add_child(column)
	var title := UiKit.text("🔍 Исследование отсека", 30, UiKit.TITLE_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_explore_bar = ProgressBar.new()
	_explore_bar.name = "ExplorationProgressBar"
	_explore_bar.max_value = 1.0
	_explore_bar.value = 0.0
	_explore_bar.show_percentage = false
	_explore_bar.custom_minimum_size.y = UiKit.fs(22)
	_explore_bar.add_theme_stylebox_override("background", UiKit.box(Color("#202733"), Color("#323d4e"), 1, 0))
	_explore_bar.add_theme_stylebox_override("fill", UiKit.box(Color("#2f8fb5"), Color("#9fd3e6"), 1, 0))
	column.add_child(_explore_bar)
	_explore_caption = UiKit.text("", 22, UiKit.ACCENT_COLOR)
	_explore_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_explore_caption)
	# Появление: плашка вырастает из центра, затемнение проявляется.
	_explore_overlay.modulate.a = 0.0
	_explore_card.pivot_offset = Vector2(360.0, 90.0)
	_explore_card.scale = Vector2(0.88, 0.88)
	var appear := create_tween().set_parallel(true)
	appear.tween_property(_explore_overlay, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE)
	appear.tween_property(_explore_card, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var fill := _explore_overlay.create_tween()
	fill.tween_property(_explore_bar, "value", 1.0, float(_explore_total) * GameState.EXPLORE_STEP_SECONDS) \
		.set_trans(Tween.TRANS_LINEAR)


func _update_explore_overlay(step: int, total: int, o2_spent: float) -> void:
	if _explore_overlay == null:
		return
	var caption := "Такт %d из %d" % [maxi(1, step), total] if step > 0 else "Осматриваем отсек…"
	if o2_spent > 0.0:
		caption += " · −%d O2" % roundi(o2_spent)
	elif is_zero_approx(ResourceSystem.get_o2_cost("explore_tick")):
		caption += " · воздух отсека"
	_explore_caption.text = caption


## Поиск закончен: шкала доходит до конца, плашка гаснет и уменьшается.
func _hide_explore_overlay() -> void:
	if _explore_overlay == null:
		return
	var overlay := _explore_overlay
	var card := _explore_card
	_explore_overlay = null
	_explore_card = null
	var bar := _explore_bar
	var fade := overlay.create_tween()
	fade.tween_property(bar, "value", 1.0, 0.12)
	fade.tween_interval(0.12)
	fade.set_parallel(true)
	fade.tween_property(overlay, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_SINE)
	fade.tween_property(card, "scale", Vector2(0.92, 0.92), 0.25).set_trans(Tween.TRANS_SINE)
	fade.chain().tween_callback(overlay.queue_free)


func _drop_explore_overlay() -> void:
	if _explore_overlay != null:
		_explore_overlay.queue_free()
		_explore_overlay = null
		_explore_card = null

## Сон и обморок уже применены системой; UI почасово показывает прошедшее
## время и фактические изменения ресурсов, не давая нажимать экран под плашкой.
func _on_rest_completed(result: Dictionary) -> void:
	if SettingsSystem.animations:
		_animate_rest_overlay(result)


func _animate_rest_overlay(result: Dictionary) -> void:
	_drop_rest_overlay()
	_rest_animation_serial += 1
	var serial := _rest_animation_serial
	var hours := maxi(1, int(result.get("hours", 1)))
	_show_rest_overlay(result, hours)
	for elapsed in range(hours + 1):
		if elapsed > 0:
			await get_tree().create_timer(REST_STEP_SECONDS).timeout
		if serial != _rest_animation_serial or _rest_overlay == null:
			return
		_update_rest_overlay(result, elapsed, hours)
	await get_tree().create_timer(0.8).timeout
	if serial == _rest_animation_serial:
		_hide_rest_overlay()


func _show_rest_overlay(result: Dictionary, hours: int) -> void:
	_rest_overlay = Control.new()
	_rest_overlay.name = "RestOverlay"
	_rest_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_rest_overlay)
	_fill_parent(_rest_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.07, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rest_overlay.add_child(dim)
	_fill_parent(dim)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rest_overlay.add_child(center)
	_fill_parent(center)
	_rest_card = PanelContainer.new()
	_rest_card.name = "RestProgress"
	_rest_card.custom_minimum_size.x = 760.0
	_rest_card.add_theme_stylebox_override("panel", UiKit.box(Color("#171d27"), Color("#8a78b8"), 2, 30))
	center.add_child(_rest_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	_rest_card.add_child(column)
	var title_text := "😵 Обморок" if bool(result.get("forced", false)) else "🛏️ Сон · %d ч." % hours
	var title := UiKit.text(title_text, 30, UiKit.TITLE_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var quality := UiKit.text("Качество сна: %s" % str(result.get("quality_title", "")), 22,
		UiKit.BAD_COLOR if str(result.get("quality", "")) == "poor" else UiKit.ACCENT_COLOR)
	quality.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(quality)
	_rest_bar = ProgressBar.new()
	_rest_bar.name = "RestProgressBar"
	_rest_bar.max_value = 1.0
	_rest_bar.value = 0.0
	_rest_bar.show_percentage = false
	_rest_bar.custom_minimum_size.y = UiKit.fs(22)
	_rest_bar.add_theme_stylebox_override("background", UiKit.box(Color("#202733"), Color("#323d4e"), 1, 0))
	_rest_bar.add_theme_stylebox_override("fill", UiKit.box(Color("#6c5ca4"), Color("#c6b6ff"), 1, 0))
	column.add_child(_rest_bar)
	_rest_caption = UiKit.text("", 22, UiKit.ACCENT_COLOR)
	_rest_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_rest_caption)
	_rest_stats = UiKit.text("", 22, UiKit.TEXT_COLOR)
	_rest_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_rest_stats)
	_rest_overlay.modulate.a = 0.0
	_rest_card.pivot_offset = Vector2(380.0, 120.0)
	_rest_card.scale = Vector2(0.88, 0.88)
	var appear := create_tween().set_parallel(true)
	appear.tween_property(_rest_overlay, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE)
	appear.tween_property(_rest_card, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var fill := _rest_overlay.create_tween()
	fill.tween_property(_rest_bar, "value", 1.0, float(hours) * REST_STEP_SECONDS).set_trans(Tween.TRANS_LINEAR)


func _update_rest_overlay(result: Dictionary, elapsed: int, hours: int) -> void:
	if _rest_overlay == null:
		return
	var total_minutes := (int(result.get("start_day", 1)) - 1) * 1440 \
		+ int(result.get("start_time", 0)) + elapsed * 60
	var shown_day := floori(float(total_minutes) / 1440.0) + 1
	var shown_time := total_minutes % 1440
	_rest_caption.text = ("Засыпаем…" if elapsed == 0 else "Прошло %d из %d ч. · День %d, %02d:%02d" % [
		elapsed, hours, shown_day, floori(float(shown_time) / 60.0), shown_time % 60])
	var ratio := float(elapsed) / float(hours)
	_rest_stats.text = "⚡ +%d сил · ❤️ +%d HP · 🍖 −%d питания" % [
		roundi(float(result.get("energy_restored", 0.0)) * ratio),
		roundi(float(result.get("hp_restored", 0)) * ratio),
		roundi(float(result.get("nutrition_spent", 0.0)) * ratio)]


func _hide_rest_overlay() -> void:
	if _rest_overlay == null:
		return
	var overlay := _rest_overlay
	var card := _rest_card
	_rest_overlay = null
	_rest_card = null
	var fade := overlay.create_tween().set_parallel(true)
	fade.tween_property(overlay, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_SINE)
	fade.tween_property(card, "scale", Vector2(0.92, 0.92), 0.25).set_trans(Tween.TRANS_SINE)
	fade.chain().tween_callback(overlay.queue_free)


func _drop_rest_overlay() -> void:
	_rest_animation_serial += 1
	if _rest_overlay != null:
		_rest_overlay.queue_free()
	_rest_overlay = null
	_rest_card = null

## Открытый эффектом узел получает заметную плашку на пять секунд. Кнопка
## открывает карту; там сам узел продолжает пульсировать до нажатия или таймера.
## Плашка ждёт, пока лента допечатает строку «Открыта новая локация» — иначе она
## перекрывает ещё не прочитанный текст события.
func _on_map_node_unlocked(node_id: String, title: String) -> void:
	_pending_map_reveal = {"node": node_id, "title": title}
	if not _is_story_screen():
		_flush_pending_map_reveal()


## Ставит показ плашки на конец печати ленты (delay — сколько ещё печатать).
func _queue_pending_map_reveal(delay: float) -> void:
	if _pending_map_reveal.is_empty() or _map_reveal_scheduled:
		return
	if delay <= 0.0 or not SettingsSystem.animations:
		_flush_pending_map_reveal()
		return
	_map_reveal_scheduled = true
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(_flush_pending_map_reveal)


func _flush_pending_map_reveal() -> void:
	_map_reveal_scheduled = false
	if _pending_map_reveal.is_empty():
		return
	var node_id := str(_pending_map_reveal.get("node", ""))
	var title := str(_pending_map_reveal.get("title", ""))
	_pending_map_reveal = {}
	_show_map_reveal_overlay(node_id, title)


func _show_map_reveal_overlay(node_id: String, title: String) -> void:
	_drop_map_reveal_overlay()
	_pending_map_focus_node = node_id
	_map_reveal_serial += 1
	var serial := _map_reveal_serial
	_map_reveal_overlay = Control.new()
	_map_reveal_overlay.name = "MapRevealOverlay"
	_map_reveal_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_map_reveal_overlay)
	_fill_parent(_map_reveal_overlay)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_reveal_overlay.add_child(center)
	_fill_parent(center)
	_map_reveal_card = PanelContainer.new()
	_map_reveal_card.name = "MapRevealCard"
	_map_reveal_card.custom_minimum_size.x = 700.0
	_map_reveal_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_reveal_card.add_theme_stylebox_override("panel", UiKit.box(Color("#242015"), UiKit.ACCENT_COLOR, 3, 26))
	center.add_child(_map_reveal_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_map_reveal_card.add_child(column)
	var caption := UiKit.text("Открыта новая локация\n«%s»" % title, 28, UiKit.TITLE_COLOR)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(caption)
	var show_btn := UiKit.button("Увидеть на карте", "default", 60)
	show_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	show_btn.pressed.connect(_show_revealed_node_on_map)
	column.add_child(show_btn)
	if SettingsSystem.animations:
		var pulse := _map_reveal_card.create_tween().set_loops()
		pulse.tween_property(_map_reveal_card, "modulate", Color("#ffd884"), 0.45).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(_map_reveal_card, "modulate", Color.WHITE, 0.45).set_trans(Tween.TRANS_SINE)
	await get_tree().create_timer(5.0).timeout
	if serial == _map_reveal_serial:
		if _pending_map_focus_node == node_id:
			_pending_map_focus_node = ""
		_drop_map_reveal_overlay()


func _show_revealed_node_on_map() -> void:
	_drop_map_reveal_overlay()
	if journal_open:
		_mark_active_journal_seen()
	if character_open:
		_mark_active_character_seen()
	journal_open = false
	character_open = false
	settings_open = false
	workbench_open = false
	map_open = GameState.current_screen != GameState.Screen.SECTOR_MAP
	SoundSystem.play("map_open")
	_route_plan = {}
	_map_message = ""
	_scroll_to_top()
	_render_current_screen()


func _drop_map_reveal_overlay() -> void:
	_map_reveal_serial += 1
	if _map_reveal_overlay != null:
		_map_reveal_overlay.queue_free()
	_map_reveal_overlay = null
	_map_reveal_card = null



func _on_screen_changed(screen: int) -> void:
	if character_open:
		_mark_active_character_seen()
	if journal_open:
		_mark_active_journal_seen()
	map_open = false
	journal_open = false
	character_open = false
	settings_open = false
	workbench_open = false
	if screen != GameState.Screen.DEATH:
		_death_message = ""
		_map_message = ""
	if screen != GameState.Screen.DIALOGUE:
		_drop_dialogue_view()
	_route_plan = {}
	_combat_fx_turn = 0
	_render_current_screen()


func _update_hud() -> void:
	hp_bar.max_value = maxi(1, ResourceSystem.max_hp)
	hp_bar.value = ResourceSystem.hp
	hp_label.text = "%d/%d" % [ResourceSystem.hp, ResourceSystem.max_hp]
	var o2i := int(ResourceSystem.o2)
	o2_label.text = "💨 O2 %d/%d" % [o2i, roundi(ResourceSystem.max_o2)]
	o2_label.add_theme_color_override("font_color", UiKit.BAD_COLOR if o2i <= ResourceSystem.low_o2() else Color("#eef3ff"))
	weapon_label.text = _weapon_text()
	weapon_label.add_theme_color_override("font_color",
		UiKit.BAD_COLOR if CharacterSystem.has_firearm() and ResourceSystem.ammo <= 0 else Color("#eef3ff"))
	bag_label.text = "🧰 %d/%d" % [InventorySystem.used_slots(), InventorySystem.max_slots]
	energy_bar.max_value = maxf(1.0, NeedsSystem.max_energy())
	energy_bar.value = NeedsSystem.energy
	energy_label.text = "%d/%d" % [roundi(NeedsSystem.energy), roundi(NeedsSystem.max_energy())]
	var nutrition := NeedsSystem.max_hunger() - NeedsSystem.hunger
	hunger_bar.max_value = maxf(1.0, NeedsSystem.max_hunger())
	hunger_bar.value = nutrition
	hunger_label.text = "%d/%d" % [roundi(nutrition), roundi(NeedsSystem.max_hunger())]
	day_label.text = "☀️ День %d · %s" % [NeedsSystem.day, NeedsSystem.clock_text()]
	_sync_need_alerts()
	xp_bar.sync()


func _sync_need_alerts() -> void:
	var tired := NeedsSystem.is_tired()
	var hungry := NeedsSystem.is_hungry()
	if tired != _energy_alert_active or (tired and not SettingsSystem.animations and _energy_alert_tween != null):
		_energy_alert_active = tired
		_energy_alert_tween = _set_need_icon_alert(energy_icon, tired, _energy_alert_tween)
	if hungry != _hunger_alert_active or (hungry and not SettingsSystem.animations and _hunger_alert_tween != null):
		_hunger_alert_active = hungry
		_hunger_alert_tween = _set_need_icon_alert(hunger_icon, hungry, _hunger_alert_tween)


func _set_need_icon_alert(icon: Label, active: bool, current: Tween) -> Tween:
	if current != null:
		current.kill()
	icon.scale = Vector2.ONE
	icon.rotation = 0.0
	icon.modulate = UiKit.BAD_COLOR if active else Color.WHITE
	if not active or not SettingsSystem.animations:
		return null
	var tween := create_tween().set_loops()
	tween.tween_property(icon, "scale", Vector2(1.28, 1.28), 0.42).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(icon, "rotation", deg_to_rad(-7.0), 0.42).set_trans(Tween.TRANS_SINE)
	tween.tween_property(icon, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(icon, "rotation", deg_to_rad(7.0), 0.42).set_trans(Tween.TRANS_SINE)
	return tween


func _restart_need_alerts() -> void:
	_energy_alert_active = false
	_hunger_alert_active = false
	if _energy_alert_tween != null:
		_energy_alert_tween.kill()
		_energy_alert_tween = null
	if _hunger_alert_tween != null:
		_hunger_alert_tween.kill()
		_hunger_alert_tween = null
	_sync_need_alerts()


func _hud_labels() -> Array:
	return [hp_icon, hp_label, o2_label, weapon_label, bag_label, energy_icon,
		energy_label, hunger_icon, hunger_label, day_label]


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
		_map_message = "😵 Силы кончились — плохой сон на %d ч. прямо в пути (−%d O2)." % [
			NeedsSystem.pass_out_hours(), roundi(o2)]
		_refresh_route_panel()


# --- HUD-вкладки ----------------------------------------------------------------

func _toggle_journal() -> void:
	if journal_button.disabled:
		return
	if journal_open:
		_mark_active_journal_seen()
		journal_open = false
	else:
		if character_open:
			_mark_active_character_seen()
		_mark_active_journal_seen()
		journal_open = true
		map_open = false
		character_open = false
		skill_open = false
		settings_open = false
		workbench_open = false
	_scroll_to_top()
	_render_current_screen()


func _toggle_settings() -> void:
	if settings_open:
		settings_open = false
	else:
		if journal_open:
			_mark_active_journal_seen()
		if character_open:
			_mark_active_character_seen()
		settings_open = true
		map_open = false
		journal_open = false
		character_open = false
		skill_open = false
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
		_mark_active_journal_seen()
	if character_open:
		_mark_active_character_seen()
	journal_open = false
	character_open = false
	skill_open = false
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


## Кнопка «Космос»: глобальная карта системы. Пока корабля нет, кнопки не видно.
## Открывается из модуля и с карты сектора; разговор и бой её не пускают.
func _toggle_galaxy() -> void:
	if galaxy_button.disabled:
		return
	if GameState.current_screen == GameState.Screen.GALAXY_MAP:
		GameState.close_galaxy()
		return
	_galaxy_selected = ""
	GameState.open_galaxy()


## Курс прокладывают из модуля и с карты сектора: из ситуации, боя и финала — нет.
func _galaxy_available() -> bool:
	match GameState.current_screen:
		GameState.Screen.LOCATION, GameState.Screen.SECTOR_MAP, GameState.Screen.GALAXY_MAP:
			return true
	return false


func _toggle_character() -> void:
	if character_button.disabled:
		return
	if character_open:
		_close_character()
		return
	if journal_open:
		_mark_active_journal_seen()
	character_open = true
	map_open = false
	journal_open = false
	skill_open = false
	settings_open = false
	workbench_open = false
	_scroll_to_top()
	_render_current_screen()


## Предметы могли измениться — в модуле перепроверяем его автособытия.
func _close_character() -> void:
	_mark_active_character_seen()
	character_open = false
	_scroll_to_top()
	if GameState.current_screen == GameState.Screen.LOCATION:
		GameState.refresh_location()
	else:
		_render_current_screen()


## Кнопка «Развитие»: кольцевое дерево поверх экрана. Игровые правила живут в
## SkillTreeSystem — панель только показывает и покупает.
func _toggle_skills() -> void:
	if skill_button.disabled:
		return
	if skill_open:
		skill_open = false
	else:
		if journal_open:
			_mark_active_journal_seen()
		if character_open:
			_mark_active_character_seen()
		skill_open = true
		map_open = false
		journal_open = false
		character_open = false
		settings_open = false
		workbench_open = false
	_scroll_to_top()
	_render_current_screen()



func _mark_active_character_seen() -> void:
	if character_tab == "items":
		NotificationSystem.mark_character_items_seen(character_items_tab)


func _mark_active_journal_seen() -> void:
	match journal_tab:
		"goals":
			NotificationSystem.mark_goals_seen()
		"lore":
			NotificationSystem.mark_lore_seen()
		"codex":
			NotificationSystem.mark_codex_seen(codex_tab)


func _render_current_screen() -> void:
	_update_hud()
	_set_chrome_visible(GameState.current_screen != GameState.Screen.MAIN_MENU)
	_update_nav_buttons()
	var story_before := _story_shown
	_set_body_stretch(false)
	_clear_body()
	if origin_picker_open:
		_render_origin_picker()
		_animate_body()
		return
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
	if skill_open:
		_render_skill_tree()
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
		GameState.Screen.GALAXY_MAP:
			_render_galaxy()
		GameState.Screen.DIALOGUE:
			_render_dialogue()
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
		or GameState.is_exploring()
		or GameState.current_screen == GameState.Screen.MAIN_MENU
		or GameState.current_screen == GameState.Screen.COMBAT
		or GameState.current_screen == GameState.Screen.VICTORY
		or GameState.current_screen == GameState.Screen.DEATH
		or GameState.current_screen == GameState.Screen.DIALOGUE
	)
	map_button.disabled = blocked
	galaxy_button.disabled = blocked or not _galaxy_available()
	galaxy_button.visible = GalaxySystem.has_ship()
	character_button.disabled = blocked
	skill_button.disabled = blocked
	journal_button.disabled = blocked
	settings_button.disabled = GameState.current_screen == GameState.Screen.COMBAT or MapSystem.is_travelling() or GameState.is_exploring()
	_set_nav_label(map_button, "🗺️", "Карта", false)
	_set_nav_label(galaxy_button, "🌌", "Космос", false)
	_set_nav_label(character_button, "🧑‍🚀", "Персонаж", NotificationSystem.has_character_alert())
	_set_nav_label(skill_button, "🌐", "Развитие", NotificationSystem.has_development_alert())
	_set_nav_label(journal_button, "📓", "Журнал", NotificationSystem.has_journal_alert())
	_set_nav_label(settings_button, "⚙️", "Настройки", false)
	var map_active := not journal_open and not character_open and not skill_open and not settings_open and (
		map_open or GameState.current_screen == GameState.Screen.SECTOR_MAP
	)
	_style_nav_button(map_button, map_active)
	_style_nav_button(galaxy_button, GameState.current_screen == GameState.Screen.GALAXY_MAP)
	_style_nav_button(character_button, character_open)
	_style_nav_button(skill_button, skill_open)
	_style_nav_button(journal_button, journal_open)
	_style_nav_button(settings_button, settings_open)


## Значок сверху, подпись снизу: так «(!)» не обрезает название на узком экране.
func _set_nav_label(btn: Button, icon: String, title: String, alert: bool) -> void:
	btn.text = "%s%s\n%s" % [icon, " (!)" if alert else "", title]


func _clear_body() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	for child in pinned_header.get_children():
		pinned_header.remove_child(child)
		child.queue_free()
	pinned_header.visible = false


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
	if SkillTreeSystem.get_origins().is_empty():
		GameState.start_new_game()
		return
	origin_index = 0
	origin_picker_open = true
	_scroll_to_top()
	_render_current_screen()


## Создание героя: одна анкета на страницу. Сюжетные крючки здесь скрыты —
## герой вспомнит профессию, но не узнает события, случившиеся во время анабиоза.
func _render_origin_picker() -> void:
	_set_body_stretch(false)
	var origins := SkillTreeSystem.get_origins()
	if origins.is_empty():
		GameState.start_new_game()
		return
	origin_index = clampi(origin_index, 0, origins.size() - 1)
	var origin: Dictionary = origins[origin_index]
	var origin_id := str(origin.get("id", ""))
	_add_title("Личное дело пассажира")
	_add_section("Профессия задаёт старт в развитии и не меняется после пробуждения.")
	var card := UiKit.card(body)
	card.add_child(UiKit.section("АНКЕТА %02d / %02d" % [origin_index + 1, origins.size()]))
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	card.add_child(header)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 6)
	header.add_child(identity)
	identity.add_child(UiKit.text(str(origin.get("name", origin_id)), 30, UiKit.TITLE_COLOR))
	identity.add_child(UiKit.text("Статус: пассажир колониального рейса", 19, UiKit.MUTED_COLOR))
	var portrait := UiKit.portrait("player", false, 148)
	if portrait != null:
		portrait.name = "OriginPortrait"
		header.add_child(portrait)
	_add_origin_field(card, "НАЗНАЧЕНИЕ", str(origin.get("why", "")), UiKit.TEXT_COLOR)
	_add_origin_field(card, "ПРОФИЛЬ ПОДГОТОВКИ", str(origin.get("sectors_text", "")), UiKit.ACCENT_COLOR)
	_add_origin_field(card, "СИЛЬНАЯ СТОРОНА", str(origin.get("buff", "")), UiKit.GOOD_COLOR)
	_add_origin_field(card, "ОГРАНИЧЕНИЕ", str(origin.get("debuff", "")), UiKit.BAD_COLOR)
	var choose := UiKit.button("🧬 Выбрать эту профессию", "default", 66)
	choose.alignment = HORIZONTAL_ALIGNMENT_CENTER
	choose.pressed.connect(_choose_origin.bind(origin_id))
	card.add_child(choose)

	var nav := HBoxContainer.new()
	nav.name = "OriginPager"
	nav.add_theme_constant_override("separation", 10)
	var previous := UiKit.button("← Предыдущая", "quiet", 58)
	previous.disabled = origin_index == 0
	previous.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	previous.alignment = HORIZONTAL_ALIGNMENT_CENTER
	previous.pressed.connect(_change_origin.bind(-1))
	nav.add_child(previous)
	var next := UiKit.button("Следующая →", "quiet", 58)
	next.disabled = origin_index >= origins.size() - 1
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next.alignment = HORIZONTAL_ALIGNMENT_CENTER
	next.pressed.connect(_change_origin.bind(1))
	nav.add_child(next)
	body.add_child(nav)
	var dots := UiKit.text(_origin_dots(origins.size()), 19, UiKit.ACCENT_COLOR)
	dots.name = "OriginPageDots"
	dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(dots)
	var back := UiKit.button("← В меню", "quiet", 62)
	back.alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.pressed.connect(_close_origin_picker)
	body.add_child(back)


func _add_origin_field(card: VBoxContainer, title: String, value: String, color: Color) -> void:
	if value == "":
		return
	card.add_child(UiKit.section(title))
	card.add_child(UiKit.text(value, 20, color))


func _origin_dots(total: int) -> String:
	var dots := PackedStringArray()
	for i in range(total):
		dots.append("●" if i == origin_index else "○")
	return " ".join(dots)


func _change_origin(delta: int) -> void:
	origin_index = clampi(origin_index + delta, 0, SkillTreeSystem.get_origins().size() - 1)
	_scroll_to_top()
	_render_current_screen()


func _choose_origin(origin_id: String) -> void:
	origin_picker_open = false
	GameState.start_new_game("", "", origin_id)
	_render_current_screen()


func _close_origin_picker() -> void:
	origin_picker_open = false
	_scroll_to_top()
	_render_current_screen()


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
	if _pending_map_focus_node != "":
		var focus_node := _pending_map_focus_node
		_pending_map_focus_node = ""
		_map_view.highlight_node(focus_node, 5.0)
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
		_route_panel.add_child(UiKit.text("Маршрут недоступен, пока не закончено событие. Вернуться — кнопкой «Карта».", 20, UiKit.MUTED_COLOR))
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
	elif o2 - cost <= ResourceSystem.low_o2():
		warnings.append("Внимание! Мало кислорода!")
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


## Разговор: оверлей поверх экрана модуля. Состояние читает сам DialogueView,
## Game только ставит его и убирает, когда система сообщает о конце разговора.
func _render_dialogue() -> void:
	_set_body_stretch(false)
	if _dialogue_view != null:
		return
	_dialogue_view = DIALOGUE_VIEW_SCRIPT.new()
	_dialogue_view.closed.connect(_on_dialogue_closed)
	add_child(_dialogue_view)
	_fill_parent(_dialogue_view)


func _on_dialogue_closed() -> void:
	_drop_dialogue_view()


func _drop_dialogue_view() -> void:
	var view := _dialogue_view
	_dialogue_view = null
	if view != null and is_instance_valid(view):
		view.queue_free()


## Глобальная карта системы: нарисованная карта на всю высоту и панель под ней.
## Выбор точки показывает, что это, сколько часов и топлива займёт перелёт.
func _render_galaxy() -> void:
	_set_body_stretch(true)
	_add_title("🌌 " + GalaxySystem.get_title())
	_galaxy_view = GALAXY_MAP_VIEW_SCRIPT.new()
	_galaxy_view.name = "GalaxyMapView"
	body.add_child(_galaxy_view)
	_galaxy_view.node_selected.connect(_on_galaxy_node_selected)
	_galaxy_panel = VBoxContainer.new()
	_galaxy_panel.name = "GalaxyPanel"
	_galaxy_panel.add_theme_constant_override("separation", 8)
	body.add_child(_galaxy_panel)
	_galaxy_view.setup({
		"nodes": GalaxySystem.get_nodes(),
		"current_id": GalaxySystem.current_node_id,
		"hex_size": GalaxySystem.hex_size,
		"selected_id": _galaxy_selected,
	})
	_refresh_galaxy_panel()


func _on_galaxy_node_selected(node_id: String) -> void:
	_galaxy_selected = node_id
	_refresh_galaxy_panel()


## Запас топлива виден всегда: панель — единственное место, где он есть.
func _refresh_galaxy_panel() -> void:
	if _galaxy_panel == null or not is_instance_valid(_galaxy_panel):
		return
	for child in _galaxy_panel.get_children():
		_galaxy_panel.remove_child(child)
		child.queue_free()
	var here := GalaxySystem.get_node_data(GalaxySystem.current_node_id)
	_galaxy_panel.add_child(UiKit.text("⛽ Топливо: %d/%d · корабль у «%s»" % [
		roundi(GalaxySystem.fuel), roundi(GalaxySystem.max_fuel), str(here.get("title", "—"))],
		21, UiKit.ACCENT_COLOR))
	if _galaxy_selected == "":
		return
	var node := GalaxySystem.get_node_data(_galaxy_selected)
	if node.is_empty():
		return
	var card := UiKit.card(_galaxy_panel)
	card.add_child(UiKit.text(str(node.get("title", _galaxy_selected)), 26, UiKit.TITLE_COLOR))
	var note := str(node.get("note", ""))
	if note != "":
		card.add_child(UiKit.text(note, 20, UiKit.MUTED_COLOR))
	var description := str(node.get("description", ""))
	if description != "":
		card.add_child(UiKit.text(description, 21))
	var cost := float(node.get("fuel", 0.0))
	# Цену перелёта показываем только там, где есть посадка: у ориентира
	# («нет посадки») считать нечего, панель ограничивается причиной.
	if not bool(node.get("here", false)) and str(node.get("sector_id", "")) != "":
		card.add_child(UiKit.text("Перелёт: ≈ %d ч · %d топлива · в баке останется %d" % [
			int(node.get("hours", 0)), roundi(cost), maxi(0, roundi(GalaxySystem.fuel - cost))],
			21, UiKit.ACCENT_COLOR))
	var plan := GalaxySystem.plan_travel(_galaxy_selected)
	if not bool(plan["ok"]):
		var message := str(plan["message"])
		if message != "":
			card.add_child(UiKit.text(message, 20, UiKit.BAD_COLOR))
		var blocked := UiKit.button("🚀 Лететь", "quiet", BUTTON_HEIGHT)
		blocked.disabled = true
		blocked.alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(blocked)
		return
	var go := UiKit.button("🚀 Лететь", "default", BUTTON_HEIGHT)
	go.name = "GalaxyGo"
	go.alignment = HORIZONTAL_ALIGNMENT_CENTER
	go.pressed.connect(_start_galaxy_travel.bind(_galaxy_selected))
	card.add_child(go)


## Перелёт: топливо и часы списывает GalaxySystem, сектор грузит GameState.
func _start_galaxy_travel(node_id: String) -> void:
	if not GalaxySystem.travel_to(node_id):
		_refresh_galaxy_panel()
		return
	_galaxy_selected = ""


## Подпись узла как на карте: явно открытый сюжетным действием отсек уже
## называется, даже если игрок пока не был внутри.
func _map_node_name(node_id: String) -> String:
	if not MapSystem.is_node_title_known(node_id):
		return "Неизвестно"
	var node: Dictionary = MapSystem.nodes.get(node_id, {})
	var cfg = node.get("map", {})
	if cfg is Dictionary and str(cfg.get("label", "")) != "":
		return str(cfg["label"])
	return str(node.get("title", node_id))


## Экран модуля и ситуация используют общий буфер, но при переходе старый
## контекст очищается: описание локации не остаётся под событием.
func _render_situation() -> void:
	var now := _now_seconds()
	var reveal_delay := _render_story()
	# Срок открытия кнопок считается от конца печати и не откатывается назад
	# перерисовками: допечатанные записи лишь отодвигают его вперёд.
	if _buttons_ready_at <= now:
		_buttons_ready_at = now + reveal_delay
	elif reveal_delay > 0.0:
		_buttons_ready_at = maxf(_buttons_ready_at, now + reveal_delay)
	var buttons: Array[Button] = []
	if SituationEngine.awaiting_continue:
		buttons.append(_add_button("▶️ Продолжить", _continue_situation, "exit"))
		_gate_story_buttons(buttons, _buttons_ready_at - now)
		return
	var options := SituationEngine.get_available_options()
	if options.is_empty():
		# Некуда выбирать — единственная кнопка закрывает ситуацию.
		buttons.append(_add_button("▶️ Продолжить", _continue_situation, "exit"))
		_gate_story_buttons(buttons, _buttons_ready_at - now)
		return
	for opt in options:
		var opt_id: String = opt.get("id", "")
		# Завершающие варианты (выход на карту, конец события, финал) выделены цветом.
		var kind := "exit" if SituationEngine.is_closing_option(opt) else "default"
		buttons.append(_add_button(str(opt.get("label", opt_id)), _make_option_callback(opt_id), kind))
	_gate_story_buttons(buttons, _buttons_ready_at - now)


func _now_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


## Кнопки ситуации появляются, только когда весь её текст допечатан, и всплывают
## по одной: решение не принимается вслепую и выбор читается как список.
func _gate_story_buttons(buttons: Array[Button], delay: float) -> void:
	if buttons.is_empty() or not SettingsSystem.animations:
		return
	for btn in buttons:
		btn.disabled = true
		btn.modulate.a = 0.45
	var cursor := maxf(delay, BUTTON_REVEAL_DELAY)
	for btn in buttons:
		var tween := btn.create_tween()
		tween.tween_interval(cursor)
		tween.tween_callback(_reveal_story_button.bind(btn))
		cursor += BUTTON_REVEAL_STEP


## Одна кнопка проявляется из чуть уменьшенного состояния; включается, когда
## анимация закончилась, — до этого нажатие невозможно.
func _reveal_story_button(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	btn.pivot_offset = btn.size * 0.5
	btn.scale = Vector2(0.94, 0.94)
	var tween := btn.create_tween().set_parallel(true)
	tween.tween_property(btn, "modulate:a", 1.0, BUTTON_REVEAL_TIME).set_trans(Tween.TRANS_SINE)
	tween.tween_property(btn, "scale", Vector2.ONE, BUTTON_REVEAL_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(btn):
			btn.disabled = false)


func _continue_situation() -> void:
	GameState.finish_situation()


## Текущий контекст: новые записи печатаются по очереди и подматываются вниз.
## Возвращает время, через которое допечатаются все новые записи (0 — печатать
## нечего): по нему кнопки ситуации ждут текст, а плашка новой локации — ленту.
func _render_story() -> float:
	var entries := NarrativeSystem.get_entries()
	var fresh_from := _story_shown if _story_shown <= entries.size() else 0
	var reveal_at := 0.0
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		if str(entry.get("kind", "")) == "backdrop" and _story_has_other_image(entries):
			continue
		var nodes := _story_nodes(entry)
		for node in nodes:
			body.add_child(node)
		if i >= fresh_from:
			reveal_at = _reveal_story_entry(entry, nodes, reveal_at)
	_story_shown = entries.size()
	_scroll_to_bottom()
	_queue_pending_map_reveal(reveal_at)
	return reveal_at


## Есть ли в ленте картинка событий или ситуации: она важнее картинки отсека.
func _story_has_other_image(entries: Array) -> bool:
	for entry in entries:
		if str(entry.get("kind", "")) != "backdrop" and str(entry.get("image", "")) != "":
			return true
	return false


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
			nodes.append(UiKit.codex_text(text, 32, UiKit.TITLE_COLOR))
		"choice":
			nodes.append(UiKit.codex_text("— " + text, 24, UiKit.EXIT_COLOR))
		"result":
			nodes.append(UiKit.codex_text(text, 24, UiKit.TEXT_COLOR))
		"notice":
			nodes.append(UiKit.codex_text(text, 22, UiKit.ACCENT_COLOR))
		"goal":
			nodes.append(UiKit.codex_text(text, 22, UiKit.GOAL_COLOR, true))
		"gain":
			nodes.append(UiKit.codex_text(text, 22, UiKit.GOOD_COLOR))
		"loss":
			nodes.append(UiKit.codex_text(text, 22, UiKit.BAD_COLOR))
		"system":
			nodes.append(UiKit.codex_text(text, 22, UiKit.MUTED_COLOR))
		_:
			nodes.append(UiKit.codex_text(text, 24, UiKit.TEXT_COLOR))
	return nodes


func _make_option_callback(opt_id: String) -> Callable:
	return func(): SituationEngine.select_option(opt_id)


func _render_location() -> void:
	_render_story()
	if GameState.is_exploring():
		return

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
			var item_card := UiKit.card(body)
			item_card.add_child(UiKit.text("%s%s" % [_item_name(item_id), _count_suffix(int(stash[item_id]))], 24, UiKit.TITLE_COLOR))
			var item_data := InventorySystem.get_item_data(item_id)
			var use_text := str(item_data.get("use_text", item_data.get("description", "")))
			if use_text != "":
				item_card.add_child(UiKit.text(use_text, 20, UiKit.MUTED_COLOR))
			var actions := HBoxContainer.new()
			actions.add_theme_constant_override("separation", 10)
			var use_btn := UiKit.button("Применить", "default", 54)
			use_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			use_btn.disabled = not LocationSystem.stash_can_use(item_id)
			use_btn.pressed.connect(_make_stash_use_callback(item_id))
			actions.add_child(use_btn)
			var take_btn := UiKit.button("Подобрать", "quiet", 54)
			take_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			take_btn.pressed.connect(_make_stash_take_callback(item_id))
			actions.add_child(take_btn)
			item_card.add_child(actions)


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
	var quality := LocationSystem.get_sleep_quality()
	_add_section("База · качество сна: %s" % NeedsSystem.sleep_quality_title(quality).to_lower())
	for hours in [4, 8, 12]:
		_add_button("🛏️ Спать %d ч." % hours, GameState.sleep.bind(hours), "quiet")
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


func _make_stash_use_callback(item_id: String) -> Callable:
	return func():
		if LocationSystem.stash_use(item_id):
			LocationSystem.add_notice("Применено: %s." % _item_name(item_id))
		else:
			LocationSystem.add_notice("«%s» нельзя применить на месте." % _item_name(item_id))
		GameState.refresh_location()


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


const CHARACTER_TABS := [
	["items", "🎒 Предметы"], ["equipment", "🛡️ Снаряжение"],
]
const CHARACTER_ITEM_TABS := [
	["bag", "Сумка"], ["info", "Записи и ключи"],
]
const DEVELOPMENT_TABS := [
	["tree", "🌐 Дерево"], ["skills", "⭐ Навыки"],
]


func _render_character() -> void:
	pinned_header.visible = true
	pinned_header.add_child(UiKit.title("Персонаж"))
	var tabs := HBoxContainer.new()
	tabs.name = "CharacterTabs"
	tabs.add_theme_constant_override("separation", 8)
	for entry in CHARACTER_TABS:
		var tab_id := str(entry[0])
		var label := str(entry[1])
		if tab_id == "items" and NotificationSystem.has_new_items():
			label += " (!)"
		var btn := UiKit.button(label, "tab_active" if tab_id == character_tab else "quiet", 56)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", UiKit.fs(18))
		btn.pressed.connect(_on_character_tab_changed.bind(tab_id))
		tabs.add_child(btn)
	pinned_header.add_child(tabs)
	if character_tab == "items":
		var item_tabs := HBoxContainer.new()
		item_tabs.name = "CharacterItemTabs"
		item_tabs.add_theme_constant_override("separation", 8)
		for entry in CHARACTER_ITEM_TABS:
			var tab_id := str(entry[0])
			var label := str(entry[1])
			if (tab_id == "bag" and NotificationSystem.has_new_items_in_bag()) \
					or (tab_id == "info" and NotificationSystem.has_new_items_in_info()):
				label += " (!)"
			var btn := UiKit.button(label, "tab_active" if tab_id == character_items_tab else "quiet", 48)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.add_theme_font_size_override("font_size", UiKit.fs(17))
			btn.pressed.connect(_on_character_item_tab_changed.bind(tab_id))
			item_tabs.add_child(btn)
		pinned_header.add_child(item_tabs)
	var panel: VBoxContainer = CHARACTER_PANEL_SCRIPT.new()
	panel.tab = character_tab
	panel.item_tab = character_items_tab
	body.add_child(panel)


## Общее развитие: кольцевое дерево и базовые навыки делят один оверлей.
func _render_skill_tree() -> void:
	pinned_header.visible = true
	pinned_header.add_child(UiKit.title("Развитие"))
	var tabs := HBoxContainer.new()
	tabs.name = "DevelopmentTabs"
	tabs.add_theme_constant_override("separation", 8)
	for entry in DEVELOPMENT_TABS:
		var tab_id := str(entry[0])
		var label := str(entry[1])
		if tab_id == "skills" and CharacterSystem.skill_points > 0:
			label += " (+%d)" % CharacterSystem.skill_points
		var btn := UiKit.button(label, "tab_active" if tab_id == skill_tab else "quiet", 56)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", UiKit.fs(18))
		btn.pressed.connect(_on_development_tab_changed.bind(tab_id))
		tabs.add_child(btn)
	pinned_header.add_child(tabs)
	if skill_tab == "skills":
		var skills_panel: VBoxContainer = CHARACTER_PANEL_SCRIPT.new()
		skills_panel.name = "DevelopmentSkills"
		skills_panel.tab = "skills"
		body.add_child(skills_panel)
	else:
		var tree_panel: VBoxContainer = SKILL_TREE_PANEL_SCRIPT.new()
		tree_panel.name = "SkillTreePanel"
		body.add_child(tree_panel)


func _render_workbench() -> void:
	var panel: VBoxContainer = WORKBENCH_PANEL_SCRIPT.new()
	panel.closed.connect(_close_workbench)
	body.add_child(panel)


func _on_character_tab_changed(new_tab: String) -> void:
	character_tab = new_tab
	if character_tab == "items":
		NotificationSystem.mark_character_items_seen(character_items_tab)
	_scroll_to_top()
	_render_current_screen()


func _on_character_item_tab_changed(new_tab: String) -> void:
	character_items_tab = new_tab
	NotificationSystem.mark_character_items_seen(character_items_tab)
	_scroll_to_top()
	_render_current_screen()

func _on_development_tab_changed(new_tab: String) -> void:
	skill_tab = new_tab
	_scroll_to_top()
	_render_current_screen()


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


## Журнал — четыре вкладки: цели, хроника забега, найденные документы и
## справочник мира с подвкладками. Закрывает журнал кнопка HUD.
const JOURNAL_TABS := [
	["goals", "🎯 Цели"], ["log", "📜 Хроника"], ["lore", "🗄️ Архив"], ["codex", "📚 Справочник"],
]
const CODEX_TABS := [
	["places", "Места"], ["people", "Люди"], ["ships", "Корабли"], ["terms", "Термины"],
]
const JOURNAL_COLORS := {
	"move": UiKit.ACCENT_COLOR,
	"combat": UiKit.BAD_COLOR,
	"death": UiKit.BAD_COLOR,
	"victory": UiKit.EXIT_COLOR,
	"lore": UiKit.TITLE_COLOR,
	"choice": UiKit.TITLE_COLOR,
	"loot": UiKit.MUTED_COLOR,
	"rest": UiKit.GOOD_COLOR,
	"goal": UiKit.GOAL_COLOR,
	"talk": UiKit.CODEX_COLOR,
}


func _render_journal() -> void:
	pinned_header.visible = true
	pinned_header.add_child(UiKit.title("Журнал"))
	var tabs := HBoxContainer.new()
	tabs.name = "JournalTabs"
	tabs.add_theme_constant_override("separation", 8)
	for entry in JOURNAL_TABS:
		var tab_id := str(entry[0])
		var label := str(entry[1])
		if (
			(tab_id == "lore" and NotificationSystem.has_new_lore())
			or (tab_id == "codex" and NotificationSystem.has_new_codex())
			or (tab_id == "goals" and NotificationSystem.has_new_goals())
		):
			label += " (!)"
		var btn := UiKit.button(label, "tab_active" if tab_id == journal_tab else "quiet", 58)
		btn.name = "JournalTab_%s" % tab_id
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_font_size_override("font_size", UiKit.fs(20))
		btn.pressed.connect(_select_journal_tab.bind(tab_id))
		tabs.add_child(btn)
	pinned_header.add_child(tabs)

	match journal_tab:
		"codex":
			_render_journal_codex()
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
		thoughts_card.add_child(UiKit.codex_text(thoughts, 22))
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
	_mark_active_journal_seen()
	_scroll_to_top()
	_render_current_screen()


## Хроника забега: свежие записи сверху, у каждой — остаток кислорода.
func _render_journal_log() -> void:
	var entries := JournalSystem.get_entries()
	if entries.is_empty():
		_add_text("Пока ничего не произошло.")
		return
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	var recent_btn := UiKit.button("Выгрузить последние 100 в лог", "quiet", 52)
	recent_btn.pressed.connect(JournalSystem.export_recent_to_log.bind(100))
	actions.add_child(recent_btn)
	var all_btn := UiKit.button("Выгрузить всё в лог", "quiet", 52)
	all_btn.pressed.connect(JournalSystem.export_all_to_log)
	actions.add_child(all_btn)
	body.add_child(actions)
	_add_section("Записей: %d" % entries.size())
	for i in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[i]
		var count := int(entry.get("count", 1))
		var line := "O2 %d · %s%s" % [int(entry.get("o2", 0)), str(entry.get("text", "")), _count_suffix(count)]
		var kind := str(entry.get("kind", ""))
		var color: Color = JOURNAL_COLORS.get(kind, UiKit.TEXT_COLOR)
		if kind == "goal":
			var goal_line := UiKit.codex_text(line, 22, color, true)
			goal_line.size.x = _body_width()
			body.add_child(goal_line)
		else:
			var lbl := _add_text(line)
			lbl.add_theme_font_size_override("font_size", UiKit.fs(22))
			lbl.add_theme_color_override("font_color", color)


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
		card.add_child(UiKit.codex_text(ArchiveSystem.get_text(str(id)), 22))

## Справочник: четыре категории знаний, открывающиеся при первом упоминании
## в повествовании. Заголовок записи окрашен тем же цветом, что понятие в ленте.
func _render_journal_codex() -> void:
	var tabs := HBoxContainer.new()
	tabs.name = "CodexTabs"
	tabs.add_theme_constant_override("separation", 8)
	for entry in CODEX_TABS:
		var category := str(entry[0])
		var label := str(entry[1])
		if NotificationSystem.has_new_codex_category(category):
			label += " (!)"
		var btn := UiKit.button(label, "tab_active" if category == codex_tab else "quiet", 52)
		btn.name = "CodexTab_%s" % category
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", UiKit.fs(18))
		btn.pressed.connect(_select_codex_tab.bind(category))
		tabs.add_child(btn)
	pinned_header.add_child(tabs)
	var ids := CodexSystem.get_unlocked(codex_tab)
	if ids.is_empty():
		_add_text("В этой категории пока нет записей.")
		return
	_add_section("%s · записей: %d" % [CodexSystem.get_category_title(codex_tab), ids.size()])
	for id in ids:
		var card := UiKit.card(body)
		card.add_child(UiKit.text(CodexSystem.get_title(str(id)), 26, UiKit.CODEX_COLOR))
		card.add_child(UiKit.codex_text(CodexSystem.get_text(str(id)), 22))


func _select_codex_tab(category: String) -> void:
	codex_tab = category
	NotificationSystem.mark_codex_seen(codex_tab)
	_scroll_to_top()
	_render_current_screen()



## Настройки интерфейса: размер шрифта, скорость текста и громкость —
## ползунки, плавные переходы и звук — переключатели. В игре настройки
## закрывает кнопка HUD; в главном меню HUD нет, поэтому там внизу «В меню».
func _render_settings() -> void:
	_add_title("Настройки")
	var font_caption := UiKit.section("")
	body.add_child(font_caption)
	var font_slider := UiKit.slider(SettingsSystem.FONT_SCALE_MIN, SettingsSystem.FONT_SCALE_MAX, 0.05,
		SettingsSystem.font_scale())
	font_slider.name = "FontScaleSlider"
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
	var speed_caption := UiKit.section("")
	body.add_child(speed_caption)
	var speed_slider := UiKit.slider(SettingsSystem.TEXT_SPEED_MIN, SettingsSystem.TEXT_SPEED_MAX,
		SettingsSystem.TEXT_SPEED_STEP, SettingsSystem.text_speed_cps)
	speed_slider.name = "TextSpeedSlider"
	speed_slider.editable = SettingsSystem.animations
	body.add_child(speed_slider)
	_bind_settings_slider(speed_slider, speed_caption,
		func(value: float) -> String: return "Скорость текста: %d зн./с%s" % [
			roundi(value), "" if SettingsSystem.animations else " · анимации выключены"],
		func(value: float) -> void: SettingsSystem.set_text_speed(roundi(value)))
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
