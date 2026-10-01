extends Node
## Уровни и опыт забега. Опыт дают:
##   explore — первый вход в модуль (кроме модуля-базы);
##   craft   — каждый предмет, собранный на верстаке;
##   lore    — каждая прочитанная за забег запись (эффект unlock_lore);
##   kill    — победа в бою (у врага можно задать своё "xp" в enemies.json).
## Сколько — data/config.json → "xp". Опыт до следующего уровня растёт:
## level_base + level_step × (уровень − 1). Новый уровень приносит
## skill_points_per_level очков навыков (CharacterSystem).
##
## Состояние забега: смерть обнуляет уровень, как и всё остальное в run.json.

## Опыт начислен: уровень и опыт уже новые; levels — сколько уровней взято.
signal xp_gained(amount: int, levels: int)
## Уровень и опыт выставлены без начисления (новый забег, загрузка сейва).
signal changed()

const CONFIG_PATH := "res://data/config.json"
const DEFAULT_CONFIG := {
	"explore": 10,
	"craft": 10,
	"lore": 15,
	"kill": 20,
	"level_base": 50,
	"level_step": 25,
	"skill_points_per_level": 1,
}

var level: int = 1
## Опыт внутри текущего уровня: 0 … xp_to_next() − 1.
var xp: int = 0

var _config: Dictionary = DEFAULT_CONFIG.duplicate()
## Записи, за которые в этом забеге уже дали опыт: id -> true.
var _lore_rewarded: Dictionary = {}


func _ready() -> void:
	_load_config()
	LocationSystem.location_entered.connect(_on_location_entered)
	CraftingSystem.crafted.connect(func(_recipe_id: String, _item_id: String) -> void: add_xp(reward("craft")))


func reset_for_new_run() -> void:
	level = 1
	xp = 0
	_lore_rewarded.clear()
	changed.emit()


func reward(kind: String) -> int:
	return maxi(0, int(_config.get(kind, 0)))


## Опыт за победу над врагом: его поле "xp" или общая награда kill.
func kill_reward(enemy: Dictionary) -> int:
	return maxi(0, int(enemy.get("xp", reward("kill"))))


func skill_points_per_level() -> int:
	return int(_config["skill_points_per_level"])


func xp_to_next(for_level: int = -1) -> int:
	if for_level < 1:
		for_level = level
	return maxi(1, int(_config["level_base"]) + int(_config["level_step"]) * (for_level - 1))


## Начисляет опыт; лишнее переходит в следующий уровень. Строка «[+10 опыта]»
## уходит в ленту, как и прочие изменения.
func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	var levels := 0
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		levels += 1
	EffectResolver.report_change("xp", amount, "опыта")
	xp_gained.emit(amount, levels)
	for i in range(levels):
		var reached := level - levels + i + 1
		var points := skill_points_per_level()
		NarrativeSystem.push("gain", "[Уровень %d · +%d очк. навыков]" % [reached, points])
		CharacterSystem.add_skill_points(points)


## Запись прочитана (unlock_lore). Архив переживает смерть, а опыт — нет:
## в новом забеге та же запись снова приносит опыт, но один раз.
func lore_read(fragment_id: String) -> void:
	if fragment_id == "" or _lore_rewarded.has(fragment_id):
		return
	_lore_rewarded[fragment_id] = true
	add_xp(reward("lore"))


func to_save_data() -> Dictionary:
	return {
		"level": level,
		"xp": xp,
		"lore_rewarded": _lore_rewarded.keys(),
	}


func load_save_data(data: Dictionary) -> void:
	level = maxi(1, int(data.get("level", 1)))
	xp = clampi(int(data.get("xp", 0)), 0, xp_to_next() - 1)
	_lore_rewarded.clear()
	var ids = data.get("lore_rewarded", [])
	if ids is Array:
		for id in ids:
			_lore_rewarded[str(id)] = true
	changed.emit()


## Первый вход в модуль — разведка. База (капсула) — дом, а не находка.
func _on_location_entered(location_id: String) -> void:
	if LocationSystem.get_visits(location_id) == 1 and not LocationSystem.is_base(location_id):
		add_xp(reward("explore"))


func _load_config() -> void:
	_config = DEFAULT_CONFIG.duplicate()
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not (parsed is Dictionary) or not (parsed.get("xp", {}) is Dictionary):
		return
	var section: Dictionary = parsed["xp"]
	for key in section.keys():
		if not DEFAULT_CONFIG.has(key):
			push_warning("ProgressionSystem: неизвестный ключ xp.%s в config.json" % key)
			continue
		_config[str(key)] = maxi(0, int(section[key]))
