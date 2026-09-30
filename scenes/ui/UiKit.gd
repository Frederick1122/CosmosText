extends RefCounted
## Общие хелперы для UI, собираемого из кода (экран персонажа, кукла).
## Подключение: const UiKit = preload("res://scenes/ui/UiKit.gd").

const TEXT_COLOR := Color("#d7deee")
const MUTED_COLOR := Color("#8a96ab")
const TITLE_COLOR := Color("#f5f8ff")
const ACCENT_COLOR := Color("#9fd3e6")
const BAD_COLOR := Color("#f0b0b9")
## Цвет завершающих действий: выход из модуля, конец события, финал забега.
const EXIT_COLOR := Color("#e0b153")

const SCENE_ART_DIR := "res://assets/art/scenes/"
const ITEM_ART_DIR := "res://assets/art/items/"
const ENEMY_ART_DIR := "res://assets/art/enemies/"
const PORTRAIT_ART_DIR := "res://assets/art/portraits/"


## Размер шрифта с учётом настройки «Размер шрифта» (SettingsSystem).
## Все размеры в UI задаются через fs(), иначе настройка их не догонит.
static func fs(size: int) -> int:
	return maxi(8, int(round(float(size) * SettingsSystem.font_scale())))


static func text(value: String, font_size: int = 24, color: Color = TEXT_COLOR) -> Label:
	var lbl := Label.new()
	lbl.text = value
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", fs(font_size))
	lbl.add_theme_color_override("font_color", color)
	return lbl


static func title(value: String) -> Label:
	return text(value, 34, TITLE_COLOR)


static func section(value: String) -> Label:
	return text(value, 20, MUTED_COLOR)


## kind: "default" | "quiet" | "danger" | "exit" | "tab_active"
## "exit" — действие, которое уводит с локации или закрывает событие.
static func button(value: String, kind: String = "default", height: int = 68) -> Button:
	var btn := Button.new()
	btn.text = value
	btn.custom_minimum_size = Vector2(0, fs(height))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.add_theme_font_size_override("font_size", fs(23))
	match kind:
		"danger":
			style_button(btn, Color("#5b2530"), Color("#7e3443"), Color("#3b1c24"), Color("#b86d79"))
		"quiet":
			style_button(btn, Color("#202733"), Color("#323d4e"), Color("#171d27"), Color("#4d6275"))
		"exit":
			style_button(btn, Color("#4a3a16"), Color("#6b5420"), Color("#33280f"), EXIT_COLOR)
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


# --- Пиксельный арт -------------------------------------------------------------
# Картинки лежат в assets/art: сцены 160×96 (иллюстрация ситуации, события или
# модуля) и иконки предметов 16×16. Масштабирование — «ближайший сосед», иначе
# пиксель-арт мылится.

static func scene_texture(image_name: String) -> Texture2D:
	return _load_texture(SCENE_ART_DIR, image_name)


static func item_texture(item_id: String) -> Texture2D:
	return _load_texture(ITEM_ART_DIR, item_id)


## Иллюстрация сцены во всю ширину тела экрана. Высота считается по пропорции
## картинки от доступной ширины: вьюпорт у игры фиксированный (портрет
## 1080×1920), поэтому кадр 160×96 показывается целиком и без обрезки.
## Возвращает null, если картинки нет.
static func scene_art(image_name: String, available_width: float) -> TextureRect:
	var texture := scene_texture(image_name)
	if texture == null:
		return null
	var size := texture.get_size()
	if size.x <= 0.0:
		return null
	var rect := TextureRect.new()
	rect.name = "SceneArt"
	rect.texture = texture
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.custom_minimum_size = Vector2(0, roundf(available_width * size.y / size.x))
	rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return rect


## Иконка предмета; null, если для предмета арта нет.
static func item_icon(item_id: String, side: int = 48) -> TextureRect:
	var texture := item_texture(item_id)
	if texture == null:
		return null
	var rect := TextureRect.new()
	rect.name = "ItemIcon"
	rect.texture = texture
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(side, side)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Портрет для экрана боя: игрок (`portraits/`) или враг (`enemies/`).
static func portrait(name: String, is_enemy: bool, side: int = 96) -> TextureRect:
	var texture := _load_texture(ENEMY_ART_DIR if is_enemy else PORTRAIT_ART_DIR, name)
	if texture == null:
		return null
	var rect := TextureRect.new()
	rect.name = "Portrait"
	rect.texture = texture
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(side, side)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func _load_texture(dir: String, name: String) -> Texture2D:
	if name == "":
		return null
	var path := dir + name + ".png"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
