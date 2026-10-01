extends Control
## Подпись в одну строку. Помещается — стоит по центру; не помещается —
## медленно ездит туда и обратно, как бегущая строка. При выключенных
## анимациях (SettingsSystem) длинная подпись обрезается многоточием.

const UiKit = preload("res://scenes/ui/UiKit.gd")
## Скорость прокрутки, px/с, и паузы на концах строки.
const SPEED := 38.0
const PAUSE := 1.1

var _label: Label
var _tween: Tween
## Ширина, под которую строка уже разложена: перезапуск только при её смене,
## иначе движение камеры карты дёргало бы бегущую строку каждый кадр.
var _laid_out_width := -1.0


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func setup(value: String, font_size: int, color: Color) -> void:
	_label.text = value
	_label.add_theme_font_size_override("font_size", UiKit.fs(font_size))
	_label.add_theme_color_override("font_color", color)
	_label.add_theme_color_override("font_outline_color", Color("#0b0e14"))
	_label.add_theme_constant_override("outline_size", UiKit.fs(6))
	_restart()


func get_text() -> String:
	return _label.text


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not is_equal_approx(size.x, _laid_out_width):
		_restart()


func _restart() -> void:
	_laid_out_width = size.x
	if _tween != null:
		_tween.kill()
		_tween = null
	_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_label.clip_text = false
	var text_width := _label.get_combined_minimum_size().x
	_label.size = Vector2(text_width, size.y)
	if text_width <= size.x + 1.0:
		_label.position = Vector2((size.x - text_width) * 0.5, 0.0)
		return
	if not SettingsSystem.animations:
		_label.clip_text = true
		_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_label.size = size
		_label.position = Vector2.ZERO
		return
	var overflow := text_width - size.x
	var travel := overflow / SPEED
	_label.position = Vector2.ZERO
	_tween = create_tween().set_loops()
	_tween.tween_interval(PAUSE)
	_tween.tween_property(_label, "position:x", -overflow, travel).set_trans(Tween.TRANS_SINE)
	_tween.tween_interval(PAUSE)
	_tween.tween_property(_label, "position:x", 0.0, travel).set_trans(Tween.TRANS_SINE)
