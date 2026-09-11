extends Node
# Временная проверка прокрутки и HUD (будет удалена).

var game: Node
var presses := 0


func _ready() -> void:
	game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await _frames(2)
	GameState.start_new_game()
	SituationEngine.select_option("C")
	SituationEngine.select_option("B")
	InventorySystem.base_slots = 20
	for id in ["pipe_scrap", "medkit", "duct_tape", "cloth_rags", "scrap_metal", "makeshift_backpack", "mag_boots", "plate_vest"]:
		InventorySystem.add_item(id)
	await _frames(2)
	(game.find_child("CharacterButton", true, false) as Button).pressed.emit()
	await _frames(4)
	var scroll: ScrollContainer = game.find_child("ContentScroll", true, false)
	print("scroll max=%s page=%s" % [scroll.get_v_scroll_bar().max_value, scroll.get_v_scroll_bar().page])
	print("bag label: ", (game.find_child("BagLabel", true, false) as Label).text)

	scroll.scroll_vertical = 0
	await _frames(2)
	var target := _first_card_button()
	target.pressed.connect(func(): presses += 1)
	var start := target.get_global_rect().get_center()
	_mouse(start, true)
	for i in range(1, 11):
		_move(start + Vector2(0, -30 * i))
	_mouse(start + Vector2(0, -300), false)
	await _frames(3)
	print("drag from button '%s' -> scroll_vertical=%d, button presses=%d" % [target.text, scroll.scroll_vertical, presses])

	scroll.scroll_vertical = 0
	await _frames(2)
	var tab := game.find_child("Tab_skills", true, false) as Button
	var p := tab.get_global_rect().get_center()
	_mouse(p, true)
	_mouse(p, false)
	await _frames(3)
	print("tap on tab -> tab=%s" % game.find_child("CharacterPanel", true, false).tab)

	(game.find_child("JournalButton", true, false) as Button).pressed.emit()
	await _frames(3)
	var cards := game.find_child("ScreenBody", true, false).find_children("*", "PanelContainer", true, false)
	print("journal cards=%d, journal active style=%s" % [cards.size(), _is_active(game.find_child("JournalButton", true, false))])
	get_tree().quit()


func _is_active(btn: Button) -> bool:
	var sb := btn.get_theme_stylebox("normal") as StyleBoxFlat
	return sb.border_width_bottom == 5


func _first_card_button() -> Button:
	var panel := game.find_child("CharacterPanel", true, false)
	for child in panel.get_children():
		if child is PanelContainer:
			for node in child.find_children("*", "Button", true, false):
				return node
	return null


func _mouse(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	get_viewport().push_input(ev, true)


func _move(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(ev, true)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
