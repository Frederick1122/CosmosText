extends VBoxContainer
## Содержимое вкладки экрана персонажа. Закреплённый заголовок и переключатели
## строит Game.gd вне общего ScrollContainer, поэтому они не уезжают при
## прокрутке. Крафт — только на верстаке базы (WorkbenchPanel). Игровой логики
## не содержит: вызывает InventorySystem / CharacterSystem и перерисовывается
## после каждого действия.


const UiKit = preload("res://scenes/ui/UiKit.gd")
const DOLL_SCRIPT = preload("res://scenes/ui/CharacterDollView.gd")

const CATEGORY_TITLES := {
	"quest": "сюжетный",
	"consumable": "расходник",
	"weapon": "оружие",
	"armor": "броня",
	"gear": "снаряжение",
	"component": "материал",
	"key": "ключ",
}

var tab: String = "items"
var item_tab: String = "bag"
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

	if message != "":
		add_child(UiKit.text(message, 22, UiKit.ACCENT_COLOR))


	match tab:
		"equipment":
			_build_equipment()
		"skills":
			_build_skills()
		_:
			_build_items()


# --- Предметы -----------------------------------------------------------------

## Физические вещи и инфо-предметы разделены подвкладками. Сетка пустых ячеек
## удалена: вместимость уже видна в заголовке сумки и HUD.
func _build_items() -> void:
	var entries: Array = []
	for entry in InventorySystem.get_slots():
		var is_info := InventorySystem.is_info_item(str(entry.get("id", "")))
		if (item_tab == "info") == is_info:
			entries.append(entry)
	if item_tab == "info":
		add_child(UiKit.section("Записи и ключи · места в сумке не занимают"))
		if entries.is_empty():
			add_child(UiKit.text("Записей и ключей пока нет.", 22, UiKit.MUTED_COLOR))
	else:
		add_child(UiKit.section("Сумка: %d/%d занято · %d свободно" % [
			InventorySystem.used_slots(), InventorySystem.max_slots, InventorySystem.free_slots()]))
		if entries.is_empty():
			add_child(UiKit.text("Сумка пуста.", 22, UiKit.MUTED_COLOR))
	for entry in entries:
		_item_card(entry)


func _item_card(entry: Dictionary) -> void:
	var item_id := str(entry.get("id", ""))
	var data := InventorySystem.get_item_data(item_id)
	var count := int(entry.get("count", 1))
	var card := UiKit.card(self)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	var icon := UiKit.item_icon(item_id, 64)
	if icon != null:
		title_row.add_child(icon)
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
	if not InventorySystem.is_info_item(item_id):
		meta.append("место в сумке: %d" % int(data.get("slot_cost", 1)))
	card.add_child(UiKit.text(" · ".join(meta), 19, UiKit.MUTED_COLOR))

	var description := str(data.get("description", ""))
	if description != "":
		card.add_child(UiKit.text(description, 21))
	var stats_text := CharacterSystem.describe_stats(InventorySystem.get_item_stats(item_id))
	if stats_text != "":
		card.add_child(UiKit.text(stats_text, 21, UiKit.ACCENT_COLOR))
	var use_text := InventorySystem.describe_use(item_id)
	if use_text != "":
		card.add_child(UiKit.text("При использовании: %s" % use_text, 21, UiKit.GOOD_COLOR))

	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	card.add_child(actions)
	if data.has("use_effect"):
		actions.add_child(_action_button("💊 Использовать" + (" (%s)" % use_text if use_text != "" else ""), _use_item.bind(item_id)))
	if slot != "":
		actions.add_child(_action_button("🦺 Надеть", _equip.bind(item_id)))
	for inter in InventorySystem.get_interactions(item_id):
		actions.add_child(_action_button(str(inter.get("label", "")), _interact.bind(item_id, str(inter.get("id", "")))))
	if InventorySystem.can_drop(item_id):
		actions.add_child(_action_button("📦 Оставить здесь" if LocationSystem.is_active() else "🗑️ Выбросить", _drop.bind(item_id), "danger"))




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
	if error == "":
		SoundSystem.play("equip")
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
		card.add_child(_action_button("↩️ Снять", _unequip.bind(selected_slot), "quiet"))
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
	if error == "":
		SoundSystem.play("equip")
	_act(error if error != "" else "Снято: %s." % item_name)


# --- Навыки -------------------------------------------------------------------

func _build_skills() -> void:
	add_child(UiKit.section("Уровень %d · опыт %d/%d · новый уровень: +%d очк. навыков" % [
		ProgressionSystem.level, ProgressionSystem.xp, ProgressionSystem.xp_to_next(),
		ProgressionSystem.skill_points_per_level()]))
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
			var btn := _action_button("⭐ Изучить (%d очк.)" % CharacterSystem.get_skill_cost(skill_id), _learn.bind(skill_id))
			btn.disabled = not CharacterSystem.can_learn(skill_id)
			card.add_child(btn)


func _learn(skill_id: String) -> void:
	if CharacterSystem.learn(skill_id):
		_act("Навык «%s» повышен до %d." % [CharacterSystem.get_skill_name(skill_id), CharacterSystem.get_skill_level(skill_id)])
	else:
		_act("Не хватает очков навыков.")


# --- Общее --------------------------------------------------------------------



func _act(text: String) -> void:
	message = text
	_rebuild()


func _action_button(text: String, callback: Callable, kind: String = "default") -> Button:
	var btn := UiKit.button(text, kind, 56)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.add_theme_font_size_override("font_size", UiKit.fs(20))
	if callback.is_valid():
		btn.pressed.connect(callback)
	return btn


func _item_name(item_id: String) -> String:
	return str(InventorySystem.get_item_data(item_id).get("name", item_id))
