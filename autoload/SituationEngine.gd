extends Node
## Ситуации — см. tech-spec-v1.md раздел 2 и gdd-v1.md раздел 5.1.
## Не переключает экраны сама: применяет effects текущего выбора и сообщает
## GameState, что дальше (next) — см. ТЗ раздел 10, единственный владелец экранов.

signal situation_started(id: String)
signal option_selected(id: String)
## next: "" (сцена сама переключит экран, например start_combat),
##       "map:<sector_id>" (открыть карту сектора) или id следующей ситуации.
## completes_event: false у варианта-отказа оставляет событие доступным.
signal situation_ended(id: String, next: String, completes_event: bool)
## Вариант применён, показан его результат — UI рисует кнопку «Продолжить».
signal option_resolved(id: String)

var current_id: String = ""
var flags: Dictionary = {}
## Ситуация не обрывается на выборе: сначала показывается текст последствия и
## кнопка «Продолжить», и только потом игрок покидает сцену.
var awaiting_continue: bool = false

var _situations: Dictionary = {}  # id -> data
var _current_data: Dictionary = {}
var _pending_next: String = ""
var _pending_completes_event: bool = true


func _ready() -> void:
	_load_all_situations()


func _load_all_situations() -> void:
	_situations.clear()
	var dir := DirAccess.open("res://data/situations")
	if dir == null:
		push_warning("SituationEngine: res://data/situations не найден")
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var path := "res://data/situations/%s" % file_name
			var f := FileAccess.open(path, FileAccess.READ)
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary and parsed.has("id"):
				_situations[parsed["id"]] = parsed
			else:
				push_warning("SituationEngine: битый файл ситуации %s" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


func reset_for_new_run() -> void:
	flags.clear()
	current_id = ""
	_current_data = {}
	awaiting_continue = false
	_pending_next = ""
	_pending_completes_event = true


func set_flag(flag: String, value) -> void:
	if flag != "":
		flags[flag] = value


func get_flag(flag: String):
	return flags.get(flag, false)


func load_situation(id: String) -> bool:
	if not _situations.has(id):
		push_error("SituationEngine: неизвестная ситуация '%s'" % id)
		return false
	_current_data = _situations[id]
	current_id = id
	awaiting_continue = false
	_pending_next = ""
	_pending_completes_event = true
	NarrativeSystem.push("text", get_current_text(), get_current_image())
	situation_started.emit(id)
	return true


func get_current_text() -> String:
	return _current_data.get("text", "")


## Пиксельная иллюстрация ситуации (assets/art/scenes/<image>.png).
func get_current_image() -> String:
	return str(_current_data.get("image", ""))


func get_available_options() -> Array:
	var result: Array = []
	for opt in _current_data.get("options", []):
		if EffectResolver.check_requirements(opt.get("requires", [])):
			result.append(opt)
	return result


## Выбор стоит кислорода: если баллон кончился, вариант не применяется —
## экран смерти выставит GameState по EventBus.player_died.
##
## Порядок: реплика игрока в ленту → цена выбора «[−2 O2]» → текст
## последствия → эффекты (их изменения ресурсов и предметов — строками в
## квадратных скобках). Дальше ситуация ждёт «Продолжить» (confirm_continue),
## а не выкидывает игрока сразу.
func select_option(option_id: String) -> void:
	var chosen = _find_option(option_id)
	if chosen == null:
		push_error("SituationEngine: опция '%s' не найдена в '%s'" % [option_id, current_id])
		return
	if awaiting_continue:
		return  # ждём «Продолжить» по предыдущему выбору
	var cost := ResourceSystem.get_o2_cost("choice")
	if not ResourceSystem.spend_o2("choice"):
		return
	NarrativeSystem.push("choice", str(chosen.get("label", option_id)))
	EffectResolver.report_change(-cost, "O2")
	NarrativeSystem.push("result", str(chosen.get("result", "")))
	_pending_completes_event = bool(chosen.get("completes_event", true))
	EffectResolver.apply_effects(chosen.get("effects", []))
	option_selected.emit(option_id)
	if ResourceSystem.is_dead():
		return
	_pending_next = str(chosen.get("next", ""))
	if CombatSystem.state == CombatSystem.State.PLAYER_TURN:
		return  # бой уже начался: итог покажет экран боя
	awaiting_continue = true
	option_resolved.emit(option_id)


## Нажатие «Продолжить»: только теперь ситуация заканчивается.
func confirm_continue() -> void:
	var ended_id := current_id
	var next_id := _pending_next
	var completes_event := _pending_completes_event
	awaiting_continue = false
	_pending_next = ""
	_pending_completes_event = true
	situation_ended.emit(ended_id, next_id, completes_event)

func pending_choice_completes_event() -> bool:
	return _pending_completes_event


func get_option_label(option_id: String) -> String:
	var opt = _find_option(option_id)
	return str(opt.get("label", option_id)) if opt is Dictionary else option_id


## Завершает ли вариант происходящее: уводит на карту, заканчивает забег или
## закрывает событие возвратом в модуль. Вариант, начинающий бой или ведущий
## в следующую ситуацию, продолжением цепочки не считается завершающим.
func is_closing_option(opt: Dictionary) -> bool:
	for effect in opt.get("effects", []):
		if not (effect is Dictionary):
			continue
		match str(effect.get("type", "")):
			"end_run":
				return true
			"start_combat":
				return false
	var next_id := str(opt.get("next", ""))
	return next_id == "" or next_id.begins_with("map:")


func _find_option(option_id: String):
	for opt in _current_data.get("options", []):
		if opt.get("id", "") == option_id:
			return opt
	return null


func to_save_data() -> Dictionary:
	return {
		"flags": flags.duplicate(true),
		"current_id": current_id,
	}


func load_save_data(data: Dictionary) -> void:
	flags = data.get("flags", {}).duplicate(true)
	current_id = str(data.get("current_id", ""))
	_current_data = _situations.get(current_id, {}) if current_id != "" else {}
