#!/usr/bin/env python3
"""
Валидатор JSON-контента CosmoTextGame — см. tech-spec-v1.md раздел 12.
Проверяет перекрёстные ссылки между situations/items/enemies/lore/sectors
без запуска Godot. Запуск: python3 tools/validate_content.py (из корня проекта).
Код возврата: 0 — всё ок, 1 — найдены ошибки.
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")

errors = []
warnings = []


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def load_dir(path):
    result = {}
    if not os.path.isdir(path):
        return result
    for name in sorted(os.listdir(path)):
        if name.endswith(".json"):
            full = os.path.join(path, name)
            try:
                result[name] = load_json(full)
            except json.JSONDecodeError as e:
                errors.append(f"{name}: невалидный JSON — {e}")
    return result


def is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def read_xy(raw, ctx, required=True):
    if not isinstance(raw, dict):
        if required:
            errors.append(f"{ctx}: ожидается объект с числовыми x/y")
        return None

    for key in ("x", "y"):
        if key not in raw or not is_number(raw[key]):
            errors.append(f"{ctx}: поле '{key}' должно быть числом")
            return None
    return float(raw["x"]), float(raw["y"])


def read_positive_int(raw, ctx, required=False):
    if raw is None:
        if required:
            errors.append(f"{ctx}: поле обязательно")
        return None
    if not isinstance(raw, int) or isinstance(raw, bool) or raw <= 0:
        errors.append(f"{ctx}: должно быть положительным целым числом")
        return None
    return raw


def read_cell(raw, ctx):
    if not isinstance(raw, dict):
        errors.append(f"{ctx}: ожидается объект с целыми x/y")
        return None

    result = []
    for key in ("x", "y"):
        value = raw.get(key)
        if not is_number(value) or int(value) != value:
            errors.append(f"{ctx}: поле '{key}' должно быть целым числом")
            return None
        result.append(int(value))
    return tuple(result)


def main():
    config = {}
    try:
        config = load_json(os.path.join(DATA, "config.json"))
    except Exception as e:
        errors.append(f"config.json: {e}")

    try:
        items = load_json(os.path.join(DATA, "items.json"))
    except Exception as e:
        errors.append(f"items.json: {e}")
        items = {}

    try:
        enemies = load_json(os.path.join(DATA, "enemies.json"))
    except Exception as e:
        errors.append(f"enemies.json: {e}")
        enemies = {}

    try:
        lore = load_json(os.path.join(DATA, "lore.json"))
    except Exception as e:
        errors.append(f"lore.json: {e}")
        lore = {}

    situations_raw = load_dir(os.path.join(DATA, "situations"))
    sectors_raw = load_dir(os.path.join(DATA, "sectors"))

    situations = {}
    for fname, data in situations_raw.items():
        sid = data.get("id")
        if not sid:
            errors.append(f"situations/{fname}: нет поля 'id'")
            continue
        if sid in situations:
            errors.append(f"situations/{fname}: дублирующийся id ситуации '{sid}'")
        situations[sid] = data

    sectors = {}
    for fname, data in sectors_raw.items():
        secid = data.get("id")
        if not secid:
            errors.append(f"sectors/{fname}: нет поля 'id'")
            continue
        sectors[secid] = data

    all_node_ids = set()
    referenced_situations = set()

    start_sector = config.get("start_sector_id", "")
    if start_sector and start_sector not in sectors:
        errors.append(f"config.json: start_sector_id ссылается на неизвестный сектор '{start_sector}'")

    opening_situation = config.get("opening_situation_id", "")
    if opening_situation:
        referenced_situations.add(opening_situation)
        if opening_situation not in situations:
            errors.append(
                f"config.json: opening_situation_id ссылается на неизвестную ситуацию '{opening_situation}'"
            )
    for secid, sec in sectors.items():
        nodes = sec.get("nodes", {})
        if not isinstance(nodes, dict):
            errors.append(f"sectors/{secid}: nodes должен быть объектом")
            continue

        default_floor = ""
        floor_ids = set()
        grid_columns = None
        grid_rows = None
        map_size = None
        map_cfg = sec.get("map", {})
        if map_cfg:
            if not isinstance(map_cfg, dict):
                errors.append(f"sectors/{secid}.map: ожидается объект")
            else:
                if "size" in map_cfg:
                    map_size = read_xy(map_cfg.get("size", {}), f"sectors/{secid}.map.size")
                viewport_height = map_cfg.get("viewport_height", None)
                if viewport_height is not None and (not is_number(viewport_height) or viewport_height <= 0):
                    errors.append(f"sectors/{secid}.map.viewport_height должен быть положительным числом")
                grid_step = map_cfg.get("grid_step", None)
                if grid_step is not None and (not is_number(grid_step) or grid_step <= 0):
                    errors.append(f"sectors/{secid}.map.grid_step должен быть положительным числом")
                grid_columns = read_positive_int(map_cfg.get("grid_columns"), f"sectors/{secid}.map.grid_columns")
                grid_rows = read_positive_int(map_cfg.get("grid_rows"), f"sectors/{secid}.map.grid_rows")
                cell_size = read_xy(map_cfg.get("cell_size", {}), f"sectors/{secid}.map.cell_size", required=False)
                if cell_size:
                    sx, sy = cell_size
                    if sx <= 0 or sy <= 0:
                        errors.append(f"sectors/{secid}.map.cell_size: размеры должны быть положительными")
                module_size = read_xy(map_cfg.get("module_size", {}), f"sectors/{secid}.map.module_size", required=False)
                if module_size:
                    sx, sy = module_size
                    if sx <= 0 or sy <= 0:
                        errors.append(f"sectors/{secid}.map.module_size: размеры должны быть положительными")
                if grid_columns and grid_rows and cell_size:
                    map_size = (grid_columns * cell_size[0], grid_rows * cell_size[1])

                floors = map_cfg.get("floors", [])
                if floors:
                    if not isinstance(floors, list):
                        errors.append(f"sectors/{secid}.map.floors: ожидается массив")
                    else:
                        for index, floor in enumerate(floors):
                            if not isinstance(floor, dict):
                                errors.append(f"sectors/{secid}.map.floors[{index}]: ожидается объект")
                                continue
                            floor_id = str(floor.get("id", ""))
                            if not floor_id:
                                errors.append(f"sectors/{secid}.map.floors[{index}]: нет поля 'id'")
                            elif floor_id in floor_ids:
                                errors.append(f"sectors/{secid}.map.floors: дублирующаяся палуба '{floor_id}'")
                            else:
                                floor_ids.add(floor_id)
                default_floor = str(map_cfg.get("default_floor", ""))
                if default_floor and floor_ids and default_floor not in floor_ids:
                    errors.append(f"sectors/{secid}.map.default_floor ссылается на неизвестную палубу '{default_floor}'")

        for node_id, node in nodes.items():
            all_node_ids.add(node_id)
        hub = sec.get("hub_node", "")
        if hub and hub not in nodes:
            errors.append(f"sectors/{secid}: hub_node '{hub}' не найден среди nodes")
        seen_cells = {}
        for node_id, node in nodes.items():
            if not isinstance(node, dict):
                errors.append(f"sectors/{secid}: узел '{node_id}' должен быть объектом")
                continue
            node_map = node.get("map", {})
            if node_map:
                if not isinstance(node_map, dict):
                    errors.append(f"sectors/{secid}.{node_id}.map: ожидается объект")
                else:
                    floor_id = str(node_map.get("floor", default_floor))
                    if floor_id and floor_ids and floor_id not in floor_ids:
                        errors.append(f"sectors/{secid}.{node_id}.map.floor ссылается на неизвестную палубу '{floor_id}'")

                    if "cell" in node_map:
                        cell = read_cell(node_map.get("cell", {}), f"sectors/{secid}.{node_id}.map.cell")
                        if cell:
                            cx, cy = cell
                            if grid_columns and (cx < 1 or cx > grid_columns):
                                warnings.append(f"sectors/{secid}.{node_id}.map.cell.x: клетка за пределами сетки 1..{grid_columns}")
                            if grid_rows and (cy < 1 or cy > grid_rows):
                                warnings.append(f"sectors/{secid}.{node_id}.map.cell.y: клетка за пределами сетки 1..{grid_rows}")
                            cell_key = (floor_id, cx, cy)
                            if cell_key in seen_cells:
                                warnings.append(
                                    f"sectors/{secid}: узлы '{node_id}' и '{seen_cells[cell_key]}' стоят в одной клетке {floor_id}:{cx},{cy}"
                                )
                            else:
                                seen_cells[cell_key] = node_id
                    elif "position" in node_map:
                        position = read_xy(node_map.get("position", {}), f"sectors/{secid}.{node_id}.map.position")
                        if position and map_size:
                            x, y = position
                            width, height = map_size
                            if x < 0 or y < 0 or x > width or y > height:
                                warnings.append(
                                    f"sectors/{secid}.{node_id}.map.position: координаты за пределами карты {width:g}x{height:g}"
                                )
                    else:
                        warnings.append(f"sectors/{secid}.{node_id}: нет map.cell/map.position, UI карты поставит узел автоматически")

                    if str(node_map.get("kind", "")) == "elevator":
                        target_floor = str(node_map.get("target_floor", ""))
                        if not target_floor:
                            errors.append(f"sectors/{secid}.{node_id}: лифт должен иметь map.target_floor")
                        elif floor_ids and target_floor not in floor_ids:
                            errors.append(f"sectors/{secid}.{node_id}.map.target_floor ссылается на неизвестную палубу '{target_floor}'")

                    if "position" in node_map and "cell" in node_map:
                        position = read_xy(node_map.get("position", {}), f"sectors/{secid}.{node_id}.map.position")
                        if position and map_size:
                            x, y = position
                            width, height = map_size
                            if x < 0 or y < 0 or x > width or y > height:
                                warnings.append(
                                    f"sectors/{secid}.{node_id}.map.position: координаты за пределами карты {width:g}x{height:g}"
                                )
                    if "size" in node_map:
                        node_size = read_xy(node_map["size"], f"sectors/{secid}.{node_id}.map.size")
                        if node_size:
                            sx, sy = node_size
                            if sx <= 0 or sy <= 0:
                                errors.append(f"sectors/{secid}.{node_id}.map.size: размеры должны быть положительными")
            elif node.get("state", "locked") != "locked":
                warnings.append(f"sectors/{secid}.{node_id}: нет map.cell/map.position, UI карты поставит узел автоматически")

            sit_id = node.get("situation_id", "")
            if sit_id:
                referenced_situations.add(sit_id)
            if sit_id and sit_id not in situations:
                errors.append(
                    f"sectors/{secid}: узел '{node_id}' ссылается на неизвестную ситуацию '{sit_id}'"
                )
            for conn in node.get("connections", []):
                if conn not in nodes:
                    warnings.append(
                        f"sectors/{secid}: узел '{node_id}' связан с несуществующим узлом '{conn}' (в этом же секторе)"
                    )

    def check_requires(reqs, ctx):
        for req in reqs or []:
            t = req.get("type")
            if t == "has_item":
                item = req.get("item", "")
                if item not in items:
                    errors.append(f"{ctx}: requires.has_item ссылается на неизвестный предмет '{item}'")
            elif t == "flag":
                pass  # флаги не в справочнике — ничего не проверяем
            elif t == "stat_gte":
                pass
            elif t is None:
                errors.append(f"{ctx}: requires-запись без 'type'")
            else:
                warnings.append(f"{ctx}: неизвестный тип requires '{t}'")

    def check_effects(effects, ctx):
        for eff in effects or []:
            t = eff.get("type")
            if t == "item_add" or t == "item_remove":
                item = eff.get("item", "")
                if item not in items:
                    errors.append(f"{ctx}: effect '{t}' ссылается на неизвестный предмет '{item}'")
            elif t == "unlock_lore":
                lore_id = eff.get("id", "")
                if lore_id not in lore:
                    errors.append(f"{ctx}: effect 'unlock_lore' ссылается на неизвестный фрагмент '{lore_id}'")
            elif t == "start_combat":
                enemy = eff.get("enemy", "")
                if enemy not in enemies:
                    errors.append(f"{ctx}: effect 'start_combat' ссылается на неизвестного врага '{enemy}'")
                clear_node = eff.get("clear_node", "")
                if clear_node and clear_node not in all_node_ids:
                    errors.append(f"{ctx}: effect 'start_combat' clear_node ссылается на неизвестный узел '{clear_node}'")
            elif t in ("open_map_node", "lock_map_node"):
                node = eff.get("node", "")
                if node not in all_node_ids:
                    errors.append(f"{ctx}: effect '{t}' ссылается на неизвестный узел карты '{node}'")
            elif t in ("hp_delta", "o2_delta", "ammo_delta", "flag_set"):
                pass
            elif t is None:
                errors.append(f"{ctx}: effect-запись без 'type'")
            else:
                warnings.append(f"{ctx}: неизвестный тип effect '{t}'")

    for sid, sit in situations.items():
        check_requires(sit.get("requires", []), f"situations/{sid}")
        for opt in sit.get("options", []):
            opt_ctx = f"situations/{sid}#{opt.get('id', '?')}"
            check_requires(opt.get("requires", []), opt_ctx)
            check_effects(opt.get("effects", []), opt_ctx)
            nxt = opt.get("next", "")
            if nxt and not nxt.startswith("map:"):
                referenced_situations.add(nxt)
            if nxt and not nxt.startswith("map:") and nxt not in situations:
                errors.append(f"{opt_ctx}: next ссылается на неизвестную ситуацию '{nxt}'")
            if nxt.startswith("map:"):
                sector_id = nxt[len("map:"):]
                if sector_id not in sectors:
                    errors.append(f"{opt_ctx}: next='map:{sector_id}' ссылается на неизвестный сектор")

    for eid, enemy in enemies.items():
        for special in enemy.get("special_actions", []):
            check_requires(special.get("requires", []), f"enemies/{eid}#{special.get('id', '?')}")
            eff_type = special.get("effect", {}).get("type")
            if eff_type not in ("skip_enemy_turn_and_guarantee_hit",):
                warnings.append(f"enemies/{eid}#{special.get('id', '?')}: неизвестный тип spec-эффекта '{eff_type}'")
        for loot_item in enemy.get("loot", []):
            if loot_item not in items:
                errors.append(f"enemies/{eid}: loot ссылается на неизвестный предмет '{loot_item}'")

    for item_id, item in items.items():
        if "use_effect" in item:
            check_effects([item["use_effect"]], f"items/{item_id}.use_effect")

    for sid in sorted(situations):
        if sid not in referenced_situations:
            warnings.append(f"situations/{sid}: ситуация не достижима из стартового конфига, карты или next-ссылок")

    print(f"Ситуаций: {len(situations)} | Секторов: {len(sectors)} | Предметов: {len(items)} | "
          f"Врагов: {len(enemies)} | Лор-фрагментов: {len(lore)}")

    if warnings:
        print(f"\nПредупреждения ({len(warnings)}):")
        for w in warnings:
            print(f"  ! {w}")

    if errors:
        print(f"\nОШИБКИ ({len(errors)}):")
        for e in errors:
            print(f"  x {e}")
        print("\nВАЛИДАЦИЯ НЕ ПРОЙДЕНА")
        return 1

    print("\nВалидация пройдена: битых ссылок не найдено.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
