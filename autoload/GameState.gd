extends Node
## Единственная система, знающая о переходах между экранами — см.
## tech-spec-v1.md раздел 10. Остальные системы только эмитят события и
## ничего не решают за пользовательский интерфейс.

signal screen_changed(screen: int)

enum Screen { MAIN_MENU, SECTOR_MAP, SITUATION, COMBAT, DEATH }

var current_screen: int = Screen.MAIN_MENU
var last_death_cause: String = ""


func _ready() -> void:
	EventBus.player_died.connect(_on_player_died)
	CombatSystem.combat_started.connect(_on_combat_started)
	CombatSystem.combat_ended.connect(_on_combat_ended)
	SituationEngine.situation_ended.connect(_on_situation_ended)


func start_new_game(sector_id: String = "", opening_situation_id: String = "") -> void:
	if sector_id == "":
		sector_id = SaveManager.get_start_sector_id()
	if opening_situation_id == "":
		opening_situation_id = SaveManager.get_opening_situation_id()
	SaveManager.start_new_run()
	if not MapSystem.load_sector(sector_id):
		return
	if opening_situation_id != "":
		enter_situation(opening_situation_id)
	else:
		_set_screen(Screen.SECTOR_MAP)


func continue_game(sector_id: String = "") -> void:
	if sector_id == "":
		sector_id = SaveManager.get_start_sector_id()
	if SaveManager.load_run(sector_id):
		_set_screen(Screen.SECTOR_MAP)
	else:
		start_new_game(sector_id)


func enter_situation(situation_id: String) -> void:
	if situation_id == "":
		push_warning("GameState: попытка войти в ситуацию с пустым id")
		return
	if SituationEngine.load_situation(situation_id):
		_set_screen(Screen.SITUATION)


func return_to_hub() -> void:
	EventBus.returned_to_hub.emit()
	_set_screen(Screen.SECTOR_MAP)


func choose_restart() -> void:
	SaveManager.confirm_restart()
	start_new_game()


func choose_rollback() -> void:
	SaveManager.confirm_rollback()
	_set_screen(Screen.SECTOR_MAP)


func _on_situation_ended(_id: String, next: String) -> void:
	if current_screen == Screen.DEATH:
		return
	if next == "":
		return  # экран переключит сама себя вызванная effect-цепочка (например start_combat)
	if next.begins_with("map:"):
		var sector_id := next.substr(4)
		var loaded := true
		if MapSystem.current_sector_id != sector_id:
			loaded = MapSystem.load_sector(sector_id)
		if loaded:
			_set_screen(Screen.SECTOR_MAP)
			EventBus.returned_to_hub.emit()
	else:
		enter_situation(next)


func _on_combat_started(_enemy_id: String) -> void:
	_set_screen(Screen.COMBAT)


func _on_combat_ended(result: String) -> void:
	if result == "died":
		return  # экран смерти выставит _on_player_died через EventBus
	if CombatSystem.clear_node_id != "":
		if result == "won":
			MapSystem.mark_cleared(CombatSystem.clear_node_id)
		elif result == "fled":
			MapSystem.set_node_state(CombatSystem.clear_node_id, "dangerous")
	_set_screen(Screen.SECTOR_MAP)


func _on_player_died(cause: String) -> void:
	last_death_cause = cause
	_set_screen(Screen.DEATH)


func _set_screen(screen: int) -> void:
	current_screen = screen
	if screen == Screen.SECTOR_MAP:
		# Защитное правило: карта не тратит O2 сама по себе — тикает только
		# внутри незагерметизированного узла (MapSystem.select_node включает
		# его явно). Без этого сбоя не будет, но так надёжнее.
		ResourceSystem.set_o2_ticking(false)
	screen_changed.emit(screen)
