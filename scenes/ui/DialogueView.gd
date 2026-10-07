extends Control
## Экран разговора: затемнение поверх модуля, карточка с крупным аватаром
## собеседника, его репликой и вариантами ответа. Логики диалога не содержит:
## читает DialogueSystem.get_state() и передаёт выбор обратно в систему.
## Game добавляет оверлей поверх экрана модуля одним add_child() и убирает его
## по сигналу closed().
##
## Реплика печатается со скоростью SettingsSystem.text_speed_cps, кнопки ответа
## включаются только после допечатки: решение не принимается вслепую (как в ленте
## ситуаций). При выключенных анимациях текст появляется целиком сразу, а кнопки
## активны с первого кадра.
##
## Перерисовка по node_changed не теряет прокрутку, а сам разговор живёт в
## ScrollContainer: длинное меню тем и шесть и больше реплик не ломают раскладку.
## Аватар, имя и варианты — из UiKit: без файла портрета карточка просто
## обходится без картинки.

signal closed()

const UiKit = preload("res://scenes/ui/UiKit.gd")

## Затемнение перекрывает модуль и перехватывает касания.
const DIM_COLOR := Color(0.02, 0.03, 0.05, 0.78)
const SIDE_MARGIN := 36
const TOP_MARGIN := 72
const BOTTOM_MARGIN := 72
## Крупный аватар слева от реплики.
const PORTRAIT_SIDE := 200
const AVATAR_GAP := 18
const BUTTON_REVEAL_TIME := 0.14
const BUTTON_REVEAL_STEP := 0.05
## Пока реплика печатается, кнопки приглушены и не нажимаются.
const DISABLED_ALPHA := 0.45

var _scroll: ScrollContainer
var _content: VBoxContainer
var _text_label: Label
var _options_box: VBoxContainer
var _typing: Tween
var _closed: bool = false


func _init() -> void:
	name = "DialogueView"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	_build()
	DialogueSystem.node_changed.connect(_on_node_changed)
	DialogueSystem.dialogue_ended.connect(_on_dialogue_ended)
	_render()


# --- Построение оверлея ---------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM_COLOR
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE_MARGIN)
	margin.add_theme_constant_override("margin_right", SIDE_MARGIN)
	margin.add_theme_constant_override("margin_top", TOP_MARGIN)
	margin.add_theme_constant_override("margin_bottom", BOTTOM_MARGIN)
	add_child(margin)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	_scroll.add_child(_content)


# --- Перерисовка по состоянию DialogueSystem ------------------------------------

func _on_node_changed(_node: Dictionary) -> void:
	_render()


func _on_dialogue_ended(_npc_id: String, _dialogue_id: String) -> void:
	if _closed:
		return
	_closed = true
	_kill_typing()
	closed.emit()


## Полная перерисовка карточки: реплика собеседника и варианты ответа. Прокрутка
## сохраняется — при разговоре с длинным меню тем игрок не теряет место.
func _render() -> void:
	var state := DialogueSystem.get_state()
	var keep := _scroll.scroll_vertical
	_kill_typing()
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_text_label = null
	_options_box = null
	if state.is_empty():
		return
	var card := _build_card(state)
	_build_options(card, state)
	_scroll.scroll_vertical = keep
	_type_text(str(state.get("text", "")))


## Карточка: аватар слева, имя собеседника и текст реплики. Возвращает колонку,
## в которую встают варианты ответа.
func _build_card(state: Dictionary) -> VBoxContainer:
	var card := UiKit.card(_content)
	var row := HBoxContainer.new()
	row.name = "Speaker"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", AVATAR_GAP)
	card.add_child(row)

	var avatar := UiKit.portrait(str(state.get("portrait", "")), false, PORTRAIT_SIDE)
	if avatar != null:
		avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(avatar)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	row.add_child(column)

	var speaker := UiKit.text(str(state.get("npc_name", "")), 28, UiKit.ACCENT_COLOR)
	speaker.name = "SpeakerName"
	column.add_child(speaker)

	_text_label = UiKit.text("", 24, UiKit.TEXT_COLOR)
	_text_label.name = "Line"
	_text_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	column.add_child(_text_label)
	return card


## Варианты ответа на всю ширину и «Закончить разговор» последней кнопкой.
func _build_options(card: VBoxContainer, state: Dictionary) -> void:
	_options_box = VBoxContainer.new()
	_options_box.name = "Options"
	_options_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options_box.add_theme_constant_override("separation", 8)
	card.add_child(_options_box)
	for raw in _as_array(state.get("options", [])):
		var option := _as_dict(raw)
		var option_id := str(option.get("id", ""))
		if option_id == "":
			continue
		_add_option(str(option.get("label", option_id)), option_id, "default")
	_add_option(str(state.get("end_label", DialogueSystem.END_LABEL)), "", "quiet")


func _add_option(label: String, option_id: String, kind: String) -> void:
	var btn := UiKit.button(label, kind)
	btn.disabled = true
	btn.modulate.a = DISABLED_ALPHA
	btn.pressed.connect(_on_option_pressed.bind(option_id))
	_options_box.add_child(btn)


func _on_option_pressed(option_id: String) -> void:
	if option_id == "":
		DialogueSystem.end()
		return
	DialogueSystem.choose(option_id)


# --- Печать реплики и допуск кнопок ---------------------------------------------

## Реплика печатается знаком за знаком; кнопки открываются только по её концу.
func _type_text(text: String) -> void:
	if _text_label == null:
		_reveal_options()
		return
	_text_label.text = text
	if not SettingsSystem.animations or text == "":
		_text_label.visible_characters = -1
		_reveal_options()
		return
	_text_label.visible_characters = 0
	var duration := maxf(0.08, float(text.length()) / float(SettingsSystem.text_speed_cps))
	_typing = create_tween()
	_typing.tween_property(_text_label, "visible_characters", text.length(), duration) \
		.set_trans(Tween.TRANS_LINEAR)
	_typing.tween_callback(_reveal_options)


## Кнопки проявляются по одной и включаются, когда анимация закончилась: до этого
## нажатие невозможно.
func _reveal_options() -> void:
	if _text_label != null:
		_text_label.visible_characters = -1
	if _options_box == null:
		return
	var cursor := 0.0
	for child in _options_box.get_children():
		var btn := child as Button
		if btn == null:
			continue
		if not SettingsSystem.animations:
			btn.disabled = false
			btn.modulate.a = 1.0
			continue
		var tween := btn.create_tween()
		tween.tween_interval(cursor)
		tween.tween_property(btn, "modulate:a", 1.0, BUTTON_REVEAL_TIME).set_trans(Tween.TRANS_SINE)
		tween.tween_callback(_enable_option.bind(btn))
		cursor += BUTTON_REVEAL_STEP


func _enable_option(btn: Button) -> void:
	if is_instance_valid(btn):
		btn.disabled = false


func _kill_typing() -> void:
	if _typing != null and _typing.is_valid():
		_typing.kill()
	_typing = null


func _as_dict(value) -> Dictionary:
	return value if value is Dictionary else {}


func _as_array(value) -> Array:
	return value if value is Array else []
