extends Node
## Крафт: рецепты из data/recipes.json. Материалы берутся только из сумки
## (надетое снаряжение не расходуется). Условия рецепта — обычные requires
## (например skill_gte или in_location). Справочник — docs/CONTENT.md.

signal crafted(recipe_id: String, item_id: String)

var _recipes: Dictionary = {}


func _ready() -> void:
	_recipes = _load_res_json("res://data/recipes.json")


func get_recipes() -> Array:
	var result: Array = []
	for recipe_id in _recipes.keys():
		if _recipes[recipe_id] is Dictionary:
			var entry: Dictionary = _recipes[recipe_id].duplicate(true)
			entry["id"] = recipe_id
			result.append(entry)
	return result


func get_recipe(recipe_id: String) -> Dictionary:
	var recipe = _recipes.get(recipe_id, {})
	return recipe if recipe is Dictionary else {}


func requirements_met(recipe_id: String) -> bool:
	return EffectResolver.check_requirements(get_recipe(recipe_id).get("requires", []))


func has_ingredients(recipe_id: String) -> bool:
	for ing in get_recipe(recipe_id).get("ingredients", []):
		if InventorySystem.count_item(str(ing.get("item", ""))) < int(ing.get("count", 1)):
			return false
	return true


func can_craft(recipe_id: String) -> bool:
	return not get_recipe(recipe_id).is_empty() and requirements_met(recipe_id) and has_ingredients(recipe_id)


## Возвращает текст ошибки или "" при успехе. При нехватке места под
## результат материалы возвращаются в сумку.
func craft(recipe_id: String) -> String:
	var recipe := get_recipe(recipe_id)
	if recipe.is_empty():
		return "Неизвестный рецепт."
	if not requirements_met(recipe_id):
		return "Не выполнены условия рецепта."
	if not has_ingredients(recipe_id):
		return "Не хватает материалов."

	var ingredients: Array = recipe.get("ingredients", [])
	for ing in ingredients:
		InventorySystem.remove_item(str(ing.get("item", "")), int(ing.get("count", 1)))

	var result: Dictionary = recipe.get("result", {})
	var result_id := str(result.get("item", ""))
	var count := int(result.get("count", 1))
	var added := 0
	while added < count and InventorySystem.add_item(result_id):
		added += 1
	if added < count:
		InventorySystem.remove_item(result_id, added)
		for ing in ingredients:
			InventorySystem.add_item(str(ing.get("item", "")), int(ing.get("count", 1)))
		return "В сумке не хватит места для результата."

	crafted.emit(recipe_id, result_id)
	return ""


func _load_res_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("CraftingSystem: файл не найден %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
