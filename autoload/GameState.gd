extends Node
## Единственная система, знающая о переходах между экранами — см.
## tech-spec-v1.md раздел 10. Остальные системы только эмитят события и
## ничего не решают за пользовательский интерфейс.

signal screen_changed(screen: int)

enum Screen { MAIN_MENU, SECTOR_MAP, SITUATION, COMBAT, DEATH, LOCATION, VICTORY }

## Предохранитель от цепочек автособытий, зацикленных контентом.
const MAX_AUTO_EVENTS_PER_STEP := 32

var current_screen: int = Screen.MAIN_MENU
var last_death_cause: String = ""
var last_ending_id: String = ""
var has_left_capsule: bool = false

func _ready() -> void:
	EventBus.player_died.connect(_on_player_died)
	CombatSystem.combat_started.connect(_on_combat_started)
	CombatSystem.combat_ended.connect(_on_combat_ended)
	SituationEngine.situation_ended.connect(_on_situation_ended)


func start_new_game(sector_id: String = "", opening_situation_id: String = "") -> void:
	has_left_capsule = false
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
	var was_in_location := LocationSystem.is_active()
	LocationSystem.leave()
	if was_in_location:
		has_left_capsule = true
	_set_screen(Screen.SECTOR_MAP)

## Ручной запуск события из меню модуля. Действие стоит кислорода, а
## запертое событие-ящик требует подходящего ключа.
func start_location_event(event_id: String) -> void:
	if not LocationSystem.is_event_available(event_id):
		push_warning("GameState: событие '%s' сейчас недоступно" % event_id)
		return
	var ev := LocationSystem.find_event(event_id)
	var lock := LocationSystem.get_event_lock(ev)
	LocationSystem.clear_notices()
	if not lock.is_empty() and not EffectResolver.can_open_lock(lock):
		LocationSystem.add_notice(EffectResolver.lock_hint(lock))
		_show_location()
		return
	if not ResourceSystem.spend_o2("action"):
		return
	if not lock.is_empty():
		var key_name := EffectResolver.open_lock(lock)
		if key_name != "":
			LocationSystem.add_notice("Открыто ключом: %s." % key_name)
	if _run_event(ev):
		return
	_resume_location()


## Перепроверить автособытия и показать локацию заново (например после
## использования предмета из инвентаря).
func refresh_location() -> void:
	_resume_location()


## Ситуация без доступных опций — игрок нажал «Продолжить».
func finish_situation() -> void:
	_on_situation_ended(SituationEngine.current_id, "")


## Победное завершение забега (эффект end_run). Забег закончен: run.json и
## чекпойнт удаляются, итог уходит в meta — как и при смерти, но без отката.
func finish_run(ending_id: String) -> void:
	if not ChronicleSystem.has_ending(ending_id):
		push_error("GameState: неизвестный финал '%s'" % ending_id)
		return
	last_ending_id = ending_id
	last_death_cause = ""
	LocationSystem.leave()
	JournalSystem.add("victory", "Забег завершён: %s" % ChronicleSystem.get_ending_title(ending_id))
	ChronicleSystem.record_victory(ending_id)
	SaveManager.finish_run()
	_set_screen(Screen.VICTORY)


## Возврат в главное меню с экрана победы.
func go_to_main_menu() -> void:
	_set_screen(Screen.MAIN_MENU)


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
	var at_hub := LocationSystem.current_node_id != "" and LocationSystem.current_node_id == MapSystem.hub_node_id
	if at_hub or LocationSystem.is_base():
		EventBus.returned_to_hub.emit()  # хаб и любой модуль-база — точка чекпойнта
	_set_screen(Screen.LOCATION)


func _on_situation_ended(_id: String, next: String) -> void:
	if current_screen == Screen.DEATH or current_screen == Screen.VICTORY:
		return  # забег уже завершён эффектом end_run или смертью
	if CombatSystem.state == CombatSystem.State.PLAYER_TURN:
		return  # эффект start_combat уже переключил экран на бой
	if next == "":
		if LocationSystem.is_active():
			_resume_location()
		else:
			_set_screen(Screen.SECTOR_MAP)
		return
	if next.begins_with("map:"):
		if LocationSystem.is_active():
			LocationSystem.leave()
			has_left_capsule = true
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
		has_left_capsule = true
		_set_screen(Screen.SECTOR_MAP)




func _on_player_died(cause: String) -> void:
	last_death_cause = cause
	_set_screen(Screen.DEATH)


func to_save_data() -> Dictionary:
	return {"has_left_capsule": has_left_capsule}


func load_save_data(data: Dictionary) -> void:
	has_left_capsule = bool(data.get("has_left_capsule", false))

func _set_screen(screen: int) -> void:
	current_screen = screen
	SaveManager.autosave()  # карта и экран модуля — безопасные точки записи
	screen_changed.emit(screen)
