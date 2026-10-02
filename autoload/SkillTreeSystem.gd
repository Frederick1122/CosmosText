extends Node
## Кольцевое дерево навыков, происхождения и знания героя.
## Схемы данных — data/skill_tree.json, data/knowledge.json, data/origins.json;
## справочник — docs/CONTENT.md, устройство — docs/ARCHITECTURE.md.
##
## Дерево — концентрические кольца (inner / middle / outer) из восьми секторов.
## Узел покупается за очки навыков (CharacterSystem.skill_points), но доступ к
## нему открывают три независимых замка:
##   * предыдущие узлы      — requires.nodes;
##   * знание               — requires.knowledge (переживает смерть, meta-слой);
##   * практика             — requires.practice (счётчики значимых действий, run).
## Плюс необязательный requires.origin — узел, открытый самим происхождением.
##
## Происхождение (data/origins.json) выбирается при создании персонажа, задаёт
## стартовые сектора и узлы, знание, характеристики, ресурсы, черту, недостаток
## и личный сюжетный крючок. Без происхождения (забег без выбора, тесты) дерево
## открыто целиком: это отладочный режим, а не игровой баланс.
##
## Состояние забега: узлы, практика, происхождение, открытые сектора — в run.json.
## Знание — в meta.json: найденное однажды направление не нужно открывать заново.

## Дерево, знание, практика или происхождение изменились — UI перерисовывается.
signal changed()
## Узел куплен (эффекты применены, очки списаны).
signal node_bought(node_id: String)
## Получено знание.
signal knowledge_gained(knowledge_id: String)
## Сектор дерева впервые открыт.
signal sector_revealed(sector_id: String)
## Происхождение применено при старте забега.
signal origin_applied(origin_id: String)

## Состояния узла для UI.
enum NodeState { UNKNOWN, LOCKED, AVAILABLE, OWNED }

const TREE_PATH := "res://data/skill_tree.json"
const KNOWLEDGE_PATH := "res://data/knowledge.json"
const ORIGINS_PATH := "res://data/origins.json"
const RING_TITLES := {"inner": "Внутреннее кольцо", "middle": "Среднее кольцо", "outer": "Внешнее кольцо"}
const TYPE_TITLES := {
	"small": "Малый",
	"notable": "Заметный",
	"mastery": "Мастерство",
	"bridge": "Перемычка",
	"key": "Ключевой",
	"legendary": "Легендарный",
}
const TYPE_COLORS := {
	"small": Color("#7f8b9e"),
	"notable": Color("#9fd3e6"),
	"mastery": Color("#c6b6ff"),
	"bridge": Color("#7fc8a8"),
	"key": Color("#e0b153"),
	"legendary": Color("#f0a0c0"),
}

var _sectors: Dictionary = {}
var _nodes: Dictionary = {}
var _practice_titles: Dictionary = {}
var _origin_db: Dictionary = {}
var _knowledge_db: Dictionary = {}

## Купленные узлы забега: node_id -> true.
var _owned: Dictionary = {}
## Счётчики практики забега: practice_id -> int.
var _practice: Dictionary = {}
## Открытые контактом сектора забега: sector_id -> true.
var _revealed: Dictionary = {}
## id выбранного происхождения ("" — отладочный забег без происхождения).
var _origin_id: String = ""
## Известное знание (meta-слой, переживает смерть): knowledge_id -> true.
var _known: Dictionary = {}


func _ready() -> void:
	_load_content()


# --- Публичный API --------------------------------------------------------------

func get_node_data(node_id: String) -> Dictionary:
	var data = _nodes.get(node_id, {})
	return data if data is Dictionary else {}


func has_node_id(node_id: String) -> bool:
	return _nodes.has(node_id)


## Сектора дерева по порядку из data/skill_tree.json; known — виден ли игроку.
func get_sectors() -> Array:
	var result: Array = []
	for sector_id in _sectors.keys():
		var data: Dictionary = _sectors[sector_id]
		result.append({
			"id": sector_id,
			"name": str(data.get("name", sector_id)),
			"color": str(data.get("color", "#9fd3e6")),
			"known": is_sector_known(sector_id),
		})
	return result


func get_sector_title(sector_id: String) -> String:
	return str(_sectors.get(sector_id, {}).get("name", sector_id))


func is_sector_known(sector_id: String) -> bool:
	if not _sectors.has(sector_id):
		return false
	if _origin_id == "":
		return true  # без происхождения дерево открыто целиком (отладка, тесты)
	if _revealed.has(sector_id):
		return true
	for knowledge_id in _known.keys():
		var reveals = _knowledge_db.get(knowledge_id, {}).get("reveal_sectors", [])
		if reveals is Array and reveals.has(sector_id):
			return true
	return false


## Открывает сектор контактом с устройством, школой или фракцией.
func reveal_sector(sector_id: String) -> bool:
	if not _sectors.has(sector_id) or is_sector_known(sector_id):
		return false
	_revealed[sector_id] = true
	NarrativeSystem.push("notice", "[Открыто направление: %s]" % get_sector_title(sector_id))
	sector_revealed.emit(sector_id)
	changed.emit()
	return true


## Узлы сектора (или все, если sector_id пуст) со всеми полями для UI:
## id, name, ring, type, cost, description, stats, tags, state, origin.
func get_nodes(sector_id: String = "") -> Array:
	var result: Array = []
	for node_id in _nodes.keys():
		var data: Dictionary = _nodes[node_id]
		if sector_id != "" and str(data.get("sector", "")) != sector_id:
			continue
		result.append(describe_node(node_id))
	return result


func describe_node(node_id: String) -> Dictionary:
	var data := get_node_data(node_id)
	var requires: Dictionary = data.get("requires", {})
	var result := {
		"id": node_id,
		"name": str(data.get("name", node_id)),
		"sector": str(data.get("sector", "")),
		"ring": str(data.get("ring", "inner")),
		"type": str(data.get("type", "small")),
		"cost": node_cost(node_id),
		"description": str(data.get("description", "")),
		"stats": data.get("stats", {}),
		"tags": data.get("tags", []),
		"state": node_state(node_id),
		"origin_title": origin_title(str(requires.get("origin", ""))),
		"origin": str(requires.get("origin", "")),
	}
	return result


func node_cost(node_id: String) -> int:
	return maxi(1, int(get_node_data(node_id).get("cost", 1)))


func node_state(node_id: String) -> int:
	if _owned.has(node_id):
		return NodeState.OWNED
	var data := get_node_data(node_id)
	if data.is_empty():
		return NodeState.UNKNOWN
	if not is_sector_known(str(data.get("sector", ""))):
		return NodeState.UNKNOWN
	if bool(data.get("hidden", false)) and not _knowledge_requirement_met(data):
		return NodeState.UNKNOWN  # размытый знак вопроса: направление есть, узла ещё нет
	if requirements_met(node_id):
		return NodeState.AVAILABLE
	return NodeState.LOCKED


func is_owned(node_id: String) -> bool:
	return _owned.has(node_id)


func owned_nodes() -> Array:
	return _owned.keys()


## Что мешает купить узел прямо сейчас — короткая строка для UI ("" — можно).
func lock_reason(node_id: String) -> String:
	var data := get_node_data(node_id)
	if is_owned(node_id) or data.is_empty():
		return ""
	var requires: Dictionary = data.get("requires", {})
	var missing: Array = []
	for prev in _as_array(requires.get("nodes", [])):
		if not _owned.has(str(prev)):
			missing.append(str(get_node_data(str(prev)).get("name", prev)))
	for knowledge_id in _as_array(requires.get("knowledge", [])):
		if not knowledge_known(str(knowledge_id)):
			missing.append("знание «%s»" % knowledge_title(str(knowledge_id)))
	for practice_id in _practice_requirements(requires).keys():
		var need := int(_practice_requirements(requires)[practice_id])
		if practice(str(practice_id)) < need:
			missing.append("%s (%d/%d)" % [practice_title(str(practice_id)), practice(str(practice_id)), need])
	var origin_id := str(requires.get("origin", ""))
	if origin_id != "" and not _origin_matches(origin_id):
		missing.append("происхождение «%s»" % origin_title(origin_id))
	for excluded in _as_array(data.get("excludes", [])):
		if _owned.has(str(excluded)):
			missing.append("несовместимо с «%s»" % str(get_node_data(str(excluded)).get("name", excluded)))
	if not missing.is_empty():
		return "Нужно: " + ", ".join(missing)
	if CharacterSystem.skill_points < node_cost(node_id):
		return "Не хватает очков развития"
	return ""


## Все внешние требования выполнены (без учёта очков и взаимоисключений).
func requirements_met(node_id: String) -> bool:
	var data := get_node_data(node_id)
	if data.is_empty():
		return false
	var requires: Dictionary = data.get("requires", {})
	for prev in _as_array(requires.get("nodes", [])):
		if not _owned.has(str(prev)):
			return false
	if not _knowledge_requirement_met(data):
		return false
	var practice_requirements: Dictionary = _practice_requirements(requires)
	for practice_id in practice_requirements.keys():
		if practice(str(practice_id)) < int(practice_requirements[practice_id]):
			return false
	var origin_id := str(requires.get("origin", ""))
	if origin_id != "" and not _origin_matches(origin_id):
		return false
	for excluded in _as_array(data.get("excludes", [])):
		if _owned.has(str(excluded)):
			return false
	return true


func can_buy(node_id: String) -> bool:
	return node_state(node_id) == NodeState.AVAILABLE \
		and CharacterSystem.skill_points >= node_cost(node_id)


## Покупка узла: очки, эффекты узла, перерасчёт характеристик.
func buy(node_id: String) -> bool:
	if not can_buy(node_id):
		return false
	var cost := node_cost(node_id)
	if not CharacterSystem.spend_skill_points(cost):
		return false
	_grant_node(node_id)
	NarrativeSystem.push("gain", "[Навык: %s]" % get_node_data(node_id).get("name", node_id))
	SoundSystem.play("level_up")
	node_bought.emit(node_id)
	_after_change()
	return true


## Сколько узлов куплено и сколько всего в известных секторах — для заголовка.
func progress() -> Dictionary:
	var total := 0
	for node_id in _nodes.keys():
		if is_sector_known(str(get_node_data(node_id).get("sector", ""))):
			total += 1
	return {"owned": _owned.size(), "known": total, "all": _nodes.size()}


## Есть ли доступный к покупке узел — для уведомления (!) на кнопке.
func has_available() -> bool:
	for node_id in _nodes.keys():
		if can_buy(node_id):
			return true
	return false


# --- Теги и характеристики ------------------------------------------------------

## Механика узла или происхождения. Контент и код спрашивают has_tag("combat:first_shot").
func has_tag(tag: String) -> bool:
	if tag == "":
		return false
	for node_id in _owned.keys():
		var tags = get_node_data(str(node_id)).get("tags", [])
		if tags is Array and tags.has(tag):
			return true
	var origin_tags = get_origin().get("tags", [])
	return origin_tags is Array and origin_tags.has(tag)


## Сумма характеристик купленных узлов и происхождения — в CharacterSystem.
func tree_stats() -> Dictionary:
	var result: Dictionary = {}
	_add_stats_into(result, get_origin().get("stats", {}))
	for node_id in _owned.keys():
		_add_stats_into(result, get_node_data(str(node_id)).get("stats", {}))
	return result


func all_tags() -> Array:
	var result: Array = []
	for node_id in _owned.keys():
		for tag in _as_array(get_node_data(str(node_id)).get("tags", [])):
			if not result.has(tag):
				result.append(tag)
	for tag in _as_array(get_origin().get("tags", [])):
		if not result.has(tag):
			result.append(tag)
	return result


# --- Знание ---------------------------------------------------------------------

func knowledge_known(knowledge_id: String) -> bool:
	return knowledge_id != "" and _known.has(knowledge_id)


func knowledge_title(knowledge_id: String) -> String:
	return str(_knowledge_db.get(knowledge_id, {}).get("name", knowledge_id))


func knowledge_source(knowledge_id: String) -> String:
	return str(_knowledge_db.get(knowledge_id, {}).get("source", ""))


func knowledge_description(knowledge_id: String) -> String:
	return str(_knowledge_db.get(knowledge_id, {}).get("description", ""))


func has_knowledge_entry(knowledge_id: String) -> bool:
	return _knowledge_db.has(knowledge_id)


## Всё знание справочника (для UI «карта известного мира»).
func all_knowledge() -> Array:
	var result: Array = []
	for knowledge_id in _knowledge_db.keys():
		result.append({
			"id": knowledge_id,
			"name": knowledge_title(knowledge_id),
			"source": knowledge_source(knowledge_id),
			"description": knowledge_description(knowledge_id),
			"known": knowledge_known(knowledge_id),
		})
	return result


func known_knowledge() -> Array:
	return _known.keys()


## Новое знание: снимает информационный замок с узлов и может открыть сектор.
func learn_knowledge(knowledge_id: String, silent: bool = false) -> bool:
	if knowledge_id == "" or _known.has(knowledge_id):
		return false
	if not _knowledge_db.has(knowledge_id):
		push_warning("SkillTreeSystem: неизвестное знание '%s'" % knowledge_id)
		return false
	_known[knowledge_id] = true
	if not silent:
		NarrativeSystem.push("notice", "[Знание: %s]" % knowledge_title(knowledge_id))
	var reveals = _knowledge_db[knowledge_id].get("reveal_sectors", [])
	if reveals is Array:
		for sector_id in reveals:
			reveal_sector(str(sector_id))
	knowledge_gained.emit(knowledge_id)
	changed.emit()
	return true


# --- Практика -------------------------------------------------------------------

func practice(practice_id: String) -> int:
	return int(_practice.get(practice_id, 0))


func practice_title(practice_id: String) -> String:
	return str(_practice_titles.get(practice_id, practice_id))


## Один значимый приём в забеге (ремонт, стыковка, операция, переговоры).
func add_practice(practice_id: String, amount: int = 1) -> void:
	if practice_id == "" or amount <= 0:
		return
	_practice[practice_id] = practice(practice_id) + amount
	changed.emit()


# --- Происхождения --------------------------------------------------------------

func get_origin_id() -> String:
	return _origin_id


func get_origin() -> Dictionary:
	var data = _origin_db.get(_origin_id, {})
	return data if data is Dictionary else {}


func origin_title(origin_id: String) -> String:
	if origin_id == "":
		return ""
	return str(_origin_db.get(origin_id, {}).get("name", origin_id))


## Все происхождения по порядку из data/origins.json — для экрана создания героя.
func get_origins() -> Array:
	var result: Array = []
	for origin_id in _origin_db.keys():
		var data: Dictionary = _origin_db[origin_id]
		result.append({
			"id": origin_id,
			"name": str(data.get("name", origin_id)),
			"why": str(data.get("why", "")),
			"sectors": _sector_titles(data.get("start_sectors", [])),
			"sectors_text": ", ".join(_sector_titles(data.get("start_sectors", []))),
			"buff": str(data.get("buff", "")),
			"debuff": str(data.get("debuff", "")),
			"hook": str(data.get("hook", "")),
			"goal": str(data.get("goal", "")),
			"start_nodes": _as_array(data.get("start_nodes", [])),
		})
	return result


## Применяет происхождение в начале забега: стартовые узлы (бесплатно), сектора,
## знание, предметы, ресурсы и очки. Вызывает SkillTreeSystem.reset_for_new_run.
func select_origin(origin_id: String) -> void:
	if origin_id == "" or not _origin_db.has(origin_id):
		if origin_id != "":
			push_warning("SkillTreeSystem: неизвестное происхождение '%s'" % origin_id)
		return
	_origin_id = origin_id
	var data: Dictionary = _origin_db[origin_id]
	for sector_id in _as_array(data.get("start_sectors", [])):
		_revealed[str(sector_id)] = true
	for knowledge_id in _as_array(data.get("knowledge", [])):
		learn_knowledge(str(knowledge_id), true)
	for node_id in _as_array(data.get("start_nodes", [])):
		if _nodes.has(str(node_id)):
			_grant_node(str(node_id))
		else:
			push_warning("SkillTreeSystem: происхождение '%s' ссылается на неизвестный узел '%s'" % [origin_id, node_id])
	for item_id in _as_array(data.get("items", [])):
		InventorySystem.add_item(str(item_id))
	var resources: Dictionary = data.get("resources", {})
	for key in resources.keys():
		match str(key):
			"ammo":
				ResourceSystem.apply_ammo_delta(int(resources[key]))
			"hp":
				ResourceSystem.apply_hp_delta(int(resources[key]))
			"o2":
				ResourceSystem.apply_o2_delta(float(resources[key]))
	var extra_points := int(data.get("skill_points", 0))
	if extra_points > 0:
		CharacterSystem.add_skill_points(extra_points)
	_after_change()
	origin_applied.emit(origin_id)
	NarrativeSystem.push("notice", "[Происхождение: %s]" % str(data.get("name", origin_id)))


func _origin_matches(origin_id: String) -> bool:
	return origin_id != "" and _origin_id == origin_id


# --- Состояние забега и meta ----------------------------------------------------

## Новый забег: узлы, практика и открытые сектора сбрасываются, знание — нет
## (оно в meta.json). origin_id берётся из config.json, если не задан явно.
func reset_for_new_run(origin_id: String = "") -> void:
	_owned.clear()
	_practice.clear()
	_revealed.clear()
	_origin_id = ""
	if origin_id != "":
		select_origin(origin_id)
	_after_change()


func to_save_data() -> Dictionary:
	return {
		"origin": _origin_id,
		"nodes": _owned.keys(),
		"practice": _practice.duplicate(),
		"revealed": _revealed.keys(),
	}


func load_save_data(data: Dictionary) -> void:
	_owned.clear()
	_practice.clear()
	_revealed.clear()
	_origin_id = str(data.get("origin", ""))
	for node_id in _as_array(data.get("nodes", [])):
		if _nodes.has(str(node_id)):
			_owned[str(node_id)] = true
	var practice_data = data.get("practice", {})
	if practice_data is Dictionary:
		for practice_id in practice_data.keys():
			_practice[str(practice_id)] = maxi(0, int(practice_data[practice_id]))
	for sector_id in _as_array(data.get("revealed", [])):
		_revealed[str(sector_id)] = true
	_after_change(false)


## Знание живёт в meta.json: открытое направление не открывают заново.
func to_meta_save_data() -> Dictionary:
	return {"knowledge": _known.keys()}


func load_meta_save_data(data: Dictionary) -> void:
	_known.clear()
	for knowledge_id in _as_array(data.get("knowledge", [])):
		if _knowledge_db.has(str(knowledge_id)):
			_known[str(knowledge_id)] = true
	changed.emit()


# --- Внутреннее -----------------------------------------------------------------

func _load_content() -> void:
	var tree := _load_json(TREE_PATH)
	var sectors = tree.get("sectors", {})
	_sectors = sectors if sectors is Dictionary else {}
	var nodes = tree.get("nodes", {})
	_nodes = nodes if nodes is Dictionary else {}
	var practice_titles = tree.get("practice", {})
	_practice_titles = practice_titles if practice_titles is Dictionary else {}
	var knowledge = _load_json(KNOWLEDGE_PATH)
	_knowledge_db = knowledge if knowledge is Dictionary else {}
	var origins = _load_json(ORIGINS_PATH)
	_origin_db = origins if origins is Dictionary else {}


func _grant_node(node_id: String) -> void:
	if _owned.has(node_id):
		return
	_owned[node_id] = true
	var data := get_node_data(node_id)
	var grants: Dictionary = data.get("grants", {})
	for knowledge_id in _as_array(grants.get("knowledge", [])):
		learn_knowledge(str(knowledge_id), true)
	for item_id in _as_array(grants.get("items", [])):
		InventorySystem.add_item(str(item_id))
	for flag in _as_array(grants.get("flags", [])):
		SituationEngine.set_flag(str(flag), true)
	for sector_id in _as_array(grants.get("reveal_sectors", [])):
		_revealed[str(sector_id)] = true


func _after_change(refresh_character: bool = true) -> void:
	if refresh_character:
		CharacterSystem.set_tree_stats(tree_stats())
	changed.emit()


func _knowledge_requirement_met(data: Dictionary) -> bool:
	var requires: Dictionary = data.get("requires", {})
	for knowledge_id in _as_array(requires.get("knowledge", [])):
		if not knowledge_known(str(knowledge_id)):
			return false
	return true


func _practice_requirements(requires: Dictionary) -> Dictionary:
	var value = requires.get("practice", {})
	return value if value is Dictionary else {}


func _sector_titles(sector_ids) -> Array:
	var result: Array = []
	for sector_id in _as_array(sector_ids):
		result.append(get_sector_title(str(sector_id)))
	return result


func _add_stats_into(target: Dictionary, stats) -> void:
	if not (stats is Dictionary):
		return
	for stat in stats.keys():
		target[str(stat)] = float(target.get(str(stat), 0.0)) + float(stats[stat])


func _as_array(value) -> Array:
	return value if value is Array else []


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("SkillTreeSystem: файл не найден %s" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
