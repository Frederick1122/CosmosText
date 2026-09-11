extends Node
## Временная сцена без UI — печатает состояние систем в консоль (Output),
## чтобы можно было проверить, что автозагрузки и данные подключены верно,
## ещё до появления настоящего интерфейса. Замени на реальный UI-флоу позже.


func _ready() -> void:
	print("=== CosmoTextGame: смоук-тест автозагрузок ===")
	GameState.start_new_game("wreck_01")
	print("Экран: ", GameState.current_screen, " (0=меню,1=карта,2=ситуация,3=бой,4=смерть)")

	print("--- Идём в грузовой отсек ---")
	MapSystem.select_node("cargo_bay")
	print("Ситуация: ", SituationEngine.get_current_text())
	for opt in SituationEngine.get_available_options():
		print(" - [%s] %s" % [opt.get("id"), opt.get("label")])

	print("--- Выбираем бой (A) ---")
	SituationEngine.select_option("A")
	print("Экран: ", GameState.current_screen, " | Бой начат с: ", CombatSystem.enemy_id)
	print("HP игрока=%d, HP врага=%d" % [ResourceSystem.hp, CombatSystem.enemy_hp])

	print("--- Атакуем до конца боя (в лимите 20 раундов) ---")
	var rounds := 0
	while CombatSystem.state == CombatSystem.State.PLAYER_TURN and rounds < 20:
		CombatSystem.player_action("attack")
		rounds += 1
	print("Бой завершён за %d раундов(а). HP игрока=%d, HP врага=%d" % [rounds, ResourceSystem.hp, CombatSystem.enemy_hp])
	print("=== Смоук-тест завершён ===")
