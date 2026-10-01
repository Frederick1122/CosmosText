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
	# Чистый старт: meta переживает забеги, а тест проверяет в том числе первое
	# открытие лора — иначе прошлый прогон делал бы результат недетерминированным.
	_delete_save(SaveManager.RUN_PATH)
	_delete_save(SaveManager.CHECKPOINT_PATH)
	_delete_save(SaveManager.META_PATH)
	ArchiveSystem.load_save_data([])

	# --- Палуба 01: капсула ---
	GameState.start_new_game()
	_expect(GameState.current_screen == Screen.SITUATION and SituationEngine.current_id == "sit_1_1_capsule",
		"новая игра: автособытие пробуждения в капсуле")
	_expect(CharacterSystem.get_equipped("body") == "flight_suit" and CharacterSystem.get_stat("armor") == 1.0
		and CharacterSystem.skill_points == 1, "стартовое снаряжение и очки навыков из config")
	_expect(SituationEngine.awaiting_continue == false, "до выбора ситуация не ждёт «Продолжить»")
	SituationEngine.select_option("C")
	_expect(SituationEngine.awaiting_continue and GameState.current_screen == Screen.SITUATION
		and _narrative_kind_last("result") != "", "после выбора показан результат и ждём «Продолжить»")
	GameState.finish_situation()
	_expect(SituationEngine.current_id == "sit_1_2_wreckage"
		and _narrative_count("result") == 0 and _narrative_count("text") == 1,
		"следующее событие очистило текст предыдущего")
	_choose("B")
	_expect(GameState.current_screen == Screen.LOCATION and LocationSystem.current_id == "hub",
		"после вступления игрок на экране локации hub")
	_expect(_narrative_count("scene") == 1 and _narrative_count("text") == 1
		and _narrative_count("choice") == 0 and _narrative_count("result") == 0,
		"после «Продолжить» событие заменено описанием локации")
	_expect(QuestSystem.is_step_done("escape_persephone", "leave_capsule") and not QuestSystem.is_completed("escape_persephone")
		and NotificationSystem.has_journal_alert() and QuestSystem.get_thoughts().contains("ничего не помню"),
		"цели: побег с обломка начат, первый шаг засчитан, мысли о пробуждении, (!) у журнала")
	var escape: Dictionary = QuestSystem.get_quests()[0]
	_expect(escape["steps"].size() == 2 and bool(escape["steps"][1]["current"]),
		"видны засчитанные шаги и один текущий, дальше цель не раскрывается")
	_expect(MapSystem.get_known_floor_ids() == ["deck_01"] and MapSystem.player_node_id == "hub",
		"игрок стоит в капсуле, палубы за лифтом на карте не видны")
	_expect(MapSystem.is_node_explored("hub") and MapSystem.is_node_fog_visible("lift_01_to_02")
		and not MapSystem.is_node_fog_visible("cargo_bay"), "туман скрывает дальние отсеки")
	_expect(not MapSystem.is_node_fog_visible("copilot_body"),
		"неоткрытая действием локация полностью скрыта")
	_expect(InventorySystem.has_item("broken_datapad"), "планшет в инвентаре")
	_expect(FileAccess.file_exists(SaveManager.CHECKPOINT_PATH), "в хабе записан чекпойнт")

	_expect(InventorySystem.get_interactions("broken_datapad").size() == 1, "у планшета есть взаимодействие «Прочитать»")
	InventorySystem.interact("broken_datapad", "read")
	_expect(ArchiveSystem.is_unlocked("log_01") and InventorySystem.get_interactions("broken_datapad").is_empty(),
		"взаимодействие открыло запись журнала и скрылось")
	_expect(not InventorySystem.drop_item("broken_datapad"), "сюжетный предмет нельзя выбросить")
	_expect(ProgressionSystem.level == 1 and ProgressionSystem.xp == ProgressionSystem.reward("lore"),
		"прочитанная запись дала опыт, вход в базу — нет (опыт: %d)" % ProgressionSystem.xp)
	EffectResolver.apply_effect({"type": "unlock_lore", "id": "log_01"})
	_expect(ProgressionSystem.xp == ProgressionSystem.reward("lore"), "повторно та же запись опыта не даёт")

	GameState.start_location_event("inspect_capsule")
	GameState.start_location_event("inspect_capsule")
	_expect(_has_manual("inspect_capsule") and _narrative_count("scene") == 0
		and _narrative_count("choice") == 1 and _narrative_count("text") == 1,
		"новое событие очистило описание модуля и предыдущее событие")
	_expect(_has_manual("follow_signal"), "после вступления доступен сигнал скафандра")

	# --- База: склад, верстак, ручной чекпойнт ---
	_expect(LocationSystem.is_base(), "капсула помечена как модуль-база")
	_expect(LocationSystem.get_image() == "base_bay" and ResourceLoader.exists("res://assets/art/scenes/base_bay.png"),
		"у базы есть пиксельная иллюстрация")
	var o2_before_decline := ResourceSystem.o2
	_expect(not _has_manual("search_supply_kit") and ExplorationSystem.can_explore(),
		"аварийный контейнер спрятан: его находят кнопкой «Исследовать»")
	ExplorationSystem.reveal("search_supply_kit")
	_expect(_has_manual("search_supply_kit") and _narrative_kind_last("notice").contains("Найдено"),
		"найденное событие появилось в меню модуля")
	GameState.start_location_event("search_supply_kit")
	_choose("C")
	_expect(_has_manual("search_supply_kit") and not LocationSystem.is_event_done("search_supply_kit"),
		"отложенный аварийный набор остаётся доступным")
	ResourceSystem.apply_o2_delta(o2_before_decline - ResourceSystem.o2)
	GameState.start_location_event("search_supply_kit")
	_choose("A")
	_expect(InventorySystem.has_item("ration_bar") and InventorySystem.has_item("improvised_bandage"),
		"аварийный набор вскрыт")
	_expect(InventorySystem.drop_item("ration_bar")
		and int(LocationSystem.get_stash().get("ration_bar", 0)) == 1,
		"лишнее выложено на склад базы")
	_expect(LocationSystem.stash_take("ration_bar") == 1 and InventorySystem.has_item("ration_bar"),
		"со склада можно забрать обратно")
	InventorySystem.remove_item("ration_bar")
	InventorySystem.remove_item("improvised_bandage")

	# --- Дни, силы и голод ---
	_expect(is_zero_approx(ResourceSystem.get_o2_cost("action")) and is_equal_approx(ResourceSystem.o2, o2_before_decline),
		"в капсуле есть воздух: действия на базе кислорода не тратят")
	_expect(NeedsSystem.energy < NeedsSystem.max_energy() and NeedsSystem.hunger > 0.0,
		"действия отнимают силы и копят голод")
	var hunger_before_sleep := NeedsSystem.hunger
	_delete_save(SaveManager.CHECKPOINT_PATH)
	GameState.end_day()
	_expect(NeedsSystem.day == 2 and is_equal_approx(NeedsSystem.energy, NeedsSystem.max_energy())
		and NeedsSystem.hunger > hunger_before_sleep and FileAccess.file_exists(SaveManager.CHECKPOINT_PATH)
		and GameState.current_screen == Screen.LOCATION,
		"сон на базе: новый день, силы восстановлены, голод вырос, чекпойнт записан")
	InventorySystem.add_item("ration_bar")
	var hunger_before_meal := NeedsSystem.hunger
	InventorySystem.use_item("ration_bar")
	_expect(NeedsSystem.hunger < hunger_before_meal and _narrative_kind_last("gain").contains("голода"),
		"брикет утоляет голод, в ленте зелёная строка")

	# --- Палуба 02: грузовой отсек ---
	GameState.leave_location()
	_expect(GameState.current_screen == Screen.SECTOR_MAP and MapSystem.player_node_id == "hub",
		"после выхода из модуля игрок стоит в его узле на карте")
	MapSystem.travel_to("lift_01_to_02")
	_expect(MapSystem.current_floor_id == "deck_02" and MapSystem.player_node_id == "lift_02_to_01"
		and MapSystem.get_known_floor_ids() == ["deck_01", "deck_02"],
		"лифт перевёз на палубу 02, она появилась на карте")

	var xp_before_explore := ProgressionSystem.xp
	MapSystem.travel_to("cargo_bay")
	_expect(ProgressionSystem.xp == xp_before_explore + ProgressionSystem.reward("explore"),
		"первый вход в модуль — опыт за разведку")
	_expect(SituationEngine.current_id == "sit_1_3_drone", "вход в грузовой отсек запускает автособытие дрона")
	_choose("B")
	_expect(GameState.current_screen == Screen.SECTOR_MAP and _node_state("cargo_bay") == "dangerous"
		and MapSystem.player_node_id == "lift_02_to_01",
		"отступление: карта, узел опасен, игрок вернулся к лифту")

	var route := MapSystem.plan_route("lift_02_to_03")
	_expect(bool(route["ok"]) and route["path"] == ["cargo_bay", "lift_02_to_03", "lift_03_to_02"]
		and is_equal_approx(float(route["cost"]),
			ResourceSystem.get_o2_cost("move", "cargo_bay") + ResourceSystem.get_o2_cost("elevator", "lift_02_to_03")),
		"маршрут к нижнему лифту идёт через грузовой отсек, цена — переход и поездка")
	MapSystem.travel_to("lift_02_to_03")
	_expect(SituationEngine.current_id == "sit_1_3_drone" and GameState.current_screen == Screen.SITUATION
		and MapSystem.player_node_id == "cargo_bay" and not MapSystem.is_travelling(),
		"дрон перехватывает игрока в пути через грузовой отсек")
	ResourceSystem.apply_ammo_delta(10)  # патроны есть, а пистолета ещё нет
	_choose("A")
	_expect(GameState.current_screen == Screen.COMBAT, "начат бой")
	_expect(CombatSystem.range_steps == 2, "бой начинается с дистанции врага (2 шага)")
	_expect(not _combat_move_enabled("strike"), "вплотную не ударить: удар доступен только на дистанции ≤ 1")
	_expect(not _combat_move_enabled("shoot") and _combat_move_reason("shoot") == "Нет огнестрела в руках",
		"без огнестрела в руках не выстрелить, даже с патронами")
	CombatSystem.player_action("approach")
	_expect(CombatSystem.range_steps <= 2 and _combat_move_enabled("strike"),
		"сближение подпускает дрона на дистанцию удара (шагов: %d)" % CombatSystem.range_steps)
	CombatSystem.player_action("grab")
	_expect(_combat_move_enabled("throw") and not _has_combat_move("grab"),
		"подобранный обломок можно бросить")
	var enemy_hp_before_throw := CombatSystem.enemy_hp
	CombatSystem.player_action("throw")
	var throw_hit := CombatSystem.enemy_hp == enemy_hp_before_throw - CombatSystem.THROW_DAMAGE
	_expect(_has_combat_move("grab") and throw_hit == CombatSystem.get_state()["enemy_conditions"].has("Потерял цель"),
		"бросок: попадание ранит и сбивает с толку, обломок израсходован (попал: %s)" % throw_hit)
	ResourceSystem.apply_hp_delta(-30)
	InventorySystem.add_item("improvised_bandage")
	CombatSystem.player_action("use_item", "improvised_bandage")
	_expect(_combat_log_has_heal(15) and not InventorySystem.has_item("improvised_bandage"),
		"расходник в бою: лечение в журнале и в эффектах карточки")
	ResourceSystem.apply_hp_delta(30)
	var xp_level_before_fight := ProgressionSystem.level
	var xp_before_fight := ProgressionSystem.xp
	var rounds := _fight()
	_expect(GameState.current_screen == Screen.LOCATION and LocationSystem.current_id == "cargo_bay",
		"победа оставляет игрока в модуле (раундов: %d)" % rounds)
	_expect(_node_state("cargo_bay") == "cleared" and SituationEngine.get_flag("drone_cargo_down") == true,
		"узел пройден, on_win выставил флаг")
	_expect(QuestSystem.is_step_done("escape_persephone", "cargo_drone") and _notice_contains("[✓ Пробиться через грузовой отсек"),
		"победа над дроном засчитала шаг цели и показала его в ленте")
	_expect(_notice_contains("[+1 Металлолом]"),
		"трофей боя показан в ленте модуля строкой в скобках")
	_expect(int(CombatSystem.reward.get("xp", 0)) == 25 and int(CombatSystem.reward.get("level_before", 0)) == xp_level_before_fight
		and int(CombatSystem.reward.get("xp_before", -1)) == xp_before_fight and CombatSystem.reward.get("loot", []) == ["scrap_metal"],
		"награда за победу: опыт врага и трофеи для экрана победы")
	_expect(ProgressionSystem.level == 2 and CharacterSystem.skill_points == 3,
		"опыт за дрона дал 2-й уровень: +1 очко навыков к очку от on_win")
	_expect(LocationSystem.get_image() == "cargo_drone_down"
		and str(NarrativeSystem.get_entries()[0].get("image", "")) == "cargo_drone_down"
		and _notice_contains("[+1 Металлолом]"),
		"после победы у отсека другая картинка уже в ленте, трофей под ней")
	NotificationSystem.mark_character_seen()
	_expect(NotificationSystem.has_character_alert() and NotificationSystem.unspent_skill_points() == 3,
		"неистраченные очки навыков держат уведомление и после просмотра персонажа")
	_expect(not _has_manual("force_shuttle_airlock"), "шлюз недоступен без трубы")

	ExplorationSystem.reveal("search_containers")
	GameState.start_location_event("search_containers")
	_expect(InventorySystem.count_item("duct_tape") == 2 and InventorySystem.count_item("cloth_rags") == 3
		and InventorySystem.count_item("scrap_metal") == 2 and InventorySystem.has_item("pipe_scrap"),
		"контейнеры обысканы (item_add с count)")
	_expect(InventorySystem.free_slots() == 1 and InventorySystem.has_item("broken_datapad"),
		"сумка 5/6: планшет — инфо-предмет и места не занимает")
	_expect(not _has_manual("search_containers"), "одноразовое событие исчезло из меню")

	InventorySystem.add_item("improvised_bandage")  # последний слот — сумка полна
	EffectResolver.apply_effect({"type": "item_add", "item": "ration_bar", "count": 2})
	_expect(int(LocationSystem.get_stash().get("ration_bar", 0)) == 2 and not InventorySystem.has_item("ration_bar")
		and _notice_contains("Не поместилось"), "полная сумка: лишнее осталось лежать в модуле")
	InventorySystem.remove_item("improvised_bandage")
	var hp_before_hurt := ResourceSystem.hp
	EffectResolver.apply_effect({"type": "hp_delta", "value": -5})
	_expect(_narrative_kind_last("loss") == "[−5 HP]", "урон из эффекта показан в ленте: [−5 HP]")
	var heal_room := ResourceSystem.max_hp - ResourceSystem.hp
	EffectResolver.apply_effect({"type": "hp_delta", "value": heal_room + 50})
	_expect(_narrative_kind_last("gain") == "[+%d HP]" % heal_room,
		"лечение показывает фактический прирост, а не запрошенный")
	ResourceSystem.apply_hp_delta(hp_before_hurt - ResourceSystem.hp)

	_expect(CharacterSystem.equip("pipe_scrap") == "" and CharacterSystem.get_stat("melee_damage") == 6.0,
		"труба надета в руки: +6 к ближнему бою")
	_expect(_has_manual("force_shuttle_airlock"), "надетая труба засчитывается в has_item")
	_expect(CraftingSystem.craft("plate_vest") != "", "жилет без Инженерии не крафтится")
	var xp_before_craft := ProgressionSystem.xp
	_expect(CraftingSystem.craft("makeshift_backpack") == "" and InventorySystem.count_item("cloth_rags") == 1,
		"рюкзак создан из ветоши и изоленты")
	_expect(ProgressionSystem.xp == xp_before_craft + ProgressionSystem.reward("craft"), "крафт дал опыт")
	_expect(CharacterSystem.equip("makeshift_backpack") == "" and InventorySystem.max_slots == 9,
		"рюкзак на спине: +3 слота сумки")
	_expect(LocationSystem.stash_take("ration_bar") == 2 and LocationSystem.get_stash().is_empty()
		and InventorySystem.count_item("ration_bar") == 2, "брикеты подняты с пола")
	_expect(InventorySystem.drop_item("cloth_rags") and int(LocationSystem.get_stash().get("cloth_rags", 0)) == 1,
		"выброшенный в модуле предмет остался лежать на полу")
	var points_before_learn := CharacterSystem.skill_points
	_expect(CharacterSystem.learn("engineering") and CharacterSystem.skill_points == points_before_learn - 1, "изучена Инженерия")
	_expect(CraftingSystem.craft("plate_vest") == "", "с Инженерией жилет крафтится")
	_expect(CharacterSystem.equip("plate_vest") == "" and CharacterSystem.get_stat("armor") == 3.0
		and InventorySystem.has_item("flight_suit"), "жилет надет, комбинезон ушёл в сумку")
	_expect(CharacterSystem.unequip("arms") == "" and CharacterSystem.get_stat("melee_damage") == 0.0
		and InventorySystem.has_item("pipe_scrap"), "труба снята в сумку")
	CharacterSystem.equip("pipe_scrap")

	_expect(not MapSystem.is_node_fog_visible("alien_shuttle"),
		"не найденный шаттл скрыт даже рядом с грузовым отсеком")
	GameState.start_location_event("force_shuttle_airlock")
	_expect(_node_state("alien_shuttle") == "available"
		and MapSystem.is_node_fog_visible("alien_shuttle")
		and _notice_contains("[Открыта новая локация \"Чужой шаттл\"]"),
		"действие показало шаттл и выделило открытие")

	GameState.leave_location()
	MapSystem.travel_to("cargo_bay")
	_expect(GameState.current_screen == Screen.LOCATION and LocationSystem.get_visits() == 3
		and int(LocationSystem.get_stash().get("cloth_rags", 0)) == 1,
		"возврат в пройденный модуль без повторного боя, вещи на полу на месте")

	# --- Ключи: техотсек за служебной панелью ---
	GameState.leave_location()
	_expect(_node_state("maintenance_bay") == "locked" and not MapSystem.can_unlock_node("maintenance_bay"),
		"техотсек заперт, ключа нет")
	MapSystem.travel_to("maintenance_bay")
	_expect(GameState.current_screen == Screen.SECTOR_MAP and _node_state("maintenance_bay") == "locked",
		"без ключа запертый узел не открывается")
	MapSystem.travel_to("cargo_bay")
	ExplorationSystem.reveal("search_forklift")
	GameState.start_location_event("search_forklift")
	_choose("B")
	_expect(InventorySystem.has_item("hex_key") and InventorySystem.free_slots() > 0,
		"шестигранник найден под погрузчиком и не занимает слот сумки")
	_expect(not InventorySystem.drop_item("hex_key"), "ключ нельзя выбросить")
	ExplorationSystem.reveal("open_rigger_locker")
	_expect(_has_manual("open_rigger_locker") and LocationSystem.is_event_locked(LocationSystem.find_event("open_rigger_locker")),
		"рундук такелажника виден в меню, но заперт")
	GameState.start_location_event("open_rigger_locker")
	_expect(not LocationSystem.is_event_done("open_rigger_locker") and _notice_contains("Заперто"),
		"попытка вскрыть рундук без ключа только сообщает о замке")

	GameState.leave_location()
	_expect(MapSystem.can_unlock_node("maintenance_bay"), "с шестигранником узел подсвечен как открываемый")
	MapSystem.travel_to("maintenance_bay")
	_expect(LocationSystem.current_id == "maintenance_bay" and _node_state("maintenance_bay") == "available"
		and InventorySystem.has_item("hex_key"), "ключ открыл служебную панель и не израсходовался")
	GameState.start_location_event("open_tool_crate")
	_expect(InventorySystem.has_item("cargo_key") and InventorySystem.has_item("hex_key"),
		"инструментальный ящик открыт тем же ключом, внутри магнитный ключ")
	ExplorationSystem.reveal("read_repair_log")
	GameState.start_location_event("read_repair_log")
	_expect(ArchiveSystem.is_unlocked("log_07"), "журнал ремонтов прочитан")
	# Находки техотсека — на пол ниши: дальше по срезу сумка нужна свободной.
	for surplus in ["scrap_metal", "scrap_metal", "duct_tape", "cloth_rags", "improvised_bandage"]:
		InventorySystem.drop_item(surplus)
	_expect(int(LocationSystem.get_stash().get("scrap_metal", 0)) == 2,
		"лишние находки сложены на полу техотсека")

	GameState.leave_location()
	MapSystem.travel_to("cargo_bay")
	var ammo_in_locker := ResourceSystem.ammo
	GameState.start_location_event("open_rigger_locker")
	_expect(ResourceSystem.ammo == ammo_in_locker + 6 and not InventorySystem.has_item("cargo_key"),
		"рундук вскрыт магнитным ключом, ключ выгорел")
	for surplus in ["stim_shot", "duct_tape"]:
		InventorySystem.drop_item(surplus)

	# --- Шаттл: выбор одного из двух ---
	GameState.leave_location()
	MapSystem.travel_to("alien_shuttle")
	_expect(LocationSystem.current_id == "alien_shuttle", "открытый модуль доступен")
	ExplorationSystem.reveal("search_cockpit")
	GameState.start_location_event("search_cockpit")
	_expect(CharacterSystem.equip("mag_boots") == "" and is_equal_approx(CharacterSystem.get_stat("flee_chance"), 0.15),
		"ботинки надеты: шанс побега +15%")
	var ammo_before := ResourceSystem.ammo
	var canisters_before := InventorySystem.count_item("o2_canister")
	GameState.start_location_event("open_locker")
	_expect(SituationEngine.current_id == "sit_2_2_locker", "оружейный шкаф: ситуация выбора")
	_choose("A")
	_expect(InventorySystem.has_item("service_pistol") and ResourceSystem.ammo == ammo_before + 6
		and InventorySystem.count_item("o2_canister") == canisters_before and not _has_manual("open_locker"),
		"взят пистолет и патроны, баллоны остались в запертом шкафу")
	_expect(CharacterSystem.learn("survival") and ResourceSystem.max_hp == 110, "Выживание: макс. HP 110")

	# --- Палуба 01: тело второго пилота ---
	GameState.leave_location()
	MapSystem.travel_to("lift_02_to_01")
	MapSystem.travel_to("hub")
	GameState.start_location_event("follow_signal")
	_expect(_node_state("copilot_body") == "available"
		and MapSystem.is_node_fog_visible("copilot_body")
		and _notice_contains("[Открыта новая локация \"Тело второго пилота\"]"),
		"событие показало узел пилота и выделило открытие")
	GameState.leave_location()
	MapSystem.travel_to("copilot_body")
	_expect(LocationSystem.current_id == "copilot_body" and _notice_contains("Метка скафандра"),
		"первое посещение: автосообщение")
	GameState.start_location_event("take_helmet")
	_expect(CharacterSystem.equip("cracked_helmet") == "" and CharacterSystem.get_stat("armor") == 4.0,
		"шлем надет: броня 4")
	GameState.start_location_event("search_pockets")
	_expect(InventorySystem.has_item("pilot_keycard") and InventorySystem.count_item("ration_bar") == 4,
		"подсумки: ключ-карта и брикеты в стак")
	_expect(MapSystem.map_revealed and InventorySystem.has_item("ship_map"), "найдена схема — туман карты снят")
	ExplorationSystem.reveal("read_tag")
	GameState.start_location_event("read_tag")
	_expect(ArchiveSystem.is_unlocked("log_02"), "бирка: запись журнала")
	GameState.start_location_event("take_canister")
	_expect(SituationEngine.current_id == "sit_2_1_canister" and _has_option("A"),
		"баллон: вариант с трубой доступен, раз труба есть")
	_choose("A")
	_expect(InventorySystem.has_item("o2_canister") and ResourceSystem.hp == ResourceSystem.hp
		and not _has_manual("take_canister") and LocationSystem.get_description().contains("уже забрал"),
		"баллон снят без потери HP, описание модуля сменилось")

	# --- Палуба 03: коридор и реактор ---
	GameState.leave_location()
	MapSystem.travel_to("hub")
	GameState.end_day()  # выспаться перед спуском: иначе вырубится по дороге к реактору
	GameState.leave_location()
	MapSystem.travel_to("lift_01_to_02")
	MapSystem.travel_to("lift_02_to_03")
	var o2_before_move := ResourceSystem.o2
	MapSystem.travel_to("service_corridor")
	var unsealed_move_cost: float = float(ResourceSystem.o2_costs["move"]) * ResourceSystem.o2_unsealed_multiplier
	_expect(LocationSystem.current_id == "service_corridor"
		and is_equal_approx(o2_before_move - ResourceSystem.o2, unsealed_move_cost),
		"переход в коридор без давления стоит двойной цены (%.0f)" % unsealed_move_cost)
	var o2_before_action := ResourceSystem.o2
	GameState.start_location_event("open_emergency_locker")
	_expect(InventorySystem.count_item("o2_canister") == 4,
		"шкаф открыт навыком Инженерии (баллонов: %d, O2: %d)" % [InventorySystem.count_item("o2_canister"), int(ResourceSystem.o2)])
	_expect(o2_before_action - ResourceSystem.o2 >= float(ResourceSystem.o2_costs["action"]),
		"ручное событие тратит кислород")
	var o2_before_item := ResourceSystem.o2
	InventorySystem.use_item("o2_canister")
	_expect(ResourceSystem.o2 > o2_before_item and InventorySystem.count_item("o2_canister") == 3,
		"баллон восполняет кислород и сам его не тратит")
	GameState.start_location_event("clear_rubble")
	_expect(_node_state("reactor") == "available", "завал разобран трубой — реактор открыт")

	GameState.leave_location()
	o2_before_move = ResourceSystem.o2
	MapSystem.travel_to("reactor")
	_expect(LocationSystem.current_id == "reactor"
		and is_equal_approx(o2_before_move - ResourceSystem.o2, float(ResourceSystem.o2_costs["move"])),
		"реакторный отсек за гермодверью — переход по базовой цене")
	_expect(not _has_manual("extract_cell"), "без ключ-карты ячейку не достать")
	GameState.start_location_event("use_keycard")
	_expect(not InventorySystem.has_item("pilot_keycard") and SituationEngine.get_flag("reactor_unlocked") == true,
		"ключ-карта израсходована, дверь открыта")
	ExplorationSystem.reveal("read_reactor_log")
	GameState.start_location_event("read_reactor_log")
	_expect(ArchiveSystem.is_unlocked("log_03"), "журнал реактора прочитан")
	# Выдыхаем запас баллонов: место в сумке нужно под энергоячейку.
	while InventorySystem.has_item("o2_canister"):
		InventorySystem.use_item("o2_canister")
	GameState.start_location_event("extract_cell")
	_choose("A")
	_expect(InventorySystem.has_item("power_cell") and SituationEngine.current_id == "sit_3_2_strain",
		"ячейка взята — автособытие Штамма сработало сразу (сумка %d/%d: %s)" % [InventorySystem.used_slots(), InventorySystem.max_slots, str(InventorySystem.get_slots())])
	_choose("B")
	_expect(GameState.current_screen == Screen.SECTOR_MAP and _node_state("reactor") == "dangerous"
		and MapSystem.player_node_id == "service_corridor", "побег от Штамма: игрок отошёл в коридор")

	_expect(CharacterSystem.equip("service_pistol") == "" and InventorySystem.has_item("pipe_scrap"),
		"пистолет надет вместо трубы")
	MapSystem.travel_to("reactor")
	_expect(SituationEngine.current_id == "sit_3_2_strain", "Штамм ждёт при повторном входе")
	_choose("A")
	rounds = _fight()
	_expect(GameState.current_screen == Screen.LOCATION and SituationEngine.get_flag("strain_down") == true
		and _node_state("reactor") == "cleared", "Штамм побеждён (раундов: %d, HP: %d)" % [rounds, ResourceSystem.hp])

	# --- Сохранение ---
	var progression_before_save := ProgressionSystem.to_save_data()
	var quests_before_save := QuestSystem.to_save_data()
	SaveManager.save_run()
	SaveManager.load_run()
	_expect(ProgressionSystem.to_save_data() == progression_before_save and ProgressionSystem.level >= 2,
		"уровень и опыт переживают сохранение (уровень %d, опыт %d)" % [ProgressionSystem.level, ProgressionSystem.xp])
	_expect(QuestSystem.to_save_data() == quests_before_save, "цели и засчитанные шаги переживают сохранение")
	_expect(LocationSystem.is_event_done("cargo_bay/search_containers") and LocationSystem.get_visits("cargo_bay") == 5,
		"состояние событий и визитов переживает сохранение (визитов: %d)" % LocationSystem.get_visits("cargo_bay"))
	_expect(CharacterSystem.get_equipped("back") == "makeshift_backpack" and InventorySystem.max_slots == 9
		and ResourceSystem.max_hp == 110 and CharacterSystem.get_skill_level("engineering") == 1,
		"снаряжение, навыки и бонусы переживают сохранение")
	_expect(int(LocationSystem.get_stash("cargo_bay").get("cloth_rags", 0)) == 1, "вещи на полу переживают сохранение")
	_expect(MapSystem.map_revealed and MapSystem.is_node_explored("reactor")
		and MapSystem.player_node_id == "reactor" and MapSystem.get_known_floor_ids().size() == 3,
		"туман, палубы и место игрока переживают сохранение")
	_expect(NotificationSystem.has_character_alert() and NotificationSystem.has_new_lore(),
		"уведомления персонажа и журнала переживают сохранение")
	_expect(_journal_has("Переход: Грузовой отсек") and _journal_has("Победа в бою.")
		and JournalSystem.entry_count() > 10, "журнал забега переживает сохранение")

	# --- Надёжность сейвов ---
	_expect(int(_read_save(SaveManager.RUN_PATH).get("version", 0)) == SaveManager.SAVE_VERSION,
		"в сейв записана версия формата")
	_expect(not FileAccess.file_exists(SaveManager.RUN_PATH + ".tmp"),
		"после записи не остаётся временного файла")
	_expect(FileAccess.file_exists(SaveManager.META_PATH) and _read_save(SaveManager.META_PATH).get("archive", []).has("log_01"),
		"лор попал в meta.json сразу, без смерти")

	_write_save(SaveManager.RUN_PATH, "{\"version\": 1, \"resources\"")  # обрыв записи
	_expect(not SaveManager.load_run(), "обрезанный сейв не загружается")
	_write_save(SaveManager.RUN_PATH, JSON.stringify({"version": SaveManager.SAVE_VERSION + 1}))
	_expect(not SaveManager.load_run(), "сейв новее игры не загружается")
	SaveManager.save_run()
	_expect(SaveManager.load_run(), "после перезаписи сейв снова читается")

	# Автосохранение: бой — не точка записи, экран модуля — точка.
	MapSystem.travel_to("service_corridor")
	_expect(GameState.current_screen == Screen.LOCATION and LocationSystem.current_id == "service_corridor",
		"после загрузки сейва игрок снова входит в коридор")
	_delete_save(SaveManager.RUN_PATH)
	CombatSystem.start_combat("drone_cargo")
	SaveManager.autosave()
	_expect(not FileAccess.file_exists(SaveManager.RUN_PATH), "в бою автосохранения нет")
	CombatSystem.reset_for_new_run()
	GameState.refresh_location()
	_expect(FileAccess.file_exists(SaveManager.RUN_PATH), "экран модуля — точка автосохранения")

	_delete_save(SaveManager.RUN_PATH)
	_delete_save(SaveManager.META_PATH)
	SaveManager.notification(NOTIFICATION_APPLICATION_PAUSED)  # сворачивание приложения
	_expect(FileAccess.file_exists(SaveManager.RUN_PATH) and FileAccess.file_exists(SaveManager.META_PATH),
		"сворачивание приложения сохраняет забег и meta")

	# --- Перелёт на «Вехтер-9» ---
	GameState.leave_location()
	MapSystem.travel_to("lift_03_to_02")
	MapSystem.travel_to("alien_shuttle")
	_expect(LocationSystem.current_id == "alien_shuttle" and _has_manual("install_power_cell"),
		"с энергоячейкой в шаттле доступна установка")
	GameState.start_location_event("install_power_cell")
	_expect(SituationEngine.current_id == "sit_3_4_departure", "ситуация отлёта открыта")
	_choose("B")
	_expect(LocationSystem.current_id == "alien_shuttle" and InventorySystem.has_item("power_cell")
		and _has_manual("install_power_cell"), "отказ от старта возвращает в шаттл, ячейка цела")
	GameState.start_location_event("install_power_cell")
	_choose("A")
	_expect(MapSystem.current_sector_id == "wreck_02" and GameState.current_screen == Screen.SECTOR_MAP
		and not InventorySystem.has_item("power_cell"), "прыжок выполнен: сектор wreck_02, ячейка израсходована")
	_expect(FileAccess.file_exists(SaveManager.CHECKPOINT_PATH), "переход между секторами пишет чекпойнт")
	_expect(QuestSystem.is_completed("escape_persephone") and not QuestSystem.is_completed("call_for_help")
		and QuestSystem.get_quests().any(func(q: Dictionary) -> bool: return q["id"] == "call_for_help")
		and QuestSystem.get_thoughts().contains("позади"),
		"улетели: побег выполнен, началась цель «Позвать помощь», мысли сменились")

	# --- «Вехтер-9»: стыковка, каюты, медблок ---
	MapSystem.travel_to("dock_bay")
	_expect(LocationSystem.current_id == "dock_bay" and ArchiveSystem.is_unlocked("log_04")
		and SituationEngine.get_flag("docked_wechter") == true, "прибытие: автособытие и запись журнала")
	GameState.leave_location()
	MapSystem.travel_to("crew_quarters")
	while InventorySystem.has_item("ration_bar"):
		InventorySystem.use_item("ration_bar")
	var day_before_quarters := NeedsSystem.day
	GameState.end_day()
	_expect(LocationSystem.is_base() and NeedsSystem.day == day_before_quarters + 1
		and is_equal_approx(NeedsSystem.energy, NeedsSystem.max_energy()) and not NeedsSystem.is_hungry(),
		"каюты смены — вторая база: поели и выспались на станции")
	ExplorationSystem.reveal("search_bunks")
	GameState.start_location_event("search_bunks")
	_expect(InventorySystem.has_item("medkit"), "в каютах найдена аптечка")
	ResourceSystem.apply_hp_delta(-mini(40, ResourceSystem.hp - 1))
	var hp_before := ResourceSystem.hp
	while InventorySystem.has_item("medkit"):
		InventorySystem.use_item("medkit")
	_expect(ResourceSystem.hp > hp_before and InventorySystem.free_slots() > 0,
		"аптечки вылечили и освободили слот под находку")
	ExplorationSystem.reveal("pry_locker")
	GameState.start_location_event("pry_locker")
	_expect(SituationEngine.current_id == "sit_4_1_locker" and _has_option("A") and _has_option("B"),
		"шкафчик старшего смены: выбор карты или патронов")
	_choose("A")
	_expect(InventorySystem.has_item("station_keycard") and not _has_manual("pry_locker"),
		"взята карта доступа, шкафчик больше не вскрыть")
	GameState.start_location_event("use_station_keycard")
	_expect(_node_state("med_bay") == "available" and not InventorySystem.has_item("station_keycard"),
		"карта открыла медблок и израсходована")
	GameState.leave_location()
	MapSystem.travel_to("med_bay")
	ExplorationSystem.reveal("read_med_log")
	ExplorationSystem.reveal("tap_medical_o2")
	GameState.start_location_event("read_med_log")
	_expect(ArchiveSystem.is_unlocked("log_05"), "карта пациента прочитана")
	_expect(_has_manual("tap_medical_o2"), "с Инженерией доступна медицинская линия O2")
	var o2_before := ResourceSystem.o2
	GameState.start_location_event("tap_medical_o2")
	_expect(ResourceSystem.o2 > o2_before, "кислород из медицинской линии получен")

	# --- «Вехтер-9»: турель и маяк ---
	GameState.leave_location()
	MapSystem.travel_to("lift_a_to_b")
	_expect(MapSystem.current_floor_id == "ring_b", "лифт поднял на антенный ярус")
	MapSystem.travel_to("comms_hall")
	_expect(SituationEngine.current_id == "sit_4_2_sentry" and not MapSystem.is_node_sealed("comms_hall"),
		"зал связи без давления: турель и удвоенная цена действий")
	_choose("A")
	_expect(GameState.current_screen == Screen.COMBAT, "бой с турелью начат")
	var o2_before_turn := ResourceSystem.o2
	CombatSystem.player_action("special", "jam_optics")
	_expect(is_equal_approx(o2_before_turn - ResourceSystem.o2,
		float(ResourceSystem.o2_costs["combat_turn"]) * ResourceSystem.o2_unsealed_multiplier),
		"ход в бою тратит кислород по цене отсека")
	rounds = _fight()
	_expect(SituationEngine.get_flag("sentry_down") == true and _node_state("comms_hall") == "cleared",
		"турель уничтожена (раундов: %d, HP: %d)" % [rounds, ResourceSystem.hp])
	var o2_in_hall := ResourceSystem.o2
	ExplorationSystem.reveal("emergency_bottle")
	GameState.start_location_event("emergency_bottle")
	_expect(ResourceSystem.o2 >= o2_in_hall + 90.0 - ResourceSystem.get_o2_cost("action"),
		"аварийный баллон пополнил кислород в зале связи")
	_expect(not MapSystem.is_node_fog_visible("antenna_mast"),
		"мачта скрыта до ремонта консоли")
	GameState.start_location_event("patch_console")
	_expect(_node_state("antenna_mast") == "available"
		and MapSystem.is_node_fog_visible("antenna_mast")
		and _notice_contains("[Открыта новая локация \"Мачта дальней связи\"]"),
		"консоль показала мачту и выделила открытие")
	GameState.leave_location()
	MapSystem.travel_to("antenna_mast")
	GameState.start_location_event("align_dish")
	_expect(SituationEngine.current_id == "sit_4_3_beacon", "на мачте открыт выбор адресата")
	_choose("A")
	_expect(SituationEngine.get_flag("beacon_online") == true and str(SituationEngine.get_flag("beacon_target")) == "colony"
		and not _has_manual("align_dish"), "маяк запущен на колонию, повторно не включить")
	GameState.start_location_event("read_mast_log")
	_expect(ArchiveSystem.is_unlocked("log_06"), "журнал последнего сеанса прочитан")

	SaveManager.save_run()
	SaveManager.load_run()
	_expect(MapSystem.current_sector_id == "wreck_02" and MapSystem.current_floor_id == "ring_b"
		and _node_state("med_bay") == "available" and SituationEngine.get_flag("beacon_online") == true,
		"второй сектор и его прогресс переживают сохранение")

	# --- Финал забега ---
	var victories_before := ChronicleSystem.victories
	MapSystem.travel_to("lift_b_to_a")
	MapSystem.travel_to("dock_bay")
	_expect(_has_manual("rescue_dock"), "после маяка в доке можно открыть шлюз")
	GameState.start_location_event("rescue_dock")
	_expect(SituationEngine.current_id == "sit_4_4_rescue" and _has_option("A") and not _has_option("B"),
		"спасатели: доступен только тот корабль, которого звал маяк")
	_choose("C")
	_expect(GameState.current_screen == Screen.LOCATION and _has_manual("rescue_dock"),
		"отказ открыть шлюз оставляет игрока на станции")
	GameState.start_location_event("rescue_dock")
	_choose("A")
	_expect(GameState.current_screen == Screen.VICTORY and GameState.last_ending_id == "rescue_colony",
		"забег завершён финалом «спасены колонией» (остаток O2: %d)" % int(ResourceSystem.o2))
	_expect(ChronicleSystem.victories == victories_before + 1 and ChronicleSystem.is_ending_seen("rescue_colony"),
		"победа записана в хронику")
	_expect(not FileAccess.file_exists(SaveManager.RUN_PATH) and not FileAccess.file_exists(SaveManager.CHECKPOINT_PATH),
		"после победы забег нельзя продолжить")
	_expect(_read_save(SaveManager.META_PATH).get("chronicle", {}).get("victories", 0) == victories_before + 1,
		"хроника сохранена в meta.json")
	SaveManager.load_meta()
	_expect(ChronicleSystem.victories == victories_before + 1 and ChronicleSystem.endings_total() == 2,
		"хроника и справочник финалов переживают перезагрузку meta")

	# --- Кислород: смерть от удушья ---
	var entries_before := JournalSystem.entry_count()
	ResourceSystem.apply_o2_delta(1.0 - ResourceSystem.o2)  # в баллоне остаётся 1 единица
	MapSystem.travel_to("dock_bay")
	_expect(GameState.current_screen == Screen.DEATH and not LocationSystem.is_active()
		and GameState.last_death_cause == "o2",
		"переход без кислорода убивает и не пускает в модуль")
	_expect(JournalSystem.entry_count() == entries_before + 1 and _journal_has("Смерть: закончился кислород."),
		"смерть от удушья записана в журнал")

	# --- Прорыв: побег из боя посреди маршрута ---
	GameState.choose_restart()
	_choose("C")
	_choose("B")
	_expect(ExplorationSystem.total("hub") == 2 and not _has_manual("search_supply_kit"),
		"в капсуле два поиска: спрятанный контейнер и одна случайная находка")
	GameState.explore_location()
	GameState.explore_location()
	_expect(_has_manual("search_supply_kit") and ExplorationSystem.remaining("hub") == 0 and not ExplorationSystem.can_explore()
		and _narrative_kind_last("choice") == "Исследовать отсек",
		"исследование нашло контейнер и разыграло находку; больше искать нечего")
	GameState.leave_location()
	MapSystem.travel_to("lift_01_to_02")
	MapSystem.travel_to("lift_02_to_03")
	_expect(SituationEngine.current_id == "sit_1_3_drone" and MapSystem.player_node_id == "cargo_bay",
		"новый забег: дрон перехватывает на пути к нижнему лифту")
	_choose("A")
	var flee_tries := 0
	while CombatSystem.state == CombatSystem.State.PLAYER_TURN and flee_tries < 20:
		CombatSystem.player_action("flee")
		flee_tries += 1
	CombatSystem.finish()
	_expect(GameState.current_screen == Screen.SECTOR_MAP and MapSystem.is_travelling(),
		"побег посреди маршрута — путь продолжается (попыток: %d)" % flee_tries)
	while MapSystem.is_travelling():
		MapSystem.travel_step()
	_expect(MapSystem.current_floor_id == "deck_03" and MapSystem.player_node_id == "lift_03_to_02"
		and _node_state("cargo_bay") == "dangerous", "прорыв: игрок за дроном, на палубе 03")

	# --- Путь не прерывают события без боя; силы и голод на исходе ---
	_expect(bool(LocationSystem.peek("service_corridor", true)["auto"])
		and not bool(LocationSystem.peek("service_corridor", true)["combat"])
		and bool(LocationSystem.peek("cargo_bay", true)["combat"]),
		"по пути останавливает только бой: предупреждение в коридоре подождёт входа")
	NeedsSystem.energy = 1.0
	var o2_before_faint := ResourceSystem.o2
	var move_cost := ResourceSystem.get_o2_cost("move", "service_corridor")
	MapSystem.travel_to("service_corridor")
	_expect(is_equal_approx(NeedsSystem.energy, 30.0) and _journal_has("Обморок от усталости")
		and is_equal_approx(o2_before_faint - ResourceSystem.o2, move_cost + 30.0),
		"силы на нуле: обморок стоит кислорода, игрок приходит в себя с запасом сил")
	NeedsSystem.hunger = NeedsSystem.max_hunger()
	var hp_before_starving := ResourceSystem.hp
	ResourceSystem.spend_o2("action")
	_expect(ResourceSystem.hp == hp_before_starving - 3 and _narrative_kind_last("loss").contains("голод"),
		"голод на максимуме: каждое действие отнимает здоровье")

	# --- Исследование: пул без спрятанных событий и навык «Поиск» ---
	_expect(LocationSystem.current_id == "service_corridor" and ExplorationSystem.remaining("service_corridor") == 2,
		"в коридоре два случайных поиска")
	GameState.explore_location()
	GameState.explore_location()
	_expect(ExplorationSystem.remaining("service_corridor") == 0 and not ExplorationSystem.can_explore(),
		"поиски в коридоре кончились")
	CharacterSystem.add_skill_points(1)
	_expect(CharacterSystem.learn("scavenging") and ExplorationSystem.remaining("service_corridor") == 1
		and ExplorationSystem.can_explore(), "навык «Поиск» добавляет поиск в каждом отсеке")

	if _failures.is_empty():
		print("SMOKE OK")
	else:
		print("SMOKE FAIL: %d проверок не прошло" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


## Простейшая боевая тактика для теста: стрелять, если есть патроны, иначе
## сначала сблизиться, потом бить. Решённая схватка держит экран боя до
## «Продолжить» (CombatSystem.finish).
func _fight() -> int:
	var rounds := 0
	while CombatSystem.state == CombatSystem.State.PLAYER_TURN and rounds < 40:
		CombatSystem.player_action(_best_move())
		rounds += 1
	_expect(GameState.current_screen == Screen.COMBAT and CombatSystem.outcome == "won",
		"победа не уводит с экрана боя до «Продолжить»")
	CombatSystem.finish()
	return rounds


func _best_move() -> String:
	if _combat_move_enabled("shoot"):
		return "shoot"
	if CombatSystem.range_steps > CombatSystem.MELEE_RANGE:
		return "approach"
	return "strike"


func _combat_move_reason(move_id: String) -> String:
	for move in CombatSystem.get_available_moves():
		if str(move.get("id", "")) == move_id:
			return str(move.get("reason", ""))
	return ""


func _combat_move_enabled(move_id: String) -> bool:
	for move in CombatSystem.get_available_moves():
		if str(move.get("id", "")) == move_id:
			return bool(move.get("enabled", false))
	return false


func _has_combat_move(move_id: String) -> bool:
	for move in CombatSystem.get_available_moves():
		if str(move.get("id", "")) == move_id:
			return true
	return false


## В журнале текущего хода есть лечение игрока на amount.
func _combat_log_has_heal(amount: int) -> bool:
	for entry in CombatSystem.log:
		if int(entry.get("turn", -1)) != CombatSystem.turn:
			continue
		for fx in entry.get("fx", []):
			if str(fx.get("style", "")) == "heal" and int(fx.get("amount", 0)) == amount:
				return true
	return false

func _expect(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		_failures.append(label)


func _has_manual(event_id: String) -> bool:
	for ev in LocationSystem.get_manual_events():
		if str(ev.get("id", "")) == event_id:
			return true
	return false


func _journal_has(fragment: String) -> bool:
	for entry in JournalSystem.get_entries():
		if str(entry.get("text", "")).contains(fragment):
			return true
	return false


func _has_option(option_id: String) -> bool:
	for opt in SituationEngine.get_available_options():
		if str(opt.get("id", "")) == option_id:
			return true
	return false


## Выбор в ситуации: применяем вариант и подтверждаем «Продолжить», как игрок.
func _choose(option_id: String) -> void:
	SituationEngine.select_option(option_id)
	if SituationEngine.awaiting_continue:
		GameState.finish_situation()


func _notice_contains(fragment: String) -> bool:
	for entry in NarrativeSystem.get_entries():
		if str(entry.get("text", "")).contains(fragment):
			return true
	return false


## Текст последней записи ленты указанного типа ("" — такой записи нет).
func _narrative_kind_last(kind: String) -> String:
	var entries := NarrativeSystem.get_entries()
	for i in range(entries.size() - 1, -1, -1):
		if str(entries[i].get("kind", "")) == kind:
			return str(entries[i].get("text", ""))
	return ""


func _narrative_count(kind: String) -> int:
	var count := 0
	for entry in NarrativeSystem.get_entries():
		if str(entry.get("kind", "")) == kind:
			count += 1
	return count


func _node_state(node_id: String) -> String:
	return str(MapSystem.nodes.get(node_id, {}).get("state", ""))


func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _write_save(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)


func _delete_save(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
