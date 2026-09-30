extends Node
## Настройки интерфейса: размер шрифта и плавные переходы. Живут вне забега
## (файл user://settings.json) и применяются сразу: UI перечитывает
## font_scale через UiKit.fs() и перерисовывается по сигналу changed.

signal changed()

const PATH := "user://settings.json"
## id → [подпись, множитель размера шрифта]
const FONT_SIZES := {
	"small": ["Маленький", 1.0],
	"medium": ["Средний", 1.2],
	"large": ["Крупный", 1.45],
}
const DEFAULT_FONT_SIZE := "medium"

var font_size_id: String = DEFAULT_FONT_SIZE
var animations: bool = true


func _ready() -> void:
	load_settings()


func font_scale() -> float:
	var entry = FONT_SIZES.get(font_size_id, FONT_SIZES[DEFAULT_FONT_SIZE])
	return float(entry[1])


func font_size_title(id: String = "") -> String:
	var entry = FONT_SIZES.get(id if id != "" else font_size_id, FONT_SIZES[DEFAULT_FONT_SIZE])
	return str(entry[0])


func set_font_size(id: String) -> void:
	if not FONT_SIZES.has(id) or id == font_size_id:
		return
	font_size_id = id
	save_settings()
	changed.emit()


func set_animations(enabled: bool) -> void:
	if enabled == animations:
		return
	animations = enabled
	save_settings()
	changed.emit()


func save_settings() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SettingsSystem: не удалось сохранить настройки")
		return
	f.store_string(JSON.stringify({"font_size": font_size_id, "animations": animations}))


func load_settings() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (parsed is Dictionary):
		return
	var id := str(parsed.get("font_size", DEFAULT_FONT_SIZE))
	font_size_id = id if FONT_SIZES.has(id) else DEFAULT_FONT_SIZE
	animations = bool(parsed.get("animations", true))
