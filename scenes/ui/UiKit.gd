extends RefCounted
## Общие хелперы для UI, собираемого из кода (экран персонажа, кукла).
## Подключение: const UiKit = preload("res://scenes/ui/UiKit.gd").

const TEXT_COLOR := Color("#d7deee")
const MUTED_COLOR := Color("#8a96ab")
const TITLE_COLOR := Color("#f5f8ff")
const ACCENT_COLOR := Color("#9fd3e6")
const BAD_COLOR := Color("#f0b0b9")


static func text(value: String, font_size: int = 24, color: Color = TEXT_COLOR) -> Label:
	var lbl := Label.new()
	lbl.text = value
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl


static func title(value: String) -> Label:
	return text(value, 34, TITLE_COLOR)


static func section(value: String) -> Label:
	return text(value, 20, MUTED_COLOR)


## kind: "default" | "quiet" | "danger" | "tab_active"
static func button(value: String, kind: String = "default", height: int = 68) -> Button:
	var btn := Button.new()
	btn.text = value
	btn.custom_minimum_size = Vector2(0, height)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 23)
	match kind:
		"danger":
			style_button(btn, Color("#5b2530"), Color("#7e3443"), Color("#3b1c24"), Color("#b86d79"))
		"quiet":
			style_button(btn, Color("#202733"), Color("#323d4e"), Color("#171d27"), Color("#4d6275"))
		"tab_active":
			style_button(btn, Color("#22415c"), Color("#2a577b"), Color("#1a324a"), Color("#8abce0"))
		_:
			style_button(btn, Color("#173f55"), Color("#1f6989"), Color("#102c3d"), Color("#5d91a8"))
	return btn


static func style_button(btn: Button, normal: Color, hover: Color, pressed: Color, border: Color) -> void:
	btn.add_theme_color_override("font_color", Color("#f4f7fb"))
	btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
	btn.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	btn.add_theme_color_override("font_disabled_color", Color("#798294"))
	btn.add_theme_stylebox_override("normal", box(normal, border))
	btn.add_theme_stylebox_override("hover", box(hover, border.lightened(0.2)))
	btn.add_theme_stylebox_override("pressed", box(pressed, border.lightened(0.3)))
	btn.add_theme_stylebox_override("disabled", box(Color("#1a1f29"), Color("#2a3240")))
	btn.add_theme_stylebox_override("focus", box(hover, Color("#d6f2ff"), 2))


static func box(bg: Color, border: Color, border_width: int = 1, margin: int = 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.6
	sb.content_margin_bottom = margin * 0.6
	return sb


## Карточка-панель внутри parent; возвращает внутренний VBoxContainer.
static func card(parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", box(Color("#171d27"), Color("#2e3a4c"), 1, 18))
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	parent.add_child(panel)
	return vbox
