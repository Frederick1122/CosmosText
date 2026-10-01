extends HBoxContainer
## Полоска уровня: «Ур. 2», тонкая полоса опыта и «35/75». Живёт в HUD и на
## экране победы. Читает ProgressionSystem, логики не содержит.
##
## animate_to() проигрывает набор опыта от показанного состояния: полоса
## дотекает до конца уровня, подпись уровня вспыхивает золотом, над полосой
## всплывает «Уровень N!», и полоса начинает новый уровень с нуля.
## float_gain() — всплывающее «+10 опыта». Без анимаций (SettingsSystem) —
## сразу итог.

const UiKit = preload("res://scenes/ui/UiKit.gd")

const FILL_TIME := 0.45
const LEVEL_PAUSE := 0.3
const FLOAT_RISE := 70.0
const FLOAT_TIME := 1.1
const FILL_COLOR := Color("#9fd3e6")
const LEVEL_COLOR := UiKit.EXIT_COLOR

## Размер подписей (до UiKit.fs) и толщина полосы, px.
var font_size: int = 18
var bar_height: int = 8
## Идёт анимация набора: sync() её не перебивает.
var animating: bool = false

var _level_label: Label
var _bar: ProgressBar
var _value_label: Label
var _level: int = 1
var _xp: int = 0
var _tween: Tween


func _init() -> void:
	name = "XpBar"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	_level_label = Label.new()
	_level_label.name = "XpLevel"
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_level_label)
	_bar = ProgressBar.new()
	_bar.name = "XpProgress"
	_bar.show_percentage = false
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.add_theme_stylebox_override("background", UiKit.box(Color("#10141b"), Color("#2e3a4c"), 1, 0))
	_bar.add_theme_stylebox_override("fill", UiKit.box(FILL_COLOR, FILL_COLOR, 0, 0))
	add_child(_bar)
	_value_label = Label.new()
	_value_label.name = "XpValue"
	_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_value_label)
	apply_fonts()


func apply_fonts() -> void:
	_level_label.add_theme_font_size_override("font_size", UiKit.fs(font_size))
	_level_label.add_theme_color_override("font_color", LEVEL_COLOR)
	_value_label.add_theme_font_size_override("font_size", UiKit.fs(font_size - 2))
	_value_label.add_theme_color_override("font_color", UiKit.MUTED_COLOR)
	# Ширина под «888/888»: пока цифры бегут, полоса не дёргается.
	var font := _value_label.get_theme_font("font")
	_value_label.custom_minimum_size.x = font.get_string_size("888/888", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.fs(font_size - 2)).x
	_bar.custom_minimum_size = Vector2(0, bar_height)


## Сразу показать состояние без анимации.
func show_state(level: int, xp: int) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	animating = false
	_level = level
	_xp = xp
	_set_shown(float(xp), level, ProgressionSystem.xp_to_next(level))


## Подтянуть к ProgressionSystem, если анимация не идёт.
func sync() -> void:
	if not animating:
		show_state(ProgressionSystem.level, ProgressionSystem.xp)


## Набор опыта от показанного состояния до (level, xp), через все взятые уровни.
func animate_to(level: int, xp: int, delay: float = 0.0) -> void:
	if not SettingsSystem.animations or not is_inside_tree():
		show_state(level, xp)
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	animating = true
	_tween = create_tween()
	if delay > 0.0:
		_tween.tween_interval(delay)
	var shown_level := _level
	var shown_xp := float(_xp)
	while shown_level < level:
		var need := ProgressionSystem.xp_to_next(shown_level)
		_tween.tween_method(_set_shown.bind(shown_level, need), shown_xp, float(need), FILL_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		shown_level += 1
		_tween.tween_callback(_level_up_fx.bind(shown_level))
		_tween.tween_interval(LEVEL_PAUSE)
		shown_xp = 0.0
	_tween.tween_method(_set_shown.bind(level, ProgressionSystem.xp_to_next(level)), shown_xp, float(xp), FILL_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_finish)
	_level = level
	_xp = xp


## «+10 опыта» всплывает над полосой и тает.
func float_gain(amount: int, delay: float = 0.0) -> void:
	_float_text("+%d опыта" % amount, UiKit.ACCENT_COLOR, font_size + 6, delay)


func _set_shown(value: float, level: int, need: int) -> void:
	_bar.max_value = maxi(1, need)
	_bar.value = clampf(value, 0.0, float(need))
	_level_label.text = "Ур. %d" % level
	_value_label.text = "%d/%d" % [roundi(value), need]


func _finish() -> void:
	animating = false
	sync()


## Новый уровень: подпись подпрыгивает, полоса вспыхивает, над ней — надпись.
func _level_up_fx(level: int) -> void:
	_set_shown(0.0, level, ProgressionSystem.xp_to_next(level))
	_level_label.pivot_offset = _level_label.size * 0.5
	var pop := create_tween()
	pop.tween_property(_level_label, "scale", Vector2(1.6, 1.6), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(_level_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_SINE)
	var flash := create_tween()
	_bar.modulate = Color(2.2, 1.9, 1.2)
	flash.tween_property(_bar, "modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_SINE)
	_float_text("⭐ Уровень %d!" % level, LEVEL_COLOR, font_size + 14, 0.0)


## Надпись над серединой полосы. top_level — контейнеры её не раскладывают;
## z_index — поверх затемнения экрана победы.
func _float_text(value: String, color: Color, size: int, delay: float) -> void:
	if not SettingsSystem.animations or not is_inside_tree():
		return
	var label := Label.new()
	label.text = value
	label.top_level = true
	label.z_index = 100
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", UiKit.fs(size))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("#0b0e14"))
	label.add_theme_constant_override("outline_size", UiKit.fs(8))
	label.modulate.a = 0.0
	add_child(label)
	var text_size := label.get_combined_minimum_size()
	var rect := _bar.get_global_rect()
	var start := Vector2(rect.get_center().x - text_size.x * 0.5, rect.position.y - text_size.y - 4.0)
	label.size = text_size
	label.global_position = start
	label.pivot_offset = text_size * 0.5
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(label, "modulate:a", 1.0, 0.08)
	tween.parallel().tween_property(label, "scale", Vector2(1.2, 1.2), 0.1).from(Vector2(0.6, 0.6))
	tween.tween_property(label, "scale", Vector2.ONE, 0.14)
	tween.parallel().tween_property(label, "global_position:y", start.y - FLOAT_RISE, FLOAT_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, FLOAT_TIME * 0.5).set_delay(FLOAT_TIME * 0.5)
	tween.tween_callback(label.queue_free)
