@tool
extends VBoxContainer
## Внутренний редактор контента. UI редактирует JSON-ресурсы структурированными
## полями; ручное редактирование файлов остаётся неосновным workflow.

const DATA_ROOT := "res://data"
const KINDS := [
	["sectors", "Карта"],
	["locations", "Локации"],
	["situations", "Ситуации"],
	["items", "Предметы"],
	["recipes", "Крафты"],
	["lore", "Журнал"],
]
const ITEM_CATEGORIES := ["quest", "consumable", "weapon", "armor", "gear", "component"]
const EFFECT_TYPES := ["", "hp_delta", "o2_delta", "ammo_delta", "item_add", "item_remove", "flag_set", "unlock_lore", "reveal_map", "open_map_node", "lock_map_node", "skill_points_add", "start_combat"]
const EVENT_STARTS := ["manual", "auto"]
const REQUIREMENT_TYPES := ["has_item", "flag", "stat_gte", "skill_gte", "in_location", "event_done", "visits_gte", "visits_lte"]
const NODE_STATES := ["locked", "available", "dangerous", "cleared"]

var kind_selector: OptionButton
var asset_selector: OptionButton
var form: VBoxContainer
var status: Label
var _kind := "sectors"
var _asset_id := ""
var _pending_asset_id := ""
var _current_path := ""
var _root_data: Dictionary = {}
var _entry: Dictionary = {}
var _dirty := false
var _sub_index := -1
var _sub_key := ""


func _ready() -> void:
	custom_minimum_size = Vector2(430, 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_build_shell()
	_refresh_assets()


func _build_shell() -> void:
	var title := Label.new()
	title.text = "CosmoText Content Studio"
	title.add_theme_font_size_override("font_size", 20)
	add_child(title)

	var type_row := HBoxContainer.new()
	add_child(type_row)
	var type_label := Label.new()
	type_label.text = "Раздел"
	type_label.custom_minimum_size.x = 86
	type_row.add_child(type_label)
	kind_selector = OptionButton.new()
	kind_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry in KINDS:
		kind_selector.add_item(str(entry[1]))
		kind_selector.set_item_metadata(kind_selector.item_count - 1, entry[0])
	kind_selector.item_selected.connect(_on_kind_selected)
	type_row.add_child(kind_selector)

	var asset_row := HBoxContainer.new()
	add_child(asset_row)
	var asset_label := Label.new()
	asset_label.text = "Ресурс"
	asset_label.custom_minimum_size.x = 86
	asset_row.add_child(asset_label)
	asset_selector = OptionButton.new()
	asset_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	asset_selector.item_selected.connect(_on_asset_selected)
	asset_row.add_child(asset_selector)

	var actions := HBoxContainer.new()
	add_child(actions)
	var new_button := Button.new()
	new_button.text = "Новый"
	new_button.pressed.connect(_new_asset)
	actions.add_child(new_button)
	var save_button := Button.new()
	save_button.text = "Сохранить"
	save_button.pressed.connect(_save_current)
	actions.add_child(save_button)
	var validate_button := Button.new()
	validate_button.text = "Проверить весь контент"
	validate_button.pressed.connect(_validate_content)
	validate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(validate_button)

	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", Color("#9fd3e6"))
	add_child(status)

	var separator := HSeparator.new()
	add_child(separator)
	var scroll := ScrollContainer.new()
	scroll.name = "ContentFormScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	form = VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 7)
	scroll.add_child(form)


func _on_kind_selected(index: int) -> void:
	_save_current(false)
	_kind = str(kind_selector.get_item_metadata(index))
	_refresh_assets()


func _on_asset_selected(index: int) -> void:
	_save_current(false)
	if index < 0 or index >= asset_selector.item_count:
		_clear_form()
		return
	_asset_id = str(asset_selector.get_item_metadata(index))
	_pending_asset_id = _asset_id
	_load_asset()


func _refresh_assets(select_id: String = "") -> void:
	asset_selector.clear()
	_root_data = {}
	var path := _dictionary_path(_kind)
	if path != "":
		var parsed = _read_json(path)
		_root_data = parsed if parsed is Dictionary else {}
		for key in _root_data.keys():
			asset_selector.add_item(str(key))
			asset_selector.set_item_metadata(asset_selector.item_count - 1, str(key))
	else:
		var dir := DirAccess.open("%s/%s" % [DATA_ROOT, _kind])
		if dir:
			dir.list_dir_begin()
			var names: Array[String] = []
			var file_name := dir.get_next()
			while file_name != "":
				if file_name.ends_with(".json"):
					names.append(file_name.trim_suffix(".json"))
				file_name = dir.get_next()
			dir.list_dir_end()
			names.sort()
			for name in names:
				asset_selector.add_item(name)
				asset_selector.set_item_metadata(asset_selector.item_count - 1, name)
	if asset_selector.item_count == 0:
		_clear_form()
		_set_status("Нет ресурсов. Нажмите «Новый».", false)
		return
	var target := select_id if select_id != "" else str(asset_selector.get_item_metadata(0))
	for i in range(asset_selector.item_count):
		if str(asset_selector.get_item_metadata(i)) == target:
			asset_selector.select(i)
			_asset_id = target
			_pending_asset_id = target
			_load_asset()
			return


func _load_asset() -> void:
	if _dictionary_path(_kind) != "":
		var dictionary_source = _root_data.get(_asset_id, {})
		_entry = dictionary_source.duplicate(true) if dictionary_source is Dictionary else {}
		_current_path = _dictionary_path(_kind)
	else:
		_current_path = "%s/%s/%s.json" % [DATA_ROOT, _kind, _asset_id]
		var file_source = _read_json(_current_path)
		_entry = file_source if file_source is Dictionary else {}
	_pending_asset_id = _asset_id
	_dirty = false
	_sub_index = -1
	_sub_key = ""
	_build_form()
	_set_status("Загружено: %s" % _asset_id, false)


func _new_asset() -> void:
	_save_current(false)
	var base_id := "new_%s" % _kind.trim_suffix("s")
	var candidate := base_id
	var suffix := 2
	while _asset_exists(candidate):
		candidate = "%s_%d" % [base_id, suffix]
		suffix += 1
	_asset_id = candidate
	_pending_asset_id = candidate
	_entry = _default_entry(_kind, _asset_id)
	_sub_index = -1
	_sub_key = ""
	if _dictionary_path(_kind) != "":
		_root_data[_asset_id] = _entry
		_refresh_assets(_asset_id)
		_dirty = true
		_set_status("Создан черновик: нажмите «Сохранить»", true)
	else:
		_current_path = "%s/%s/%s.json" % [DATA_ROOT, _kind, _asset_id]
		_build_form()
		_dirty = true
		_set_status("Создан черновик: нажмите «Сохранить»", true)


func _asset_exists(id: String) -> bool:
	if _dictionary_path(_kind) != "":
		return _root_data.has(id)
	return FileAccess.file_exists("%s/%s/%s.json" % [DATA_ROOT, _kind, id])


func _save_current(show_status: bool = true) -> void:
	if not _dirty:
		return
	if _asset_id == "" or _entry.is_empty():
		return
	if _dictionary_path(_kind) != "":
		var id := _pending_asset_id if _pending_asset_id != "" else _asset_id
		if id != _asset_id:
			if _root_data.has(id):
				_set_status("Такой ID уже существует", true)
				return
			_root_data.erase(_asset_id)
		_root_data[id] = _entry.duplicate(true)
		if not _write_json(_current_path, _root_data):
			_set_status("Ошибка записи %s" % _current_path, true)
			return
		_asset_id = id
		_pending_asset_id = id
	else:
		if not _write_json(_current_path, _entry):
			_set_status("Ошибка записи %s" % _current_path, true)
			return
	_dirty = false
	EditorInterface.get_resource_filesystem().scan()
	if show_status:
		_set_status("Сохранено: %s" % _asset_id, false)


func _validate_content() -> void:
	_save_current(false)
	var output: Array[String] = []
	var exit_code := OS.execute("python", PackedStringArray(["tools/validate_content.py"]), output, true)
	if exit_code == 0:
		_set_status("Контент проверен: ошибок нет\n%s" % "\n".join(output), false)
	else:
		_set_status("Валидатор завершился с кодом %d\n%s" % [exit_code, "\n".join(output)], true)
func _clear_form() -> void:
	_entry = {}
	_asset_id = ""
	_pending_asset_id = ""
	_current_path = ""
	for child in form.get_children():
		form.remove_child(child)
		child.queue_free()

func _build_form() -> void:
	for child in form.get_children():
		form.remove_child(child)
		child.queue_free()
	if _entry.is_empty():
		form.add_child(_label("Нет данных для редактирования."))
		return
	match _kind:
		"sectors":
			_build_sector_form()
		"locations":
			_build_location_form()
		"situations":
			_build_situation_form()
		"items":
			_build_item_form()
		"recipes":
			_build_recipe_form()
		"lore":
			_build_lore_form()


func _build_sector_form() -> void:
	_section("Карта сектора")
	_line("ID", str(_entry.get("id", _asset_id)), func(value): _set_entry_value("id", value))
	_line("Название", str(_entry.get("title", "")), func(value): _set_entry_value("title", value))
	_line("Хаб", str(_entry.get("hub_node", "")), func(value): _set_entry_value("hub_node", value))
	_section("Палубы")
	_json_edit("Палубы и параметры карты", _entry.get("map", {}), func(value): _set_entry_value("map", value))
	_section("Отсеки и лифты")
	_build_node_list()


func _build_node_list() -> void:
	var nodes: Dictionary = _entry.get("nodes", {})
	var list := ItemList.new()
	list.custom_minimum_size.y = 130
	list.select_mode = ItemList.SELECT_SINGLE
	for node_id in nodes.keys():
		list.add_item(str(node_id))
	list.item_selected.connect(func(index):
		_sub_key = str(list.get_item_text(index))
		_build_form()
	)
	form.add_child(list)
	var buttons := HBoxContainer.new()
	var add := Button.new()
	add.text = "Добавить отсек"
	add.pressed.connect(func():
		var id := _unique_dict_id(nodes, "new_room")
		nodes[id] = _default_node(id)
		_entry["nodes"] = nodes
		_sub_key = id
		_mark_dirty()
		_build_form()
	)
	buttons.add_child(add)
	var remove := Button.new()
	remove.text = "Удалить выбранный"
	remove.pressed.connect(func():
		if _sub_key != "" and nodes.has(_sub_key):
			nodes.erase(_sub_key)
			_entry["nodes"] = nodes
			_sub_key = ""
			_mark_dirty()
			_build_form()
	)
	buttons.add_child(remove)
	form.add_child(buttons)
	if _sub_key != "" and nodes.has(_sub_key):
		_build_node_fields(nodes[_sub_key])


func _build_node_fields(node: Dictionary) -> void:
	_section("Выбранный отсек: %s" % _sub_key)
	_line("ID", _sub_key, func(value): _rename_node(value))
	_line("Название", str(node.get("title", "")), func(value): _set_sub_value(node, "title", value))
	_line("Локация", str(node.get("location_id", "")), func(value): _set_sub_value(node, "location_id", value))
	_option("Состояние", NODE_STATES, str(node.get("state", "locked")), func(value): _set_sub_value(node, "state", value))
	_bool("Герметично", bool(node.get("sealed", true)), func(value): _set_sub_value(node, "sealed", value))
	var map_data: Dictionary = node.get("map", {}) if node.get("map", {}) is Dictionary else {}
	_line("Палуба", str(map_data.get("floor", "")), func(value): _set_nested_value(node, "map", "floor", value))
	var cell: Dictionary = map_data.get("cell", {}) if map_data.get("cell", {}) is Dictionary else {}
	_int("Клетка X", int(cell.get("x", 1)), func(value): _set_cell_value(node, "x", value))
	_int("Клетка Y", int(cell.get("y", 1)), func(value): _set_cell_value(node, "y", value))
	_line("Подпись", str(map_data.get("label", "")), func(value): _set_nested_value(node, "map", "label", value))
	_line("Связи через запятую", ", ".join(_string_array(node.get("connections", []))), func(value): _set_sub_value(node, "connections", _split_csv(value)))


func _build_location_form() -> void:
	_section("Локация")
	_line("ID", str(_entry.get("id", _asset_id)), func(value): _set_entry_value("id", value))
	_line("Название", str(_entry.get("title", "")), func(value): _set_entry_value("title", value))
	_text("Описание", str(_entry.get("description", "")), func(value): _set_entry_value("description", value))
	_section("События")
	_build_array_list("events", "Событие", func(event): _build_event_fields(event))


func _build_event_fields(event: Dictionary) -> void:
	_section("Выбранное событие")
	_line("ID", str(event.get("id", "")), func(value): _set_sub_value(event, "id", value))
	_option("Запуск", EVENT_STARTS, str(event.get("start", "manual")), func(value): _set_sub_value(event, "start", value))
	_line("Кнопка", str(event.get("label", "")), func(value): _set_sub_value(event, "label", value))
	_bool("Повторяемое", bool(event.get("repeatable", false)), func(value): _set_sub_value(event, "repeatable", value))
	_line("Ситуация", str(event.get("situation", "")), func(value): _set_sub_value(event, "situation", value))
	_text("Сообщение", str(event.get("text", "")), func(value): _set_sub_value(event, "text", value))
	_requirements_editor("Условия запуска", event.get("triggers", []), func(value): _set_sub_value(event, "triggers", value))
	_effects_editor("Эффекты", event.get("effects", []), func(value): _set_sub_value(event, "effects", value))


func _build_situation_form() -> void:
	_section("Ситуация")
	_line("ID", str(_entry.get("id", _asset_id)), func(value): _set_entry_value("id", value))
	_text("Текст", str(_entry.get("text", "")), func(value): _set_entry_value("text", value))
	_requirements_editor("Общие условия", _entry.get("requires", []), func(value): _set_entry_value("requires", value))
	_section("Варианты выбора")
	_build_array_list("options", "Вариант", func(option): _build_option_fields(option))


func _build_option_fields(option: Dictionary) -> void:
	_section("Выбранный вариант")
	_line("ID", str(option.get("id", "")), func(value): _set_sub_value(option, "id", value))
	_line("Кнопка", str(option.get("label", "")), func(value): _set_sub_value(option, "label", value))
	_line("Следующая ситуация", str(option.get("next", "")), func(value): _set_sub_value(option, "next", value))
	_requirements_editor("Условия", option.get("requires", []), func(value): _set_sub_value(option, "requires", value))
	_effects_editor("Эффекты", option.get("effects", []), func(value): _set_sub_value(option, "effects", value))


func _build_item_form() -> void:
	_section("Предмет")
	_line("ID", _asset_id, func(value): _rename_dictionary_asset(value))
	_line("Название", str(_entry.get("name", "")), func(value): _set_entry_value("name", value))
	_option("Категория", ITEM_CATEGORIES, str(_entry.get("category", "component")), func(value): _set_entry_value("category", value))
	_int("Место в сумке", int(_entry.get("slot_cost", 1)), func(value): _set_entry_value("slot_cost", value))
	_bool("Стакается", bool(_entry.get("stackable", false)), func(value): _set_entry_value("stackable", value))
	_line("Слот снаряжения", str(_entry.get("equip_slot", "")), func(value): _set_entry_value("equip_slot", value))
	_text("Описание", str(_entry.get("description", "")), func(value): _set_entry_value("description", value))
	_section("Использование")
	_single_effect_editor("Эффект использования", _entry.get("use_effect", {}), func(value): _set_entry_value("use_effect", value))
	_section("Особые взаимодействия")
	_json_edit("Взаимодействия", _entry.get("interactions", []), func(value): _set_entry_value("interactions", value))


func _build_recipe_form() -> void:
	_section("Рецепт")
	_line("ID", _asset_id, func(value): _rename_dictionary_asset(value))
	_line("Название", str(_entry.get("name", "")), func(value): _set_entry_value("name", value))
	_json_edit("Результат", _entry.get("result", {}), func(value): _set_entry_value("result", value))
	_section("Ингредиенты")
	_build_array_list("ingredients", "Ингредиент", func(ingredient): _build_ingredient_fields(ingredient))
	_requirements_editor("Условия", _entry.get("requires", []), func(value): _set_entry_value("requires", value))

func _build_ingredient_fields(ingredient: Dictionary) -> void:
	_section("Выбранный ингредиент")
	_line("Предмет", str(ingredient.get("item", "")), func(value): _set_sub_value(ingredient, "item", value))
	_int("Количество", int(ingredient.get("count", 1)), func(value): _set_sub_value(ingredient, "count", int(value)))


func _build_lore_form() -> void:
	_section("Запись журнала")
	_line("ID", _asset_id, func(value): _rename_dictionary_asset(value))
	_line("Заголовок", str(_entry.get("title", "")), func(value): _set_entry_value("title", value))
	_text("Текст", str(_entry.get("text", "")), func(value): _set_entry_value("text", value))


func _build_array_list(key: String, label: String, field_builder: Callable) -> void:
	var values = _entry.get(key, [])
	if not (values is Array):
		values = []
		_entry[key] = values
	var list := ItemList.new()
	list.custom_minimum_size.y = 120
	for i in range(values.size()):
		var value: Dictionary = values[i] if values[i] is Dictionary else {}
		list.add_item(str(value.get("id", "%s %d" % [label, i + 1])))
	list.item_selected.connect(func(index):
		_sub_key = key
		_sub_index = index
		_build_form()
	)
	form.add_child(list)
	var buttons := HBoxContainer.new()
	var add := Button.new()
	add.text = "Добавить"
	add.pressed.connect(func():
		values.append(_default_array_entry(key, values.size()))
		_entry[key] = values
		_sub_key = key
		_sub_index = values.size() - 1
		_mark_dirty()
		_build_form()
	)
	buttons.add_child(add)
	var remove := Button.new()
	remove.text = "Удалить"
	remove.pressed.connect(func():
		if _sub_key == key and _sub_index >= 0 and _sub_index < values.size():
			values.remove_at(_sub_index)
			_entry[key] = values
			_sub_index = -1
			_mark_dirty()
			_build_form()
	)
	buttons.add_child(remove)
	form.add_child(buttons)
	if _sub_key == key and _sub_index >= 0 and _sub_index < values.size():
		field_builder.call(values[_sub_index])


func _default_array_entry(key: String, index: int) -> Dictionary:
	match key:
		"ingredients":
			return {"item": "", "count": 1}
		"options":
			return {"id": String.chr(65 + index), "label": "Новый вариант", "requires": [], "effects": [], "next": ""}
		"events":
			return {"id": "new_event_%d" % (index + 1), "start": "manual", "label": "Новое событие", "repeatable": false, "triggers": [], "effects": [], "text": "", "situation": ""}
	return {"id": "new_entry_%d" % (index + 1)}


func _default_entry(kind: String, id: String) -> Dictionary:
	match kind:
		"sectors":
			return {"id": id, "title": "Новый сектор", "hub_node": "hub", "map": {"floors": []}, "nodes": {}}
		"locations":
			return {"id": id, "title": "Новая локация", "description": "", "events": []}
		"situations":
			return {"id": id, "text": "", "requires": [], "options": []}
		"items":
			return {"name": "Новый предмет", "category": "component", "slot_cost": 1, "stackable": false, "description": "", "interactions": []}
		"recipes":
			return {"name": "Новый рецепт", "result": {"item": "", "count": 1}, "ingredients": [], "requires": []}
		"lore":
			return {"title": "Новая запись", "text": ""}
	return {}


func _default_node(id: String) -> Dictionary:
	return {"title": "Новый отсек", "location_id": "", "connections": [], "sealed": true, "state": "locked", "map": {"label": id, "floor": "deck_01", "cell": {"x": 1, "y": 1}, "order": 0}}


func _set_entry_value(key: String, value) -> void:
	_entry[key] = value
	_mark_dirty()


func _set_sub_value(target: Dictionary, key: String, value) -> void:
	target[key] = value
	_mark_dirty()


func _set_nested_value(target: Dictionary, parent: String, key: String, value) -> void:
	var nested: Dictionary = target.get(parent, {}) if target.get(parent, {}) is Dictionary else {}
	nested[key] = value
	target[parent] = nested
	_mark_dirty()


func _set_cell_value(target: Dictionary, axis: String, value: float) -> void:
	var map_data: Dictionary = target.get("map", {}) if target.get("map", {}) is Dictionary else {}
	var cell: Dictionary = map_data.get("cell", {}) if map_data.get("cell", {}) is Dictionary else {}
	cell[axis] = int(value)
	map_data["cell"] = cell
	target["map"] = map_data
	_mark_dirty()


func _rename_node(new_id: String) -> void:
	new_id = new_id.strip_edges()
	if new_id == "" or new_id == _sub_key:
		return
	var nodes: Dictionary = _entry.get("nodes", {})
	if nodes.has(new_id):
		_set_status("Такой ID отсека уже существует", true)
		return
	if nodes.has(_sub_key):
		nodes[new_id] = nodes[_sub_key]
		nodes.erase(_sub_key)
		_sub_key = new_id
		_entry["nodes"] = nodes
		_mark_dirty()


func _rename_dictionary_asset(new_id: String) -> void:
	new_id = new_id.strip_edges()
	if new_id == "" or new_id == _asset_id:
		_pending_asset_id = _asset_id
		return
	if _root_data.has(new_id):
		_set_status("Такой ID уже существует", true)
		return
	_pending_asset_id = new_id
	_mark_dirty()


func _unique_dict_id(values: Dictionary, base: String) -> String:
	var id := base
	var suffix := 2
	while values.has(id):
		id = "%s_%d" % [base, suffix]
		suffix += 1
	return id


func _line(label: String, value: String, setter: Callable) -> LineEdit:
	var row := HBoxContainer.new()
	var caption := Label.new()
	caption.text = label
	caption.custom_minimum_size.x = 125
	row.add_child(caption)
	var edit := LineEdit.new()
	edit.text = value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(func(text): setter.call(text))
	row.add_child(edit)
	form.add_child(row)
	return edit


func _text(label: String, value: String, setter: Callable) -> TextEdit:
	var caption := Label.new()
	caption.text = label
	form.add_child(caption)
	var edit := TextEdit.new()
	edit.text = value
	edit.custom_minimum_size.y = 86
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(func(): setter.call(edit.text))
	form.add_child(edit)
	return edit


func _int(label: String, value: int, setter: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	var caption := Label.new()
	caption.text = label
	caption.custom_minimum_size.x = 125
	row.add_child(caption)
	var edit := SpinBox.new()
	edit.value = value
	edit.min_value = 0
	edit.max_value = 9999
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.value_changed.connect(func(number): setter.call(number))
	row.add_child(edit)
	form.add_child(row)
	return edit


func _bool(label: String, value: bool, setter: Callable) -> CheckButton:
	var edit := CheckButton.new()
	edit.text = label
	edit.button_pressed = value
	edit.toggled.connect(func(pressed): setter.call(pressed))
	form.add_child(edit)
	return edit


func _option(label: String, values: Array, value: String, setter: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	var caption := Label.new()
	caption.text = label
	caption.custom_minimum_size.x = 125
	row.add_child(caption)
	var edit := OptionButton.new()
	for item in values:
		edit.add_item(str(item))
	var selected := values.find(value)
	if selected >= 0:
		edit.select(selected)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.item_selected.connect(func(index): setter.call(str(values[index])))
	row.add_child(edit)
	form.add_child(row)
	return edit


func _requirements_editor(label: String, value, setter: Callable) -> void:
	var caption := Label.new()
	caption.text = label
	form.add_child(caption)
	var values: Array = value if value is Array else []
	var rows := VBoxContainer.new()
	for index in range(values.size()):
		var requirement: Dictionary = values[index] if values[index] is Dictionary else {}
		var row_index := index
		var row := HBoxContainer.new()
		var type := OptionButton.new()
		for requirement_type in REQUIREMENT_TYPES:
			type.add_item(requirement_type)
		var selected := REQUIREMENT_TYPES.find(str(requirement.get("type", "flag")))
		if selected >= 0:
			type.select(selected)
		type.custom_minimum_size.x = 115
		type.item_selected.connect(func(option_index):
			requirement["type"] = REQUIREMENT_TYPES[option_index]
			setter.call(values)
			_mark_dirty()
		)
		row.add_child(type)
		var key := LineEdit.new()
		key.placeholder_text = "предмет / флаг / навык"
		key.text = _requirement_key(requirement)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key.text_changed.connect(func(text):
			_set_requirement_key(requirement, text)
			setter.call(values)
		)
		row.add_child(key)
		var requirement_value := LineEdit.new()
		requirement_value.placeholder_text = "значение"
		requirement_value.text = _requirement_value_text(requirement)
		requirement_value.custom_minimum_size.x = 72
		requirement_value.text_changed.connect(func(text):
			_set_requirement_value(requirement, text)
			setter.call(values)
		)
		row.add_child(requirement_value)
		var remove := Button.new()
		remove.text = "×"
		remove.pressed.connect(func():
			if row_index < values.size():
				values.remove_at(row_index)
				setter.call(values)
				_mark_dirty()
				_build_form()
		)
		row.add_child(remove)
		rows.add_child(row)
	form.add_child(rows)
	var add := Button.new()
	add.text = "Добавить условие"
	add.pressed.connect(func():
		values.append({"type": "flag", "flag": ""})
		setter.call(values)
		_mark_dirty()
		_build_form()
	)
	form.add_child(add)


func _effects_editor(label: String, value, setter: Callable) -> void:
	var caption := Label.new()
	caption.text = label
	form.add_child(caption)
	var values: Array = value if value is Array else []
	var rows := VBoxContainer.new()
	for index in range(values.size()):
		var effect: Dictionary = values[index] if values[index] is Dictionary else {}
		var row_index := index
		var row := HBoxContainer.new()
		var type := OptionButton.new()
		for effect_type in EFFECT_TYPES:
			type.add_item(effect_type if effect_type != "" else "—")
		var selected := EFFECT_TYPES.find(str(effect.get("type", "")))
		if selected >= 0:
			type.select(selected)
		type.custom_minimum_size.x = 120
		type.item_selected.connect(func(option_index):
			effect["type"] = EFFECT_TYPES[option_index]
			setter.call(values)
			_mark_dirty()
		)
		row.add_child(type)
		var key := LineEdit.new()
		key.placeholder_text = "предмет / узел / флаг"
		key.text = _effect_key(effect)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key.text_changed.connect(func(text):
			_set_effect_key(effect, text)
			setter.call(values)
		)
		row.add_child(key)
		var effect_value := LineEdit.new()
		effect_value.placeholder_text = "значение"
		effect_value.text = _effect_value_text(effect)
		effect_value.custom_minimum_size.x = 72
		effect_value.text_changed.connect(func(text):
			_set_effect_value(effect, text)
			setter.call(values)
		)
		row.add_child(effect_value)
		var remove := Button.new()
		remove.text = "×"
		remove.pressed.connect(func():
			if row_index < values.size():
				values.remove_at(row_index)
				setter.call(values)
				_mark_dirty()
				_build_form()
		)
		row.add_child(remove)
		rows.add_child(row)
	form.add_child(rows)
	var add := Button.new()
	add.text = "Добавить эффект"
	add.pressed.connect(func():
		values.append({"type": "item_add", "item": ""})
		setter.call(values)
		_mark_dirty()
		_build_form()
	)
	form.add_child(add)


func _single_effect_editor(label: String, value, setter: Callable) -> void:
	var values: Array = [] if not (value is Dictionary) or value.is_empty() else [value]
	_effects_editor(label, values, func(updated):
		setter.call(updated[0] if updated is Array and not updated.is_empty() else {})
	)


func _requirement_key(requirement: Dictionary) -> String:
	for key in ["item", "flag", "stat", "skill", "location", "event"]:
		if requirement.has(key):
			return str(requirement[key])
	return ""


func _requirement_value_text(requirement: Dictionary) -> String:
	if requirement.has("value"):
		return str(requirement["value"])
	return ""


func _set_requirement_key(requirement: Dictionary, text: String) -> void:
	var key := "flag"
	match str(requirement.get("type", "flag")):
		"has_item":
			key = "item"
		"in_location":
			key = "location"
		"event_done":
			key = "event"
		"skill_gte":
			key = "skill"
		"stat_gte":
			key = "stat"
	requirement.erase("item")
	requirement.erase("flag")
	requirement.erase("stat")
	requirement.erase("skill")
	requirement.erase("location")
	requirement.erase("event")
	requirement[key] = text
	_mark_dirty()


func _set_requirement_value(requirement: Dictionary, text: String) -> void:
	if text == "":
		requirement.erase("value")
	else:
		requirement["value"] = _parse_scalar(text)
	_mark_dirty()


func _effect_key(effect: Dictionary) -> String:
	for key in ["item", "flag", "id", "node", "enemy"]:
		if effect.has(key):
			return str(effect[key])
	return ""


func _effect_value_text(effect: Dictionary) -> String:
	if effect.has("value"):
		return str(effect["value"])
	if effect.has("count"):
		return str(effect["count"])
	if effect.has("state"):
		return str(effect["state"])
	return ""


func _set_effect_key(effect: Dictionary, text: String) -> void:
	var effect_type := str(effect.get("type", ""))
	for key in ["item", "flag", "id", "node", "enemy"]:
		effect.erase(key)
	var key_name := "item"
	match effect_type:
		"flag_set":
			key_name = "flag"
		"unlock_lore":
			key_name = "id"
		"open_map_node", "lock_map_node":
			key_name = "node"
		"start_combat":
			key_name = "enemy"
	effect[key_name] = text
	_mark_dirty()


func _set_effect_value(effect: Dictionary, text: String) -> void:
	var effect_type := str(effect.get("type", ""))
	if text == "":
		effect.erase("value")
		effect.erase("count")
		effect.erase("state")
	else:
		match effect_type:
			"item_add", "item_remove":
				effect["count"] = int(text) if text.is_valid_int() else 1
			"lock_map_node":
				effect["state"] = text
			_:
				effect["value"] = _parse_scalar(text)
	_mark_dirty()


func _parse_scalar(text: String):
	var clean := text.strip_edges()
	if clean.to_lower() == "true":
		return true
	if clean.to_lower() == "false":
		return false
	if clean.is_valid_int():
		return int(clean)
	if clean.is_valid_float():
		return float(clean)
	return clean

func _json_edit(label: String, value, setter: Callable) -> TextEdit:
	var caption := Label.new()
	caption.text = label + " (структурированные данные)"
	form.add_child(caption)
	var edit := TextEdit.new()
	edit.text = JSON.stringify(value, "\t")
	edit.custom_minimum_size.y = 100
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(func():
		var parsed = JSON.parse_string(edit.text)
		if parsed != null:
			setter.call(parsed)
			_set_status("Есть несохранённые изменения", false)
		else:
			_set_status("Ошибка JSON в поле «%s»" % label, true)
	)
	form.add_child(edit)
	return edit


func _section(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color("#9fd3e6"))
	form.add_child(label)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _split_csv(text: String) -> Array:
	var result: Array = []
	for part in text.split(","):
		var clean := part.strip_edges()
		if clean != "":
			result.append(clean)
	return result


func _string_array(value) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result


func _dictionary_path(kind: String) -> String:
	match kind:
		"items":
			return "%s/items.json" % DATA_ROOT
		"recipes":
			return "%s/recipes.json" % DATA_ROOT
		"lore":
			return "%s/lore.json" % DATA_ROOT
	return ""

func _normalize_json_value(value):
	if value is Dictionary:
		var result := {}
		for key in value.keys():
			result[key] = _normalize_json_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_normalize_json_value(item))
		return result
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return value


func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed = JSON.parse_string(file.get_as_text())
	return _normalize_json_value(parsed)


func _write_json(path: String, value) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t") + "\n")
	return true


func _mark_dirty() -> void:
	_dirty = true
	status.text = "Есть несохранённые изменения"


func _set_status(text: String, is_error: bool) -> void:
	status.text = text
	status.add_theme_color_override("font_color", Color("#f0b0b9") if is_error else Color("#9fd3e6"))
