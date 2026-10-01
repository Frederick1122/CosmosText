extends Node
## Цели забега и мысли героя — data/quests.json.
##
##   thoughts — что герой думает сейчас: берётся первый вариант, чьи requires
##              выполнены (самые поздние по сюжету — в начале списка).
##   quests   — цели. Цель начинается, когда выполнены её start (нет поля —
##              сразу), и состоит из шагов: шаг засчитан, как только выполнены
##              его done. Цель выполнена по своим done, а без них — когда
##              засчитаны все шаги. Всё засчитанное фиксируется и не
##              откатывается, даже если условие потом перестало выполняться
##              (предмет израсходован). Шаг с hidden: true не виден, пока не
##              засчитан, — так собираются улики.
##
## Условия — обычные requires (EffectResolver). Проверка — refresh(): после
## каждого набора эффектов (EffectResolver.apply_effects) и завершения
## события модуля (LocationSystem.mark_completed). Новые цели и засчитанные
## шаги пишутся в ленту и хронику, кнопка «Журнал» получает (!).
##
## Состояние забега: reset_for_new_run / to_save_data / load_save_data.

signal changed()

const QUESTS_PATH := "res://data/quests.json"

var _thoughts: Array = []
var _quests: Array = []
var _started: Dictionary = {}  # quest_id -> true
var _completed: Dictionary = {}  # quest_id -> true
var _steps_done: Dictionary = {}  # "quest_id/step_id" -> true


func _ready() -> void:
	if not FileAccess.file_exists(QUESTS_PATH):
		push_warning("QuestSystem: файл не найден %s" % QUESTS_PATH)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(QUESTS_PATH))
	if not (parsed is Dictionary):
		push_warning("QuestSystem: битый %s" % QUESTS_PATH)
		return
	_thoughts = parsed.get("thoughts", []) if parsed.get("thoughts", []) is Array else []
	_quests = parsed.get("quests", []) if parsed.get("quests", []) is Array else []


func reset_for_new_run() -> void:
	_started.clear()
	_completed.clear()
	_steps_done.clear()
	changed.emit()


## Засчитать всё, что стало выполненным.
func refresh() -> void:
	var any := false
	for quest in _quests:
		var quest_id := str(quest.get("id", ""))
		if _completed.has(quest_id):
			continue
		var title := str(quest.get("title", quest_id))
		if not _started.has(quest_id):
			if not EffectResolver.check_requirements(quest.get("start", [])):
				continue
			_started[quest_id] = true
			any = true
			NarrativeSystem.push("goal", "[Новая цель: %s]" % title)
			JournalSystem.add("goal", "Новая цель: %s" % title)
		var all_done := true
		for step in quest.get("steps", []):
			var key := "%s/%s" % [quest_id, str(step.get("id", ""))]
			if _steps_done.has(key):
				continue
			if EffectResolver.check_requirements(step.get("done", [])):
				_steps_done[key] = true
				any = true
				NarrativeSystem.push("goal", "[✓ %s]" % str(step.get("text", "")))
			else:
				all_done = false
		var finished := EffectResolver.check_requirements(quest["done"]) if quest.has("done") else all_done
		if finished:
			_completed[quest_id] = true
			any = true
			NarrativeSystem.push("goal", "[Цель выполнена: %s]" % title)
			JournalSystem.add("goal", "Цель выполнена: %s" % title)
	if any:
		NotificationSystem.mark_goals_new()
		changed.emit()


## Мысли героя о происходящем сейчас.
func get_thoughts() -> String:
	for variant in _thoughts:
		if variant is Dictionary and EffectResolver.check_requirements(variant.get("requires", [])):
			return str(variant.get("text", ""))
	return ""


## Начатые цели: [{ id, title, description, completed, steps: [{ text, done, current }] }].
## Шаги — засчитанные и первый незасчитанный видимый (current), дальше
## не показываются: цель раскрывается по ходу.
func get_quests() -> Array:
	var result: Array = []
	for quest in _quests:
		var quest_id := str(quest.get("id", ""))
		if not _started.has(quest_id):
			continue
		var completed := _completed.has(quest_id)
		var steps: Array = []
		var current_shown := completed
		for step in quest.get("steps", []):
			var done := _steps_done.has("%s/%s" % [quest_id, str(step.get("id", ""))])
			if done:
				steps.append({"text": str(step.get("text", "")), "done": true, "current": false})
			elif not current_shown and not bool(step.get("hidden", false)):
				current_shown = true
				steps.append({"text": str(step.get("text", "")), "done": false, "current": true})
		result.append({
			"id": quest_id,
			"title": str(quest.get("title", quest_id)),
			"description": str(quest.get("description", "")),
			"completed": completed,
			"steps": steps,
		})
	return result


func is_completed(quest_id: String) -> bool:
	return _completed.has(quest_id)


func is_step_done(quest_id: String, step_id: String) -> bool:
	return _steps_done.has("%s/%s" % [quest_id, step_id])


func to_save_data() -> Dictionary:
	return {
		"started": _started.keys(),
		"completed": _completed.keys(),
		"steps": _steps_done.keys(),
	}


func load_save_data(data: Dictionary) -> void:
	_started = _id_set(data.get("started", []))
	_completed = _id_set(data.get("completed", []))
	_steps_done = _id_set(data.get("steps", []))
	changed.emit()


func _id_set(ids) -> Dictionary:
	var result := {}
	if ids is Array:
		for id in ids:
			result[str(id)] = true
	return result
