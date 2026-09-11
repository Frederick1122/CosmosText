extends VBoxContainer
## Экран персонажа — оверлей поверх текущего экрана (кнопка «Персонаж» в HUD).
## Вкладки: «Предметы», «Снаряжение», «Навыки», «Крафт». Игровой логики не
## содержит: вызывает InventorySystem / CharacterSystem / CraftingSystem и
## перерисовывается после каждого действия.

signal closed()
signal tab_changed(tab: String)

const UiKit = preload("res://scenes/ui/UiKit.gd")
const DOLL_SCRIPT = preload("res://scenes/ui/CharacterDollView.gd")

const TABS := [
	["items", "Предметы"],
	["equipment", "Снаряжение"],
	["skills", "Навыки"],
	["craft", "Крафт"],
]
const CATEGORY_TITLES := {
	"quest": "сюжетный",
	"consumable": "расходник",
	"weapon": "оружие",
	"armor": "броня",
	"gear": "снаряжение",
	"component": "материал",
}

var tab: String = "items"
var selected_slot: String = "body"
var message: String = ""


func _init() -> void:
	name = "CharacterPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 14)


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	add_child(UiKit.title("Персонаж"))
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.add_theme_constant_override("separation", 8)
	for entry in TABS:
		var label := str(entry[1])
		if entry[0] == "items" and NotificationSystem.has_new_items():
			label += "  •"
		elif entry[0] == "skills" and NotificationSystem.has_new_skill_points():
			label += "  •"
		var btn := UiKit.button(label, "tab_active" if entry[0] == tab else "quiet", 58)
		btn.name = "Tab_%s" % entry[0]
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(_select_tab.bind(entry[0]))
		tabs.add_child(btn)
	add_child(tabs)

	if message != "":
		add_child(UiKit.text(message, 22, UiKit.ACCENT_COLOR))

	match tab:
		"equipment":
			_build_equipment()
		"skills":
			_build_skills()
		"craft":
			_build_craft()
		_:
			_build_items()

	var close := UiKit.button("Закрыть", "quiet")
	close.name = "CloseCharacter"
	close.pressed.connect(func(): closed.emit())
	add_child(close)


# --- Предметы -----------------------------------------------------------------

func _build_items() -> void:
	add_child(UiKit.section("Сумка: %d/%d слотов" % [InventorySystem.used_slots(), InventorySystem.max_slots]))
	var entries := InventorySystem.get_slots()
	if entries.is_empty():
		add_child(UiKit.text("Сумка пуста."))
		return
	for entry in entries:
		var item_id := str(entry.get("id", ""))
		var data := InventorySystem.get_item_data(item_id)
		var count := int(entry.get("count", 1))
		var card := UiKit.card(self)
		var title_row := HBoxContainer.new()
		title_row.add_theme_constant_override("separation", 10)
		var title := UiKit.text(_item_name(item_id) + (" x%d" % count if count > 1 else ""), 26, UiKit.TITLE_COLOR)
		title_row.add_child(title)
		if NotificationSystem.is_item_new(item_id):
			title_row.add_child(UiKit.text("НОВОЕ", 18, UiKit.ACCENT_COLOR))
		card.add_child(title_row)
		var card_panel := card.get_parent() as PanelContainer
		card_panel.gui_input.connect(_on_item_card_input.bind(item_id))
		var meta := PackedStringArray()
		var category := str(data.get("category", ""))
		meta.append(str(CATEGORY_TITLES.get(category, category)))
		var slot := CharacterSystem.get_item_slot(item_id)
		if slot != "":
			meta.append("слот: " + str(CharacterSystem.SLOT_TITLES.get(slot, slot)))
		meta.append("место в сумке: %d" % int(data.get("slot_cost", 1)))
		card.add_child(UiKit.text(" · ".join(meta), 19, UiKit.MUTED_COLOR))

		var description := str(data.get("description", ""))
		if description != "":
			card.add_child(UiKit.text(description, 21))
		var stats_text := CharacterSystem.describe_stats(InventorySystem.get_item_stats(item_id))
		if stats_text != "":
			card.add_child(UiKit.text(stats_text, 21, UiKit.ACCENT_COLOR))

		var actions := HFlowContainer.new()
		actions.add_theme_constant_override("h_separation", 8)
		actions.add_theme_constant_override("v_separation", 8)
		card.add_child(actions)
		if data.has("use_effect"):
			actions.add_child(_action_button("Использовать", _use_item.bind(item_id)))
		if slot != "":
			actions.add_child(_action_button("Надеть", _equip.bind(item_id)))
		for inter in InventorySystem.get_interactions(item_id):
			actions.add_child(_action_button(str(inter.get("label", "")), _interact.bind(item_id, str(inter.get("id", "")))))
		if InventorySystem.can_drop(item_id):
			actions.add_child(_action_button("Оставить здесь" if LocationSystem.is_active() else "Выбросить", _drop.bind(item_id), "danger"))


func _on_item_card_input(event: InputEvent, item_id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if NotificationSystem.is_item_new(item_id):
			NotificationSystem.mark_item_seen(item_id)
			_rebuild()


func _use_item(item_id: String) -> void:
	NotificationSystem.mark_item_seen(item_id)
	var item_name := _item_name(item_id)
	_act("Использовано: %s." % item_name if InventorySystem.use_item(item_id) else "Нельзя использовать.")

func _equip(item_id: String) -> void:
	NotificationSystem.mark_item_seen(item_id)
	var error := CharacterSystem.equip(item_id)
	_act(error if error != "" else "Надето: %s." % _item_name(item_id))

func _interact(item_id: String, interaction_id: String) -> void:
	NotificationSystem.mark_item_seen(item_id)
	var text := InventorySystem.interact(item_id, interaction_id)
	_act(text if text != "" else "Готово.")

func _drop(item_id: String) -> void:
	NotificationSystem.mark_item_seen(item_id)
	var item_name := _item_name(item_id)
	var where := "Оставлено здесь: %s." if LocationSystem.is_active() else "Выброшено: %s."
	_act(where % item_name if InventorySystem.drop_item(item_id) else "Этот предмет нельзя выбросить.")


# --- Снаряжение ---------------------------------------------------------------

func _build_equipment() -> void:
	var info := {}
	for slot in CharacterSystem.SLOTS:
		info[slot] = {
			"title": CharacterSystem.SLOT_TITLES[slot],
			"item_name": CharacterSystem.get_equipped_name(slot),
		}
	var doll: Control = DOLL_SCRIPT.new()
	doll.name = "CharacterDoll"
	doll.setup(info, selected_slot)
	doll.slot_selected.connect(_select_slot)
	add_child(doll)

	var card := UiKit.card(self)
	card.add_child(UiKit.section("Слот: " + str(CharacterSystem.SLOT_TITLES.get(selected_slot, selected_slot))))
	var equipped := CharacterSystem.get_equipped(selected_slot)
	if equipped != "":
		card.add_child(UiKit.text(_item_name(equipped), 26, UiKit.TITLE_COLOR))
		var stats_text := CharacterSystem.describe_stats(InventorySystem.get_item_stats(equipped))
		if stats_text != "":
			card.add_child(UiKit.text(stats_text, 21, UiKit.ACCENT_COLOR))
		card.add_child(_action_button("Снять", _unequip.bind(selected_slot), "quiet"))
	else:
		card.add_child(UiKit.text("Пусто."))

	var candidates: Array = []
	for entry in InventorySystem.get_slots():
		var item_id := str(entry.get("id", ""))
		if CharacterSystem.get_item_slot(item_id) == selected_slot:
			candidates.append(item_id)
	if candidates.is_empty():
		card.add_child(UiKit.text("В сумке нет подходящих предметов.", 20, UiKit.MUTED_COLOR))
	for item_id in candidates:
		var stats_text := CharacterSystem.describe_stats(InventorySystem.get_item_stats(item_id))
		var label := "Надеть: %s" % _item_name(item_id)
		if stats_text != "":
			label += " (%s)" % stats_text
		card.add_child(_action_button(label, _equip.bind(item_id)))

	var stats_card := UiKit.card(self)
	stats_card.add_child(UiKit.section("Характеристики"))
	for stat in CharacterSystem.STAT_TITLES.keys():
		stats_card.add_child(UiKit.text("%s: %s" % [CharacterSystem.STAT_TITLES[stat], _stat_total_text(stat)], 22))


func _stat_total_text(stat: String) -> String:
	var bonus := CharacterSystem.get_stat(stat)
	match stat:
		"max_hp":
			return "%d (%s)" % [ResourceSystem.max_hp, CharacterSystem.format_stat(stat, bonus)]
		"inventory_slots":
			return "%d (%s)" % [InventorySystem.max_slots, CharacterSystem.format_stat(stat, bonus)]
		_:
			return CharacterSystem.format_stat(stat, bonus)


func _select_slot(slot: String) -> void:
	selected_slot = slot
	message = ""
	_rebuild()


func _unequip(slot: String) -> void:
	var item_name := CharacterSystem.get_equipped_name(slot)
	var error := CharacterSystem.unequip(slot)
	_act(error if error != "" else "Снято: %s." % item_name)


# --- Навыки -------------------------------------------------------------------

func _build_skills() -> void:
	add_child(UiKit.section("Очки навыков: %d" % CharacterSystem.skill_points))
	for skill in CharacterSystem.get_skills():
		var skill_id := str(skill.get("id", ""))
		var level := int(skill.get("level", 0))
		var max_level := int(skill.get("max_level", 1))
		var card := UiKit.card(self)
		card.add_child(UiKit.text("%s — %d/%d" % [str(skill.get("name", skill_id)), level, max_level], 26, UiKit.TITLE_COLOR))
		var description := str(skill.get("description", ""))
		if description != "":
			card.add_child(UiKit.text(description, 21))
		var per_level = skill.get("per_level", {})
		var bonus_text := CharacterSystem.describe_stats(per_level) if per_level is Dictionary else ""
		if bonus_text != "":
			card.add_child(UiKit.text("За уровень: " + bonus_text, 21, UiKit.ACCENT_COLOR))
		if level >= max_level:
			var maxed := _action_button("Максимальный уровень", Callable(), "quiet")
			maxed.disabled = true
			card.add_child(maxed)
		else:
			var btn := _action_button("Изучить (%d очк.)" % CharacterSystem.get_skill_cost(skill_id), _learn.bind(skill_id))
			btn.disabled = not CharacterSystem.can_learn(skill_id)
			card.add_child(btn)


func _learn(skill_id: String) -> void:
	if CharacterSystem.learn(skill_id):
		_act("Навык «%s» повышен до %d." % [CharacterSystem.get_skill_name(skill_id), CharacterSystem.get_skill_level(skill_id)])
	else:
		_act("Не хватает очков навыков.")


# --- Крафт --------------------------------------------------------------------

func _build_craft() -> void:
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
		card.add_child(UiKit.text(str(recipe.get("name", _item_name(result_id))), 26, UiKit.TITLE_COLOR))
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

		var btn := _action_button("Создать", _craft.bind(recipe_id))
		btn.disabled = not CraftingSystem.can_craft(recipe_id)
		card.add_child(btn)


func _craft(recipe_id: String) -> void:
	var error := CraftingSystem.craft(recipe_id)
	if error != "":
		_act(error)
		return
	var result_id := str(CraftingSystem.get_recipe(recipe_id).get("result", {}).get("item", ""))
	_act("Создано: %s." % _item_name(result_id))


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


# --- Общее --------------------------------------------------------------------

func _select_tab(new_tab: String) -> void:
	tab = new_tab
	if tab == "skills":
		NotificationSystem.mark_skill_points_seen()
	message = ""
	tab_changed.emit(tab)
	_rebuild()


func _act(text: String) -> void:
	message = text
	_rebuild()


func _action_button(text: String, callback: Callable, kind: String = "default") -> Button:
	var btn := UiKit.button(text, kind, 56)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.add_theme_font_size_override("font_size", 20)
	if callback.is_valid():
		btn.pressed.connect(callback)
	return btn


func _item_name(item_id: String) -> String:
	return str(InventorySystem.get_item_data(item_id).get("name", item_id))
