extends Control
## Схематичный персонаж со слотами снаряжения. Только отрисовка и выбор
## слота — надевание и снятие делает CharacterPanel через CharacterSystem.

signal slot_selected(slot: String)

const UiKit = preload("res://scenes/ui/UiKit.gd")

const FIGURE_HEIGHT := 560.0
const TOP_PADDING := 20.0
const BUTTON_SIZE := Vector2(250, 76)
## anchor — точка на фигуре (x от центра, y от макушки, в единицах фигуры),
## side — колонка кнопки слота, y — вертикаль кнопки в тех же единицах.
const LAYOUT := {
	"head": {"anchor": Vector2(0, 60), "side": "right", "y": 20},
	"back": {"anchor": Vector2(-90, 160), "side": "left", "y": 110},
	"body": {"anchor": Vector2(-30, 230), "side": "left", "y": 270},
	"arms": {"anchor": Vector2(116, 300), "side": "right", "y": 240},
	"legs": {"anchor": Vector2(34, 440), "side": "right", "y": 440},
}

const PART_EMPTY := Color("#1e2735")
const PART_EQUIPPED := Color("#2c5a74")
const PART_BORDER := Color("#3b4c61")
const LEADER_COLOR := Color(0.54, 0.74, 0.88, 0.6)

var _slots_info: Dictionary = {}  # slot -> { title, item_name }
var _selected: String = ""
var _buttons: Dictionary = {}


func _init() -> void:
	custom_minimum_size = Vector2(0, FIGURE_HEIGHT + TOP_PADDING * 2.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS


func setup(slots_info: Dictionary, selected: String) -> void:
	_slots_info = slots_info.duplicate(true)
	_selected = selected
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_buttons.clear()
	for slot in LAYOUT.keys():
		var info: Dictionary = _slots_info.get(slot, {})
		var item_name := str(info.get("item_name", ""))
		var kind := "tab_active" if slot == _selected else ("default" if item_name != "" else "quiet")
		var btn := UiKit.button("%s\n%s" % [str(info.get("title", slot)), item_name if item_name != "" else "пусто"], kind, int(BUTTON_SIZE.y))
		btn.name = "Slot_%s" % slot
		btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		btn.custom_minimum_size = BUTTON_SIZE
		btn.clip_text = true
		btn.add_theme_font_size_override("font_size", 19)
		btn.pressed.connect(_on_slot_pressed.bind(slot))
		add_child(btn)
		_buttons[slot] = btn
	call_deferred("_layout")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _on_slot_pressed(slot: String) -> void:
	slot_selected.emit(slot)


func _scale() -> float:
	if size.y <= 0.0:
		return 1.0
	return maxf(0.3, (size.y - TOP_PADDING * 2.0) / FIGURE_HEIGHT)


func _figure_point(p: Vector2) -> Vector2:
	return Vector2(size.x * 0.5, TOP_PADDING) + p * _scale()


func _layout() -> void:
	for slot in _buttons.keys():
		var btn: Button = _buttons[slot]
		var cfg: Dictionary = LAYOUT[slot]
		var x := 0.0 if cfg["side"] == "left" else size.x - BUTTON_SIZE.x
		btn.position = Vector2(x, TOP_PADDING + float(cfg["y"]) * _scale()).round()
		btn.size = BUTTON_SIZE
	queue_redraw()


func _draw() -> void:
	var s := _scale()
	_draw_part_rect("back", Rect2(-92, 128, 184, 150))
	_draw_part_rect("legs", Rect2(-62, 305, 54, 225))
	_draw_part_rect("legs", Rect2(8, 305, 54, 225))
	for side in [-1.0, 1.0]:
		var shoulder := _figure_point(Vector2(78 * side, 128))
		var hand := _figure_point(Vector2(116 * side, 296))
		draw_line(shoulder, hand, PART_BORDER, 32.0 * s, true)
		draw_line(shoulder, hand, _part_color("arms"), 26.0 * s, true)
		draw_circle(hand, 16.0 * s, _part_color("arms"))
	_draw_part_rect("body", Rect2(-72, 112, 144, 196))
	var head_center := _figure_point(Vector2(0, 60))
	draw_circle(head_center, 48.0 * s, PART_BORDER)
	draw_circle(head_center, 45.0 * s, _part_color("head"))

	for slot in _buttons.keys():
		var btn: Button = _buttons[slot]
		var from_x := btn.position.x + (BUTTON_SIZE.x if LAYOUT[slot]["side"] == "left" else 0.0)
		var from := Vector2(from_x, btn.position.y + BUTTON_SIZE.y * 0.5)
		var to := _figure_point(LAYOUT[slot]["anchor"])
		draw_line(from, to, LEADER_COLOR, 2.0, true)
		draw_circle(to, 6.0, LEADER_COLOR)


func _draw_part_rect(slot: String, r: Rect2) -> void:
	var rect := Rect2(_figure_point(r.position), r.size * _scale())
	draw_rect(rect, _part_color(slot), true)
	draw_rect(rect, PART_BORDER, false, 2.0)


func _part_color(slot: String) -> Color:
	var equipped := str(_slots_info.get(slot, {}).get("item_name", "")) != ""
	var color := PART_EQUIPPED if equipped else PART_EMPTY
	if slot == _selected:
		color = color.lightened(0.25)
	return color
