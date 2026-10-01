extends Node
## Общий буфер текста для экрана модуля и ситуации. При переходе между
## локацией и событием буфер очищается: на экране всегда только текущий
## контекст, без описания предыдущей локации или завершённого события.
##
## Запись: { "kind": ..., "text": ..., "image": ... }
##   scene  — заголовок новой сцены (вход в модуль, начало ситуации);
##   text   — описание, текст события или ситуации;
##   choice — выбор игрока («— Выбить крышку плечом»);
##   result — последствие выбора;
##   notice — служебное сообщение (взял предмет, заперто, не поместилось);
##   gain   — прибыль ресурса или предмета: «[+25 HP]», «[+1 Аптечка]»;
##   loss   — убыль: «[−2 O2]», «[−5 HP]», «[−1 Ключ-карта]»
##            (пишет EffectResolver.report_change);
##   system — переход, бой, смерть.
##
## Ограничение защищает сохранение от разросшегося текущего события.

signal entries_added(count: int)
signal cleared()

const MAX_ENTRIES := 120

var entries: Array = []


func reset_for_new_run() -> void:
	clear()


func clear() -> void:
	entries.clear()
	cleared.emit()


## Заголовок новой сцены: название и (необязательно) иллюстрация.
func push_scene(title: String, image: String = "") -> void:
	push("scene", title, image)


func push(kind: String, text: String, image: String = "") -> void:
	var trimmed := text.strip_edges()
	if trimmed == "" and image == "":
		return
	entries.append({"kind": kind, "text": trimmed, "image": image})
	if entries.size() > MAX_ENTRIES:
		entries = entries.slice(entries.size() - MAX_ENTRIES)
	entries_added.emit(1)


## Модуль сменил вариант (победа выставила флаг): заголовок сцены, картинка и
## описание в начале ленты обновляются, записи под ними остаются.
func update_head(title: String, image: String, text: String) -> void:
	if entries.size() < 2 or entries[0]["kind"] != "scene" or entries[1]["kind"] != "text":
		return
	entries[0]["text"] = title.strip_edges()
	entries[0]["image"] = image
	entries[1]["text"] = text.strip_edges()


func get_entries() -> Array:
	return entries


func size() -> int:
	return entries.size()


func to_save_data() -> Array:
	return entries.duplicate(true)


func load_save_data(data: Array) -> void:
	entries.clear()
	for entry in data:
		if not (entry is Dictionary):
			continue
		entries.append({
			"kind": str(entry.get("kind", "text")),
			"text": str(entry.get("text", "")),
			"image": str(entry.get("image", "")),
		})
	cleared.emit()
