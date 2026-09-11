extends Node
## Единственная система, знающая о переходах между экранами — см.
## tech-spec-v1.md раздел 10. Остальные системы только эмитят события и
## ничего не решают за пользовательский интерфейс.

signal screen_changed(screen: int)

enum Screen { MAIN_MENU, SECTOR_MAP, SITUATION, COMBAT, DEATH, LOCATION }

## Предохранитель от цепочек автособытий, зацикленных контентом.
const MAX_AUTO_EVENTS_PER_STEP := 32

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
	elif MapSystem.hub_node_id != "":
		# Вступление — автособытия локации хаба.
		MapSystem.select_node(MapSystem.hub_node_id)
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


func enter_location(location_id: String, node_id: String = "") -> void:
	if not LocationSystem.enter(location_id, node_id):
		return
	_resume_location()


func leave_location() -> void:
	LocationSystem.leave()
	_set_screen(Screen.SECTOR_MAP)


## Ручной запуск события из меню модуля.
func start_location_event(event_id: String) -> void:
	if not LocationSystem.is_event_available(event_id):
		push_warning("GameState: событие '%s' сейчас недоступно" % event_id)
		return
	LocationSystem.clear_notices()
	if _run_event(LocationSystem.find_event(event_id)):
		return
	_resume_location()


## Перепроверить автособытия и показать локацию заново (например после
## использования предмета из инвентаря).
func refresh_location() -> void:
	_resume_location()


## Ситуация без доступных опций — игрок нажал «Продолжить».
func finish_situation() -> void:
	_on_situation_ended(SituationEngine.current_id, "")


func choose_restart() -> void:
	SaveManager.confirm_restart()
	start_new_game()


func choose_rollback() -> void:
	SaveManager.confirm_rollback()
	_set_screen(Screen.SECTOR_MAP)


## Запускает подходящие автособытия текущей локации; если ни одно не увело
## игрока с экрана локации — показывает её.
func _resume_location() -> void:
	if not LocationSystem.is_active():
		_set_screen(Screen.SECTOR_MAP)
		return
	for i in range(MAX_AUTO_EVENTS_PER_STEP):
		var ev: Dictionary = LocationSystem.next_auto_event()
		if ev.is_empty():
			break
		if _run_event(ev):
			return
	_show_location()


## Возвращает true, если событие увело игрока с экрана локации
## (ситуация, бой или смерть).
func _run_event(ev: Dictionary) -> bool:
	LocationSystem.mark_started(ev)
	EffectResolver.apply_effects(ev.get("effects", []))
	LocationSystem.add_notice(str(ev.get("text", "")))
	if ResourceSystem.is_dead() or CombatSystem.state == CombatSystem.State.PLAYER_TURN:
		return true
	var situation_id := str(ev.get("situation", ""))
	if situation_id != "":
		enter_situation(situation_id)
		return current_screen == Screen.SITUATION
	return false


func _show_location() -> void:
	if LocationSystem.current_node_id != "" and LocationSystem.current_node_id == MapSystem.hub_node_id:
		EventBus.returned_to_hub.emit()  # хаб — точка чекпойнта
	_set_screen(Screen.LOCATION)


func _on_situation_ended(_id: String, next: String) -> void:
	if current_screen == Screen.DEATH:
		return
	if CombatSystem.state == CombatSystem.State.PLAYER_TURN:
		return  # эффект start_combat уже переключил экран на бой
	if next == "":
		if LocationSystem.is_active():
			_resume_location()
		else:
			_set_screen(Screen.SECTOR_MAP)
		return
	if next.begins_with("map:"):
		LocationSystem.leave()
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
	if result == "won":
		EffectResolver.apply_effects(CombatSystem.on_win_effects)
	elif result == "fled":
		EffectResolver.apply_effects(CombatSystem.on_flee_effects)
	if ResourceSystem.is_dead():
		return
	if CombatSystem.clear_node_id != "":
		if result == "won":
			MapSystem.mark_cleared(CombatSystem.clear_node_id)
		elif result == "fled":
			MapSystem.set_node_state(CombatSystem.clear_node_id, "dangerous")
	if result == "won" and LocationSystem.is_active():
		_resume_location()  # победа — игрок остаётся в модуле
	else:
		LocationSystem.leave()  # побег — выход на карту
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
