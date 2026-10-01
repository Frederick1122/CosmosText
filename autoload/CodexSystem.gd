extends Node
## Справочник мира: места, люди, корабли и термины из data/codex.json.
## Запись открывается один раз, когда одно из её написаний впервые появляется
## в ленте NarrativeSystem. Знания сохраняются в meta.json и переживают забеги.

signal entry_unlocked(id: String)

const DATA_PATH := "res://data/codex.json"
const CATEGORY_ORDER := ["places", "people", "ships", "terms"]
const CATEGORY_TITLES := {
	"places": "Места",
	"people": "Люди",
	"ships": "Корабли",
	"terms": "Термины",
}

var _entries: Dictionary = {}
var _unlocked: Dictionary = {}  # id -> true


func _ready() -> void:
	_entries = _load_res_json(DATA_PATH)
	NarrativeSystem.entries_added.connect(_on_narrative_entries_added)


## Все категории в стабильном порядке для подвкладок журнала.
func get_categories() -> Array:
	return CATEGORY_ORDER.duplicate()


func get_category_title(category: String) -> String:
	return str(CATEGORY_TITLES.get(category, category))


func is_unlocked(id: String) -> bool:
	return _unlocked.has(id)


## Открытые записи категории, отсортированные по заголовку.
func get_unlocked(category: String = "") -> Array:
	var result: Array = []
	for id in _unlocked.keys():
		var entry: Dictionary = _entries.get(str(id), {})
		if category == "" or str(entry.get("category", "")) == category:
			result.append(str(id))
	result.sort_custom(func(a: String, b: String) -> bool: return get_title(a) < get_title(b))
	return result


func get_title(id: String) -> String:
	return str(_entries.get(id, {}).get("title", id))


func get_text(id: String) -> String:
	return str(_entries.get(id, {}).get("text", ""))


func get_category(id: String) -> String:
	return str(_entries.get(id, {}).get("category", ""))


## Части строки для RichTextLabel: [{ text, highlighted }]. Совпадения
## пересекаются редко; при одинаковом начале берётся самое длинное написание.
func highlighted_segments(text: String) -> Array:
	var matches: Array = []
	var lowered := text.to_lower()
	for id in _entries.keys():
		var aliases = _entries[id].get("aliases", [])
		if not (aliases is Array):
			continue
		for raw_alias in aliases:
			var alias := str(raw_alias)
			if alias == "":
				continue
			var needle := alias.to_lower()
			var start := lowered.find(needle)
			while start >= 0:
				matches.append({"start": start, "length": alias.length()})
				start = lowered.find(needle, start + alias.length())
	matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["start"]) < int(b["start"]) \
			or (int(a["start"]) == int(b["start"]) and int(a["length"]) > int(b["length"])))
	var result: Array = []
	var cursor := 0
	for match in matches:
		var start := int(match["start"])
		var length := int(match["length"])
		if start < cursor:
			continue
		if start > cursor:
			result.append({"text": text.substr(cursor, start - cursor), "highlighted": false})
		result.append({"text": text.substr(start, length), "highlighted": true})
		cursor = start + length
	if cursor < text.length():
		result.append({"text": text.substr(cursor), "highlighted": false})
	if result.is_empty():
		result.append({"text": text, "highlighted": false})
	return result


func to_save_data() -> Array:
	return _unlocked.keys()


func load_save_data(ids: Array) -> void:
	_unlocked.clear()
	for id in ids:
		if _entries.has(str(id)):
			_unlocked[str(id)] = true


func _on_narrative_entries_added(count: int) -> void:
	var entries := NarrativeSystem.get_entries()
	var first := maxi(0, entries.size() - count)
	var found: Array = []
	for i in range(first, entries.size()):
		var text := str(entries[i].get("text", ""))
		var lowered := text.to_lower()
		for id in _entries.keys():
			var key := str(id)
			if _unlocked.has(key) or found.has(key):
				continue
			if _matches_entry(lowered, _entries[id]):
				found.append(key)
	if found.is_empty():
		return
	for id in found:
		_unlocked[id] = true
		entry_unlocked.emit(id)
	SaveManager.save_meta()


func _matches_entry(lowered_text: String, entry: Dictionary) -> bool:
	var aliases = entry.get("aliases", [])
	if not (aliases is Array):
		return false
	for alias in aliases:
		var needle := str(alias).to_lower()
		if needle != "" and lowered_text.contains(needle):
			return true
	return false


func _load_res_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("CodexSystem: файл не найден %s" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
