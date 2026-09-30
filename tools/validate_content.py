#!/usr/bin/env python3
"""
Валидатор JSON-контента CosmoTextGame — см. tech-spec-v1.md раздел 12
и docs/CONTENT.md. Проверяет перекрёстные ссылки между
situations/locations/items/skills/recipes/enemies/lore/sectors без запуска Godot.
Запуск: python tools/validate_content.py (из корня проекта).
Код возврата: 0 — всё ок, 1 — найдены ошибки.
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")

# Должны совпадать с CharacterSystem.SLOTS / STAT_TITLES.
EQUIP_SLOTS = ("head", "body", "arms", "legs", "back")
STATS = ("armor", "melee_damage", "ranged_damage", "hit_chance", "flee_chance", "max_hp", "inventory_slots")
# Должны совпадать с ResourceSystem.DEFAULT_O2_COSTS.
O2_COST_KINDS = ("move", "elevator", "action", "choice", "combat_turn")
# Должны совпадать с CombatSystem: типы ИИ и предел дистанции.
ENEMY_AI_TYPES = ("brawler", "shooter", "turret")
MAX_COMBAT_RANGE = 5
# Пиксельные иллюстрации сцен (поле "image" у локаций, событий и ситуаций).
SCENE_ART_DIR = os.path.join(ROOT, "assets", "art", "scenes")

errors = []
warnings = []


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def load_optional(name):
    path = os.path.join(DATA, name)
    if not os.path.exists(path):
        return {}
    try:
        return load_json(path)
    except Exception as e:
        errors.append(f"{name}: {e}")
        return {}


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


def is_positive_int(value):
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


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
    if not is_positive_int(raw):
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


def check_stats(stats, ctx):
    if not isinstance(stats, dict):
        errors.append(f"{ctx}: ожидается объект характеристик")
        return
    for key, value in stats.items():
        if key not in STATS:
            errors.append(f"{ctx}: неизвестная характеристика '{key}' (допустимы: {', '.join(STATS)})")
        elif not is_number(value):
            errors.append(f"{ctx}.{key}: должно быть числом")


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

    skills = load_optional("skills.json")
    recipes = load_optional("recipes.json")
    endings = load_optional("endings.json")

    situations_raw = load_dir(os.path.join(DATA, "situations"))
    sectors_raw = load_dir(os.path.join(DATA, "sectors"))
    locations_raw = load_dir(os.path.join(DATA, "locations"))

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

    locations = {}
    for fname, data in locations_raw.items():
        lid = data.get("id")
        if not lid:
            errors.append(f"locations/{fname}: нет поля 'id'")
            continue
        if lid in locations:
            errors.append(f"locations/{fname}: дублирующийся id локации '{lid}'")
        locations[lid] = data

    event_keys = set()
    for lid, loc in locations.items():
        events = loc.get("events", [])
        if not isinstance(events, list):
            errors.append(f"locations/{lid}.events: ожидается массив")
            continue
        for ev in events:
            if isinstance(ev, dict) and ev.get("id"):
                key = f"{lid}/{ev['id']}"
                if key in event_keys:
                    errors.append(f"locations/{lid}: дублирующийся id события '{ev['id']}'")
                event_keys.add(key)

    # Замки и ключи: "unlocks" у предметов задаёт, какие замки открываются.
    lock_keys = {}
    for item_id, item in items.items():
        if not isinstance(item, dict):
            continue
        unlocks = item.get("unlocks", [])
        if not isinstance(unlocks, list):
            errors.append(f"items/{item_id}.unlocks: ожидается массив id замков")
            continue
        for lock_id in unlocks:
            if not isinstance(lock_id, str) or not lock_id.strip():
                errors.append(f"items/{item_id}.unlocks: id замка должен быть непустой строкой")
                continue
            lock_keys.setdefault(lock_id, []).append(item_id)
        if unlocks and item.get("category") != "key":
            warnings.append(f"items/{item_id}: предмет открывает замки, но его category не 'key'")
        if item.get("category") == "key" and not unlocks:
            errors.append(f"items/{item_id}: ключ без списка 'unlocks' ничего не открывает")

    def check_lock(lock, ctx):
        if not isinstance(lock, dict):
            errors.append(f"{ctx}.lock: ожидается объект {{ key, consume, text }}")
            return
        lock_id = lock.get("key", "")
        if not isinstance(lock_id, str) or not lock_id.strip():
            errors.append(f"{ctx}.lock.key: нужен непустой id замка")
        elif lock_id not in lock_keys:
            errors.append(f"{ctx}.lock.key: замок '{lock_id}' не открывает ни один предмет-ключ")
        if "consume" in lock and not isinstance(lock["consume"], bool):
            errors.append(f"{ctx}.lock.consume: должно быть true/false")
        if "text" in lock and not isinstance(lock["text"], str):
            errors.append(f"{ctx}.lock.text: должно быть строкой")

    def check_image(name, ctx):
        if name is None:
            return
        if not isinstance(name, str) or not name.strip():
            errors.append(f"{ctx}.image: должно быть именем файла без расширения")
            return
        if not os.path.exists(os.path.join(SCENE_ART_DIR, name + ".png")):
            errors.append(f"{ctx}.image: нет файла assets/art/scenes/{name}.png")

    all_node_ids = set()
    nodes_without_location = set()
    referenced_situations = set()
    referenced_locations = set()
    referenced_endings = set()

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

            if "situation_id" in node:
                errors.append(
                    f"sectors/{secid}: узел '{node_id}' использует устаревшее поле situation_id — "
                    f"перенесите ситуацию в событие локации и укажите location_id"
                )
            is_elevator = isinstance(node_map, dict) and str(node_map.get("kind", "")) == "elevator"
            loc_id = node.get("location_id", "")
            if loc_id:
                referenced_locations.add(loc_id)
                if loc_id not in locations:
                    errors.append(f"sectors/{secid}: узел '{node_id}' ссылается на неизвестную локацию '{loc_id}'")
                if is_elevator:
                    warnings.append(f"sectors/{secid}: лифт '{node_id}' имеет location_id — лифт её не открывает")
            elif not is_elevator:
                nodes_without_location.add(node_id)
                if node.get("state", "locked") != "locked":
                    errors.append(f"sectors/{secid}: доступный узел '{node_id}' без location_id — клик по нему ничего не сделает")
                else:
                    warnings.append(f"sectors/{secid}: закрытый узел '{node_id}' пока без location_id")
            if "lock" in node:
                check_lock(node["lock"], f"sectors/{secid}.{node_id}")
                if node.get("state", "locked") != "locked":
                    warnings.append(f"sectors/{secid}: у узла '{node_id}' есть замок, но он не 'locked' — ключ не понадобится")
            for conn in node.get("connections", []):
                if conn not in nodes:
                    warnings.append(
                        f"sectors/{secid}: узел '{node_id}' связан с несуществующим узлом '{conn}' (в этом же секторе)"
                    )

    def check_requires(reqs, ctx, loc_id=None):
        if not isinstance(reqs, list):
            errors.append(f"{ctx}: ожидается массив условий")
            return
        for req in reqs:
            if not isinstance(req, dict):
                errors.append(f"{ctx}: условие должно быть объектом")
                continue
            t = req.get("type")
            if t == "has_item":
                item = req.get("item", "")
                if item not in items:
                    errors.append(f"{ctx}: requires.has_item ссылается на неизвестный предмет '{item}'")
            elif t == "flag":
                pass  # флаги не в справочнике — ничего не проверяем
            elif t == "stat_gte":
                if req.get("stat", "hp") not in ("hp", "o2", "ammo"):
                    errors.append(f"{ctx}: stat_gte.stat должен быть hp, o2 или ammo")
            elif t == "skill_gte":
                if req.get("skill", "") not in skills:
                    errors.append(f"{ctx}: skill_gte ссылается на неизвестный навык '{req.get('skill', '')}'")
                if not is_positive_int(req.get("value", 1)):
                    errors.append(f"{ctx}: skill_gte.value должен быть положительным целым")
            elif t == "in_location":
                if req.get("location", "") not in locations:
                    errors.append(f"{ctx}: in_location ссылается на неизвестную локацию '{req.get('location', '')}'")
            elif t == "event_done":
                ref = str(req.get("event", ""))
                if not ref:
                    errors.append(f"{ctx}: event_done без поля 'event'")
                    continue
                if "/" in ref:
                    key = ref
                elif loc_id:
                    key = f"{loc_id}/{ref}"
                else:
                    errors.append(f"{ctx}: event_done '{ref}' вне локации — укажите полный id 'локация/событие'")
                    continue
                if key not in event_keys:
                    errors.append(f"{ctx}: event_done ссылается на неизвестное событие '{key}'")
            elif t == "has_key":
                lock_id = req.get("lock", "")
                if lock_id not in lock_keys:
                    errors.append(f"{ctx}: has_key ссылается на замок '{lock_id}', который не открывает ни один ключ")
            elif t in ("visits_gte", "visits_lte"):
                value = req.get("value")
                if not isinstance(value, int) or isinstance(value, bool) or value < 0:
                    errors.append(f"{ctx}: {t}.value должен быть неотрицательным целым")
            elif t is None:
                errors.append(f"{ctx}: requires-запись без 'type'")
            else:
                warnings.append(f"{ctx}: неизвестный тип requires '{t}'")

    def check_effects(effects, ctx):
        if not isinstance(effects, list):
            errors.append(f"{ctx}: ожидается массив эффектов")
            return
        for eff in effects:
            if not isinstance(eff, dict):
                errors.append(f"{ctx}: эффект должен быть объектом")
                continue
            t = eff.get("type")
            if t == "item_add" or t == "item_remove":
                item = eff.get("item", "")
                if item not in items:
                    errors.append(f"{ctx}: effect '{t}' ссылается на неизвестный предмет '{item}'")
                if "count" in eff and not is_positive_int(eff["count"]):
                    errors.append(f"{ctx}: effect '{t}'.count должен быть положительным целым")
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
                for key in ("on_win", "on_flee"):
                    if key in eff:
                        check_effects(eff[key], f"{ctx}.{key}")
            elif t in ("open_map_node", "lock_map_node"):
                node = eff.get("node", "")
                if node not in all_node_ids:
                    errors.append(f"{ctx}: effect '{t}' ссылается на неизвестный узел карты '{node}'")
                elif t == "open_map_node" and node in nodes_without_location:
                    errors.append(f"{ctx}: effect 'open_map_node' открывает узел '{node}' без location_id")
            elif t == "skill_points_add":
                value = eff.get("value", 1)
                if not isinstance(value, int) or isinstance(value, bool):
                    errors.append(f"{ctx}: skill_points_add.value должен быть целым")
            elif t == "end_run":
                ending = eff.get("ending", "")
                referenced_endings.add(ending)
                if ending not in endings:
                    errors.append(f"{ctx}: effect 'end_run' ссылается на неизвестный финал '{ending}'")
            elif t in ("hp_delta", "o2_delta", "ammo_delta", "flag_set", "reveal_map"):
                pass
            elif t is None:
                errors.append(f"{ctx}: effect-запись без 'type'")
            else:
                warnings.append(f"{ctx}: неизвестный тип effect '{t}'")

    for sid, sit in situations.items():
        if "requires" in sit:
            errors.append(
                f"situations/{sid}: поле 'requires' верхнего уровня не поддерживается "
                f"движком — условия задаются у вариантов (options[].requires) "
                f"или у события локации (events[].triggers)"
            )
        check_image(sit.get("image"), f"situations/{sid}")
        for opt in sit.get("options", []):
            opt_ctx = f"situations/{sid}#{opt.get('id', '?')}"
            check_requires(opt.get("requires", []), opt_ctx)
            check_effects(opt.get("effects", []), opt_ctx)
            if not str(opt.get("result", "")).strip():
                errors.append(f"{opt_ctx}: нет текста последствия (result) — игроку нечего показать перед «Продолжить»")
            nxt = opt.get("next", "")
            if nxt and not nxt.startswith("map:"):
                referenced_situations.add(nxt)
            if nxt and not nxt.startswith("map:") and nxt not in situations:
                errors.append(f"{opt_ctx}: next ссылается на неизвестную ситуацию '{nxt}'")
            if nxt.startswith("map:"):
                sector_id = nxt[len("map:"):]
                if sector_id not in sectors:
                    errors.append(f"{opt_ctx}: next='map:{sector_id}' ссылается на неизвестный сектор")

    events_total = 0
    for lid, loc in locations.items():
        ctx = f"locations/{lid}"
        check_image(loc.get("image"), ctx)
        if "base" in loc and not isinstance(loc["base"], bool):
            errors.append(f"{ctx}.base: должно быть true/false")
        if not str(loc.get("description", "")).strip():
            warnings.append(f"{ctx}: нет базового описания (description)")
        variants = loc.get("descriptions", [])
        if not isinstance(variants, list):
            errors.append(f"{ctx}.descriptions: ожидается массив")
        else:
            for i, variant in enumerate(variants):
                if not isinstance(variant, dict) or not str(variant.get("text", "")).strip():
                    errors.append(f"{ctx}.descriptions[{i}]: нужен объект с непустым text")
                    continue
                check_requires(variant.get("requires", []), f"{ctx}.descriptions[{i}]", lid)
        events = loc.get("events", [])
        if not isinstance(events, list):
            continue
        for i, ev in enumerate(events):
            if not isinstance(ev, dict):
                errors.append(f"{ctx}.events[{i}]: событие должно быть объектом")
                continue
            events_total += 1
            eid = ev.get("id")
            ev_ctx = f"{ctx}#{eid or i}"
            if not eid:
                errors.append(f"{ev_ctx}: у события нет id")
            start = ev.get("start")
            if start not in ("auto", "manual"):
                errors.append(f"{ev_ctx}: start должен быть 'auto' или 'manual'")
            if start == "manual" and not str(ev.get("label", "")).strip():
                errors.append(f"{ev_ctx}: у ручного события нужен label (текст пункта меню)")
            if "repeatable" in ev and not isinstance(ev["repeatable"], bool):
                errors.append(f"{ev_ctx}: repeatable должен быть true/false")
            check_requires(ev.get("triggers", []), f"{ev_ctx}.triggers", lid)
            check_effects(ev.get("effects", []), ev_ctx)
            check_image(ev.get("image"), ev_ctx)
            if "lock" in ev:
                check_lock(ev["lock"], ev_ctx)
            sit = ev.get("situation", "")
            if sit:
                referenced_situations.add(sit)
                if sit not in situations:
                    errors.append(f"{ev_ctx}: situation ссылается на неизвестную ситуацию '{sit}'")
            if not sit and not ev.get("effects") and not str(ev.get("text", "")).strip():
                errors.append(f"{ev_ctx}: событие ничего не делает — нужна situation, text или effects")

    for lid in sorted(locations):
        if lid not in referenced_locations:
            warnings.append(f"locations/{lid}: локация не привязана ни к одному узлу карты")

    for end_id, ending in endings.items():
        ctx = f"endings/{end_id}"
        if not isinstance(ending, dict):
            errors.append(f"{ctx}: ожидается объект")
            continue
        if not str(ending.get("title", "")).strip():
            errors.append(f"{ctx}: нет заголовка (title)")
        if not str(ending.get("text", "")).strip():
            errors.append(f"{ctx}: нет текста финала (text)")
        if end_id not in referenced_endings:
            warnings.append(f"{ctx}: финал недостижим — ни один effect 'end_run' на него не ссылается")

    for eid, enemy in enemies.items():
        for special in enemy.get("special_actions", []):
            check_requires(special.get("requires", []), f"enemies/{eid}#{special.get('id', '?')}")
            eff_type = special.get("effect", {}).get("type")
            if eff_type not in ("distract",):
                warnings.append(f"enemies/{eid}#{special.get('id', '?')}: неизвестный тип spec-эффекта '{eff_type}'")
        ai = enemy.get("ai", "brawler")
        if ai not in ENEMY_AI_TYPES:
            errors.append(f"enemies/{eid}.ai: '{ai}' — допустимы {', '.join(ENEMY_AI_TYPES)}")
        attack = enemy.get("attack", {})
        if not isinstance(attack, dict):
            errors.append(f"enemies/{eid}.attack: ожидается объект")
        else:
            reach = attack.get("range", 1)
            if not is_positive_int(reach) or reach > MAX_COMBAT_RANGE:
                errors.append(f"enemies/{eid}.attack.range: целое от 1 до {MAX_COMBAT_RANGE}")
        for field in ("start_range", "preferred_range"):
            if field in enemy:
                value = enemy[field]
                if not isinstance(value, int) or isinstance(value, bool) or value < 0 or value > MAX_COMBAT_RANGE:
                    errors.append(f"enemies/{eid}.{field}: целое от 0 до {MAX_COMBAT_RANGE}")
        for loot_item in enemy.get("loot", []):
            if loot_item not in items:
                errors.append(f"enemies/{eid}: loot ссылается на неизвестный предмет '{loot_item}'")

    for item_id, item in items.items():
        ctx = f"items/{item_id}"
        if "use_effect" in item:
            check_effects([item["use_effect"]], f"{ctx}.use_effect")
        slot = item.get("equip_slot")
        if slot is not None:
            if slot not in EQUIP_SLOTS:
                errors.append(f"{ctx}.equip_slot: '{slot}' — допустимы {', '.join(EQUIP_SLOTS)}")
            if item.get("stackable"):
                warnings.append(f"{ctx}: надеваемый предмет не должен стакаться")
        if "stats" in item:
            check_stats(item["stats"], f"{ctx}.stats")
            if slot is None:
                warnings.append(f"{ctx}: stats действуют только у надеваемых предметов (нет equip_slot)")
        interactions = item.get("interactions", [])
        if not isinstance(interactions, list):
            errors.append(f"{ctx}.interactions: ожидается массив")
            continue
        seen_ids = set()
        for i, inter in enumerate(interactions):
            if not isinstance(inter, dict):
                errors.append(f"{ctx}.interactions[{i}]: ожидается объект")
                continue
            iid = inter.get("id")
            ictx = f"{ctx}.interactions#{iid or i}"
            if not iid:
                errors.append(f"{ictx}: нет id")
            elif iid in seen_ids:
                errors.append(f"{ictx}: дублирующийся id")
            seen_ids.add(iid)
            if not str(inter.get("label", "")).strip():
                errors.append(f"{ictx}: нужен label (текст кнопки)")
            if "consume" in inter and not isinstance(inter["consume"], bool):
                errors.append(f"{ictx}: consume должен быть true/false")
            check_requires(inter.get("requires", []), ictx)
            check_effects(inter.get("effects", []), ictx)

    for skill_id, skill in skills.items():
        ctx = f"skills/{skill_id}"
        if not isinstance(skill, dict):
            errors.append(f"{ctx}: ожидается объект")
            continue
        if not str(skill.get("name", "")).strip():
            errors.append(f"{ctx}: нет name")
        if not is_positive_int(skill.get("max_level")):
            errors.append(f"{ctx}.max_level: должно быть положительным целым")
        if "cost" in skill and not is_positive_int(skill["cost"]):
            errors.append(f"{ctx}.cost: должно быть положительным целым")
        check_stats(skill.get("per_level", {}), f"{ctx}.per_level")

    for recipe_id, recipe in recipes.items():
        ctx = f"recipes/{recipe_id}"
        if not isinstance(recipe, dict):
            errors.append(f"{ctx}: ожидается объект")
            continue
        result = recipe.get("result")
        if not isinstance(result, dict) or result.get("item") not in items:
            errors.append(f"{ctx}.result: нужен объект с существующим item")
        elif "count" in result and not is_positive_int(result["count"]):
            errors.append(f"{ctx}.result.count: должно быть положительным целым")
        ingredients = recipe.get("ingredients", [])
        if not isinstance(ingredients, list) or not ingredients:
            errors.append(f"{ctx}.ingredients: нужен непустой массив")
        else:
            for i, ing in enumerate(ingredients):
                if not isinstance(ing, dict) or ing.get("item") not in items:
                    errors.append(f"{ctx}.ingredients[{i}]: неизвестный предмет")
                elif "count" in ing and not is_positive_int(ing["count"]):
                    errors.append(f"{ctx}.ingredients[{i}].count: должно быть положительным целым")
        check_requires(recipe.get("requires", []), ctx)

    start_equipment = config.get("start_equipment", {})
    if not isinstance(start_equipment, dict):
        errors.append("config.json: start_equipment должен быть объектом {слот: предмет}")
    else:
        for slot, item_id in start_equipment.items():
            if slot not in EQUIP_SLOTS:
                errors.append(f"config.json: start_equipment — неизвестный слот '{slot}'")
            elif item_id not in items:
                errors.append(f"config.json: start_equipment.{slot} — неизвестный предмет '{item_id}'")
            elif items[item_id].get("equip_slot") != slot:
                errors.append(f"config.json: start_equipment.{slot} — '{item_id}' надевается в слот '{items[item_id].get('equip_slot')}'")
    start_points = config.get("start_skill_points", 0)
    if not isinstance(start_points, int) or isinstance(start_points, bool) or start_points < 0:
        errors.append("config.json: start_skill_points должен быть неотрицательным целым")

    start_o2 = config.get("start_o2")
    if not is_number(start_o2) or start_o2 <= 0:
        errors.append("config.json: start_o2 должен быть положительным числом")
    o2_costs = config.get("o2_costs", {})
    if not isinstance(o2_costs, dict):
        errors.append("config.json: o2_costs должен быть объектом {действие: цена}")
    else:
        for kind, value in o2_costs.items():
            if kind not in O2_COST_KINDS:
                errors.append(f"config.json: o2_costs — неизвестное действие '{kind}' (допустимы: {', '.join(O2_COST_KINDS)})")
            elif not is_number(value) or value < 0:
                errors.append(f"config.json: o2_costs.{kind} — цена должна быть неотрицательным числом")
        for kind in O2_COST_KINDS:
            if kind not in o2_costs:
                warnings.append(f"config.json: o2_costs.{kind} не задан — взята цена по умолчанию из ResourceSystem")
    multiplier = config.get("o2_unsealed_multiplier", 1.0)
    if not is_number(multiplier) or multiplier < 1.0:
        errors.append("config.json: o2_unsealed_multiplier должен быть числом не меньше 1")

    for sid in sorted(situations):
        if sid not in referenced_situations:
            warnings.append(f"situations/{sid}: ситуация не достижима из стартового конфига, событий или next-ссылок")

    print(f"Локаций: {len(locations)} (событий: {events_total}) | Ситуаций: {len(situations)} | "
          f"Секторов: {len(sectors)} | Предметов: {len(items)} | Навыков: {len(skills)} | "
          f"Рецептов: {len(recipes)} | Врагов: {len(enemies)} | Лор-фрагментов: {len(lore)} | "
          f"Финалов: {len(endings)}")

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
