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
STATS = ("armor", "melee_damage", "ranged_damage", "hit_chance", "flee_chance", "max_hp", "inventory_slots",
         "explore_rolls", "find_chance")
# Должны совпадать с ResourceSystem.DEFAULT_O2_COSTS.
O2_COST_KINDS = ("move", "elevator", "action", "explore_tick", "choice", "combat_turn")
# Должны совпадать с ProgressionSystem.DEFAULT_CONFIG (секция config.json → xp).
XP_CONFIG_KEYS = ("explore", "craft", "lore", "kill", "level_base", "level_step", "skill_points_per_level")
# Должны совпадать с NeedsSystem.DEFAULT_CONFIG (секция config.json → needs).
NEEDS_CONFIG_KEYS = ("max_energy", "max_hunger", "energy_costs", "hunger_costs", "tired_energy",
                     "tired_hit_penalty", "hungry_hunger", "hungry_energy_multiplier", "starving_hp",
                     "sleep_hunger", "sleep_hp", "pass_out_o2", "pass_out_energy", "pass_out_hunger")
# Должны совпадать с CombatSystem: типы ИИ и предел дистанции.
ENEMY_AI_TYPES = ("brawler", "shooter", "turret")
MAX_COMBAT_RANGE = 5
# Пиксельные иллюстрации сцен (поле "image" у локаций, событий и ситуаций).
SCENE_ART_DIR = os.path.join(ROOT, "assets", "art", "scenes")
SOUND_DIR = os.path.join(ROOT, "assets", "sounds")

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

    try:
        codex = load_json(os.path.join(DATA, "codex.json"))
    except Exception as e:
        errors.append(f"codex.json: {e}")
        codex = {}

    try:
        quests_data = load_json(os.path.join(DATA, "quests.json"))
    except Exception as e:
        errors.append(f"quests.json: {e}")
        quests_data = {}

    try:
        explore_pools = load_json(os.path.join(DATA, "explore_pools.json"))
    except Exception as e:
        errors.append(f"explore_pools.json: {e}")
        explore_pools = {}

    skills = load_optional("skills.json")
    recipes = load_optional("recipes.json")
    endings = load_optional("endings.json")
    # Кольцевое дерево навыков, происхождения и знание (SkillTreeSystem).
    skill_tree = load_optional("skill_tree.json")
    knowledge = load_optional("knowledge.json")
    origins = load_optional("origins.json")
    tree_sectors = skill_tree.get("sectors", {}) if isinstance(skill_tree.get("sectors", {}), dict) else {}
    tree_nodes = skill_tree.get("nodes", {}) if isinstance(skill_tree.get("nodes", {}), dict) else {}
    tree_practice = skill_tree.get("practice", {}) if isinstance(skill_tree.get("practice", {}), dict) else {}

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

    def check_sound(name, ctx):
        if name is None:
            return
        if not isinstance(name, str) or not name.strip():
            errors.append(f"{ctx}.sound: должно быть именем файла без расширения")
            return
        if not os.path.exists(os.path.join(SOUND_DIR, name + ".wav")):
            errors.append(f"{ctx}.sound: нет файла assets/sounds/{name}.wav")

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

                    if "hidden_until_open" in node_map and not isinstance(node_map["hidden_until_open"], bool):
                        errors.append(
                            f"sectors/{secid}.{node_id}.map.hidden_until_open должен быть bool"
                        )

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
                        else:
                            # Поездка — шаг маршрута к связанному лифту палубы target_floor.
                            linked = set(node.get("connections", []) or [])
                            linked |= {oid for oid, other in nodes.items()
                                       if isinstance(other, dict) and node_id in (other.get("connections", []) or [])}
                            pairs = [oid for oid in linked
                                     if isinstance(nodes.get(oid), dict)
                                     and isinstance(nodes[oid].get("map"), dict)
                                     and str(nodes[oid]["map"].get("kind", "")) == "elevator"
                                     and str(nodes[oid]["map"].get("floor", default_floor)) == target_floor]
                            if not pairs:
                                errors.append(
                                    f"sectors/{secid}.{node_id}: лифт не связан с лифтом палубы '{target_floor}' — ехать некуда"
                                )

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
            elif t == "knowledge":
                kid = req.get("knowledge", "")
                if kid not in knowledge:
                    errors.append(f"{ctx}: requires.knowledge ссылается на неизвестное знание '{kid}'")
            elif t == "node_bought":
                nid = req.get("node", "")
                if nid not in tree_nodes:
                    errors.append(f"{ctx}: requires.node_bought ссылается на неизвестный узел дерева '{nid}'")
            elif t == "practice_gte":
                pid = req.get("practice", "")
                if pid not in tree_practice:
                    errors.append(f"{ctx}: requires.practice_gte ссылается на неизвестную практику '{pid}'")
                if not is_positive_int(req.get("value", 1)):
                    errors.append(f"{ctx}: practice_gte.value должен быть положительным целым")
            elif t == "tag":
                if not str(req.get("tag", "")).strip():
                    errors.append(f"{ctx}: tag без непустого поля 'tag'")
            elif t == "origin":
                oid = req.get("origin", "")
                if oid not in origins:
                    errors.append(f"{ctx}: requires.origin ссылается на неизвестное происхождение '{oid}'")
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
            elif t == "unlock_knowledge":
                kid = eff.get("knowledge", "")
                if kid not in knowledge:
                    errors.append(f"{ctx}: effect 'unlock_knowledge' ссылается на неизвестное знание '{kid}'")
            elif t == "practice_add":
                pid = eff.get("practice", "")
                if pid not in tree_practice:
                    errors.append(f"{ctx}: effect 'practice_add' ссылается на неизвестную практику '{pid}'")
                if "value" in eff and not is_positive_int(eff["value"]):
                    errors.append(f"{ctx}: effect 'practice_add'.value должен быть положительным целым")
            elif t == "reveal_sector":
                sid = eff.get("sector", "")
                if sid not in tree_sectors:
                    errors.append(f"{ctx}: effect 'reveal_sector' ссылается на неизвестный сектор дерева '{sid}'")
            elif t == "end_run":
                ending = eff.get("ending", "")
                referenced_endings.add(ending)
                if ending not in endings:
                    errors.append(f"{ctx}: effect 'end_run' ссылается на неизвестный финал '{ending}'")
            elif t in ("hp_delta", "o2_delta", "ammo_delta", "hunger_delta", "flag_set", "reveal_map"):
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
            if "completes_event" in opt and not isinstance(opt["completes_event"], bool):
                errors.append(f"{opt_ctx}: completes_event должен быть bool")
            nxt = opt.get("next", "")
            if nxt and not nxt.startswith("map:"):
                referenced_situations.add(nxt)
            if nxt and not nxt.startswith("map:") and nxt not in situations:
                errors.append(f"{opt_ctx}: next ссылается на неизвестную ситуацию '{nxt}'")
            if nxt.startswith("map:"):
                sector_id = nxt[len("map:"):]
                if sector_id not in sectors:
                    errors.append(f"{opt_ctx}: next='map:{sector_id}' ссылается на неизвестный сектор")

    # Справочник мира (CodexSystem): четыре фиксированные категории.
    codex_categories = {"places", "people", "ships", "terms"}
    for entry_id, entry in codex.items():
        ctx = f"codex/{entry_id}"
        if not isinstance(entry, dict):
            errors.append(f"{ctx}: ожидается объект")
            continue
        if entry.get("category") not in codex_categories:
            errors.append(f"{ctx}.category: допустимы places, people, ships, terms")
        if not str(entry.get("title", "")).strip():
            errors.append(f"{ctx}: нужен непустой title")
        if not str(entry.get("text", "")).strip():
            errors.append(f"{ctx}: нужен непустой text")
        aliases = entry.get("aliases", [])
        if not isinstance(aliases, list) or not aliases or any(not str(alias).strip() for alias in aliases):
            errors.append(f"{ctx}.aliases: нужен непустой массив непустых строк")


    events_total = 0
    for lid, loc in locations.items():
        ctx = f"locations/{lid}"
        check_image(loc.get("image"), ctx)
        if "base" in loc and not isinstance(loc["base"], bool):
            errors.append(f"{ctx}.base: должно быть true/false")
        if "breathable" in loc and not isinstance(loc["breathable"], bool):
            errors.append(f"{ctx}.breathable: должно быть true/false")
        explore = loc.get("explore")
        if explore is not None:
            if not isinstance(explore, dict):
                errors.append(f"{ctx}.explore: ожидается объект {{pool, rolls, duration}}")
            else:
                if explore.get("pool") not in explore_pools:
                    errors.append(f"{ctx}.explore.pool: неизвестный пул '{explore.get('pool')}' (explore_pools.json)")
                rolls = explore.get("rolls", 0)
                if not isinstance(rolls, int) or isinstance(rolls, bool) or rolls < 0:
                    errors.append(f"{ctx}.explore.rolls: неотрицательное целое")
                elif explore.get("pool") in explore_pools and len(explore_pools[explore["pool"]]) < rolls + 2:
                    warnings.append(f"{ctx}.explore: в пуле '{explore['pool']}' меньше rolls+2 событий — навыку «Поиск» не хватит находок")
                duration = explore.get("duration", [])
                if (not isinstance(duration, list) or len(duration) != 2
                        or any(not isinstance(v, int) or isinstance(v, bool) or v <= 0 for v in duration)
                        or (len(duration) == 2 and duration[0] > duration[1])):
                    errors.append(f"{ctx}.explore.duration: нужны два положительных целых [min, max]")
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
                check_image(variant.get("image"), f"{ctx}.descriptions[{i}]")
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
            if "clear_image" in ev and not isinstance(ev["clear_image"], bool):
                errors.append(f"{ev_ctx}.clear_image: должно быть true/false")
            if "discover" in ev:
                if not isinstance(ev["discover"], bool):
                    errors.append(f"{ev_ctx}.discover: должно быть true/false")
                elif ev["discover"] and start != "manual":
                    errors.append(f"{ev_ctx}.discover: прятать под исследованием можно только ручные события")
                elif ev["discover"] and not str(ev.get("found", "")).strip():
                    warnings.append(f"{ev_ctx}: у спрятанного события нет текста находки (found)")
            check_requires(ev.get("triggers", []), f"{ev_ctx}.triggers", lid)
            check_effects(ev.get("effects", []), ev_ctx)
            check_image(ev.get("image"), ev_ctx)
            check_sound(ev.get("sound"), ev_ctx)
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

    # Пулы случайных находок исследования (ExplorationSystem).
    allowed_pool_effects = ("item_add", "o2_delta", "hp_delta", "hunger_delta", "ammo_delta",
                            "unlock_knowledge", "reveal_sector")
    for pool_id, entries in explore_pools.items():
        pctx = f"explore_pools/{pool_id}"
        if not isinstance(entries, list) or not entries:
            errors.append(f"{pctx}: нужен непустой массив событий")
            continue
        seen_entries = set()
        for entry in entries:
            entry_id = entry.get("id", "") if isinstance(entry, dict) else ""
            ectx = f"{pctx}#{entry_id or '?'}"
            if not entry_id:
                errors.append(f"{ectx}: нужен id")
                continue
            if entry_id in seen_entries:
                errors.append(f"{ectx}: дублирующийся id")
            seen_entries.add(entry_id)
            if not str(entry.get("text", "")).strip():
                errors.append(f"{ectx}: нужен text")
            weight = entry.get("weight", 1)
            if not is_positive_int(weight):
                errors.append(f"{ectx}.weight: положительное целое")
            check_requires(entry.get("requires", []), ectx)
            check_effects(entry.get("effects", []), ectx)
            for eff in entry.get("effects", []):
                if isinstance(eff, dict) and eff.get("type") not in allowed_pool_effects:
                    errors.append(f"{ectx}: в пуле допустимы только {', '.join(allowed_pool_effects)}")
    used_pools = {loc.get("explore", {}).get("pool") for loc in locations.values() if isinstance(loc.get("explore"), dict)}
    for pool_id in explore_pools:
        if pool_id not in used_pools:
            warnings.append(f"explore_pools/{pool_id}: пул не привязан ни к одной локации")

    # Цели и мысли героя (QuestSystem).
    thoughts = quests_data.get("thoughts", [])
    if not isinstance(thoughts, list):
        errors.append("quests.json: thoughts — ожидается массив")
        thoughts = []
    for i, variant in enumerate(thoughts):
        tctx = f"quests/thoughts[{i}]"
        if not isinstance(variant, dict) or not str(variant.get("text", "")).strip():
            errors.append(f"{tctx}: нужен объект с непустым text")
            continue
        check_requires(variant.get("requires", []), tctx)
    if thoughts and thoughts[-1].get("requires"):
        warnings.append("quests/thoughts: последний вариант стоит оставить без условий — мысли будут всегда")
    quest_list = quests_data.get("quests", [])
    if not isinstance(quest_list, list):
        errors.append("quests.json: quests — ожидается массив")
        quest_list = []
    quest_ids = set()
    for i, quest in enumerate(quest_list):
        if not isinstance(quest, dict):
            errors.append(f"quests/quests[{i}]: цель должна быть объектом")
            continue
        qid = quest.get("id", "")
        qctx = f"quests/{qid or i}"
        if not qid:
            errors.append(f"{qctx}: нет id")
        elif qid in quest_ids:
            errors.append(f"{qctx}: дублирующийся id")
        quest_ids.add(qid)
        if not str(quest.get("title", "")).strip():
            errors.append(f"{qctx}: нужен title")
        check_requires(quest.get("start", []), f"{qctx}.start")
        if "done" in quest:
            check_requires(quest["done"], f"{qctx}.done")
        steps = quest.get("steps", [])
        if not isinstance(steps, list) or not steps:
            errors.append(f"{qctx}.steps: нужен непустой массив шагов")
            continue
        step_ids = set()
        for step in steps:
            sid = step.get("id", "") if isinstance(step, dict) else ""
            sctx = f"{qctx}#{sid or '?'}"
            if not sid:
                errors.append(f"{sctx}: шагу нужен id")
            elif sid in step_ids:
                errors.append(f"{sctx}: дублирующийся id шага")
            step_ids.add(sid)
            if not str(step.get("text", "")).strip():
                errors.append(f"{sctx}: нужен text")
            if "hidden" in step and not isinstance(step["hidden"], bool):
                errors.append(f"{sctx}.hidden: должно быть true/false")
            done = step.get("done", [])
            if not isinstance(done, list) or not done:
                errors.append(f"{sctx}.done: нужны условия — шаг без них засчитается сразу")
            else:
                check_requires(done, sctx)

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
        if "xp" in enemy:
            xp = enemy["xp"]
            if not isinstance(xp, int) or isinstance(xp, bool) or xp < 0:
                errors.append(f"enemies/{eid}.xp: неотрицательное целое (опыт за победу)")

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
        if "firearm" in item:
            if not isinstance(item["firearm"], bool):
                errors.append(f"{ctx}.firearm: должно быть true/false")
            elif item["firearm"] and slot != "arms":
                errors.append(f"{ctx}.firearm: огнестрел должен надеваться в руки (equip_slot: arms)")
        if item.get("category") in ("quest", "key") and item.get("slot_cost", 1) != 0:
            errors.append(f"{ctx}.slot_cost: сюжетные предметы и ключи не занимают сумку — нужен 0")
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

    # Кольцевое дерево навыков, происхождение и знание (SkillTreeSystem).
    valid_rings = ("inner", "middle", "outer")
    valid_node_types = ("small", "notable", "mastery", "bridge", "key", "legendary")
    for sector_id, sector in tree_sectors.items():
        ctx = f"skill_tree/sectors/{sector_id}"
        if not isinstance(sector, dict):
            errors.append(f"{ctx}: ожидается объект")
        elif not str(sector.get("name", "")).strip():
            errors.append(f"{ctx}: нет name")
    for practice_id, title in tree_practice.items():
        if not str(title).strip():
            errors.append(f"skill_tree/practice/{practice_id}: пустое название практики")
    for node_id, node in tree_nodes.items():
        ctx = f"skill_tree/nodes/{node_id}"
        if not isinstance(node, dict):
            errors.append(f"{ctx}: ожидается объект")
            continue
        if not str(node.get("name", "")).strip():
            errors.append(f"{ctx}: нет name")
        if not str(node.get("description", "")).strip():
            errors.append(f"{ctx}: нет description")
        if node.get("sector") not in tree_sectors:
            errors.append(f"{ctx}: неизвестный сектор '{node.get('sector')}'")
        if node.get("ring") not in valid_rings:
            errors.append(f"{ctx}.ring: допустимы {', '.join(valid_rings)}")
        if node.get("type") not in valid_node_types:
            errors.append(f"{ctx}.type: допустимы {', '.join(valid_node_types)}")
        if not is_positive_int(node.get("cost")):
            errors.append(f"{ctx}.cost: положительное целое")
        elif node.get("type") in ("key", "legendary") and node["cost"] < 2:
            errors.append(f"{ctx}: ключевой и легендарный узел стоят не меньше 2 очков")
        if "hidden" in node and not isinstance(node["hidden"], bool):
            errors.append(f"{ctx}.hidden: true/false")
        if "stats" in node:
            check_stats(node["stats"], f"{ctx}.stats")
        requires = node.get("requires", {})
        if not isinstance(requires, dict):
            errors.append(f"{ctx}.requires: ожидается объект")
            requires = {}
        for prev in requires.get("nodes", []):
            if prev not in tree_nodes:
                errors.append(f"{ctx}.requires.nodes: неизвестный узел '{prev}'")
            elif prev == node_id:
                errors.append(f"{ctx}.requires.nodes: узел ссылается сам на себя")
        for kid in requires.get("knowledge", []):
            if kid not in knowledge:
                errors.append(f"{ctx}.requires.knowledge: неизвестное знание '{kid}'")
        practice_req = requires.get("practice", {})
        if not isinstance(practice_req, dict):
            errors.append(f"{ctx}.requires.practice: ожидается объект {{практика: число}}")
        else:
            for pid, amount in practice_req.items():
                if pid not in tree_practice:
                    errors.append(f"{ctx}.requires.practice: неизвестная практика '{pid}'")
                if not is_positive_int(amount):
                    errors.append(f"{ctx}.requires.practice.{pid}: положительное целое")
        origin_req = str(requires.get("origin", ""))
        if origin_req and origin_req not in origins:
            errors.append(f"{ctx}.requires.origin: неизвестное происхождение '{origin_req}'")
        for other in node.get("excludes", []):
            if other not in tree_nodes:
                errors.append(f"{ctx}.excludes: неизвестный узел '{other}'")
        grants = node.get("grants", {})
        if grants and not isinstance(grants, dict):
            errors.append(f"{ctx}.grants: ожидается объект")
        elif isinstance(grants, dict):
            for kid in grants.get("knowledge", []):
                if kid not in knowledge:
                    errors.append(f"{ctx}.grants.knowledge: неизвестное знание '{kid}'")
            for item_id in grants.get("items", []):
                if item_id not in items:
                    errors.append(f"{ctx}.grants.items: неизвестный предмет '{item_id}'")
            for sector_id in grants.get("reveal_sectors", []):
                if sector_id not in tree_sectors:
                    errors.append(f"{ctx}.grants.reveal_sectors: неизвестный сектор '{sector_id}'")
    for sector_id in tree_sectors:
        if not any(isinstance(n, dict) and n.get("sector") == sector_id for n in tree_nodes.values()):
            errors.append(f"skill_tree/sectors/{sector_id}: у сектора нет ни одного узла")

    for knowledge_id, entry in knowledge.items():
        ctx = f"knowledge/{knowledge_id}"
        if not isinstance(entry, dict):
            errors.append(f"{ctx}: ожидается объект")
            continue
        if not str(entry.get("name", "")).strip():
            errors.append(f"{ctx}: нет name")
        if not str(entry.get("source", "")).strip():
            errors.append(f"{ctx}: нет source — откуда игрок добывает знание")
        for sector_id in entry.get("reveal_sectors", []):
            if sector_id not in tree_sectors:
                errors.append(f"{ctx}.reveal_sectors: неизвестный сектор '{sector_id}'")

    for origin_id, origin in origins.items():
        ctx = f"origins/{origin_id}"
        if not isinstance(origin, dict):
            errors.append(f"{ctx}: ожидается объект")
            continue
        if not str(origin.get("name", "")).strip():
            errors.append(f"{ctx}: нет name")
        for sector_id in origin.get("start_sectors", []):
            if sector_id not in tree_sectors:
                errors.append(f"{ctx}.start_sectors: неизвестный сектор '{sector_id}'")
        for node_id in origin.get("start_nodes", []):
            if node_id not in tree_nodes:
                errors.append(f"{ctx}.start_nodes: неизвестный узел дерева '{node_id}'")
        for knowledge_id in origin.get("knowledge", []):
            if knowledge_id not in knowledge:
                errors.append(f"{ctx}.knowledge: неизвестное знание '{knowledge_id}'")
        for item_id in origin.get("items", []):
            if item_id not in items:
                errors.append(f"{ctx}.items: неизвестный предмет '{item_id}'")
        if "stats" in origin:
            check_stats(origin["stats"], f"{ctx}.stats")
        resources = origin.get("resources", {})
        if resources and not isinstance(resources, dict):
            errors.append(f"{ctx}.resources: ожидается объект")
        elif isinstance(resources, dict):
            for key in resources:
                if key not in ("ammo", "hp", "o2"):
                    errors.append(f"{ctx}.resources: неизвестный ключ '{key}' (допустимы ammo, hp, o2)")

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
    start_origin = config.get("start_origin", "")
    if not isinstance(start_origin, str):
        errors.append("config.json: start_origin должен быть строкой (id происхождения или пусто)")
    elif start_origin and start_origin not in origins:
        errors.append(f"config.json: start_origin ссылается на неизвестное происхождение '{start_origin}'")

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

    needs_config = config.get("needs", {})
    if not isinstance(needs_config, dict):
        errors.append("config.json: needs должен быть объектом")
    else:
        for key, value in needs_config.items():
            if key not in NEEDS_CONFIG_KEYS:
                errors.append(f"config.json: needs — неизвестный ключ '{key}' (допустимы: {', '.join(NEEDS_CONFIG_KEYS)})")
            elif key in ("energy_costs", "hunger_costs"):
                if not isinstance(value, dict):
                    errors.append(f"config.json: needs.{key} должен быть объектом {{действие: цена}}")
                    continue
                for kind, cost in value.items():
                    if kind not in O2_COST_KINDS:
                        errors.append(f"config.json: needs.{key} — неизвестное действие '{kind}' (допустимы: {', '.join(O2_COST_KINDS)})")
                    elif not is_number(cost) or cost < 0:
                        errors.append(f"config.json: needs.{key}.{kind} — неотрицательное число")
            elif not is_number(value) or value < 0:
                errors.append(f"config.json: needs.{key} — неотрицательное число")
        for key in ("max_energy", "max_hunger"):
            if key in needs_config and is_number(needs_config[key]) and needs_config[key] <= 0:
                errors.append(f"config.json: needs.{key} должен быть больше нуля")

    xp_config = config.get("xp", {})
    if not isinstance(xp_config, dict):
        errors.append("config.json: xp должен быть объектом {источник: опыт}")
    else:
        for key, value in xp_config.items():
            if key not in XP_CONFIG_KEYS:
                errors.append(f"config.json: xp — неизвестный ключ '{key}' (допустимы: {', '.join(XP_CONFIG_KEYS)})")
            elif not isinstance(value, int) or isinstance(value, bool) or value < 0:
                errors.append(f"config.json: xp.{key} — неотрицательное целое")
        if xp_config.get("level_base", 1) == 0 and xp_config.get("level_step", 1) == 0:
            errors.append("config.json: xp.level_base и xp.level_step не могут быть оба нулевыми")

    for sid in sorted(situations):
        if sid not in referenced_situations:
            warnings.append(f"situations/{sid}: ситуация не достижима из стартового конфига, событий или next-ссылок")

    print(f"Локаций: {len(locations)} (событий: {events_total}) | Ситуаций: {len(situations)} | "
          f"Секторов: {len(sectors)} | Предметов: {len(items)} | Навыков: {len(skills)} | "
          f"Рецептов: {len(recipes)} | Врагов: {len(enemies)} | Лор-фрагментов: {len(lore)} | "
          f"Записей справочника: {len(codex)} | Финалов: {len(endings)}")
    print(f"Дерево навыков: узлов {len(tree_nodes)} в {len(tree_sectors)} секторах | "
          f"Знаний: {len(knowledge)} | Происхождений: {len(origins)}")

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
