extends Node
## HP / O2 / патроны — см. tech-spec-v1.md раздел 4.

signal hp_changed(value: int)
signal o2_changed(value: float)
signal ammo_changed(value: int)
signal resource_depleted(kind: String)  # kind: "hp" | "o2"

var hp: int = 100
var max_hp: int = 100
var o2_seconds: float = 0.0
var ammo: int = 0

var o2_ticking: bool = false
var _died_this_run: bool = false


func _process(delta: float) -> void:
	if o2_ticking and o2_seconds > 0.0 and not _died_this_run:
		o2_seconds = max(0.0, o2_seconds - delta)
		o2_changed.emit(o2_seconds)
		if o2_seconds <= 0.0:
			_trigger_death("o2")


func reset_for_new_run(config: Dictionary) -> void:
	max_hp = int(config.get("start_hp", 100))
	hp = max_hp
	o2_seconds = float(config.get("start_o2_seconds", 252.0))
	ammo = int(config.get("start_ammo", 0))
	o2_ticking = false
	_died_this_run = false
	hp_changed.emit(hp)
	o2_changed.emit(o2_seconds)
	ammo_changed.emit(ammo)


func apply_hp_delta(v: int) -> void:
	if _died_this_run:
		return
	hp = clampi(hp + v, 0, max_hp)
	hp_changed.emit(hp)
	if hp <= 0:
		_trigger_death("hp")


func apply_o2_delta(v: float) -> void:
	if _died_this_run:
		return
	o2_seconds = max(0.0, o2_seconds + v)
	o2_changed.emit(o2_seconds)
	if o2_seconds <= 0.0:
		_trigger_death("o2")


func apply_ammo_delta(v: int) -> void:
	ammo = max(0, ammo + v)
	ammo_changed.emit(ammo)


func set_o2_ticking(active: bool) -> void:
	o2_ticking = active


func is_dead() -> bool:
	return _died_this_run


func to_save_data() -> Dictionary:
	return {
		"hp": hp,
		"max_hp": max_hp,
		"o2_seconds": o2_seconds,
		"ammo": ammo,
	}


func load_save_data(data: Dictionary) -> void:
	max_hp = int(data.get("max_hp", max_hp))
	hp = clampi(int(data.get("hp", hp)), 0, max_hp)
	o2_seconds = max(0.0, float(data.get("o2_seconds", o2_seconds)))
	ammo = max(0, int(data.get("ammo", ammo)))
	o2_ticking = false
	_died_this_run = false
	hp_changed.emit(hp)
	o2_changed.emit(o2_seconds)
	ammo_changed.emit(ammo)


func _trigger_death(cause: String) -> void:
	if _died_this_run:
		return
	_died_this_run = true
	resource_depleted.emit(cause)
	EventBus.player_died.emit(cause)
