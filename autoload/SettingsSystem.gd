extends Node
## Настройки интерфейса: размер шрифта, плавные переходы и звук. Живут вне
## забега (файл user://settings.json) и применяются сразу: UI перечитывает
## font_scale через UiKit.fs() и перерисовывается по сигналу changed,
## SoundSystem читает sound_enabled и sound_volume() при каждом звуке.
##
## Размер шрифта — множитель 1…2 (ползунок с якорями 1×, 1.5×, 2×: рядом с
## якорем значение к нему притягивается), громкость — 0…100.

signal changed()

const PATH := "user://settings.json"
const FONT_SCALE_MIN := 1.0
const FONT_SCALE_MAX := 2.0
const FONT_SCALE_ANCHORS := [1.0, 1.5, 2.0]
## Ближе этого к якорю — значение становится якорем.
const FONT_SCALE_SNAP := 0.08
const DEFAULT_FONT_SCALE := 1.5
const DEFAULT_SOUND_VOLUME := 65
## Сейвы настроек до ползунков хранили id пресетов.
const LEGACY_FONT_SIZES := {"small": 1.0, "medium": 1.5, "large": 2.0}
const LEGACY_SOUND_VOLUMES := {"low": 35, "medium": 65, "high": 100}

var font_scale_value: float = DEFAULT_FONT_SCALE
var animations: bool = true
var sound_enabled: bool = true
## Громкость, 0…100.
var sound_volume_percent: int = DEFAULT_SOUND_VOLUME


func _ready() -> void:
	load_settings()


func font_scale() -> float:
	return font_scale_value


## Притянуть значение ползунка к ближайшему якорю и ограничить диапазоном.
func snap_font_scale(value: float) -> float:
	value = clampf(value, FONT_SCALE_MIN, FONT_SCALE_MAX)
	for anchor in FONT_SCALE_ANCHORS:
		if absf(value - float(anchor)) <= FONT_SCALE_SNAP:
			return float(anchor)
	return snappedf(value, 0.05)


func set_font_scale(value: float) -> void:
	value = snap_font_scale(value)
	if is_equal_approx(value, font_scale_value):
		return
	font_scale_value = value
	save_settings()
	changed.emit()


func set_animations(enabled: bool) -> void:
	if enabled == animations:
		return
	animations = enabled
	save_settings()
	changed.emit()


## Громкость для AudioStreamPlayer, 0…1.
func sound_volume() -> float:
	return float(sound_volume_percent) / 100.0


func set_sound_enabled(enabled: bool) -> void:
	if enabled == sound_enabled:
		return
	sound_enabled = enabled
	save_settings()
	changed.emit()


func set_sound_volume(percent: int) -> void:
	percent = clampi(percent, 0, 100)
	if percent == sound_volume_percent:
		return
	sound_volume_percent = percent
	save_settings()
	changed.emit()


func save_settings() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SettingsSystem: не удалось сохранить настройки")
		return
	f.store_string(JSON.stringify({
		"font_scale": font_scale_value,
		"animations": animations,
		"sound": sound_enabled,
		"sound_volume": sound_volume_percent,
	}))


func load_settings() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (parsed is Dictionary):
		return
	if parsed.has("font_scale"):
		font_scale_value = snap_font_scale(float(parsed["font_scale"]))
	else:
		font_scale_value = float(LEGACY_FONT_SIZES.get(str(parsed.get("font_size", "")), DEFAULT_FONT_SCALE))
	animations = bool(parsed.get("animations", true))
	sound_enabled = bool(parsed.get("sound", true))
	var volume = parsed.get("sound_volume", DEFAULT_SOUND_VOLUME)
	if volume is String:
		sound_volume_percent = int(LEGACY_SOUND_VOLUMES.get(volume, DEFAULT_SOUND_VOLUME))
	else:
		sound_volume_percent = clampi(int(volume), 0, 100)
