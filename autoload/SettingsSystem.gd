extends Node
## Настройки интерфейса: размер шрифта, плавные переходы и звук. Живут вне
## забега (файл user://settings.json) и применяются сразу: UI перечитывает
## font_scale через UiKit.fs() и перерисовывается по сигналу changed,
## SoundSystem читает sound_enabled и sound_volume() при каждом звуке.

signal changed()

const PATH := "user://settings.json"
## id → [подпись, множитель размера шрифта]
const FONT_SIZES := {
	"small": ["Маленький", 1.0],
	"medium": ["Средний", 1.5],
	"large": ["Крупный", 2.0],
}
const DEFAULT_FONT_SIZE := "medium"
## id → [подпись, громкость 0..1]
const SOUND_VOLUMES := {
	"low": ["Тихо", 0.35],
	"medium": ["Средне", 0.65],
	"high": ["Громко", 1.0],
}
const DEFAULT_SOUND_VOLUME := "medium"

var font_size_id: String = DEFAULT_FONT_SIZE
var animations: bool = true
var sound_enabled: bool = true
var sound_volume_id: String = DEFAULT_SOUND_VOLUME


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


func sound_volume() -> float:
	var entry = SOUND_VOLUMES.get(sound_volume_id, SOUND_VOLUMES[DEFAULT_SOUND_VOLUME])
	return float(entry[1])


func sound_volume_title(id: String) -> String:
	return str(SOUND_VOLUMES.get(id, SOUND_VOLUMES[DEFAULT_SOUND_VOLUME])[0])


func set_sound_enabled(enabled: bool) -> void:
	if enabled == sound_enabled:
		return
	sound_enabled = enabled
	save_settings()
	changed.emit()


func set_sound_volume(id: String) -> void:
	if not SOUND_VOLUMES.has(id) or id == sound_volume_id:
		return
	sound_volume_id = id
	save_settings()
	changed.emit()


func save_settings() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SettingsSystem: не удалось сохранить настройки")
		return
	f.store_string(JSON.stringify({
		"font_size": font_size_id,
		"animations": animations,
		"sound": sound_enabled,
		"sound_volume": sound_volume_id,
	}))


func load_settings() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (parsed is Dictionary):
		return
	var id := str(parsed.get("font_size", DEFAULT_FONT_SIZE))
	font_size_id = id if FONT_SIZES.has(id) else DEFAULT_FONT_SIZE
	animations = bool(parsed.get("animations", true))
	sound_enabled = bool(parsed.get("sound", true))
	var volume_id := str(parsed.get("sound_volume", DEFAULT_SOUND_VOLUME))
	sound_volume_id = volume_id if SOUND_VOLUMES.has(volume_id) else DEFAULT_SOUND_VOLUME
