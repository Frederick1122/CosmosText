extends VBoxContainer
## Верстак модуля-базы — оверлей с рецептами (кнопка «Верстак» в разделе
## «База»). Крафт доступен только здесь, в экране персонажа его нет. Игровой
## логики не содержит: вызывает CraftingSystem и перерисовывается после
## каждого действия.

signal closed()

const UiKit = preload("res://scenes/ui/UiKit.gd")

var message: String = ""


func _init() -> void:
	name = "WorkbenchPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 14)


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	add_child(UiKit.title("Верстак"))
	add_child(UiKit.section("Сумка: %d/%d слотов" % [InventorySystem.used_slots(), InventorySystem.max_slots]))
	if message != "":
		add_child(UiKit.text(message, 22, UiKit.ACCENT_COLOR))

	_build_recipes()

	var close := UiKit.button("✖ Закрыть", "quiet")
	close.name = "CloseWorkbench"
	close.pressed.connect(func(): closed.emit())
	add_child(close)


## Все рецепты видны всегда: недостающие материалы и невыполненные условия
## подсвечены, кнопка «Создать» неактивна.
func _build_recipes() -> void:
	var recipes := CraftingSystem.get_recipes()
	if recipes.is_empty():
		add_child(UiKit.text("Рецептов пока нет."))
		return
	for recipe in recipes:
		var recipe_id := str(recipe.get("id", ""))
		var result: Dictionary = recipe.get("result", {})
		var result_id := str(result.get("item", ""))
		var result_count := int(result.get("count", 1))
		var card := UiKit.card(self)
		var title_row := HBoxContainer.new()
		title_row.add_theme_constant_override("separation", 10)
		var icon := UiKit.item_icon(result_id, 64)
		if icon != null:
			title_row.add_child(icon)
		title_row.add_child(UiKit.text(str(recipe.get("name", _item_name(result_id))), 26, UiKit.TITLE_COLOR))
		card.add_child(title_row)
		card.add_child(UiKit.text("Результат: %s%s" % [_item_name(result_id), " x%d" % result_count if result_count > 1 else ""], 21))
		var stats_text := CharacterSystem.describe_stats(InventorySystem.get_item_stats(result_id))
		if stats_text != "":
			card.add_child(UiKit.text(stats_text, 21, UiKit.ACCENT_COLOR))

		var parts := PackedStringArray()
		for ing in recipe.get("ingredients", []):
			var ing_id := str(ing.get("item", ""))
			parts.append("%s ×%d (есть %d)" % [_item_name(ing_id), int(ing.get("count", 1)), InventorySystem.count_item(ing_id)])
		var enough := CraftingSystem.has_ingredients(recipe_id)
		card.add_child(UiKit.text("Материалы: " + ", ".join(parts), 21, UiKit.TEXT_COLOR if enough else UiKit.BAD_COLOR))

		for req in recipe.get("requires", []):
			if req is Dictionary:
				var met := EffectResolver.check_requirement(req)
				card.add_child(UiKit.text("Условие: %s%s" % [_describe_requirement(req), "" if met else " (не выполнено)"], 21, UiKit.TEXT_COLOR if met else UiKit.BAD_COLOR))

		var btn := UiKit.button("🛠️ Создать", "default", 56)
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_font_size_override("font_size", UiKit.fs(20))
		btn.pressed.connect(_craft.bind(recipe_id))
		btn.disabled = not CraftingSystem.can_craft(recipe_id)
		card.add_child(btn)


func _craft(recipe_id: String) -> void:
	var error := CraftingSystem.craft(recipe_id)
	if error != "":
		message = error
	else:
		var result_id := str(CraftingSystem.get_recipe(recipe_id).get("result", {}).get("item", ""))
		message = "Создано: %s." % _item_name(result_id)
	_rebuild()


func _describe_requirement(req: Dictionary) -> String:
	match str(req.get("type", "")):
		"skill_gte":
			var skill_id := str(req.get("skill", ""))
			return "навык «%s» не ниже %d" % [CharacterSystem.get_skill_name(skill_id), int(req.get("value", 1))]
		"in_location":
			return "находиться в модуле «%s»" % LocationSystem.get_location_title(str(req.get("location", "")))
		"has_item":
			return "нужен предмет «%s»" % _item_name(str(req.get("item", "")))
		"stat_gte":
			return "%s не ниже %s" % [str(req.get("stat", "")), str(req.get("value", ""))]
		_:
			return "особое условие"


func _item_name(item_id: String) -> String:
	return str(InventorySystem.get_item_data(item_id).get("name", item_id))
