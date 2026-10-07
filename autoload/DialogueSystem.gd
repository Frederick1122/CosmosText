extends Node
## Диалоги: реплики собеседника, варианты ответа игрока, условия и эффекты из
## `data/dialogues/*.json` (схема — docs/CONTENT.md). Экран диалога рисует UI
## (`scenes/ui/DialogueView.gd`), переключает экраны GameState по сигналу
## `dialogue_started`, эффекты применяет EffectResolver — сам система ничего не
## решает и никого не зовёт, кроме них.
##
## Состояние забега: завершённые разговоры и уже использованные реплики
## (`done`, `used`). Незаконченный диалог в сейв не попадает: как бой и
## ситуация, он переигрывается — автосохранение бывает только на карте и в
## модуле, а там диалог уже закрыт.
##
## NPC: строка `npc` в файле диалога — id собеседника (портрет, подпись).

## Разговор начался: GameState переключает экран.
signal dialogue_started(npc_id: String, npc_name: String)
## Сменился узел (или начался разговор): UI перерисовывается по get_state().
signal node_changed(node: Dictionary)
## Разговор закончен (последняя реплика, конец ветки или отказ игрока).
signal dialogue_ended(npc_id: String, dialogue_id: String)
signal changed()

const DATA_DIR := "res://data/dialogues"
## Кнопка «выйти из разговора» есть на любом узле: игрок не заперт в диалоге.
const END_LABEL := "Закончить разговор"

var _dialogues: Dictionary = {}  # id -> данные файла
var _done: Dictionary = {}  # dialogue_id -> true (завершался в этом забеге)
var _used: Dictionary = {}  # "dialogue/option" -> true (реплика с "once")
var _current_id: String = ""
var _node_id: String = ""


func _ready() -> void:
	_load_all()


func reset_for_new_run() -> void:
	_current_id = ""
	_node_id = ""
	_done.clear()
	_used.clear()
	changed.emit()


func has_dialogue(dialogue_id: String) -> bool:
	return _dialogues.has(dialogue_id)


func is_active() -> bool:
	return _current_id != ""


func current_dialogue_id() -> String:
	return _current_id


func current_npc_id() -> String:
	return str(_data().get("npc", ""))


func npc_name(dialogue_id: String = "") -> String:
	var data := _data() if dialogue_id == "" else _as_dict(_dialogues.get(dialogue_id, {}))
	return str(data.get("name", data.get("npc", "")))


func portrait_id(dialogue_id: String = "") -> String:
	var data := _data() if dialogue_id == "" else _as_dict(_dialogues.get(dialogue_id, {}))
	var portrait := str(data.get("portrait", ""))
	return portrait if portrait != "" else str(data.get("npc", ""))


## Разговор уже доводили до конца в этом забеге (условие dialogue_done).
func is_done(dialogue_id: String) -> bool:
	return _done.has(dialogue_id)


func is_option_used(dialogue_id: String, option_id: String) -> bool:
	return _used.has("%s/%s" % [dialogue_id, option_id])


## Начать разговор: выбирается первый подходящий узел входа.
func start(dialogue_id: String) -> bool:
	if dialogue_id == "" or not _dialogues.has(dialogue_id):
		push_warning("DialogueSystem: неизвестный диалог '%s'" % dialogue_id)
		return false
	var entry := _entry_node(dialogue_id)
	if entry == "":
		push_warning("DialogueSystem: у диалога '%s' нет подходящего входного узла" % dialogue_id)
		return false
	_current_id = dialogue_id
	_node_id = ""
	_enter(entry)
	dialogue_started.emit(current_npc_id(), npc_name())
	return true


## Выбор реплики игрока: эффекты варианта — через EffectResolver, затем переход.
func choose(option_id: String) -> void:
	if not is_active():
		return
	if option_id == "":
		end()
		return
	var chosen := _find_option(option_id)
	if chosen.is_empty():
		push_warning("DialogueSystem: у узла '%s' нет реплики '%s'" % [_node_id, option_id])
		return
	if not EffectResolver.check_requirements(_as_array(chosen.get("requires", []))):
		return
	_used["%s/%s" % [_current_id, option_id]] = true
	EffectResolver.apply_effects(_as_array(chosen.get("effects", [])))
	var next := str(chosen.get("next", ""))
	if next == "":
		end()
		return
	_enter(next)


## Выйти из разговора (кнопка «Закончить разговор» или конец ветки).
func end() -> void:
	if not is_active():
		return
	var npc := current_npc_id()
	var dialogue_id := _current_id
	if not _done.has(dialogue_id):
		JournalSystem.add("talk", "Разговор: %s" % _speaker_title())
	_done[dialogue_id] = true
	_current_id = ""
	_node_id = ""
	dialogue_ended.emit(npc, dialogue_id)
	changed.emit()


## Текущий узел для UI: реплика, доступные варианты и подпись собеседника.
## Пустой словарь — разговор не идёт.
func get_state() -> Dictionary:
	if not is_active():
		return {}
	var node := _node()
	var node_id := _node_id
	var options: Array = []
	for option in _options(node):
		var option_id := str(option.get("id", ""))
		if option_id == "":
			continue
		if bool(option.get("once", false)) and is_option_used(_current_id, option_id):
			continue
		if not EffectResolver.check_requirements(_as_array(option.get("requires", []))):
			continue
		options.append({
			"id": option_id,
			"label": str(option.get("label", option_id)),
		})
	return {
		"dialogue_id": _current_id,
		"npc_id": current_npc_id(),
		"npc_name": _speaker_title(),
		"portrait": portrait_id(),
		"node": node_id,
		"speaker": str(node.get("speaker", npc_name())),
		"text": str(node.get("text", "")),
		"image": str(node.get("image", "")),
		"options": options,
		"end_label": END_LABEL,
	}


func to_save_data() -> Dictionary:
	return {"done": _done.keys(), "used": _used.keys()}


func load_save_data(data: Dictionary) -> void:
	_current_id = ""
	_node_id = ""
	_done.clear()
	_used.clear()
	for id in _as_array(data.get("done", [])):
		_done[str(id)] = true
	for key in _as_array(data.get("used", [])):
		_used[str(key)] = true
	changed.emit()


# --- Внутреннее ---------------------------------------------------------------

func _enter(node_id: String) -> void:
	var nodes := _nodes()
	if not nodes.has(node_id):
		push_warning("DialogueSystem: у диалога '%s' нет узла '%s'" % [_current_id, node_id])
		end()
		return
	_node_id = node_id
	EffectResolver.apply_effects(_as_array(_node().get("effects", [])))
	node_changed.emit(get_state())


## Узел входа: первый подходящий из "entries" (у каждого свой requires),
## иначе "entry"; без обоих — первый узел файла.
func _entry_node(dialogue_id: String) -> String:
	var data := _as_dict(_dialogues.get(dialogue_id, {}))
	for candidate in _as_array(data.get("entries", [])):
		var entry := _as_dict(candidate)
		if EffectResolver.check_requirements(_as_array(entry.get("requires", []))):
			return str(entry.get("node", ""))
	var single := str(data.get("entry", ""))
	if single != "":
		return single
	var nodes := _nodes()
	return str(nodes.keys()[0]) if not nodes.is_empty() else ""


func _find_option(option_id: String) -> Dictionary:
	for option in _options(_node()):
		if str(option.get("id", "")) == option_id:
			return option
	return {}


func _speaker_title() -> String:
	var node := _node()
	var speaker := str(node.get("speaker", ""))
	return speaker if speaker != "" else npc_name()


func _data() -> Dictionary:
	return _as_dict(_dialogues.get(_current_id, {}))


func _nodes() -> Dictionary:
	return _as_dict(_data().get("nodes", {}))


func _node() -> Dictionary:
	return _as_dict(_nodes().get(_node_id, {}))


func _options(node: Dictionary) -> Array:
	return _as_array(node.get("options", []))


func _as_dict(value) -> Dictionary:
	return value if value is Dictionary else {}


func _as_array(value) -> Array:
	return value if value is Array else []


func _load_all() -> void:
	_dialogues.clear()
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		push_warning("DialogueSystem: %s не найден" % DATA_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_DIR + "/" + file_name))
			if parsed is Dictionary and str(parsed.get("id", "")) != "":
				_dialogues[str(parsed["id"])] = parsed
			else:
				push_warning("DialogueSystem: битый файл диалога %s" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
