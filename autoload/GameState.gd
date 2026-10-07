extends Node
## Единственная система, знающая о переходах между экранами — см.
## tech-spec-v1.md раздел 10. Остальные системы только эмитят события и
## ничего не решают за пользовательский интерфейс.

signal screen_changed(screen: int)
## Такт исследования: номер, всего тактов, уже потрачено O2.
signal exploration_progressed(step: int, total: int, o2_spent: float)
## Поиск закончен (или прерван): плашку прогресса можно убирать.
signal exploration_finished

enum Screen { MAIN_MENU, SECTOR_MAP, SITUATION, COMBAT, DEATH, LOCATION, VICTORY, GALAXY_MAP, DIALOGUE }

## Предохранитель от цепочек автособытий, зацикленных контентом.
const MAX_AUTO_EVENTS_PER_STEP := 32
const EXPLORE_STEP_SECONDS := 0.5

var current_screen: int = Screen.MAIN_MENU
var last_death_cause: String = ""
## Смертельный удар в бою («Дрон попадает. Урон: 12.»); "" — погиб не от удара.
var last_death_blow: String = ""
var last_ending_id: String = ""
## Событие локации считается выполненным только после завершающего выбора.
var _active_location_event_id: String = ""
var _active_event_completes_on_win: bool = true
## Явный clear_image текущего события действует на всю цепочку его ситуаций.
var _active_event_clears_image: bool = false
var _exploring: bool = false
var _exploration_progress: Dictionary = {}

func _ready() -> void:
	EventBus.player_died.connect(_on_player_died)
	CombatSystem.combat_started.connect(_on_combat_started)
	CombatSystem.combat_ended.connect(_on_combat_ended)
	SituationEngine.situation_ended.connect(_on_situation_ended)
	DialogueSystem.dialogue_started.connect(_on_dialogue_started)
	DialogueSystem.dialogue_ended.connect(_on_dialogue_ended)
	GalaxySystem.arrived.connect(_on_galaxy_arrived)


func start_new_game(sector_id: String = "", opening_situation_id: String = "", origin_id: String = "") -> void:
	_active_location_event_id = ""
	_active_event_completes_on_win = true
	_active_event_clears_image = false
	_exploring = false
	_exploration_progress.clear()
	if sector_id == "":
		sector_id = SaveManager.get_start_sector_id()
	if opening_situation_id == "":
		opening_situation_id = SaveManager.get_opening_situation_id()
	SaveManager.start_new_run(origin_id)
	if not MapSystem.load_sector(sector_id):
		return
	if opening_situation_id != "":
		enter_situation(opening_situation_id)
	elif MapSystem.hub_node_id != "":
		# Вступление — автособытия локации хаба: игрок уже стоит в ней.
		MapSystem.travel_to(MapSystem.hub_node_id)
	else:
		_set_screen(Screen.SECTOR_MAP)

func continue_game(sector_id: String = "") -> void:
	_active_location_event_id = ""
	_active_event_completes_on_win = true
	_active_event_clears_image = false
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
	_active_location_event_id = ""
	_active_event_completes_on_win = true
	_active_event_clears_image = false
	if not LocationSystem.enter(location_id, node_id):
		return
	_resume_location()


## Выход из модуля на карту: маршрут, по которому игрок шёл, закончен.
func leave_location() -> void:
	LocationSystem.leave()
	_active_location_event_id = ""
	_active_event_clears_image = false
	NarrativeSystem.clear()
	MapSystem.cancel_travel()
	_set_screen(Screen.SECTOR_MAP)

## Ручной запуск события из меню модуля. Действие стоит кислорода, а
## запертое событие-ящик требует подходящего ключа.
func start_location_event(event_id: String) -> void:
	if not LocationSystem.is_event_available(event_id):
		push_warning("GameState: событие '%s' сейчас недоступно" % event_id)
		return
	var ev := LocationSystem.find_event(event_id)
	var lock := LocationSystem.get_event_lock(ev)
	if not lock.is_empty() and not EffectResolver.can_open_lock(lock):
		LocationSystem.add_notice(EffectResolver.lock_hint(lock))
		_show_location()
		return
	var cost := ResourceSystem.get_o2_cost("action")
	if not ResourceSystem.spend_o2("action"):
		return
	# Событие заменяет описание модуля в общем текстовом буфере.
	NarrativeSystem.clear()
	_push_location_backdrop(ev)
	NarrativeSystem.push("choice", str(ev.get("label", event_id)))
	EffectResolver.report_change("o2", -cost, "O2")
	if not lock.is_empty():
		var key_name := EffectResolver.open_lock(lock)
		if key_name != "":
			LocationSystem.add_notice("Открыто ключом: %s." % key_name)
	if _run_event(ev, false):
		return
	_resume_location()


## «Исследовать» в меню модуля: результат выбирается сразу, затем 2–5 тактов
## показывают поиск и по одному списывают O2. Длительность берётся из контента.
func explore_location() -> void:
	if _exploring:
		return
	if not LocationSystem.is_active() or not ExplorationSystem.can_explore():
		push_warning("GameState: в модуле нечего исследовать")
		return
	var plan := ExplorationSystem.prepare()
	if plan.is_empty():
		return
	var total := maxi(1, int(plan.get("steps", 1)))
	var spent := 0.0
	_exploring = true
	_exploration_progress = {"step": 0, "total": total, "o2_spent": spent}
	NarrativeSystem.clear()
	_push_location_backdrop()
	NarrativeSystem.push("choice", "Исследовать отсек")
	exploration_progressed.emit(0, total, spent)
	for step in range(1, total + 1):
		if SettingsSystem.animations:
			await get_tree().create_timer(EXPLORE_STEP_SECONDS).timeout
		var before := ResourceSystem.o2
		if not ResourceSystem.spend_o2("explore_tick", "", false):
			_finish_exploring()
			return
		spent += before - ResourceSystem.o2
		_exploration_progress = {"step": step, "total": total, "o2_spent": spent}
		exploration_progressed.emit(step, total, spent)
	if not ResourceSystem.finish_action("action"):
		_finish_exploring()
		return
	EffectResolver.report_change("o2", -spent, "O2")
	var journal_text := _exploration_journal_text(plan)
	ExplorationSystem.resolve(plan)
	JournalSystem.add("event", journal_text)
	_finish_exploring()
	if ResourceSystem.is_dead():
		return
	_resume_location()


func _finish_exploring() -> void:
	_exploring = false
	_exploration_progress.clear()
	exploration_finished.emit()

func _exploration_journal_text(plan: Dictionary) -> String:
	var location_title := LocationSystem.get_title()
	if str(plan.get("kind", "")) == "event":
		var ev := LocationSystem.find_event(str(plan.get("event_id", "")))
		var label := str(ev.get("label", plan.get("event_id", "")))
		return "Исследование: %s — найдено «%s»" % [location_title, label]
	if str(plan.get("kind", "")) == "pool":
		var entry: Dictionary = plan.get("entry", {})
		return "Исследование: %s — %s" % [location_title, str(entry.get("text", "находка"))]
	return "Исследование: %s" % location_title



func is_exploring() -> bool:
	return _exploring


func get_exploration_progress() -> Dictionary:
	return _exploration_progress.duplicate()


## Перепроверить автособытия и показать локацию заново (например после
## использования предмета из инвентаря).
func refresh_location() -> void:
	_resume_location()


## Сон на базе на 4 / 8 / 12 часов. Качество задаёт сама база; _show_location
## после отдыха записывает чекпойнт с новым временем и ресурсами.
func sleep(hours: int) -> void:
	if not LocationSystem.is_base():
		push_warning("GameState: спать можно только на базе")
		return
	if not [4, 8, 12].has(hours):
		push_warning("GameState: длительность сна должна быть 4, 8 или 12 часов")
		return
	NeedsSystem.sleep(hours, LocationSystem.get_sleep_quality())
	_show_location()


## Игрок нажал «Продолжить» под результатом выбора (или под ситуацией без
## вариантов) — только теперь ситуация заканчивается.
func finish_situation() -> void:
	SituationEngine.confirm_continue()


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


## Картинка модуля висит над лентой, пока событие не покажет свою (поле image)
## или не попросит убрать фон на всю цепочку (clear_image: true). Если картинку
## покажет ситуация, лента рисует только её (Game._render_story).
func _push_location_backdrop(ev: Dictionary = {}) -> void:
	var clears_image := _active_event_clears_image or bool(ev.get("clear_image", false))
	if not LocationSystem.is_active() or clears_image or str(ev.get("image", "")) != "":
		return
	var image := LocationSystem.get_image()
	if image != "":
		NarrativeSystem.push("backdrop", "", image)


## Возвращает true, если событие увело игрока с экрана локации
## (ситуация, бой, разговор или смерть).
func _run_event(ev: Dictionary, clear_narrative: bool = true) -> bool:
	LocationSystem.mark_started(ev)
	_active_location_event_id = str(ev.get("id", ""))
	_active_event_completes_on_win = true
	_active_event_clears_image = bool(ev.get("clear_image", false))
	if clear_narrative:
		NarrativeSystem.clear()
		_push_location_backdrop(ev)
	# Сначала текст события, потом его последствия: лента должна читаться сверху вниз.
	NarrativeSystem.push("text", str(ev.get("text", "")), str(ev.get("image", "")), str(ev.get("sound", "")))
	EffectResolver.apply_effects(ev.get("effects", []))
	if ResourceSystem.is_dead() or CombatSystem.state == CombatSystem.State.PLAYER_TURN or DialogueSystem.is_active():
		return true
	var situation_id := str(ev.get("situation", ""))
	if situation_id != "":
		enter_situation(situation_id)
		return current_screen == Screen.SITUATION
	_complete_active_location_event()
	return false


## Экран модуля — конец пути: игрок дошёл или его перехватили в отсеке.
func _show_location() -> void:
	MapSystem.cancel_travel()
	var at_hub := LocationSystem.current_node_id != "" and LocationSystem.current_node_id == MapSystem.hub_node_id
	if at_hub or LocationSystem.is_base():
		EventBus.returned_to_hub.emit()  # хаб и любой модуль-база — точка чекпойнта
	_set_screen(Screen.LOCATION)


func _on_situation_ended(_id: String, next: String, completes_event: bool) -> void:
	if current_screen == Screen.DEATH or current_screen == Screen.VICTORY:
		return  # забег уже завершён эффектом end_run или смертью
	if CombatSystem.state == CombatSystem.State.PLAYER_TURN:
		return  # эффект start_combat уже переключил экран на бой
	var continues_situation := next != "" and not next.begins_with("map:") and next != "galaxy"
	NarrativeSystem.clear()
	# Фон следующей ситуации выбирается до завершения события: clear_image
	# относится ко всей связанной цепочке, а не только к первому экрану.
	if continues_situation:
		_push_location_backdrop()
	if next == "" or next.begins_with("map:") or next == "galaxy":
		if completes_event:
			_complete_active_location_event()
		else:
			_active_location_event_id = ""
			_active_event_clears_image = false
	if next == "":
		if LocationSystem.is_active():
			LocationSystem.show_current_narrative()
			_resume_location()
		else:
			_set_screen(Screen.SECTOR_MAP)
		return
	if next == "galaxy":
		# Событие уводит на глобальную карту: корабль за штурвалом, курс выбирает игрок.
		if LocationSystem.is_active():
			LocationSystem.leave()
		_set_screen(Screen.GALAXY_MAP)
		EventBus.returned_to_hub.emit()
		return
	if next.begins_with("map:"):
		if LocationSystem.is_active():
			LocationSystem.leave()
		var sector_id := next.substr(4)
		if MapSystem.current_sector_id == sector_id:
			# Отступление: игрок не входит в отсек и возвращается туда, откуда пришёл.
			MapSystem.retreat()
			_set_screen(Screen.SECTOR_MAP)
			EventBus.returned_to_hub.emit()
		elif MapSystem.load_sector(sector_id):
			_set_screen(Screen.SECTOR_MAP)
			EventBus.returned_to_hub.emit()
	else:
		enter_situation(next)


## Глобальная карта открыта (кнопка HUD «Космос»).
func open_galaxy() -> void:
	if not GalaxySystem.has_ship():
		return
	_set_screen(Screen.GALAXY_MAP)


## Возврат с глобальной карты без перелёта: в модуль, где стоял игрок, иначе на карту.
func close_galaxy() -> void:
	if LocationSystem.is_active():
		_resume_location()
	else:
		_set_screen(Screen.SECTOR_MAP)


## Перелёт закончен: грузим сектор узла, корабль уже стоит в нём (GalaxySystem).
func _on_galaxy_arrived(node_id: String) -> void:
	var node := GalaxySystem.get_node_data(node_id)
	var sector_id := str(node.get("sector_id", ""))
	if sector_id == "":
		return
	if LocationSystem.is_active():
		LocationSystem.leave()
	NarrativeSystem.clear()
	if not MapSystem.load_sector(sector_id):
		_set_screen(Screen.GALAXY_MAP)
		return
	_set_screen(Screen.SECTOR_MAP)
	EventBus.returned_to_hub.emit()


## Разговор начался (эффект start_dialogue или кнопка в модуле).
func _on_dialogue_started(_npc_id: String, _npc_name: String) -> void:
	_set_screen(Screen.DIALOGUE)


## Разговор закончен: возвращаемся в модуль или на карту.
func _on_dialogue_ended(_npc_id: String, _dialogue_id: String) -> void:
	if current_screen != Screen.DIALOGUE:
		return
	if SituationEngine.awaiting_continue:
		_set_screen(Screen.SITUATION)
		return
	if LocationSystem.is_active():
		LocationSystem.show_current_narrative()
		_resume_location()
	else:
		_set_screen(Screen.SECTOR_MAP)


func _on_combat_started(_enemy_id: String) -> void:
	if current_screen == Screen.SITUATION and _active_location_event_id != "":
		_active_event_completes_on_win = SituationEngine.pending_choice_completes_event()
	_set_screen(Screen.COMBAT)


func _on_combat_ended(result: String) -> void:
	if result == "died":
		return  # экран смерти выставит _on_player_died через EventBus
	var stays_in_location := result == "won" and LocationSystem.is_active()
	if stays_in_location:
		# Лента модуля — до трофеев и on_win: их «[+1 …]» должны остаться под описанием.
		LocationSystem.show_current_narrative()
	if result == "won":
		EffectResolver.apply_effects(CombatSystem.loot_effects())  # лишнее — на пол модуля
		EffectResolver.apply_effects(CombatSystem.on_win_effects)
		if stays_in_location:
			LocationSystem.refresh_current_narrative()  # on_win мог сменить вариант модуля
	elif result == "fled":
		EffectResolver.apply_effects(CombatSystem.on_flee_effects)
	if ResourceSystem.is_dead():
		return
	if CombatSystem.clear_node_id != "":
		if result == "won":
			MapSystem.mark_cleared(CombatSystem.clear_node_id)
		elif result == "fled":
			MapSystem.set_node_state(CombatSystem.clear_node_id, "dangerous")
	if result == "won" and _active_event_completes_on_win:
		_complete_active_location_event()
	elif result == "fled":
		_active_location_event_id = ""
		_active_event_clears_image = false
	if stays_in_location:
		_resume_location()  # победа — игрок остаётся в модуле
		return
	NarrativeSystem.clear()
	LocationSystem.leave()
	# Побег посреди маршрута — прорыв: игрок идёт дальше. Иначе он отходит туда,
	# откуда пришёл, и мимо врага без боя не пройти.
	if not MapSystem.resume_travel_after_flee():
		MapSystem.retreat()
	_set_screen(Screen.SECTOR_MAP)

func _complete_active_location_event() -> void:
	if _active_location_event_id == "":
		return
	LocationSystem.mark_completed(_active_location_event_id)
	_active_location_event_id = ""
	_active_event_clears_image = false
	_active_event_completes_on_win = true



func _on_player_died(cause: String) -> void:
	last_death_cause = cause
	last_death_blow = CombatSystem.last_hit_on_player() \
		if cause == "hp" and current_screen == Screen.COMBAT else ""
	_active_location_event_id = ""
	_active_event_clears_image = false
	MapSystem.cancel_travel()
	_set_screen(Screen.DEATH)

func _set_screen(screen: int) -> void:
	current_screen = screen
	SaveManager.autosave()  # карта и экран модуля — безопасные точки записи
	screen_changed.emit(screen)
