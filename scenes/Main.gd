extends Node
## Консольный смоук-тест без UI: проходит вертикальный срез через системы
## напрямую — локации и события, бой, снаряжение, навыки, крафт, подбор
## предметов (в т. ч. при полной сумке), все три палубы, сохранение.
## Печатает шаги в Output, в конце — "SMOKE OK" или "SMOKE FAIL", код выхода 0/1.
## Запуск: F6 на Main.tscn или
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . res://scenes/Main.tscn
## ВНИМАНИЕ: перезаписывает run.json и checkpoint.json в user://.

const Screen = GameState.Screen

var _failures: Array = []


func _ready() -> void:
	seed(1)
	print("=== CosmoTextGame: смоук-тест ===")

	# --- Палуба 01: капсула ---
	GameState.start_new_game()
	_expect(GameState.current_screen == Screen.SITUATION and SituationEngine.current_id == "sit_1_1_capsule",
		"новая игра: автособытие пробуждения в капсуле")
	_expect(CharacterSystem.get_equipped("body") == "flight_suit" and CharacterSystem.get_stat("armor") == 1.0
		and CharacterSystem.skill_points == 1, "стартовое снаряжение и очки навыков из config")
	SituationEngine.select_option("C")
	_expect(SituationEngine.current_id == "sit_1_2_wreckage",
		"второе автособытие сработало по триггеру event_done")
	SituationEngine.select_option("B")
	_expect(GameState.current_screen == Screen.LOCATION and LocationSystem.current_id == "hub",
		"после вступления игрок на экране локации hub")
	_expect(not GameState.has_left_capsule, "карта и персонаж заблокированы внутри капсулы")
	_expect(MapSystem.is_node_explored("hub") and MapSystem.is_node_fog_visible("lift_01_to_02")
		and not MapSystem.is_node_fog_visible("cargo_bay"), "туман скрывает дальние отсеки")
	_expect(InventorySystem.has_item("broken_datapad"), "планшет в инвентаре")
	_expect(FileAccess.file_exists(SaveManager.CHECKPOINT_PATH), "в хабе записан чекпойнт")

	_expect(InventorySystem.get_interactions("broken_datapad").size() == 1, "у планшета есть взаимодействие «Прочитать»")
	InventorySystem.interact("broken_datapad", "read")
	_expect(ArchiveSystem.is_unlocked("log_01") and InventorySystem.get_interactions("broken_datapad").is_empty(),
		"взаимодействие открыло запись журнала и скрылось")
	_expect(not InventorySystem.drop_item("broken_datapad"), "сюжетный предмет нельзя выбросить")

	GameState.start_location_event("inspect_capsule")
	GameState.start_location_event("inspect_capsule")
	_expect(_has_manual("inspect_capsule") and LocationSystem.notices.size() == 1,
		"повторяемое ручное событие остаётся доступным")
	_expect(_has_manual("follow_signal"), "после вступления доступен сигнал скафандра")

	# --- Палуба 02: грузовой отсек ---
	GameState.leave_location()
	_expect(GameState.has_left_capsule and MapSystem.get_explored_floor_ids().has("deck_01"),
		"после выхода из капсулы открыты карта и персонаж")
	MapSystem.select_node("lift_01_to_02")
	_expect(MapSystem.current_floor_id == "deck_02", "лифт перевёз на палубу 02")

	MapSystem.select_node("cargo_bay")
	_expect(SituationEngine.current_id == "sit_1_3_drone", "вход в грузовой отсек запускает автособытие дрона")
	SituationEngine.select_option("B")
	_expect(GameState.current_screen == Screen.SECTOR_MAP and _node_state("cargo_bay") == "dangerous",
		"отступление: карта, узел опасен")

	MapSystem.select_node("cargo_bay")
	_expect(SituationEngine.current_id == "sit_1_3_drone" and GameState.current_screen == Screen.SITUATION,
		"повторяемое автособытие срабатывает при новом визите")
	ResourceSystem.apply_ammo_delta(10)  # чит для детерминированной победы
	SituationEngine.select_option("A")
	_expect(GameState.current_screen == Screen.COMBAT, "начат бой")
	CombatSystem.player_action("special", "distract_datapad")
	var rounds := _fight()
	_expect(GameState.current_screen == Screen.LOCATION and LocationSystem.current_id == "cargo_bay",
		"победа оставляет игрока в модуле (раундов: %d)" % rounds)
	_expect(_node_state("cargo_bay") == "cleared" and SituationEngine.get_flag("drone_cargo_down") == true,
		"узел пройден, on_win выставил флаг")
	_expect(CharacterSystem.skill_points == 2, "on_win выдал очко навыка")
	_expect(not _has_manual("force_shuttle_airlock"), "шлюз недоступен без трубы")

	GameState.start_location_event("search_containers")
	_expect(InventorySystem.count_item("duct_tape") == 2 and InventorySystem.count_item("cloth_rags") == 3
		and InventorySystem.count_item("scrap_metal") == 2 and InventorySystem.has_item("pipe_scrap"),
		"контейнеры обысканы (item_add с count)")
	_expect(InventorySystem.free_slots() == 0, "сумка заполнена: 6/6")
	_expect(not _has_manual("search_containers"), "одноразовое событие исчезло из меню")

	EffectResolver.apply_effect({"type": "item_add", "item": "ration_bar", "count": 2})
	_expect(int(LocationSystem.get_stash().get("ration_bar", 0)) == 2 and not InventorySystem.has_item("ration_bar")
		and _notice_contains("Не поместилось"), "полная сумка: лишнее осталось лежать в модуле")

	_expect(CharacterSystem.equip("pipe_scrap") == "" and CharacterSystem.get_stat("melee_damage") == 6.0,
		"труба надета в руки: +6 к ближнему бою")
	_expect(_has_manual("force_shuttle_airlock"), "надетая труба засчитывается в has_item")
	_expect(CraftingSystem.craft("plate_vest") != "", "жилет без Инженерии не крафтится")
	_expect(CraftingSystem.craft("makeshift_backpack") == "" and InventorySystem.count_item("cloth_rags") == 1,
		"рюкзак создан из ветоши и изоленты")
	_expect(CharacterSystem.equip("makeshift_backpack") == "" and InventorySystem.max_slots == 9,
		"рюкзак на спине: +3 слота сумки")
	_expect(LocationSystem.stash_take("ration_bar") == 2 and LocationSystem.get_stash().is_empty()
		and InventorySystem.count_item("ration_bar") == 2, "брикеты подняты с пола")
	_expect(InventorySystem.drop_item("cloth_rags") and int(LocationSystem.get_stash().get("cloth_rags", 0)) == 1,
		"выброшенный в модуле предмет остался лежать на полу")
	_expect(CharacterSystem.learn("engineering") and CharacterSystem.skill_points == 1, "изучена Инженерия")
	_expect(CraftingSystem.craft("plate_vest") == "", "с Инженерией жилет крафтится")
	_expect(CharacterSystem.equip("plate_vest") == "" and CharacterSystem.get_stat("armor") == 3.0
		and InventorySystem.has_item("flight_suit"), "жилет надет, комбинезон ушёл в сумку")
	_expect(CharacterSystem.unequip("arms") == "" and CharacterSystem.get_stat("melee_damage") == 0.0
		and InventorySystem.has_item("pipe_scrap"), "труба снята в сумку")
	CharacterSystem.equip("pipe_scrap")

	GameState.start_location_event("force_shuttle_airlock")
	_expect(_node_state("alien_shuttle") == "available", "ручное событие открыло закрытый шлюз")

	GameState.leave_location()
	MapSystem.select_node("cargo_bay")
	_expect(GameState.current_screen == Screen.LOCATION and LocationSystem.get_visits() == 3
		and int(LocationSystem.get_stash().get("cloth_rags", 0)) == 1,
		"возврат в пройденный модуль без повторного боя, вещи на полу на месте")

	# --- Шаттл: выбор одного из двух ---
	GameState.leave_location()
	MapSystem.select_node("alien_shuttle")
	_expect(LocationSystem.current_id == "alien_shuttle", "открытый модуль доступен")
	GameState.start_location_event("search_cockpit")
	_expect(CharacterSystem.equip("mag_boots") == "" and is_equal_approx(CharacterSystem.get_stat("flee_chance"), 0.15),
		"ботинки надеты: шанс побега +15%")
	var ammo_before := ResourceSystem.ammo
	GameState.start_location_event("open_locker")
	_expect(SituationEngine.current_id == "sit_2_2_locker", "оружейный шкаф: ситуация выбора")
	SituationEngine.select_option("A")
	_expect(InventorySystem.has_item("service_pistol") and ResourceSystem.ammo == ammo_before + 6
		and not InventorySystem.has_item("o2_canister") and not _has_manual("open_locker"),
		"взят пистолет и патроны, баллоны остались в запертом шкафу")
	_expect(CharacterSystem.learn("survival") and ResourceSystem.max_hp == 110, "Выживание: макс. HP 110")

	# --- Палуба 01: тело второго пилота ---
	GameState.leave_location()
	MapSystem.select_node("lift_02_to_01")
	MapSystem.select_node("hub")
	GameState.start_location_event("follow_signal")
	_expect(_node_state("copilot_body") == "available", "событие в хабе открыло узел пилота")
	GameState.leave_location()
	MapSystem.select_node("copilot_body")
	_expect(LocationSystem.current_id == "copilot_body" and _notice_contains("Метка скафандра"),
		"первое посещение: автосообщение")
	GameState.start_location_event("take_helmet")
	_expect(CharacterSystem.equip("cracked_helmet") == "" and CharacterSystem.get_stat("armor") == 4.0,
		"шлем надет: броня 4")
	GameState.start_location_event("search_pockets")
	_expect(InventorySystem.has_item("pilot_keycard") and InventorySystem.count_item("ration_bar") == 4,
		"подсумки: ключ-карта и брикеты в стак")
	_expect(MapSystem.map_revealed and InventorySystem.has_item("ship_map"), "найдена схема — туман карты снят")
	GameState.start_location_event("read_tag")
	_expect(ArchiveSystem.is_unlocked("log_02"), "бирка: запись журнала")
	GameState.start_location_event("take_canister")
	_expect(SituationEngine.current_id == "sit_2_1_canister" and _has_option("A"),
		"баллон: вариант с трубой доступен, раз труба есть")
	SituationEngine.select_option("A")
	_expect(InventorySystem.has_item("o2_canister") and ResourceSystem.hp == ResourceSystem.hp
		and not _has_manual("take_canister") and LocationSystem.get_description().contains("уже забрал"),
		"баллон снят без потери HP, описание модуля сменилось")

	# --- Палуба 03: коридор и реактор ---
	GameState.leave_location()
	MapSystem.select_node("lift_01_to_02")
	MapSystem.select_node("lift_02_to_03")
	MapSystem.select_node("service_corridor")
	_expect(LocationSystem.current_id == "service_corridor" and ResourceSystem.o2_ticking,
		"коридор без давления: O2 тратится")
	GameState.start_location_event("open_emergency_locker")
	_expect(InventorySystem.count_item("o2_canister") == 3, "шкаф открыт навыком Инженерии")
	GameState.start_location_event("clear_rubble")
	_expect(_node_state("reactor") == "available", "завал разобран трубой — реактор открыт")

	GameState.leave_location()
	MapSystem.select_node("reactor")
	_expect(not _has_manual("extract_cell"), "без ключ-карты ячейку не достать")
	GameState.start_location_event("use_keycard")
	_expect(not InventorySystem.has_item("pilot_keycard") and SituationEngine.get_flag("reactor_unlocked") == true,
		"ключ-карта израсходована, дверь открыта")
	GameState.start_location_event("read_reactor_log")
	_expect(ArchiveSystem.is_unlocked("log_03"), "журнал реактора прочитан")
	GameState.start_location_event("extract_cell")
	SituationEngine.select_option("A")
	_expect(InventorySystem.has_item("power_cell") and SituationEngine.current_id == "sit_3_2_strain",
		"ячейка взята — автособытие Штамма сработало сразу")
	SituationEngine.select_option("B")
	_expect(GameState.current_screen == Screen.SECTOR_MAP and _node_state("reactor") == "dangerous", "побег от Штамма")

	_expect(CharacterSystem.equip("service_pistol") == "" and InventorySystem.has_item("pipe_scrap"),
		"пистолет надет вместо трубы")
	MapSystem.select_node("reactor")
	_expect(SituationEngine.current_id == "sit_3_2_strain", "Штамм ждёт при повторном входе")
	SituationEngine.select_option("A")
	rounds = _fight()
	_expect(GameState.current_screen == Screen.LOCATION and SituationEngine.get_flag("strain_down") == true
		and _node_state("reactor") == "cleared", "Штамм побеждён (раундов: %d, HP: %d)" % [rounds, ResourceSystem.hp])

	# --- Сохранение ---
	SaveManager.save_run()
	SaveManager.load_run()
	_expect(LocationSystem.is_event_done("cargo_bay/search_containers") and LocationSystem.get_visits("cargo_bay") == 3,
		"состояние событий и визитов переживает сохранение")
	_expect(CharacterSystem.get_equipped("back") == "makeshift_backpack" and InventorySystem.max_slots == 9
		and ResourceSystem.max_hp == 110 and CharacterSystem.get_skill_level("engineering") == 1,
		"снаряжение, навыки и бонусы переживают сохранение")
	_expect(int(LocationSystem.get_stash("cargo_bay").get("cloth_rags", 0)) == 1, "вещи на полу переживают сохранение")
	_expect(MapSystem.map_revealed and MapSystem.is_node_explored("reactor")
		and GameState.has_left_capsule, "туман и прогресс выхода переживают сохранение")
	_expect(NotificationSystem.has_character_alert() and NotificationSystem.has_new_lore(),
		"уведомления персонажа и журнала переживают сохранение")

	if _failures.is_empty():
		print("SMOKE OK")
	else:
		print("SMOKE FAIL: %d проверок не прошло" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _fight() -> int:
	var rounds := 0
	while CombatSystem.state == CombatSystem.State.PLAYER_TURN and rounds < 40:
		CombatSystem.player_action("attack")
		rounds += 1
	return rounds


func _expect(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		_failures.append(label)


func _has_manual(event_id: String) -> bool:
	for ev in LocationSystem.get_manual_events():
		if str(ev.get("id", "")) == event_id:
			return true
	return false


func _has_option(option_id: String) -> bool:
	for opt in SituationEngine.get_available_options():
		if str(opt.get("id", "")) == option_id:
			return true
	return false


func _notice_contains(fragment: String) -> bool:
	for notice in LocationSystem.notices:
		if str(notice).contains(fragment):
			return true
	return false


func _node_state(node_id: String) -> String:
	return str(MapSystem.nodes.get(node_id, {}).get("state", ""))
