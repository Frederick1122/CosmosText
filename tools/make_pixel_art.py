#!/usr/bin/env python3
"""
Генератор пиксель-арта для CosmosText: иллюстрации сцен и иконки предметов.
Всё рисуется кодом на чистой стандартной библиотеке (без Pillow), PNG собирается
вручную через zlib. Результат детерминирован (фиксированный seed).

Запуск из корня проекта: python tools/make_pixel_art.py
Пишет:
  assets/art/scenes/<name>.png  — 160x96, RGB (цветовой тип 2), без альфы;
  assets/art/scenes/title_screen.png — 240x150, RGB, заглавный кадр меню;
  assets/art/items/<item_id>.png — 16x16, RGBA (цветовой тип 6), фон прозрачный.
  assets/art/portraits/player.png — 64x64, RGBA, портрет игрока для боя;
  assets/art/enemies/<enemy_id>.png — 64x64, RGBA, портреты противников.
Все файлы перезаписываются, список записанного печатается в stdout.
"""

import os
import random
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENES_DIR = os.path.join(ROOT, "assets", "art", "scenes")
ITEMS_DIR = os.path.join(ROOT, "assets", "art", "items")
PORTRAITS_DIR = os.path.join(ROOT, "assets", "art", "portraits")
ENEMIES_DIR = os.path.join(ROOT, "assets", "art", "enemies")

SEED = 20260929
SCENE_W, SCENE_H = 160, 96
ICON_W, ICON_H = 16, 16
PORTRAIT_W, PORTRAIT_H = 64, 64
TITLE_W, TITLE_H = 240, 150


# ----------------------------------------------------------------------------
# Мини-движок растра
# ----------------------------------------------------------------------------

def rgba(col):
    """Приводит цвет к RGBA (3-кортеж считается непрозрачным)."""
    if len(col) == 4:
        return col
    return (col[0], col[1], col[2], 255)


class Canvas:
    """Прямоугольный холст пикселей RGBA без сглаживания и смешивания."""

    def __init__(self, w, h, bg=(0, 0, 0, 0)):
        self.w = w
        self.h = h
        self.px = [rgba(bg)] * (w * h)

    # --- базовые операции -----------------------------------------------
    def pixel(self, x, y, col):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y * self.w + x] = rgba(col)

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[y * self.w + x]
        return (0, 0, 0, 0)

    def fill(self, col):
        self.px = [rgba(col)] * (self.w * self.h)

    def fill_rect(self, x0, y0, x1, y1, col):
        """Заливка прямоугольника включительно по обеим границам."""
        c = rgba(col)
        if x0 > x1:
            x0, x1 = x1, x0
        if y0 > y1:
            y0, y1 = y1, y0
        for y in range(max(0, y0), min(self.h - 1, y1) + 1):
            row = y * self.w
            for x in range(max(0, x0), min(self.w - 1, x1) + 1):
                self.px[row + x] = c

    def rect(self, x0, y0, x1, y1, col):
        """Контур прямоугольника толщиной 1 пиксель."""
        self.hline(x0, x1, y0, col)
        self.hline(x0, x1, y1, col)
        self.vline(x0, y0, y1, col)
        self.vline(x1, y0, y1, col)

    def hline(self, x0, x1, y, col):
        if x0 > x1:
            x0, x1 = x1, x0
        for x in range(x0, x1 + 1):
            self.pixel(x, y, col)

    def vline(self, x, y0, y1, col):
        if y0 > y1:
            y0, y1 = y1, y0
        for y in range(y0, y1 + 1):
            self.pixel(x, y, col)

    def line(self, x0, y0, x1, y1, col):
        """Отрезок по Брезенхэму."""
        dx = abs(x1 - x0)
        dy = -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            self.pixel(x0, y0, col)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def ellipse(self, cx, cy, rx, ry, col, filled=True):
        """Эллипс по уравнению — без сглаживания."""
        if rx <= 0 or ry <= 0:
            return
        for y in range(cy - ry, cy + ry + 1):
            dy = (y - cy) / float(ry)
            for x in range(cx - rx, cx + rx + 1):
                dx = (x - cx) / float(rx)
                d = dx * dx + dy * dy
                if d <= 1.0:
                    if filled:
                        self.pixel(x, y, col)
                    elif d > 0.55:
                        # грубое кольцо: внешняя часть диска
                        n = 0
                        for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                            ddx = (x + ox - cx) / float(rx)
                            ddy = (y + oy - cy) / float(ry)
                            if ddx * ddx + ddy * ddy > 1.0:
                                n += 1
                        if n:
                            self.pixel(x, y, col)

    def circle(self, cx, cy, r, col, filled=True):
        self.ellipse(cx, cy, r, r, col, filled)

    def ring(self, cx, cy, r_in, r_out, col):
        """Кольцо между двумя радиусами."""
        for y in range(cy - r_out, cy + r_out + 1):
            for x in range(cx - r_out, cx + r_out + 1):
                d = (x - cx) ** 2 + (y - cy) ** 2
                if r_in * r_in <= d <= r_out * r_out:
                    self.pixel(x, y, col)

    # --- фактуры ---------------------------------------------------------
    def dither_rect(self, x0, y0, x1, y1, c1, c2, phase=0):
        """Шахматный дизеринг двумя цветами."""
        for y in range(max(0, y0), min(self.h - 1, y1) + 1):
            for x in range(max(0, x0), min(self.w - 1, x1) + 1):
                self.pixel(x, y, c1 if (x + y + phase) % 2 == 0 else c2)

    def dither_over(self, x0, y0, x1, y1, col, phase=0):
        """Полупрозрачный на вид налёт: красит только половину клеток."""
        for y in range(max(0, y0), min(self.h - 1, y1) + 1):
            for x in range(max(0, x0), min(self.w - 1, x1) + 1):
                if (x + y + phase) % 2 == 0:
                    self.pixel(x, y, col)

    def dither_disc(self, cx, cy, r, col, phase=0):
        """Шахматное свечение вокруг точки."""
        for y in range(cy - r, cy + r + 1):
            for x in range(cx - r, cx + r + 1):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r and (x + y + phase) % 2 == 0:
                    self.pixel(x, y, col)

    def noise_specks(self, rng, x0, y0, x1, y1, col, count):
        """Детерминированные крапины в прямоугольнике."""
        for _ in range(count):
            self.pixel(rng.randint(x0, x1), rng.randint(y0, y1), col)

    def specks_on(self, rng, x0, y0, x1, y1, target, col, count):
        """Крапины только поверх пикселей заданного цвета (дешёвая обрезка по маске)."""
        t = rgba(target)
        for _ in range(count):
            x = rng.randint(x0, x1)
            y = rng.randint(y0, y1)
            if self.get(x, y) == t:
                self.pixel(x, y, col)

    def outline_alpha(self, col):
        """Тёмный контур вокруг непрозрачного силуэта (по 8 соседям)."""
        c = rgba(col)
        add = []
        for y in range(self.h):
            for x in range(self.w):
                if self.get(x, y)[3] != 0:
                    continue
                touch = False
                for oy in (-1, 0, 1):
                    for ox in (-1, 0, 1):
                        if ox == 0 and oy == 0:
                            continue
                        if self.get(x + ox, y + oy)[3] != 0:
                            touch = True
                            break
                    if touch:
                        break
                if touch:
                    add.append((x, y))
        for x, y in add:
            self.px[y * self.w + x] = c


def write_png(path, canvas, with_alpha):
    """Ручная сборка PNG: IHDR + IDAT (фильтр 0 в каждой строке) + IEND."""
    raw = bytearray()
    for y in range(canvas.h):
        raw.append(0)
        row = y * canvas.w
        for x in range(canvas.w):
            r, g, b, a = canvas.px[row + x]
            if with_alpha:
                raw += bytes((r, g, b, a))
            else:
                raw += bytes((r, g, b))
    color_type = 6 if with_alpha else 2
    ihdr = struct.pack(">IIBBBBB", canvas.w, canvas.h, 8, color_type, 0, 0, 0)
    data = b"\x89PNG\r\n\x1a\n"
    data += _chunk(b"IHDR", ihdr)
    data += _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    data += _chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(data)


def _chunk(tag, payload):
    return (struct.pack(">I", len(payload)) + tag + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))


# ----------------------------------------------------------------------------
# Общая палитра проекта (тёмный UI: фон #11141b, акцент #9fd3e6, янтарь #e0b153)
# ----------------------------------------------------------------------------

VOID = (8, 10, 15)
STAR = (215, 222, 238)
STAR_DIM = (120, 132, 156)
CYAN = (159, 211, 230)
AMBER = (224, 177, 83)
RED = (200, 55, 66)
RED_LIT = (240, 176, 185)


def draw_room(c, box, tones, seam):
    """
    Рисует коробку отсека в одноточечной перспективе.
    box — прямоугольник дальней стены (x0, y0, x1, y1).
    tones — словарь region -> (ближний, средний, дальний) тон для
    'ceil' / 'floor' / 'left' / 'right' и одиночный цвет 'far'.
    seam — цвет рёбер перспективы.
    """
    x0, y0, x1, y1 = box
    w, h = c.w, c.h
    far = tones["far"]
    for y in range(h):
        sy_t = y / float(y0)
        sy_b = (y - (h - 1)) / float(y1 - (h - 1))
        for x in range(w):
            sx_l = x / float(x0)
            sx_r = (x - (w - 1)) / float(x1 - (w - 1))
            s = sx_l
            region = "left"
            if sx_r < s:
                s = sx_r
                region = "right"
            if sy_t < s:
                s = sy_t
                region = "ceil"
            if sy_b < s:
                s = sy_b
                region = "floor"
            if s >= 1.0:
                c.px[y * w + x] = rgba(far)
                continue
            band = int(s * 3.0)
            if band > 2:
                band = 2
            c.px[y * w + x] = rgba(tones[region][band])
    # рёбра схода
    c.line(0, 0, x0, y0, seam)
    c.line(w - 1, 0, x1, y0, seam)
    c.line(0, h - 1, x0, y1, seam)
    c.line(w - 1, h - 1, x1, y1, seam)
    c.rect(x0, y0, x1, y1, seam)


# ----------------------------------------------------------------------------
# Сцены 160x96
# ----------------------------------------------------------------------------

def _poly(c, pts, col, phase=None):
    """Заливка многоугольника по строкам (правило чёт-нечет), вершины — float.
    phase=None — сплошная заливка, иначе шахматный налёт с этой фазой."""
    ys = [pt[1] for pt in pts]
    n = len(pts)
    for y in range(max(0, int(min(ys))), min(c.h - 1, int(max(ys)) + 1) + 1):
        yc = y + 0.5
        xs = []
        for i in range(n):
            ax, ay = pts[i]
            bx, by = pts[(i + 1) % n]
            if (ay <= yc < by) or (by <= yc < ay):
                xs.append(ax + (yc - ay) * (bx - ax) / (by - ay))
        xs.sort()
        for k in range(0, len(xs) - 1, 2):
            for x in range(int(xs[k] + 0.5), int(xs[k + 1] + 0.5)):
                if phase is None or (x + y + phase) % 2 == 0:
                    c.pixel(x, y, col)


# Отсек гибернации строится в настоящей перспективе: глаз в центре кадра,
# X — поперёк (-1 левая стена, 1 правая), v — по высоте (-1 потолок, 1 пол),
# z — глубина (1 — край кадра, BAY_FAR — дальняя стена).
BAY_FAR = 3.6
BAY_SLOTS = ((1.0, 1.5), (1.65, 2.15), (2.3, 2.8), (2.95, 3.45))


def _bay_pt(x, v, z):
    """Проекция точки отсека на экран 160x96."""
    return (79.5 + x * 79.5 / z, 47.5 + v * 47.5 / z)


def _bay_box(c, x0, x1, v0, v1, z0, z1, front, side, cap, phase=None):
    """Брусок в отсеке: видимые грани — торец к зрителю, бок к проходу
    и верх (если брусок ниже глаза). x0 < x1, v0 < v1 (v0 — верх), z0 < z1."""
    P = _bay_pt
    if x1 < 0:
        _poly(c, [P(x1, v0, z0), P(x1, v0, z1), P(x1, v1, z1), P(x1, v1, z0)], side, phase)
    elif x0 > 0:
        _poly(c, [P(x0, v0, z0), P(x0, v0, z1), P(x0, v1, z1), P(x0, v1, z0)], side, phase)
    if v0 > 0:
        _poly(c, [P(x0, v0, z0), P(x1, v0, z0), P(x1, v0, z1), P(x0, v0, z1)], cap, phase)
    _poly(c, [P(x0, v0, z0), P(x1, v0, z0), P(x1, v1, z0), P(x0, v1, z0)], front, phase)


def _cryo_pod(c, p, side, za, zb, state):
    """Капсула гибернации в ряду у стены: side -1 слева, 1 справа;
    state 'closed' — крышка из тёмного заиндевевшего стекла, 'open' — крышка поднята."""
    P = _bay_pt
    wall, aisle = sorted((side * 1.0, side * 0.42))
    _bay_box(c, wall, aisle, 0.6, 1.0, za, zb, p["pod_front"], p["pod_side"], p["pod_top"])
    # кромка корпуса и индикатор на торце
    fx = side * 0.42
    c.line(*[int(t) for t in P(wall, 0.6, za) + P(aisle, 0.6, za)], p["pod_edge"])
    c.line(*[int(t) for t in P(fx, 0.6, za) + P(fx, 0.6, zb)], p["pod_edge"])
    lx, ly = P(side * 0.55, 0.78, za)
    lamp = p["lamp_open"] if state == "open" else p["lamp"]
    c.pixel(int(lx), int(ly), lamp)
    c.pixel(int(lx) + side, int(ly), lamp)
    gx0, gx1 = sorted((side * 0.92, side * 0.5))
    if state == "closed":
        _bay_box(c, gx0, gx1, 0.48, 0.6, za + 0.05, zb - 0.05,
                 p["glass_d"], p["glass_s"], p["glass"])
        # иней по стеклу и блик вдоль кромки к проходу
        gin, gout = sorted((side * 0.82, side * 0.58))
        _poly(c, [P(gin, 0.48, za + 0.1), P(gout, 0.48, za + 0.1),
                  P(gout, 0.48, zb - 0.12), P(gin, 0.48, zb - 0.12)], p["frost"], 1)
        c.line(*[int(t) for t in P(side * 0.52, 0.48, za + 0.07) + P(side * 0.52, 0.48, zb - 0.1)],
               p["frost_l"])
        return
    # открытая: светящееся ложе внутри и поднятая крышка на петлях у стены
    _poly(c, [P(gx0, 0.6, za + 0.05), P(gx1, 0.6, za + 0.05),
              P(gx1, 0.6, zb - 0.05), P(gx0, 0.6, zb - 0.05)], p["bed"])
    hx0, hx1 = sorted((side * 0.86, side * 0.56))
    _poly(c, [P(hx0, 0.6, za + 0.1), P(hx1, 0.6, za + 0.1),
              P(hx1, 0.6, zb - 0.1), P(hx0, 0.6, zb - 0.1)], p["bed_l"])
    # свет поднимается из ложа столбом, шахматным налётом
    _bay_box(c, hx0, hx1, 0.05, 0.6, za + 0.1, zb - 0.1, p["bed"], p["bed"], p["bed"], 1)
    hinge, free = side * 0.94, side * 0.76
    lid = [P(hinge, 0.5, za + 0.05), P(hinge, 0.5, zb - 0.05),
           P(free, -0.2, zb - 0.05), P(free, -0.2, za + 0.05)]
    _poly(c, lid, p["glass"])
    _poly(c, lid, p["glass_d"], 0)
    for a, b in ((0, 1), (1, 2), (2, 3), (3, 0)):
        c.line(*[int(t) for t in lid[a] + lid[b]], p["pod_edge"])
    c.line(*[int(t) for t in lid[2] + lid[3]], p["frost_l"])


def _cryo_bay_room(c, p, left, right):
    """Отсек гибернации: коробка, ряды капсул вдоль стен (по слотам BAY_SLOTS,
    состояния 'closed' / 'open' / None — пусто), трубы и аварийные лампы."""
    P = _bay_pt
    fx0, fy0 = P(-1, -1, BAY_FAR)
    fx1, fy1 = P(1, 1, BAY_FAR)
    draw_room(c, (int(fx0), int(fy0), int(fx1), int(fy1)),
              {"ceil": (p["d0"], p["d1"], p["d2"]),
               "floor": (p["f0"], p["f1"], p["f2"]),
               "left": (p["w0"], p["w1"], p["w2"]),
               "right": (p["w0"], p["w1"], p["w2"]),
               "far": p["far"]}, p["seam"])
    # герметичный люк в торце и красная лампа над ним
    hx0, hy0 = P(-0.3, -0.55, BAY_FAR)
    hx1, hy1 = P(0.3, 1.0, BAY_FAR)
    c.fill_rect(int(hx0), int(hy0), int(hx1), int(hy1), p["w2"])
    c.rect(int(hx0), int(hy0), int(hx1), int(hy1), p["seam"])
    c.vline(80, int(hy0) + 1, int(hy1), p["seam"])
    c.dither_disc(80, int(hy0) - 3, 6, p["red_d"], 1)
    c.fill_rect(78, int(hy0) - 4, 81, int(hy0) - 2, p["red"])
    for s in (-1, 1):
        # трубы вдоль стен над капсулами
        for v in (-0.38, -0.3):
            c.line(*[int(t) for t in P(s, v, 1.0) + P(s, v, BAY_FAR)], p["pipe"])
        # рёбра стены между капсулами
        for za, zb in BAY_SLOTS:
            x, ya = P(s, -1, zb + 0.07)
            _, yb = P(s, 1, zb + 0.07)
            c.vline(int(x), int(ya), int(yb), p["rib"])
        # аварийные лампы под потолком над каждым слотом и отсвет по стене
        for za, zb in BAY_SLOTS:
            z0, z1 = za + 0.1, zb - 0.1
            _poly(c, [P(s, -0.95, z0 - 0.05), P(s, -0.95, z1 + 0.05),
                      P(s, -0.45, z1 + 0.05), P(s, -0.45, z0 - 0.05)], p["red_d"], 1)
            c.line(*[int(t) for t in P(s, -0.72, z0) + P(s, -0.72, z1)], p["red"])
            c.line(*[int(t) for t in P(s, -0.7, z0) + P(s, -0.7, z1)], p["red"])
    # капсулы от дальних к ближним
    for k in range(len(BAY_SLOTS) - 1, -1, -1):
        za, zb = BAY_SLOTS[k]
        for s, row in ((-1, left), (1, right)):
            if row[k]:
                _cryo_pod(c, p, s, za, zb, row[k])


CRYO_PALETTE = {
    "d0": (30, 36, 48), "d1": (23, 28, 38), "d2": (17, 21, 29),
    "f0": (36, 40, 49), "f1": (27, 30, 38), "f2": (19, 22, 29),
    "w0": (42, 50, 63), "w1": (32, 38, 49), "w2": (23, 28, 37),
    "far": (16, 20, 27),
    "seam": (11, 14, 19),
    "rib": (52, 62, 78),
    "pipe": (58, 68, 84),
    "pod_front": (50, 60, 74), "pod_side": (64, 76, 92), "pod_top": (86, 100, 118),
    "pod_edge": (118, 134, 154),
    "glass": (26, 46, 60), "glass_s": (20, 36, 48), "glass_d": (14, 26, 36),
    "frost": (100, 146, 166), "frost_l": (176, 214, 228),
    "bed": (70, 112, 130), "bed_l": (150, 204, 222),
    "lamp": (60, 150, 170), "lamp_open": AMBER,
    "red": RED, "red_d": (88, 26, 34),
}


def scene_cryo_pod(c, rng):
    """Взгляд из капсулы гибернации: близкая выпуклая крышка, затянутая инеем
    и треснувшая; сквозь неё — тёмный отсек, мигает красная аварийная лампа,
    на стекле горит красное предупреждение."""
    p = dict(CRYO_PALETTE)
    p.update({
        "shell_d": (12, 16, 23), "shell": (20, 26, 35), "shell_l": (30, 38, 50),
        "gasket": (64, 84, 100), "gasket_l": (110, 136, 154),
        "frost_m": (130, 176, 196), "frost_r": (168, 112, 128), "frost_rl": (226, 170, 182),
        "crack": (226, 240, 248), "crack_d": (40, 58, 72),
        "red_l": RED_LIT,
    })
    # отсек за стеклом рисуется на отдельном холсте и потом «замораживается»
    bay = Canvas(c.w, c.h, VOID)
    _cryo_bay_room(bay, p, ("closed",) * 4, ("closed",) * 4)
    lamp_x, lamp_y = 112, 20
    bay.dither_disc(lamp_x, lamp_y, 18, p["red_d"], 0)
    bay.circle(lamp_x, lamp_y, 5, p["red"])
    bay.circle(lamp_x, lamp_y - 1, 2, p["red_l"])
    # грубый шум 8x8 для неровной кромки инея
    grid = [[rng.random() for _ in range(22)] for _ in range(14)]

    def noise(x, y):
        gx, gy = x / 8.0, y / 8.0
        ix, iy = int(gx), int(gy)
        tx, ty = gx - ix, gy - iy
        a = grid[iy][ix] * (1 - tx) + grid[iy][ix + 1] * tx
        b = grid[iy + 1][ix] * (1 - tx) + grid[iy + 1][ix + 1] * tx
        return a * (1 - ty) + b * ty

    cx, cy, rx, ry = 79.5, 46.5, 70.0, 41.0
    for y in range(c.h):
        for x in range(c.w):
            d = (abs(x - cx) / rx) ** 3 + (abs(y - cy) / ry) ** 3
            r = d ** (1.0 / 3.0)
            if r >= 1.0:
                # обшивка капсулы вокруг крышки: уплотнитель и мягкие сегменты
                if r < 1.035:
                    col = p["gasket_l"] if y < cy else p["gasket"]
                elif r < 1.07:
                    col = p["seam"]
                elif r < 1.18:
                    col = p["shell_l"]
                elif r < 1.3:
                    col = p["shell"]
                else:
                    col = p["shell_d"]
                c.px[y * c.w + x] = rgba(col)
                continue
            f = (r - 0.55) / 0.45 + (noise(x, y) - 0.5) * 0.7
            red = (x - lamp_x) ** 2 + (y - lamp_y) ** 2 < 26 * 26
            frost_l = p["frost_rl"] if red else p["frost_l"]
            frost = p["frost_r"] if red else p["frost_m"]
            if f > 0.92:
                col = frost_l
            elif f > 0.72:
                col = frost
            elif f > 0.5 and (x + y) % 2 == 0:
                col = frost
            elif f > 0.3 and x % 2 == 0 and y % 2 == 0:
                col = frost
            else:
                # стекло холодит отсек: чуть синее и темнее
                br, bg, bb, _ = bay.px[y * c.w + x]
                col = (int(br * 0.75), int(bg * 0.85) + 4, int(bb * 0.9) + 10)
            c.px[y * c.w + x] = rgba(col)
    # кристаллы инея у кромки
    for _ in range(40):
        x = rng.randint(10, 150)
        y = rng.randint(6, 88)
        d = (abs(x - cx) / rx) ** 3 + (abs(y - cy) / ry) ** 3
        if not 0.55 < d < 0.95:
            continue
        col = p["crack"] if rng.random() < 0.5 else p["frost_l"]
        c.pixel(x, y, col)
        for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            c.pixel(x + ox, y + oy, col)
        if rng.random() < 0.5:
            for ox, oy in ((2, 2), (-2, -2), (2, -2), (-2, 2)):
                c.pixel(x + ox, y + oy, p["frost_l"])
    # выпуклость стекла: дугообразный блик сверху слева (кривая Безье)
    for i in range(40):
        t = i / 39.0
        u = 1.0 - t
        x = int(u * u * 28 + 2 * u * t * 34 + t * t * 70)
        y = int(u * u * 40 + 2 * u * t * 14 + t * t * 13)
        if i % 9 < 7:
            c.pixel(x, y, p["crack"])
            c.pixel(x + 1, y + 1, p["frost_m"])
    # мигающая аварийная лампа просвечивает сквозь иней размытым пятном
    c.dither_disc(lamp_x, lamp_y, 8, p["red"], 1)
    c.circle(lamp_x, lamp_y, 3, p["red"])
    c.circle(lamp_x, lamp_y, 1, p["red_l"])
    # трещина от точки удара с отростками
    ix, iy = 46, 52
    for (x1, y1), (x2, y2) in (((ix, iy), (18, 36)), ((ix, iy), (30, 76)),
                               ((ix, iy), (74, 40)), ((74, 40), (98, 44)),
                               ((74, 40), (82, 24)), ((ix, iy), (66, 70)),
                               ((30, 76), (22, 84)), ((18, 36), (12, 30))):
        c.line(x1, y1 + 1, x2, y2 + 1, p["crack_d"])
        c.line(x1, y1, x2, y2, p["crack"])
    c.ring(ix, iy, 3, 4, p["crack"])
    c.pixel(ix, iy, p["crack"])
    # красное предупреждение, выведенное на стекло крышки
    c.dither_disc(80, 72, 13, p["red_d"], 1)
    for i in range(7):
        c.hline(80 - i, 80 + i, 64 + i, p["red"])
    c.vline(80, 66, 68, p["seam"])
    c.pixel(80, 70, p["seam"])
    for k, w in enumerate((22, 14)):
        y = 74 + k * 3
        for x in range(80 - w // 2, 80 + w // 2):
            if (x * 7 + k) % 5:
                c.pixel(x, y, p["red"])
    # капли талой воды на нижней кромке
    c.noise_specks(rng, 30, 82, 130, 86, p["frost_l"], 10)


def scene_bridge(c, rng):
    """Рубка грузовика: широкий треснувший обзорный экран, залатанный аварийной
    плёнкой, за ним звёзды; мёртвые пульты, живой только янтарный экран маршрута;
    одно кресло пилота сорвано, за креслами в тени осела фигура в скафандре."""
    p = {
        "hull_d": (16, 19, 26), "hull": (26, 31, 40), "hull_l": (40, 47, 59),
        "frame": (50, 58, 72), "frame_l": (84, 96, 114),
        "void": VOID, "star": STAR,
        "planet": (46, 62, 84), "planet_l": (96, 124, 150), "planet_d": (30, 40, 56),
        "crack": (196, 212, 228),
        "film": (64, 60, 44), "film_l": (120, 112, 80),
        "tape": (196, 182, 136), "tape_d": (120, 108, 76),
        "con_top": (46, 52, 64), "con_front": (30, 35, 45), "con_edge": (70, 78, 94),
        "screen": (14, 17, 22), "glare": (52, 60, 72),
        "amber": AMBER, "amber_d": (92, 66, 26), "amber_bg": (40, 28, 12),
        "amber_l": (252, 220, 150),
        "seat": (50, 52, 60), "seat_m": (42, 44, 51), "seat_d": (28, 29, 35),
        "seat_l": (76, 78, 88),
        "cable": (120, 70, 46),
        "f0": (30, 33, 40), "f1": (22, 25, 31),
        "suit": (37, 38, 44), "suit_l": (48, 49, 55),
        "red": RED,
    }
    c.fill(p["hull"])
    # потолок с потухшей панелью
    c.fill_rect(0, 0, 159, 4, p["hull_d"])
    for x in range(20, 140, 6):
        c.pixel(x, 2, p["hull_l"])
    # обзорный экран: рама и стекло
    _poly(c, [(2, 4), (158, 4), (142, 50), (18, 50)], p["frame"])
    glass = [(8, 7), (152, 7), (138, 47), (22, 47)]
    _poly(c, glass, p["void"])
    c.specks_on(rng, 8, 7, 152, 47, p["void"], p["star"], 70)
    c.specks_on(rng, 8, 7, 152, 47, p["void"], STAR_DIM, 90)
    # край холодной планеты внизу справа — только по пикселям неба
    sky = (rgba(p["void"]), rgba(p["star"]), rgba(STAR_DIM))
    ox, oy, orr = 132, 96, 60
    for y in range(7, 48):
        for x in range(70, 153):
            d = (x - ox) ** 2 + (y - oy) ** 2
            if d > orr * orr or c.get(x, y) not in sky:
                continue
            if d > (orr - 2) ** 2:
                col = p["planet_l"]
            elif (y + x // 3) % 7 == 0:
                col = p["planet_d"]
            else:
                col = p["planet"]
            c.pixel(x, y, col)
    # стойки-переплёты между секциями экрана
    for (x1, x2) in ((56, 60), (104, 100)):
        for o in (-1, 0, 1):
            c.line(x1 + o, 7, x2 + o, 47, p["frame"])
        c.line(x1 - 1, 7, x2 - 1, 47, p["frame_l"])
    c.line(8, 7, 152, 7, p["frame_l"])
    # трещины на левой секции
    ix, iy = 36, 24
    for x2, y2 in ((12, 12), (24, 44), (52, 14), (54, 36), (14, 30), (40, 46)):
        c.line(ix, iy, x2, y2, p["crack"])
    c.ring(ix, iy, 2, 3, p["crack"])
    # аварийная плёнка поверх трещин: тусклый налёт, блик, рамка и крест из ленты
    patch = [(20, 13), (52, 11), (54, 37), (24, 40)]
    _poly(c, patch, p["film"], 0)
    c.line(26, 34, 46, 15, p["film_l"])
    c.line(29, 35, 48, 17, p["film_l"])
    for a, b in ((0, 1), (1, 2), (2, 3), (3, 0), (0, 2), (1, 3)):
        c.line(int(patch[a][0]), int(patch[a][1]), int(patch[b][0]), int(patch[b][1]), p["tape"])
    for a, b in ((0, 1), (3, 2)):
        c.line(int(patch[a][0]), int(patch[a][1]) + 1, int(patch[b][0]), int(patch[b][1]) + 1,
               p["tape_d"])
    patch2 = [(112, 26), (130, 24), (128, 40), (110, 42)]
    c.line(118, 28, 126, 38, p["crack"])
    c.line(120, 33, 113, 38, p["crack"])
    _poly(c, patch2, p["film"], 1)
    c.line(114, 38, 124, 28, p["film_l"])
    for a, b in ((0, 1), (1, 2), (2, 3), (3, 0)):
        c.line(int(patch2[a][0]), int(patch2[a][1]), int(patch2[b][0]), int(patch2[b][1]), p["tape"])
    # приборная доска: наклонная крышка и лицевая панель
    _poly(c, [(14, 50), (146, 50), (158, 62), (2, 62)], p["con_top"])
    c.hline(14, 146, 50, p["con_edge"])
    c.fill_rect(0, 62, 159, 69, p["con_front"])
    c.hline(0, 159, 62, p["con_edge"])
    # мёртвые экраны с бликом
    for (x0, x1) in ((18, 38), (42, 60), (100, 118), (122, 142)):
        c.fill_rect(x0, 52, x1, 59, p["screen"])
        c.rect(x0 - 1, 51, x1 + 1, 60, p["hull_d"])
        c.line(x0 + 2, 58, x0 + 7, 53, p["glare"])
    # единственный живой экран — маршрут янтарём
    c.dither_disc(80, 56, 16, p["amber_d"], 1)
    c.fill_rect(65, 51, 95, 60, p["amber_bg"])
    c.rect(64, 50, 96, 61, p["hull_d"])
    for x in range(67, 94, 4):
        c.vline(x, 52, 59, p["amber_d"])
    route = ((68, 58), (74, 55), (80, 57), (86, 53), (92, 54))
    for (x1, y1), (x2, y2) in zip(route, route[1:]):
        c.line(x1, y1, x2, y2, p["amber"])
    for x, y in route[:-1]:
        c.pixel(x, y, p["amber_l"])
    c.rect(91, 53, 93, 55, p["amber_l"])
    # редкие живые огоньки на пульте
    for x, y, col in ((10, 65, p["amber_d"]), (150, 65, p["red"]), (46, 65, p["amber_d"])):
        c.pixel(x, y, col)
    # палуба
    c.dither_rect(0, 70, 159, 95, p["f0"], p["f1"])
    c.fill_rect(0, 88, 159, 95, p["f1"])
    c.hline(0, 159, 70, p["hull_d"])
    # левое кресло пилота, вид со спины: подголовник, спинка с боковинами
    c.fill_rect(40, 84, 46, 95, p["seat_d"])
    c.ellipse(43, 61, 14, 6, p["seat_d"])
    c.fill_rect(29, 61, 57, 87, p["seat_d"])
    c.ellipse(43, 61, 13, 5, p["seat"])
    c.fill_rect(30, 61, 56, 86, p["seat"])
    c.fill_rect(34, 60, 52, 84, p["seat_m"])
    for y in (66, 72, 78):
        c.hline(35, 51, y, p["seat_d"])
    c.fill_rect(41, 52, 45, 56, p["seat_d"])
    c.ellipse(43, 48, 8, 5, p["seat_d"])
    c.ellipse(43, 48, 7, 4, p["seat"])
    # янтарный экран подсвечивает правую кромку кресла
    for x, y in ((47, 44), (48, 44), (49, 45), (50, 46), (50, 47)):
        c.pixel(x, y, p["amber_d"])
    c.vline(56, 62, 86, p["amber_d"])
    c.hline(45, 54, 56, p["amber_d"])
    c.hline(36, 44, 44, p["seat_l"])
    c.hline(32, 44, 56, p["seat_l"])
    # правое кресло сорвано: обломок стойки с рваным краем, кабель, спинка на боку
    c.fill_rect(100, 82, 106, 95, p["seat_d"])
    for x, h in ((100, 80), (101, 77), (102, 80), (103, 76), (104, 79), (105, 78), (106, 81)):
        c.vline(x, h, 82, p["seat_d"])
    c.pixel(103, 76, p["seat_l"])
    c.pixel(101, 77, p["seat_l"])
    c.fill_rect(98, 92, 108, 95, p["hull_d"])
    c.line(104, 80, 112, 76, p["cable"])
    c.line(112, 76, 118, 80, p["cable"])
    c.pixel(103, 75, p["amber"])
    back = [(126, 60), (154, 72), (146, 95), (116, 86)]
    _poly(c, back, p["seat_d"])
    _poly(c, [(127, 62), (151, 73), (144, 93), (118, 85)], p["seat"])
    _poly(c, [(129, 66), (147, 74), (141, 89), (123, 83)], p["seat_m"])
    c.line(126, 60, 154, 72, p["seat_l"])
    c.line(125, 76, 145, 84, p["seat_d"])
    _poly(c, [(134, 52), (150, 59), (146, 68), (130, 61)], p["seat_d"])
    _poly(c, [(135, 54), (148, 60), (145, 66), (132, 60)], p["seat"])
    c.line(134, 52, 150, 59, p["seat_l"])
    # за креслами в тени осел второй пилот: шлем склонён на грудь, рука на палубе
    c.ellipse(79, 86, 12, 9, p["suit"])
    c.ellipse(80, 80, 11, 6, p["suit"])
    _suit_limb(c, ((88, 84, 3), (96, 89, 3), (104, 93, 2)), p["suit"], p["suit_l"])
    _suit_limb(c, ((70, 82, 3), (66, 89, 3), (64, 94, 2)), p["suit"], p["suit_l"])
    c.circle(77, 71, 7, p["hull_d"])
    c.circle(77, 71, 6, p["suit"])
    c.ellipse(80, 74, 4, 2, p["hull_d"])
    # кромку шлема и плеч ловит отсвет экрана, в визоре — янтарная искра
    for x, y in ((71, 67), (72, 66), (74, 65), (76, 64), (78, 64), (80, 65), (82, 66)):
        c.pixel(x, y, p["amber_d"])
    for x, y in ((84, 74), (86, 75), (88, 76), (90, 78)):
        c.pixel(x, y, p["suit_l"])
    c.pixel(81, 75, p["amber"])
    c.noise_specks(rng, 0, 76, 159, 95, p["hull_d"], 40)
    c.noise_specks(rng, 60, 70, 110, 80, p["amber_d"], 4)


def _cargo_bay(c):
    """Грузовой отсек без дрона: коробка, штабели контейнеров. Возвращает палитру."""
    p = {
        "d0": (38, 44, 54), "d1": (28, 33, 41), "d2": (22, 27, 35),
        "f0": (46, 44, 40), "f1": (35, 34, 31), "f2": (22, 27, 35),
        "w0": (50, 56, 68), "w1": (38, 44, 54), "w2": (28, 33, 41),
        "far": (20, 25, 33),
        "seam": (13, 17, 23),
        "crate": (112, 86, 44),
        "crate_d": (72, 54, 28),
        "metal": (128, 140, 160),
        "metal_d": (62, 72, 90),
        "amber": AMBER,
        "red": RED,
        "spark": (250, 240, 214),
    }
    draw_room(c, (54, 28, 106, 66),
              {"ceil": (p["d0"], p["d1"], p["d2"]),
               "floor": (p["f0"], p["f1"], p["f2"]),
               "left": (p["w0"], p["w1"], p["w2"]),
               "right": (p["w0"], p["w1"], p["w2"]),
               "far": p["far"]}, p["seam"])
    # штабели контейнеров вдоль стен (ближе — крупнее)
    stacks = ((2, 18, 30, 78), (32, 30, 22, 70), (124, 16, 34, 80), (108, 32, 16, 68))
    for (bx, by, bw, bh) in stacks:
        c.fill_rect(bx, by, bx + bw, by + bh, p["crate"])
        c.rect(bx, by, bx + bw, by + bh, p["seam"])
        c.hline(bx + 1, bx + bw - 1, by + 1, p["amber"])
        for yy in range(by + 6, by + bh, 14):
            c.hline(bx, bx + bw, yy, p["crate_d"])
            c.hline(bx, bx + bw, yy + 1, p["seam"])
            c.fill_rect(bx + 4, yy + 4, bx + 9, yy + 7, p["crate_d"])
        c.vline(bx + bw // 2, by, by + bh, p["crate_d"])
    # верхние ящики на дальнем плане
    c.fill_rect(58, 52, 74, 66, p["crate_d"])
    c.rect(58, 52, 74, 66, p["seam"])
    c.fill_rect(88, 56, 102, 66, p["crate_d"])
    c.rect(88, 56, 102, 66, p["seam"])
    return p


def _cargo_bay_floor(c, rng, p):
    """Разбросанный по палубе грузового отсека груз."""
    c.noise_specks(rng, 40, 76, 120, 95, p["crate_d"], 40)
    c.noise_specks(rng, 40, 80, 120, 95, p["metal_d"], 20)


def scene_cargo_drone(c, rng):
    """Грузовой отсек: контейнеры, в центре сервисный дрон с красным окуляром."""
    p = _cargo_bay(c)
    # дрон в центре
    c.dither_disc(80, 44, 20, p["metal_d"], 1)
    c.ellipse(80, 42, 15, 11, p["metal"])
    c.ellipse(80, 42, 15, 11, p["seam"], filled=False)
    c.ellipse(80, 40, 11, 6, p["metal_d"])
    c.circle(80, 41, 4, p["seam"])
    c.circle(80, 41, 3, p["red"])
    c.circle(79, 40, 1, RED_LIT)
    c.dither_disc(80, 41, 8, p["red"], 0)
    c.circle(80, 41, 3, p["red"])
    # антенна и маячок
    c.vline(80, 26, 31, p["metal_d"])
    c.pixel(80, 25, p["amber"])
    # опоры-сопла
    c.fill_rect(70, 52, 74, 58, p["metal_d"])
    c.fill_rect(86, 52, 90, 58, p["metal_d"])
    c.dither_over(69, 58, 75, 62, p["amber"], 1)
    c.dither_over(85, 58, 91, 62, p["amber"], 1)
    # искрящий манипулятор
    c.line(94, 44, 108, 50, p["metal"])
    c.line(94, 45, 108, 51, p["seam"])
    c.line(108, 50, 116, 44, p["metal"])
    c.line(108, 51, 116, 45, p["seam"])
    c.fill_rect(114, 40, 120, 46, p["metal_d"])
    c.noise_specks(rng, 112, 34, 126, 52, p["amber"], 14)
    c.noise_specks(rng, 114, 36, 124, 50, p["spark"], 7)
    c.line(66, 46, 56, 54, p["metal"])
    c.line(66, 47, 56, 55, p["seam"])
    _cargo_bay_floor(c, rng, p)


def scene_cargo_drone_down(c, rng):
    """Тот же грузовой отсек после боя: дрон рухнул на палубу, окуляр погас."""
    p = _cargo_bay(c)
    _cargo_bay_floor(c, rng, p)
    dead = (54, 30, 36)
    smoke = (84, 90, 102)
    # тень и корпус, завалившийся набок
    c.ellipse(80, 89, 21, 3, p["seam"])
    c.ellipse(80, 80, 16, 9, p["metal"])
    c.ellipse(80, 84, 15, 5, p["metal_d"])
    c.ellipse(85, 76, 10, 4, p["metal_d"])
    c.ellipse(80, 80, 16, 9, p["seam"], filled=False)
    # вмятины и копоть
    c.line(76, 72, 80, 78, p["seam"])
    c.line(80, 78, 78, 82, p["seam"])
    c.dither_over(86, 73, 95, 80, p["seam"], 0)
    # погасший окуляр с трещиной
    c.circle(72, 81, 5, p["seam"])
    c.circle(72, 81, 4, p["metal_d"])
    c.circle(72, 81, 3, dead)
    c.line(70, 78, 72, 81, p["seam"])
    c.line(72, 81, 71, 84, p["seam"])
    c.line(72, 81, 75, 80, p["seam"])
    c.pixel(70, 80, p["metal"])
    # пробоина в корпусе: оголённая проводка
    c.fill_rect(88, 74, 93, 78, p["seam"])
    c.pixel(87, 75, p["seam"])
    c.pixel(94, 77, p["seam"])
    c.pixel(89, 76, p["amber"])
    c.pixel(91, 75, p["red"])
    c.pixel(92, 77, p["crate_d"])
    # погнутая антенна с погасшим маячком
    c.line(84, 72, 87, 66, p["metal_d"])
    c.line(87, 66, 93, 64, p["metal_d"])
    c.pixel(94, 64, p["seam"])
    # обломанное сопло
    c.fill_rect(63, 85, 67, 88, p["metal_d"])
    c.rect(63, 85, 67, 88, p["seam"])
    # обвисший манипулятор лежит на палубе
    c.line(95, 82, 101, 89, p["metal"])
    c.line(94, 83, 100, 90, p["seam"])
    c.fill_rect(99, 89, 104, 92, p["metal_d"])
    c.rect(99, 89, 104, 92, p["seam"])
    c.pixel(105, 93, p["metal_d"])
    # оторванная вторая рука
    c.line(56, 91, 62, 87, p["metal"])
    c.line(56, 92, 62, 88, p["seam"])
    # дым из пробоины и редкие искры
    c.dither_disc(91, 69, 4, smoke, 0)
    c.dither_disc(93, 61, 4, smoke, 1)
    c.dither_disc(96, 53, 3, smoke, 0)
    c.dither_disc(98, 47, 2, smoke, 1)
    c.noise_specks(rng, 86, 68, 97, 79, p["amber"], 6)
    c.noise_specks(rng, 87, 69, 96, 78, p["spark"], 4)
    # осколки корпуса на палубе
    c.noise_specks(rng, 56, 86, 106, 95, p["metal"], 14)
    c.noise_specks(rng, 56, 86, 106, 95, p["seam"], 10)


def scene_shuttle_bay(c, rng):
    """Чужой шаттл в стыковочном шлюзе, трап опущен."""
    p = {
        "d0": (35, 39, 50), "d1": (26, 29, 38), "d2": (20, 24, 32),
        "f0": (44, 46, 52), "f1": (34, 36, 42), "f2": (20, 24, 32),
        "w0": (46, 50, 64), "w1": (35, 39, 50), "w2": (26, 29, 38),
        "far": (17, 21, 30),
        "seam": (12, 15, 21),
        "hull": (96, 104, 126),
        "hull_d": (56, 62, 80),
        "hull_l": (146, 154, 176),
        "alien": (120, 96, 158),
        "glow": (150, 226, 214),
        "amber": AMBER,
        "red": RED,
    }
    draw_room(c, (50, 20, 110, 68),
              {"ceil": (p["d0"], p["d1"], p["d2"]),
               "floor": (p["f0"], p["f1"], p["f2"]),
               "left": (p["w0"], p["w1"], p["w2"]),
               "right": (p["w0"], p["w1"], p["w2"]),
               "far": p["far"]}, p["seam"])
    # створки внешнего шлюза на дальней стене
    c.fill_rect(52, 22, 108, 66, p["d2"])
    c.rect(52, 22, 108, 66, p["hull_d"])
    c.vline(80, 22, 66, p["seam"])
    for yy in range(26, 66, 8):
        c.hline(53, 107, yy, p["w1"])
    c.fill_rect(72, 24, 88, 28, p["hull_d"])
    c.dither_over(54, 24, 106, 34, p["amber"], 1)
    # фонари шлюза
    for xx in (56, 68, 92, 104):
        c.fill_rect(xx, 20, xx + 3, 22, p["amber"])
    # корпус шаттла (клин носом к зрителю)
    for y in range(34, 70):
        half = int(6 + (y - 34) * 1.55)
        c.hline(80 - half, 80 + half, y, p["hull"])
    for y in range(34, 70):
        half = int(6 + (y - 34) * 1.55)
        c.pixel(80 - half, y, p["seam"])
        c.pixel(80 + half, y, p["seam"])
        if y % 2 == 0:
            c.pixel(80 - half + 1, y, p["hull_l"])
    c.hline(24, 136, 70, p["seam"])
    c.fill_rect(26, 70, 134, 76, p["hull_d"])
    c.hline(26, 134, 76, p["seam"])
    # кокпит и обводы
    c.ellipse(80, 44, 16, 6, p["alien"])
    c.ellipse(80, 43, 13, 4, p["glow"])
    c.line(64, 50, 96, 50, p["hull_d"])
    c.line(58, 58, 102, 58, p["hull_d"])
    # крылья
    c.line(40, 66, 20, 56, p["hull"])
    c.line(40, 67, 20, 57, p["seam"])
    c.fill_rect(14, 52, 24, 60, p["hull_d"])
    c.rect(14, 52, 24, 60, p["seam"])
    c.line(120, 66, 140, 56, p["hull"])
    c.line(120, 67, 140, 57, p["seam"])
    c.fill_rect(136, 52, 146, 60, p["hull_d"])
    c.rect(136, 52, 146, 60, p["seam"])
    c.dither_over(14, 60, 24, 66, p["glow"], 1)
    c.dither_over(136, 60, 146, 66, p["glow"], 1)
    # опущенный трап и свет из люка
    c.fill_rect(66, 60, 94, 70, p["seam"])
    c.rect(66, 60, 94, 70, p["alien"])
    c.dither_over(68, 61, 92, 70, p["glow"], 0)
    for y in range(76, 96):
        half = 14 + (y - 76)
        c.hline(80 - half, 80 + half, y, p["hull_d"] if y % 4 else p["hull"])
        c.pixel(80 - half, y, p["seam"])
        c.pixel(80 + half, y, p["seam"])
    c.dither_over(62, 78, 98, 94, p["glow"], 1)
    # сигнальные огни на полу
    for xx in (10, 26, 134, 150):
        c.fill_rect(xx, 88, xx + 3, 90, p["red"])
    c.noise_specks(rng, 0, 80, 159, 95, p["f2"], 30)


def scene_reactor_core(c, rng):
    """Реакторный отсек: светящаяся сине-зелёная колонна ядра за решёткой."""
    p = {
        "d0": (32, 39, 49), "d1": (24, 29, 37), "d2": (18, 22, 29),
        "f0": (36, 42, 50), "f1": (27, 32, 39), "f2": (18, 22, 29),
        "w0": (42, 50, 62), "w1": (32, 39, 49), "w2": (24, 29, 37),
        "far": (16, 22, 28),
        "seam": (11, 15, 20),
        "core_d": (26, 92, 96),
        "core": (58, 168, 158),
        "core_l": (132, 226, 202),
        "core_w": (226, 250, 238),
        "grate": (58, 70, 86),
        "grate_d": (30, 38, 48),
        "amber": AMBER,
        "cyan": CYAN,
    }
    draw_room(c, (52, 14, 108, 74),
              {"ceil": (p["d0"], p["d1"], p["d2"]),
               "floor": (p["f0"], p["f1"], p["f2"]),
               "left": (p["w0"], p["w1"], p["w2"]),
               "right": (p["w0"], p["w1"], p["w2"]),
               "far": p["far"]}, p["seam"])
    # ореол свечения на дальней стене и потолке
    c.dither_over(52, 14, 108, 74, p["core_d"], 0)
    c.dither_over(40, 0, 120, 12, p["core_d"], 1)
    # колонна ядра
    c.fill_rect(66, 8, 94, 88, p["core_d"])
    c.fill_rect(69, 8, 91, 88, p["core"])
    c.fill_rect(74, 8, 86, 88, p["core_l"])
    c.fill_rect(78, 8, 82, 88, p["core_w"])
    for yy in range(10, 88, 9):
        c.hline(66, 94, yy, p["core_d"])
        c.hline(67, 93, yy + 1, p["core"])
    # кожухи сверху и снизу
    c.fill_rect(60, 0, 100, 10, p["grate"])
    c.rect(60, 0, 100, 10, p["seam"])
    c.fill_rect(60, 86, 100, 95, p["grate"])
    c.rect(60, 86, 100, 95, p["seam"])
    c.hline(62, 98, 88, p["grate_d"])
    # решётка перед ядром
    for xx in range(58, 104, 6):
        c.vline(xx, 6, 90, p["grate"])
        c.vline(xx + 1, 6, 90, p["grate_d"])
    for yy in range(14, 90, 16):
        c.hline(58, 103, yy, p["grate"])
        c.hline(58, 103, yy + 1, p["grate_d"])
    # отсвет на полу
    c.dither_over(44, 76, 116, 95, p["core_d"], 1)
    c.dither_over(60, 84, 100, 95, p["core"], 0)
    # трубопроводы по бокам
    for xx in (14, 22, 138, 146):
        c.vline(xx, 0, 95, p["grate"])
        c.vline(xx + 1, 0, 95, p["grate_d"])
    for yy in (18, 46, 74):
        c.fill_rect(12, yy, 25, yy + 4, p["grate_d"])
        c.fill_rect(136, yy, 149, yy + 4, p["grate_d"])
        c.pixel(18, yy + 2, p["amber"])
        c.pixel(142, yy + 2, p["cyan"])
    # пульт контроля слева
    c.fill_rect(30, 56, 48, 72, p["grate"])
    c.rect(30, 56, 48, 72, p["seam"])
    c.fill_rect(32, 58, 46, 66, p["seam"])
    c.hline(33, 41, 60, p["cyan"])
    c.hline(33, 44, 63, p["core_l"])
    c.pixel(34, 69, p["amber"])
    c.pixel(38, 69, p["cyan"])
    c.noise_specks(rng, 0, 84, 159, 95, p["f2"], 26)


def scene_service_corridor(c, rng):
    """Узкий техкоридор без давления: иней, оборванные кабели, завал."""
    p = {
        "d0": (31, 38, 48), "d1": (23, 28, 36), "d2": (19, 23, 30),
        "f0": (30, 36, 44), "f1": (23, 28, 36), "f2": (19, 23, 30),
        "w0": (40, 48, 60), "w1": (31, 38, 48), "w2": (23, 28, 36),
        "far": (14, 18, 25),
        "seam": (10, 13, 19),
        "frost": (188, 214, 232),
        "frost_d": (108, 140, 164),
        "pipe": (58, 68, 84),
        "rubble": (52, 56, 64),
        "cyan": CYAN,
        "amber": AMBER,
        "red": RED,
    }
    draw_room(c, (66, 18, 96, 78),
              {"ceil": (p["d0"], p["d1"], p["d2"]),
               "floor": (p["f0"], p["f1"], p["f2"]),
               "left": (p["w0"], p["w1"], p["w2"]),
               "right": (p["w0"], p["w1"], p["w2"]),
               "far": p["far"]}, p["seam"])
    # трубы вдоль стен, сходящиеся к дальнему концу
    for t in (0, 1, 2):
        y_near = 22 + t * 22
        y_far = 26 + t * 16
        c.line(0, y_near, 66, y_far, p["pipe"])
        c.line(0, y_near + 1, 66, y_far + 1, p["seam"])
        c.line(159, y_near, 96, y_far, p["pipe"])
        c.line(159, y_near + 1, 96, y_far + 1, p["seam"])
    # хомуты на трубах
    for x in (12, 34, 52):
        c.vline(x, 18, 70, p["w2"])
    for x in (108, 126, 148):
        c.vline(x, 18, 70, p["w2"])
    # тусклая лампа в дальнем конце
    c.fill_rect(72, 20, 90, 24, p["cyan"])
    c.dither_over(66, 18, 96, 40, p["cyan"], 1)
    c.fill_rect(68, 18, 94, 20, p["pipe"])
    # оборванные кабели с потолка
    for (x, ln) in ((22, 26), (44, 18), (58, 34), (112, 22), (134, 30)):
        c.line(x, 0, x + 3, ln, p["seam"])
        c.line(x + 3, ln, x - 2, ln + 9, p["seam"])
        c.pixel(x - 2, ln + 10, p["amber"])
    c.noise_specks(rng, 40, 30, 62, 46, p["amber"], 8)
    c.noise_specks(rng, 108, 20, 120, 32, p["red"], 5)
    # завал в дальней части коридора
    for (bx, by, bw, bh) in ((60, 64, 16, 14), (74, 58, 14, 20), (86, 66, 14, 12),
                             (52, 70, 14, 10), (96, 70, 16, 10)):
        c.fill_rect(bx, by, bx + bw, by + bh, p["rubble"])
        c.rect(bx, by, bx + bw, by + bh, p["seam"])
        c.hline(bx + 1, bx + bw - 1, by + 1, p["w0"])
    c.noise_specks(rng, 48, 62, 114, 84, p["rubble"], 40)
    # иней: налёт по углам отсека, кромкам труб и завалу, а не сплошной шум
    c.dither_over(0, 0, 159, 8, p["frost_d"], 0)
    c.dither_over(0, 9, 159, 12, p["frost_d"], 1)
    c.dither_over(0, 86, 159, 95, p["frost_d"], 1)
    for t in (0, 1, 2):
        y_near = 22 + t * 22
        y_far = 26 + t * 16
        c.line(0, y_near - 1, 66, y_far - 1, p["frost_d"])
        c.line(159, y_near - 1, 96, y_far - 1, p["frost_d"])
    c.dither_over(0, 30, 10, 78, p["frost_d"], 0)
    c.dither_over(150, 30, 159, 78, p["frost_d"], 0)
    for (bx, by, bw) in ((60, 64, 16), (74, 58, 14), (86, 66, 14), (52, 70, 14), (96, 70, 16)):
        c.dither_over(bx, by, bx + bw, by + 2, p["frost_d"], 0)
    c.noise_specks(rng, 0, 0, 159, 14, p["frost"], 26)
    c.noise_specks(rng, 0, 84, 159, 95, p["frost"], 26)
    c.noise_specks(rng, 48, 56, 114, 80, p["frost"], 18)


def scene_dock_bay(c, rng):
    """Стыковочный узел станции: большой шлюз, огни посадочной разметки."""
    p = {
        "d0": (37, 43, 54), "d1": (27, 32, 41), "d2": (21, 26, 34),
        "f0": (48, 48, 48), "f1": (37, 37, 38), "f2": (21, 26, 34),
        "w0": (48, 54, 68), "w1": (37, 43, 54), "w2": (27, 32, 41),
        "far": (18, 23, 32),
        "seam": (12, 16, 22),
        "gate": (62, 72, 90),
        "gate_d": (34, 42, 54),
        "gate_l": (124, 138, 160),
        "amber": AMBER,
        "amber_d": (128, 96, 40),
        "cyan": CYAN,
        "red": RED,
    }
    draw_room(c, (40, 14, 120, 70),
              {"ceil": (p["d0"], p["d1"], p["d2"]),
               "floor": (p["f0"], p["f1"], p["f2"]),
               "left": (p["w0"], p["w1"], p["w2"]),
               "right": (p["w0"], p["w1"], p["w2"]),
               "far": p["far"]}, p["seam"])
    # большой шлюз в торце
    c.fill_rect(46, 20, 114, 70, p["gate_d"])
    c.rect(46, 20, 114, 70, p["gate"])
    c.rect(44, 18, 116, 70, p["gate_l"])
    for y in range(20, 70):
        if y % 2 == 0:
            c.pixel(46 + (y - 20) // 6, y, p["gate"])
    # створки, расходящиеся от центра
    c.vline(79, 20, 70, p["seam"])
    c.vline(80, 20, 70, p["gate_l"])
    c.vline(81, 20, 70, p["seam"])
    for yy in range(24, 70, 10):
        c.hline(47, 113, yy, p["gate"])
        c.hline(47, 113, yy + 1, p["seam"])
    # предупредительная штриховка над шлюзом
    for x in range(44, 117, 4):
        c.line(x, 18, x - 4, 12, p["amber"])
        c.line(x + 1, 18, x - 3, 12, p["amber_d"])
    # окно диспетчерской слева сверху
    c.fill_rect(6, 12, 34, 30, p["seam"])
    c.rect(5, 11, 35, 31, p["gate"])
    c.dither_over(7, 13, 33, 29, p["cyan"], 0)
    c.vline(20, 12, 30, p["gate_d"])
    # причальные фермы и кран справа
    c.fill_rect(128, 10, 134, 70, p["gate"])
    c.rect(128, 10, 134, 70, p["seam"])
    for yy in range(14, 70, 10):
        c.line(128, yy, 134, yy + 8, p["gate_d"])
    c.fill_rect(120, 24, 148, 28, p["gate"])
    c.hline(120, 148, 29, p["seam"])
    c.pixel(122, 26, p["red"])
    # посадочная разметка на полу: шевроны к шлюзу
    for i, yy in enumerate(range(74, 96, 7)):
        half = 26 + i * 12
        c.line(80 - half, yy + 6, 80, yy, p["amber"])
        c.line(80 + half, yy + 6, 80, yy, p["amber"])
        c.line(80 - half, yy + 7, 80, yy + 1, p["amber_d"])
        c.line(80 + half, yy + 7, 80, yy + 1, p["amber_d"])
    # огни разметки по краям пола
    for i in range(6):
        y = 72 + i * 4
        dx = 10 + i * 11
        c.fill_rect(80 - dx - 1, y, 80 - dx + 1, y + 1, p["cyan"])
        c.fill_rect(80 + dx - 1, y, 80 + dx + 1, y + 1, p["cyan"])
    c.noise_specks(rng, 0, 72, 159, 95, p["f2"], 34)


def _comms_hall(c):
    """Зал связи без турели: аппаратура в торце, антенные стойки. Возвращает палитру."""
    p = {
        "d0": (34, 39, 50), "d1": (25, 30, 39), "d2": (19, 23, 31),
        "f0": (38, 40, 48), "f1": (29, 31, 38), "f2": (19, 23, 31),
        "w0": (44, 50, 64), "w1": (34, 39, 50), "w2": (25, 30, 39),
        "far": (16, 21, 29),
        "seam": (11, 14, 20),
        "rack": (62, 72, 88),
        "rack_d": (34, 42, 54),
        "screen": (18, 46, 56),
        "cyan": CYAN,
        "red": RED,
        "red_d": (108, 30, 40),
        "amber": AMBER,
    }
    draw_room(c, (56, 24, 104, 68),
              {"ceil": (p["d0"], p["d1"], p["d2"]),
               "floor": (p["f0"], p["f1"], p["f2"]),
               "left": (p["w0"], p["w1"], p["w2"]),
               "right": (p["w0"], p["w1"], p["w2"]),
               "far": p["far"]}, p["seam"])
    # стена аппаратуры связи в торце
    c.fill_rect(58, 30, 102, 68, p["rack_d"])
    c.rect(58, 30, 102, 68, p["rack"])
    for yy in range(33, 66, 6):
        c.hline(59, 101, yy, p["rack"])
        for i in range(6):
            xx = 62 + i * 7
            c.pixel(xx, yy + 2, p["cyan"] if (i + yy) % 3 else p["amber"])
    c.fill_rect(62, 34, 78, 46, p["screen"])
    c.dither_over(63, 35, 77, 45, p["cyan"], 0)
    # антенные стойки по бокам (решётчатые мачты)
    for (bx, bw) in ((8, 26), (126, 26)):
        c.fill_rect(bx, 8, bx + bw, 82, p["rack_d"])
        c.rect(bx, 8, bx + bw, 82, p["seam"])
        c.vline(bx + 2, 8, 82, p["rack"])
        c.vline(bx + bw - 2, 8, 82, p["rack"])
        for yy in range(10, 82, 8):
            c.line(bx + 2, yy, bx + bw - 2, yy + 8, p["rack"])
            c.line(bx + 2, yy + 8, bx + bw - 2, yy, p["rack_d"])
            c.hline(bx + 2, bx + bw - 2, yy, p["rack"])
        c.fill_rect(bx + 4, 2, bx + bw - 4, 8, p["rack"])
        c.pixel(bx + bw // 2, 1, p["amber"])
    # кабельные лотки к стойкам
    c.line(34, 40, 56, 44, p["rack_d"])
    c.line(126, 40, 104, 44, p["rack_d"])
    return p


def _comms_hall_floor(c, rng, p):
    """Блики экранов и мусор на полу зала связи."""
    c.dither_over(56, 70, 104, 78, p["cyan"], 1)
    c.noise_specks(rng, 0, 76, 159, 95, p["f2"], 30)
    c.noise_specks(rng, 30, 80, 130, 95, p["rack_d"], 16)


def scene_comms_sentry(c, rng):
    """Зал связи: антенные стойки, турель охраны на потолке с красным лучом."""
    p = _comms_hall(c)
    # турель на потолке
    c.fill_rect(72, 0, 88, 6, p["rack_d"])
    c.fill_rect(74, 6, 86, 12, p["rack"])
    c.rect(74, 6, 86, 12, p["seam"])
    c.ellipse(80, 14, 9, 6, p["rack"])
    c.ellipse(80, 14, 9, 6, p["seam"], filled=False)
    c.fill_rect(76, 16, 84, 20, p["rack_d"])
    c.circle(80, 18, 2, p["red"])
    c.pixel(80, 17, RED_LIT)
    # красный луч сканера вниз и вбок
    c.line(80, 20, 52, 95, p["red_d"])
    c.line(81, 20, 53, 95, p["red"])
    c.line(82, 20, 54, 95, p["red_d"])
    c.dither_over(40, 84, 70, 95, p["red_d"], 1)
    c.dither_disc(80, 18, 10, p["red_d"], 0)
    _comms_hall_floor(c, rng, p)


def scene_comms_sentry_down(c, rng):
    """Тот же зал связи после боя: турель сорвана с подвеса, линза погасла."""
    p = _comms_hall(c)
    _comms_hall_floor(c, rng, p)
    dead = (46, 26, 32)
    lit = (98, 110, 130)
    smoke = (66, 72, 88)
    spark = (250, 240, 214)
    # потолочная плита с вырванным креплением
    c.fill_rect(72, 0, 88, 6, p["rack_d"])
    c.fill_rect(79, 3, 86, 6, p["seam"])
    c.pixel(78, 5, p["seam"])
    c.pixel(87, 4, p["seam"])
    # уцелевший кронштейн перекошен: турель качнулась вниз и вправо
    for d in range(3):
        c.line(74 + d, 6, 84 + d, 17, p["rack"])
    c.line(74, 7, 83, 18, p["seam"])
    c.line(77, 6, 87, 17, lit)
    # оборванный кабель с искрящим концом
    c.line(83, 6, 80, 13, p["seam"])
    c.line(80, 13, 81, 22, p["seam"])
    c.pixel(81, 23, p["amber"])
    # корпус турели висит под углом
    c.ellipse(91, 23, 11, 7, p["rack"])
    c.ellipse(93, 26, 9, 3, p["rack_d"])
    c.ellipse(91, 23, 11, 7, p["seam"], filled=False)
    c.line(84, 18, 92, 17, lit)
    c.line(85, 22, 98, 28, p["seam"])
    # блок излучателя с погасшей треснувшей линзой
    c.fill_rect(93, 27, 101, 32, p["rack_d"])
    c.rect(93, 27, 101, 32, p["seam"])
    c.circle(97, 30, 2, dead)
    c.line(96, 28, 98, 31, p["seam"])
    # погнутый спаренный ствол обвис вниз
    for d in range(2):
        c.line(99 + d, 33, 104 + d, 41, p["rack"])
        c.line(104 + d, 41, 103 + d, 51, p["rack"])
    c.line(98, 33, 103, 41, lit)
    c.line(106, 33, 106, 41, p["seam"])
    c.line(106, 42, 105, 51, p["seam"])
    c.pixel(103, 52, p["seam"])
    c.pixel(104, 52, p["seam"])
    # второй ствол обломан
    c.line(95, 33, 96, 38, p["rack"])
    c.line(96, 33, 97, 38, p["rack_d"])
    c.pixel(95, 39, p["seam"])
    c.pixel(97, 39, p["rack"])
    # дымок вдоль потолка и искры, падающие из крепления
    c.dither_disc(88, 6, 3, smoke, 0)
    c.dither_disc(94, 4, 3, smoke, 1)
    c.dither_disc(100, 3, 2, smoke, 0)
    c.noise_specks(rng, 76, 2, 90, 14, p["amber"], 6)
    c.noise_specks(rng, 78, 4, 88, 12, spark, 4)
    for sx, sy in ((81, 27), (82, 32), (80, 38), (81, 45)):
        c.pixel(sx, sy, p["amber"])
    # обломки под турелью
    c.fill_rect(86, 84, 90, 86, p["rack"])
    c.rect(86, 84, 90, 86, p["seam"])
    c.line(96, 88, 102, 86, p["rack"])
    c.line(96, 89, 102, 87, p["seam"])
    c.noise_specks(rng, 78, 80, 110, 94, p["rack"], 12)
    c.noise_specks(rng, 78, 80, 110, 94, p["seam"], 8)


def scene_antenna_mast(c, rng):
    """Антенная мачта снаружи: тарелка на фоне звёзд и планеты."""
    p = {
        "void": VOID,
        "space": (12, 15, 24),
        "star": STAR,
        "star_d": STAR_DIM,
        "planet_d": (52, 66, 104),
        "planet": (80, 104, 150),
        "planet_l": (126, 158, 196),
        "band": (58, 78, 118),
        "mast": (86, 96, 116),
        "mast_d": (44, 52, 68),
        "dish": (166, 176, 196),
        "dish_d": (96, 106, 128),
        "amber": AMBER,
        "red": RED,
        "cyan": CYAN,
    }
    c.fill(p["space"])
    c.dither_rect(0, 0, 159, 30, p["void"], p["space"])
    c.specks_on(rng, 0, 0, 159, 95, p["space"], p["star_d"], 220)
    c.noise_specks(rng, 0, 0, 159, 88, p["star"], 90)
    # планета в правом нижнем углу
    pcx, pcy, pr = 134, 86, 44
    c.circle(pcx, pcy, pr, p["planet_d"])
    c.circle(pcx, pcy, pr - 2, p["planet"])
    for k, yy in enumerate(range(pcy - pr + 6, pcy + pr, 7)):
        col = p["band"] if k % 2 == 0 else p["planet_l"]
        for x in range(pcx - pr, pcx + pr + 1):
            d = (x - pcx) ** 2 + (yy - pcy) ** 2
            if d <= (pr - 3) ** 2:
                c.pixel(x, yy, col)
                if k % 2:
                    c.pixel(x, yy + 1, p["planet"])
    c.dither_disc(pcx - 18, pcy - 20, 16, p["planet_l"], 0)
    # обшивка станции вдоль нижнего края
    c.fill_rect(0, 84, 159, 95, p["mast_d"])
    c.hline(0, 159, 84, p["mast"])
    for x in range(4, 158, 12):
        c.fill_rect(x, 86, x + 6, 92, p["void"])
        c.pixel(x + 1, 87, p["mast"])
    # решётчатая мачта
    c.fill_rect(44, 26, 48, 86, p["mast_d"])
    c.vline(44, 26, 86, p["mast"])
    c.vline(48, 26, 86, p["mast"])
    for yy in range(28, 86, 8):
        c.line(44, yy, 48, yy + 8, p["mast"])
        c.line(44, yy + 8, 48, yy, p["mast_d"])
        c.hline(43, 49, yy, p["mast"])
    # растяжки
    c.line(46, 30, 12, 84, p["mast_d"])
    c.line(46, 30, 92, 84, p["mast_d"])
    # тарелка
    dcx, dcy = 74, 34
    c.ellipse(dcx, dcy, 26, 22, p["dish_d"])
    c.ellipse(dcx, dcy, 22, 18, p["dish"])
    c.ellipse(dcx + 4, dcy + 2, 15, 12, p["dish_d"])
    c.ellipse(dcx + 4, dcy + 2, 11, 9, p["dish"])
    c.ellipse(dcx, dcy, 26, 22, p["mast_d"], filled=False)
    c.line(dcx, dcy, 48, 44, p["mast"])
    c.line(dcx, dcy + 1, 48, 45, p["mast_d"])
    # облучатель и стойки
    c.line(dcx - 14, dcy - 10, dcx + 2, dcy + 2, p["mast_d"])
    c.line(dcx + 16, dcy - 8, dcx + 2, dcy + 2, p["mast_d"])
    c.fill_rect(dcx - 2, dcy - 2, dcx + 2, dcy + 2, p["mast"])
    c.pixel(dcx, dcy, p["cyan"])
    c.dither_disc(dcx, dcy, 6, p["cyan"], 1)
    # маячки на мачте
    c.pixel(46, 24, p["red"])
    c.fill_rect(45, 24, 47, 25, p["red"])
    c.dither_disc(46, 24, 5, p["red"], 0)
    c.pixel(20, 86, p["amber"])
    c.pixel(104, 86, p["amber"])


def scene_cryo_bay(c, rng):
    """Отсек гибернации — база выжившего: два ряда капсул вдоль стен, одна открыта
    и светится; аварийный свет; верстак из сорванной сервисной панели и ящики-склад."""
    p = dict(CRYO_PALETTE)
    p.update({
        "panel": (98, 108, 122), "panel_l": (150, 160, 176), "panel_d": (60, 66, 78),
        "hole": (10, 12, 16), "cable": (120, 70, 46),
        "crate": (112, 86, 44), "crate_l": (150, 118, 62), "crate_d": (72, 54, 28),
        "amber": AMBER, "lamp_glow": (110, 84, 40), "lamp_l": (252, 226, 168),
        "metal": (128, 140, 160), "metal_d": (62, 72, 90),
    })
    P = _bay_pt
    _cryo_bay_room(c, p, (None, "closed", "closed", "closed"), (None, "open", "closed", "closed"))
    # дыра в стене, откуда сорвана сервисная панель, и свисающие кабели
    hole = [P(-1, -0.6, 1.08), P(-1, -0.6, 1.42), P(-1, 0.12, 1.42), P(-1, 0.12, 1.08)]
    _poly(c, hole, p["hole"])
    for a, b in ((0, 1), (1, 2), (3, 0)):
        c.line(int(hole[a][0]), int(hole[a][1]), int(hole[b][0]), int(hole[b][1]), p["panel_d"])
    for x0, y0, x1, y1, col in ((12, 22, 14, 44, p["cable"]), (20, 24, 18, 40, p["metal_d"]),
                                (26, 25, 29, 36, p["cable"])):
        c.line(x0, y0, x1, y1, col)
    c.pixel(14, 45, p["amber"])
    # верстак: панель лежит на двух ножках, кромка к проходу рваная
    for z0 in (1.04, 1.36):
        _bay_box(c, -0.56, -0.5, 0.58, 1.0, z0, z0 + 0.04, p["metal_d"], p["seam"], p["metal_d"])
    _bay_box(c, -1.0, -0.4, 0.52, 0.58, 1.0, 1.46, p["panel_d"], p["panel_d"], p["panel"])
    for k in range(1, 6):
        x = -1.0 + k * 0.1
        c.line(*[int(t) for t in P(x, 0.52, 1.0) + P(x, 0.52, 1.46)], p["panel_d"])
    c.line(*[int(t) for t in P(-1.0, 0.52, 1.0) + P(-0.4, 0.52, 1.0)], p["panel_l"])
    jx, jy = P(-0.4, 0.52, 1.0)
    kx, ky = P(-0.4, 0.52, 1.46)
    n = 9
    for i in range(n + 1):
        t = i / float(n)
        x = int(jx + (kx - jx) * t)
        y = int(jy + (ky - jy) * t)
        dent = (0, 2, 1, 3, 0, 2, 1, 0, 2, 1)[i]
        c.fill_rect(x - dent, y - 1, x, y + 1, p["panel_l"] if dent == 0 else p["seam"])
    # на верстаке: лампа с тёплым отсветом, ключ и энергоячейка
    lx, ly = [int(t) for t in P(-0.82, 0.52, 1.28)]
    c.dither_disc(lx, ly - 6, 9, p["lamp_glow"], 1)
    c.vline(lx, ly - 7, ly, p["metal_d"])
    c.fill_rect(lx - 3, ly - 10, lx + 3, ly - 8, p["metal"])
    c.hline(lx - 3, lx + 3, ly - 7, p["lamp_l"])
    c.fill_rect(lx - 2, ly, lx + 2, ly + 1, p["metal_d"])
    wx, wy = [int(t) for t in P(-0.62, 0.52, 1.08)]
    c.line(wx - 6, wy + 2, wx + 4, wy - 2, p["metal"])
    c.fill_rect(wx + 3, wy - 4, wx + 5, wy - 2, p["metal"])
    ex, ey = [int(t) for t in P(-0.92, 0.52, 1.1)]
    c.fill_rect(ex, ey - 4, ex + 5, ey, p["metal_d"])
    c.hline(ex + 1, ex + 4, ey - 2, p["amber"])
    # ящики-склад справа: два больших и один сверху
    for x0, x1, v0, v1, z0, z1 in ((0.66, 1.0, 0.58, 1.0, 1.0, 1.42),
                                   (0.7, 1.0, 0.26, 0.58, 1.02, 1.32),
                                   (0.76, 0.98, 0.04, 0.26, 1.06, 1.24)):
        _bay_box(c, x0, x1, v0, v1, z0, z1, p["crate"], p["crate_d"], p["crate_l"])
        ax, ay = P(x0, v0, z0)
        bx, by = P(x1, v1, z0)
        c.rect(int(ax), int(ay), int(bx), int(by), p["crate_d"])
        c.hline(int(ax) + 1, int(bx) - 1, int((ay + by) / 2), p["crate_d"])
        c.fill_rect(int(ax) + 3, int(ay) + 3, int(ax) + 8, int(ay) + 6, p["crate_d"])
    c.noise_specks(rng, 30, 80, 130, 95, p["f2"], 30)
    c.noise_specks(rng, 50, 70, 110, 95, p["seam"], 12)


def _suit_limb(c, pts, dark, lit):
    """Конечность скафандра: тёмный жгут с узкой светлой кромкой сверху."""
    _tendril(c, pts, dark)
    _tendril(c, [(x, y - 1, max(0, r - 1)) for x, y, r in pts], lit)


def scene_death_o2(c, rng):
    """Смерть от удушья: тело в скафандре дрейфует в пустоте, визор затянут инеем,
    оборванный фал уходит за край кадра, пустой баллон уплывает прочь."""
    p = {
        "void": VOID,
        "neb_d": (14, 20, 34),
        "neb": (22, 32, 52),
        "wreck": (26, 31, 42),
        "wreck_l": (40, 48, 62),
        "frost": (206, 232, 244),
        "frost_d": (126, 162, 186),
        "tether": (150, 132, 106),
        "amber": AMBER,
        "red": RED,
    }
    c.fill(p["void"])
    # холодная туманность по диагонали кадра
    for y in range(96):
        x0 = int(y * 1.4) - 30
        c.dither_over(x0, y, x0 + 46, y, p["neb_d"], y % 2)
        c.dither_over(x0 + 12, y, x0 + 30, y, p["neb"], (y + 1) % 2)
    c.noise_specks(rng, 0, 0, 159, 95, STAR_DIM, 90)
    c.noise_specks(rng, 0, 0, 159, 95, STAR, 40)
    # далёкий обломок корабля с тусклым огнём
    c.fill_rect(118, 12, 150, 17, p["wreck"])
    c.fill_rect(126, 9, 140, 12, p["wreck"])
    c.hline(118, 150, 12, p["wreck_l"])
    for x in range(151, 157):
        c.pixel(x, 13 + (x % 3), p["wreck"])
    c.pixel(131, 14, p["amber"])
    # оборванный фал: от пояса к левому краю, конец распушён
    last = (80, 52)
    for i in range(1, 15):
        t = i / 14.0
        x = int(80 - 78 * t)
        y = int(52 + 26 * t - 18 * t * (1 - t) * 2)
        c.line(last[0], last[1], x, y, p["tether"])
        last = (x, y)
    c.line(2, 78, 0, 82, p["tether"])
    c.pixel(1, 76, p["tether"])
    # руки и ноги безвольно раскинуты: тело медленно кувыркается
    _suit_limb(c, ((70, 46, 3), (58, 38, 3), (50, 42, 2)), SUIT_D, SUIT)
    _suit_limb(c, ((88, 44, 3), (98, 34, 3), (104, 26, 2)), SUIT_D, SUIT)
    _suit_limb(c, ((84, 60, 4), (96, 70, 3), (106, 80, 3)), SUIT_D, SUIT)
    _suit_limb(c, ((78, 62, 4), (82, 74, 3), (80, 86, 3)), SUIT_D, SUIT)
    # перчатки и ботинки
    c.circle(49, 43, 2, STEEL_D)
    c.circle(105, 25, 2, STEEL_D)
    c.fill_rect(104, 79, 109, 83, STEEL_D)
    c.fill_rect(78, 85, 83, 89, STEEL_D)
    # корпус скафандра с ранцем
    c.ellipse(80, 52, 11, 12, SUIT_D)
    c.ellipse(79, 51, 10, 11, SUIT)
    c.ellipse(76, 47, 5, 5, SUIT_L)
    c.fill_rect(86, 44, 92, 60, STEEL_D)
    c.rect(86, 44, 92, 60, DARK)
    c.pixel(89, 48, p["red"])
    c.pixel(89, 52, RED_DIM)
    # шлем: визор затянут инеем, лица не видно
    c.circle(70, 36, 10, STEEL_D)
    c.circle(69, 35, 9, STEEL)
    c.ellipse(66, 31, 5, 4, STEEL_L)
    c.ellipse(69, 37, 7, 5, DARK)
    c.ellipse(69, 37, 6, 4, p["frost_d"])
    c.dither_over(63, 33, 75, 41, p["frost"], 0)
    c.line(64, 38, 70, 34, p["frost"])
    c.line(68, 40, 73, 36, WHITE)
    # кристаллы льда вокруг шлема
    for (x, y) in ((58, 26), (61, 22), (77, 24), (81, 28), (56, 34), (66, 22)):
        c.pixel(x, y, p["frost"])
    c.noise_specks(rng, 52, 18, 88, 50, p["frost_d"], 14)
    # пустой баллон уплывает, стрелка манометра на нуле
    c.fill_rect(118, 58, 124, 72, STEEL_D)
    c.fill_rect(119, 58, 123, 71, STEEL)
    c.hline(119, 123, 58, STEEL_L)
    c.fill_rect(120, 55, 122, 57, DARK)
    c.circle(121, 64, 2, DARK)
    c.pixel(120, 65, p["red"])
    c.pixel(121, 64, p["red"])
    for (x, y) in ((127, 61), (131, 59), (136, 57)):
        c.pixel(x, y, STAR_DIM)


def scene_death_hp(c, rng):
    """Смерть от ран: в коридоре под аварийной лампой у стены осел выживший,
    визор расколот, по палубе расползлось тёмное пятно, с кабеля сыплются искры."""
    p = {
        "d0": (38, 24, 30), "d1": (28, 18, 24), "d2": (20, 14, 19),
        "f0": (40, 28, 32), "f1": (30, 21, 25), "f2": (21, 15, 19),
        "w0": (48, 32, 38), "w1": (36, 24, 30), "w2": (26, 18, 23),
        "far": (14, 10, 14),
        "seam": (10, 7, 10),
        "glow": (96, 26, 34),
        "pipe": (62, 44, 50),
        "amber": AMBER,
        "red": RED,
        "red_l": RED_LIT,
    }
    draw_room(c, (62, 20, 100, 70),
              {"ceil": (p["d0"], p["d1"], p["d2"]),
               "floor": (p["f0"], p["f1"], p["f2"]),
               "left": (p["w0"], p["w1"], p["w2"]),
               "right": (p["w0"], p["w1"], p["w2"]),
               "far": p["far"]}, p["seam"])
    # трубы вдоль стен
    for t in (0, 1):
        y_near = 26 + t * 26
        y_far = 28 + t * 18
        c.line(0, y_near, 62, y_far, p["pipe"])
        c.line(159, y_near, 100, y_far, p["pipe"])
    # аварийная лампа под потолком и её красный отсвет
    c.dither_disc(81, 6, 14, p["glow"], 1)
    c.fill_rect(74, 4, 88, 8, p["red"])
    c.hline(75, 87, 5, p["red_l"])
    c.fill_rect(72, 2, 90, 3, p["pipe"])
    # оборванный кабель справа искрит
    c.line(128, 0, 132, 20, p["seam"])
    c.line(132, 20, 127, 30, p["seam"])
    c.pixel(127, 31, WHITE)
    for (x, y) in ((125, 33), (129, 34), (124, 37), (130, 38), (127, 41), (122, 40)):
        c.pixel(x, y, p["amber"])
    # тёмное пятно на палубе под телом
    c.ellipse(64, 86, 30, 6, RED_DARK)
    c.ellipse(60, 86, 18, 4, RED_DIM)
    c.dither_over(34, 80, 96, 92, RED_DARK, 1)
    # ноги вытянуты по палубе
    _suit_limb(c, ((44, 78, 4), (62, 82, 4), (80, 84, 3)), SUIT_D, SUIT)
    _suit_limb(c, ((40, 82, 4), (56, 88, 4), (72, 91, 3)), SUIT_D, SUIT)
    c.fill_rect(79, 80, 85, 86, STEEL_D)
    c.fill_rect(71, 88, 77, 93, STEEL_D)
    # корпус привален к левой стене
    c.ellipse(34, 68, 11, 14, SUIT_D)
    c.ellipse(33, 67, 10, 13, SUIT)
    c.ellipse(30, 62, 5, 6, SUIT_L)
    c.specks_on(rng, 24, 56, 44, 80, SUIT, SUIT_D, 26)
    # рука безвольно лежит на полу, другая прижата к боку
    _suit_limb(c, ((42, 70, 3), (50, 76, 3), (56, 80, 2)), SUIT_D, SUIT)
    c.circle(57, 81, 2, STEEL_D)
    _suit_limb(c, ((26, 70, 3), (28, 78, 3)), SUIT_D, SUIT)
    # шлем склонён на грудь, визор расколот
    c.circle(36, 50, 9, STEEL_D)
    c.circle(35, 49, 8, STEEL)
    c.ellipse(32, 45, 4, 3, STEEL_L)
    c.ellipse(38, 52, 6, 4, DARK)
    c.ellipse(38, 52, 5, 3, GLASS_D)
    c.line(35, 50, 41, 54, WHITE)
    c.line(38, 52, 39, 49, GREY)
    # потёки на стене и красный отсвет лампы по кромке шлема
    c.vline(22, 58, 76, RED_DIM)
    c.vline(23, 64, 80, RED_DARK)
    for (x, y) in ((31, 42), (33, 41), (35, 41), (37, 41), (39, 42)):
        c.pixel(x, y, p["red"])
    c.noise_specks(rng, 0, 84, 159, 95, p["f2"], 30)


SCENES = (
    ("cryo_pod", scene_cryo_pod),
    ("bridge", scene_bridge),
    ("cargo_drone", scene_cargo_drone),
    ("shuttle_bay", scene_shuttle_bay),
    ("reactor_core", scene_reactor_core),
    ("service_corridor", scene_service_corridor),
    ("dock_bay", scene_dock_bay),
    ("comms_sentry", scene_comms_sentry),
    ("antenna_mast", scene_antenna_mast),
    ("cryo_bay", scene_cryo_bay),
    # экран смерти: своя картинка на каждую причину (GameState.last_death_cause)
    ("death_o2", scene_death_o2),
    ("death_hp", scene_death_hp),
    # те же отсеки после уничтожения стража (в конце, чтобы не сдвигать seed остальных)
    ("cargo_drone_down", scene_cargo_drone_down),
    ("comms_sentry_down", scene_comms_sentry_down),
)


# ----------------------------------------------------------------------------
# Заглавный кадр 240x150 — крупная иллюстрация главного меню.
# Нижние ~30 строк специально притушены: поверх них ложится название игры.
# ----------------------------------------------------------------------------

# Рваная кромка носовой половины: смещения (верх, низ) от осевой линии.
HULL_TEAR = ((-9, 9), (-9, 6), (-7, 9), (-9, 3), (-5, 8),
             (-8, 5), (-3, 7), (-6, 2), (-2, 5), (-4, 1), (-1, 3))
# Рваная кромка оторванной кормы (слева направо она «раскрывается»).
STERN_TEAR = ((-2, 2), (-5, 3), (-3, 7), (-7, 4),
              (-4, 9), (-9, 6), (-6, 10), (-10, 8))


def _title_spans(profile, x0, x1):
    """Силуэт по столбцам: {x: (верх, низ)} из функции профиля."""
    spans = {}
    for x in range(x0, x1 + 1):
        top, bot = profile(x)
        if bot >= top:
            spans[x] = (top, bot)
    return spans


def _title_body(c, spans, p):
    """Корпус: сначала тёмный контур по 8 соседям, затем четыре тона стали."""
    inside = set()
    for x, (top, bot) in spans.items():
        for y in range(top, bot + 1):
            inside.add((x, y))
    order = sorted(inside)
    for x, y in order:
        for oy in (-1, 0, 1):
            for ox in (-1, 0, 1):
                if (x + ox, y + oy) not in inside:
                    c.pixel(x + ox, y + oy, p["edge"])
    for x, y in order:
        top, bot = spans[x]
        t = (y - top) / float(max(1, bot - top))
        even = (x + y) % 2 == 0
        if t < 0.12:
            col = p["steel_l"]
        elif t < 0.24:
            col = p["steel_l"] if even else p["steel"]
        elif t < 0.52:
            col = p["steel"]
        elif t < 0.63:
            col = p["steel"] if even else p["steel_m"]
        elif t < 0.84:
            col = p["steel_m"]
        else:
            col = p["steel_d"]
        c.pixel(x, y, col)


def _title_chunk(c, x, y, w, h, p, top_col=None):
    """Обломок: тёмный контур, тело и подсвеченная верхняя грань."""
    c.fill_rect(x - 1, y - 1, x + w, y + h, p["edge"])
    c.fill_rect(x, y, x + w - 1, y + h - 1, p["steel_m"])
    c.hline(x, x + w - 1, y, top_col or p["steel"])


def _title_shade_bottom(c, y0, y1, levels):
    """Ступенчатое затемнение низа кадра с дизерингом на стыках ступеней."""
    last = len(levels) - 1
    span = float(max(1, y1 - y0))
    for y in range(y0, y1 + 1):
        t = (y - y0) / span * last
        i = min(last, int(t))
        f = t - i
        for x in range(c.w):
            step = i
            if f >= 0.75:
                step = min(last, i + 1)
            elif f >= 0.25 and (x + y) % 2 == 0:
                step = min(last, i + 1)
            k = levels[step]
            r, g, b, a = c.get(x, y)
            c.pixel(x, y, (int(r * k), int(g * k), int(b * k), a))


def scene_title_screen(c, rng):
    """Заглавный кадр: обломок грузовика «Персефона» над холодной планетой."""
    p = {
        "sky0": (18, 22, 34), "sky1": (14, 18, 28), "sky2": (11, 14, 22),
        "sky3": (9, 11, 17), "sky4": VOID,
        "neb": (44, 66, 92), "neb_d": (26, 40, 58),
        "star": STAR, "star_m": (168, 178, 200), "star_d": STAR_DIM,
        "pl_l": (168, 192, 214), "pl": (104, 132, 162),
        "pl_d": (54, 72, 100), "pl_n": (18, 24, 36),
        "atmo": (150, 206, 228), "atmo_d": (64, 108, 138),
        "steel_l": (176, 186, 202), "steel": (122, 132, 152),
        "steel_m": (78, 88, 108), "steel_d": (46, 54, 70),
        "edge": (16, 19, 27),
        "win": (22, 28, 40), "win_lit": (240, 206, 132),
        "amber": AMBER, "amber_d": (146, 106, 44), "cyan": CYAN,
        "vent": (206, 232, 240), "vent_d": (96, 148, 172),
        "ice": (186, 218, 232),
        "red": RED,
    }

    # --- небо: пять полос от светлого верха к глухому низу ------------------
    sky = (p["sky0"], p["sky1"], p["sky2"], p["sky3"], p["sky4"])
    for i, col in enumerate(sky):
        c.fill_rect(0, i * 30, c.w - 1, i * 30 + 29, col)
    for i in range(1, len(sky)):
        c.dither_rect(0, i * 30 - 3, c.w - 1, i * 30 + 2, sky[i - 1], sky[i])

    # --- туманности: голубоватые пятна с дизерингом и размытым краем --------
    for ncx, ncy, nrx, nry, phase in ((46, 24, 40, 19, 0), (200, 20, 34, 16, 1),
                                      (122, 58, 46, 27, 0), (16, 76, 22, 15, 1)):
        for y in range(ncy - nry - 6, ncy + nry + 7):
            for x in range(ncx - nrx - 8, ncx + nrx + 9):
                dx = (x - ncx) / float(nrx)
                dy = (y - ncy) / float(nry)
                d = dx * dx + dy * dy
                if d > 1.6 or (x + y + phase) % 2:
                    continue
                if d < 0.35:
                    c.pixel(x, y, p["neb"])
                elif d < 0.7:
                    c.pixel(x, y, p["neb"] if (x + 2 * y) % 4 == 0 else p["neb_d"])
                elif d < 1.1:
                    if (x + 2 * y) % 4 == 0:
                        c.pixel(x, y, p["neb_d"])
                elif (x * 3 + y) % 8 == 0:
                    c.pixel(x, y, p["neb_d"])

    # --- звёзды трёх яркостей -----------------------------------------------
    c.noise_specks(rng, 0, 0, c.w - 1, c.h - 1, p["star_d"], 300)
    c.noise_specks(rng, 0, 0, c.w - 1, 138, p["star_m"], 130)
    c.noise_specks(rng, 0, 0, c.w - 1, 118, p["star"], 52)
    for sx, sy in ((22, 16), (188, 30), (94, 10), (58, 100), (218, 62), (146, 18)):
        c.pixel(sx, sy, p["star"])
        c.pixel(sx - 1, sy, p["star_d"])
        c.pixel(sx + 1, sy, p["star_d"])
        c.pixel(sx, sy - 1, p["star_d"])
        c.pixel(sx, sy + 1, p["star_d"])

    # --- холодная планета в правом нижнем углу ------------------------------
    pcx, pcy, pr = 252, 176, 96
    lx, ly, lz = 0.62, -0.50, 0.60
    x_from = max(0, pcx - pr - 3)
    y_from = max(0, pcy - pr - 3)
    for y in range(y_from, c.h):
        for x in range(x_from, c.w):
            nx = (x - pcx) / float(pr)
            ny = (y - pcy) / float(pr)
            d = nx * nx + ny * ny
            if d > 1.0:
                # тонкая атмосферная кайма: ярче со стороны светила
                dist = (d ** 0.5) * pr
                if dist > pr + 2.5:
                    continue
                f = (nx * lx + ny * ly) / (d ** 0.5)
                if f > 0.05:
                    c.pixel(x, y, p["atmo"])
                elif f > -0.30:
                    c.pixel(x, y, p["atmo"] if (x + y) % 2 == 0 else p["atmo_d"])
                elif (x + y) % 2 == 0:
                    c.pixel(x, y, p["atmo_d"])
                continue
            lam = nx * lx + ny * ly + ((1.0 - d) ** 0.5) * lz
            even = (x + y) % 2 == 0
            if lam > 0.78:
                col = p["pl_l"]
            elif lam > 0.62:
                col = p["pl_l"] if even else p["pl"]
            elif lam > 0.34:
                col = p["pl"]
            elif lam > 0.22:
                col = p["pl"] if even else p["pl_d"]
            elif lam > 0.06:
                col = p["pl_d"]
            elif lam > -0.04:
                col = p["pl_d"] if even else p["pl_n"]
            else:
                col = p["pl_n"]
            c.pixel(x, y, col)
    # ледяные поля и полосы облаков на освещённой стороне
    for icx, icy, irx, iry, phase in ((228, 96, 16, 7, 0), (206, 122, 20, 6, 1),
                                      (236, 132, 12, 5, 0)):
        for y in range(icy - iry, icy + iry + 1):
            for x in range(icx - irx, icx + irx + 1):
                dx = (x - icx) / float(irx)
                dy = (y - icy) / float(iry)
                if dx * dx + dy * dy <= 1.0 and (x + y + phase) % 2 == 0:
                    if c.get(x, y) in (rgba(p["pl"]), rgba(p["pl_l"])):
                        c.pixel(x, y, p["ice"])
    c.specks_on(rng, 160, 84, c.w - 1, c.h - 1, p["pl"], p["pl_d"], 120)

    # --- носовая половина «Персефоны»: модульный корпус с рёбрами -----------
    def hull(x):
        """Ось наклонена, силуэт набран из модулей разной высоты."""
        yc = 76.0 - (x - 28) * 0.115
        if x <= 38:                                 # клин носа
            t = (x - 28) / 10.0
            top, bot = -2.0 - t * 6.0, 2.0 + t * 4.0
        elif x <= 52:                               # носовой модуль и рубка
            top, bot = -8.0, 6.0
            if 41 <= x <= 50:
                top = -14.0
        elif x <= 57:                               # переходный тоннель
            top, bot = -6.0, 5.0
        elif x <= 94:                               # грузовой барабан
            top, bot = -13.0, 12.0
            if (x - 60) % 9 in (0, 1):              # наружные шпангоуты
                top, bot = -15.0, 12.0
        elif x <= 99:
            top, bot = -6.0, 5.0
        elif x <= 126:                              # машинный модуль с баком
            top, bot = -11.0, 10.0
            if 104 <= x <= 118:
                bot = 16.0
        elif x <= 133:
            top, bot = -7.0, 6.0
        else:
            top, bot = HULL_TEAR[x - 134]
        return int(round(yc + top)), int(round(yc + bot))

    bow = _title_spans(hull, 28, 144)
    _title_body(c, bow, p)
    # продольные швы обшивки: подчёркивают длину корпуса
    for x, (top, bot) in sorted(bow.items()):
        if bot - top < 9:
            continue
        c.pixel(x, top + 3, p["steel_l"])
        c.pixel(x, bot - 3, p["steel_d"])
    # шпангоуты барабана
    for x in range(60, 95, 9):
        if x not in bow:
            continue
        top, bot = bow[x]
        c.vline(x, top + 1, top + 7, p["steel_l"])
        c.vline(x + 1, top + 1, top + 7, p["steel_m"])
    # рваная кромка разлома ловит свет — чтобы перелом читался
    for x in range(134, 145):
        top, bot = bow[x]
        c.pixel(x, top, p["steel_l"])
        c.pixel(x, bot, p["steel"])
    # окна рубки: два из них горят
    for x in range(42, 50):
        c.pixel(x, bow[x][0] + 4, p["win_lit"] if x in (44, 45) else p["win"])
    # ряд иллюминаторов грузового барабана
    for x in range(63, 93, 5):
        top, bot = bow[x]
        c.hline(x, x + 1, (top + bot) // 2 - 2, p["win_lit"] if x == 78 else p["win"])
    # машинный модуль: холодный свет реакторного окна
    top, bot = bow[110]
    c.hline(108, 112, top + 4, p["cyan"])
    # мачта связи над рубкой и носовой габаритный огонь
    mtop = bow[48][0]
    c.vline(48, mtop - 12, mtop, p["edge"])
    c.vline(47, mtop - 11, mtop, p["steel_l"])
    c.hline(45, 50, mtop - 9, p["steel_m"])
    c.pixel(47, mtop - 13, p["red"])
    c.pixel(29, (bow[29][0] + bow[29][1]) // 2, p["red"])

    # --- оторванная кормовая секция с дюзами --------------------------------
    def stern(x):
        yc = 46.0 + (x - 158) * 0.20
        if x <= 165:
            top, bot = STERN_TEAR[x - 158]
        elif x <= 190:
            top, bot = -11.0, 10.0
            if (x - 168) % 10 in (0, 1):
                top, bot = -13.0, 12.0
        elif x <= 196:
            top, bot = -13.0, 12.0
        else:
            top, bot = -14.0, 13.0
        return int(round(yc + top)), int(round(yc + bot))

    aft = _title_spans(stern, 158, 206)
    _title_body(c, aft, p)
    for x, (top, bot) in sorted(aft.items()):
        if bot - top < 9:
            continue
        c.pixel(x, top + 3, p["steel_l"])
        c.pixel(x, bot - 3, p["steel_d"])
    for x in range(168, 191, 10):
        top, bot = aft[x]
        c.vline(x, top + 1, top + 7, p["steel_l"])
        c.vline(x + 1, top + 1, top + 7, p["steel_m"])
    for x in range(158, 166):
        top, bot = aft[x]
        c.pixel(x, top, p["steel_l"])
        c.pixel(x, bot, p["steel"])
    # три остывшие дюзы в кормовом срезе
    top, bot = aft[206]
    for k in range(3):
        ey = top + 5 + k * 9
        c.fill_rect(200, ey, 206, ey + 5, p["edge"])
        c.fill_rect(201, ey + 1, 206, ey + 4, p["steel_d"])
        c.vline(201, ey + 1, ey + 4, p["steel_m"])
    c.hline(176, 180, aft[176][0] + 5, p["win"])
    c.hline(186, 188, aft[186][0] + 6, p["win_lit"])

    # --- шлейф обломков и замёрзшего топлива между половинами ---------------
    for dx, dy, dw, dh in ((148, 44, 4, 3), (152, 74, 3, 2), (140, 92, 3, 2),
                           (164, 86, 4, 2), (133, 30, 3, 2), (156, 26, 2, 2),
                           (170, 98, 2, 2), (124, 102, 3, 2), (174, 34, 3, 2),
                           (116, 26, 2, 2), (151, 58, 2, 2)):
        _title_chunk(c, dx, dy, dw, dh, p)
    # разреженная дымка замёрзшего топлива — не сплошное пятно
    for fx, fy, fr, mod in ((153, 74, 8, 5), (168, 84, 6, 5)):
        for y in range(fy - fr, fy + fr + 1):
            for x in range(fx - fr, fx + fr + 1):
                if (x - fx) ** 2 + (y - fy) ** 2 > fr * fr:
                    continue
                if (x * 2 + y) % mod:
                    continue
                c.pixel(x, y, p["vent_d"])
    c.noise_specks(rng, 146, 34, 176, 96, p["ice"], 26)
    c.noise_specks(rng, 144, 30, 180, 100, p["steel_m"], 16)

    # --- аварийный маяк с ореолом -------------------------------------------
    bx = 72
    by = bow[bx][0] - 3
    for y in range(by - 8, by + 5):
        for x in range(bx - 8, bx + 9):
            d = (x - bx) ** 2 + (y - by) ** 2
            if d <= 4:
                c.pixel(x, y, p["amber"])
            elif d <= 16 and (x + y) % 2 == 0:
                c.pixel(x, y, p["amber"])
            elif d <= 44 and (x * 2 + y) % 5 == 0:
                c.pixel(x, y, p["amber_d"])
    c.pixel(bx, by, (255, 236, 196))
    c.vline(bx, by + 3, by + 5, p["steel_d"])

    # --- тонкая струя утечки газа из разлома --------------------------------
    for i in range(46):
        t = i / 45.0
        jx = 128 + int(round(t * 30))
        jy = 54 - int(round(t * 38))
        w = t * 3.4
        for o in range(-4, 5):
            if abs(o) > w + 0.5:
                continue
            if rng.random() > 0.72 - t * 0.34:
                continue
            c.pixel(jx + o, jy, p["vent"] if t < 0.35 else p["vent_d"])

    # --- спасательная капсула уходит от обломка -----------------------------
    for i in range(24):
        t = i / 23.0
        tx = 146 - int(round(t * 22))
        ty = 98 - int(round(t * 15))
        if (tx + ty) % 2 == 0:
            c.pixel(tx, ty, p["vent"] if t < 0.35 else p["vent_d"])
    c.fill_rect(147, 99, 158, 105, p["edge"])
    c.fill_rect(148, 100, 157, 104, p["steel_m"])
    c.hline(148, 157, 100, p["steel_l"])
    c.pixel(148, 100, p["edge"])
    c.pixel(148, 104, p["edge"])
    c.hline(149, 151, 102, p["cyan"])
    c.pixel(157, 103, p["amber"])

    # --- нижняя полоса под название игры: ступенчатое затемнение ------------
    _title_shade_bottom(c, 112, c.h - 1, (1.0, 0.84, 0.68, 0.52, 0.40, 0.30))


# ----------------------------------------------------------------------------
# Иконки предметов 16x16 (силуэт держим в пределах 2..13, чтобы контур
# не выходил на края и рамка холста осталась прозрачной)
# ----------------------------------------------------------------------------

OUTLINE = (14, 17, 24)

STEEL_L = (176, 186, 202)
STEEL = (124, 134, 152)
STEEL_D = (74, 82, 98)
GOLD_L = (240, 206, 132)
GOLD = AMBER
GOLD_D = (150, 110, 44)
CLOTH_L = (196, 178, 150)
CLOTH = (150, 132, 106)
CLOTH_D = (98, 84, 66)
GREEN_L = (150, 226, 160)
GREEN = (86, 176, 104)
GREEN_D = (44, 104, 62)
CYAN_L = (206, 238, 246)
CYAN_D = (72, 132, 154)
RUST = (142, 84, 52)
RUST_D = (92, 52, 32)
WHITE = (228, 234, 244)
GREY = (168, 174, 186)
DARK = (40, 46, 58)


def icon_pipe_scrap(c):
    """Обрезок трубы с раструбом и рваным срезом."""
    c.fill_rect(4, 6, 12, 10, STEEL)
    c.hline(4, 12, 6, STEEL_L)
    c.hline(4, 12, 10, STEEL_D)
    c.ellipse(4, 8, 2, 3, STEEL_D)
    c.fill_rect(3, 7, 4, 9, DARK)
    c.pixel(6, 8, STEEL_L)
    c.pixel(9, 7, STEEL_L)
    c.pixel(12, 6, STEEL_D)
    c.fill_rect(12, 7, 13, 9, STEEL)
    c.pixel(13, 7, STEEL_L)
    c.pixel(13, 10, STEEL_D)
    c.pixel(8, 10, STEEL_D)


def icon_medkit(c):
    """Аптечка: белый кейс с красным крестом."""
    c.fill_rect(6, 2, 9, 3, STEEL_D)
    c.fill_rect(3, 4, 12, 12, WHITE)
    c.fill_rect(3, 10, 12, 12, GREY)
    c.hline(3, 12, 7, GREY)
    c.fill_rect(7, 5, 8, 10, RED)
    c.fill_rect(5, 7, 10, 8, RED)


def icon_o2_canister(c):
    """Кислородный баллон с вентилем."""
    c.fill_rect(6, 2, 9, 3, STEEL)
    c.pixel(5, 2, STEEL_D)
    c.pixel(10, 2, STEEL_D)
    c.fill_rect(5, 4, 10, 13, CYAN_D)
    c.fill_rect(6, 4, 8, 13, CYAN)
    c.vline(6, 5, 12, CYAN_L)
    c.fill_rect(5, 7, 10, 9, WHITE)
    c.pixel(7, 8, CYAN_D)
    c.pixel(8, 8, CYAN_D)
    c.hline(5, 10, 12, CYAN_D)


def icon_pilot_keycard(c):
    """Карта-ключ пилота: янтарная, с чипом."""
    c.fill_rect(3, 4, 12, 11, GOLD)
    c.hline(4, 11, 4, GOLD_L)
    c.fill_rect(3, 10, 12, 11, GOLD_D)
    c.fill_rect(4, 6, 6, 8, GOLD_D)
    c.pixel(5, 7, GOLD_L)
    c.hline(8, 11, 6, GOLD_D)
    c.hline(8, 10, 8, GOLD_D)
    c.pixel(11, 9, WHITE)


def icon_station_keycard(c):
    """Карта-ключ станции: бирюзовая, чип справа."""
    c.fill_rect(3, 4, 12, 11, CYAN_D)
    c.hline(4, 11, 4, CYAN_L)
    c.fill_rect(3, 10, 12, 11, (40, 84, 104))
    c.fill_rect(9, 6, 11, 8, CYAN_L)
    c.pixel(10, 7, CYAN_D)
    c.hline(4, 7, 6, CYAN)
    c.hline(4, 8, 8, CYAN)
    c.pixel(4, 9, WHITE)


def icon_service_pistol(c):
    """Служебный пистолет."""
    c.fill_rect(3, 5, 12, 8, STEEL)
    c.hline(3, 12, 5, STEEL_L)
    c.fill_rect(11, 6, 13, 7, STEEL_D)
    c.hline(3, 12, 8, STEEL_D)
    c.fill_rect(4, 9, 8, 13, RUST)
    c.fill_rect(4, 9, 5, 13, RUST_D)
    c.pixel(6, 10, RUST_D)
    c.pixel(9, 9, STEEL_D)
    c.pixel(3, 6, STEEL_L)


def icon_ration_bar(c):
    """Паёк: батончик в обёртке."""
    c.fill_rect(3, 5, 12, 10, CLOTH)
    c.hline(4, 11, 5, CLOTH_L)
    c.hline(3, 12, 10, CLOTH_D)
    c.fill_rect(5, 6, 10, 9, RUST)
    c.hline(5, 10, 6, RUST_D)
    c.vline(2, 6, 9, CLOTH_D)
    c.pixel(2, 7, CLOTH_L)
    c.vline(13, 6, 9, CLOTH_D)
    c.pixel(13, 8, CLOTH_L)
    c.pixel(7, 8, GOLD)


def icon_duct_tape(c):
    """Моток технического скотча."""
    c.circle(8, 8, 5, STEEL_D)
    c.circle(8, 8, 4, GREY)
    c.ring(8, 8, 2, 3, STEEL_D)
    c.circle(8, 8, 1, DARK)
    c.pixel(6, 5, STEEL_L)
    c.pixel(5, 6, STEEL_L)
    c.fill_rect(11, 10, 13, 12, GREY)
    c.pixel(13, 12, STEEL_D)


def icon_cloth_rags(c):
    """Тряпьё: лоскут с оборванным краем."""
    c.fill_rect(3, 4, 12, 10, CLOTH)
    c.fill_rect(4, 3, 8, 4, CLOTH_L)
    c.hline(3, 12, 4, CLOTH_L)
    c.hline(4, 11, 9, CLOTH_D)
    for x, y in ((3, 11), (5, 12), (7, 11), (9, 12), (11, 11), (4, 12), (10, 11)):
        c.pixel(x, y, CLOTH)
    c.pixel(5, 13, CLOTH_D)
    c.pixel(9, 13, CLOTH_D)
    c.line(5, 6, 10, 8, CLOTH_D)
    c.pixel(11, 5, CLOTH_L)


def icon_scrap_metal(c):
    """Обломки металла: две изогнутые пластины."""
    for i in range(8):
        c.hline(3 + i // 2, 11 - i // 3, 3 + i, STEEL if i % 2 else STEEL_L)
    c.fill_rect(3, 5, 9, 9, STEEL)
    c.hline(3, 8, 5, STEEL_L)
    c.line(3, 9, 9, 4, STEEL_D)
    c.fill_rect(7, 9, 13, 12, STEEL_D)
    c.hline(7, 12, 9, STEEL)
    c.pixel(12, 10, STEEL_L)
    c.pixel(5, 7, STEEL_D)
    c.pixel(10, 11, DARK)


def icon_power_cell(c):
    """Энергоячейка с индикаторной шкалой."""
    c.fill_rect(6, 2, 9, 3, STEEL)
    c.fill_rect(4, 3, 11, 13, DARK)
    c.fill_rect(4, 3, 5, 13, STEEL_D)
    c.fill_rect(5, 5, 10, 11, (22, 54, 36))
    c.fill_rect(6, 6, 9, 6, GREEN_L)
    c.fill_rect(6, 8, 9, 8, GREEN)
    c.fill_rect(6, 10, 9, 10, GREEN_D)
    c.hline(5, 10, 12, STEEL_D)
    c.pixel(4, 4, STEEL)


def icon_ship_map(c):
    """Схема корабля: лист с маршрутом."""
    c.fill_rect(2, 3, 13, 12, CLOTH_L)
    c.hline(2, 13, 3, WHITE)
    c.hline(2, 13, 12, CLOTH_D)
    c.vline(8, 3, 12, CLOTH)
    c.line(4, 10, 6, 6, CYAN_D)
    c.line(6, 6, 11, 6, CYAN_D)
    c.line(11, 6, 11, 9, CYAN_D)
    c.pixel(4, 10, RED)
    c.pixel(11, 9, RED)
    c.pixel(6, 6, CYAN)
    c.pixel(5, 4, CLOTH)
    c.pixel(12, 10, CLOTH)


def icon_broken_datapad(c):
    """Разбитый датапад."""
    c.fill_rect(3, 2, 12, 13, STEEL_D)
    c.fill_rect(4, 3, 11, 11, (16, 34, 42))
    c.hline(4, 11, 3, CYAN_D)
    c.line(5, 4, 8, 7, CYAN_L)
    c.line(8, 7, 6, 10, CYAN_L)
    c.line(8, 7, 11, 5, CYAN_L)
    c.line(8, 8, 10, 11, GREY)
    c.pixel(6, 6, CYAN)
    c.fill_rect(6, 12, 9, 13, DARK)
    c.pixel(11, 12, RED)


def icon_flight_suit(c):
    """Комбинезон пассажира гибернации."""
    c.fill_rect(5, 3, 10, 9, CLOTH_D)
    c.fill_rect(6, 4, 9, 8, (78, 96, 120))
    c.fill_rect(3, 4, 4, 9, CLOTH_D)
    c.fill_rect(11, 4, 12, 9, CLOTH_D)
    c.fill_rect(5, 10, 7, 13, CLOTH_D)
    c.fill_rect(8, 10, 10, 13, CLOTH_D)
    c.hline(6, 9, 3, CYAN_D)
    c.pixel(7, 3, CYAN_L)
    c.vline(7, 5, 8, (54, 68, 88))
    c.pixel(10, 6, GOLD)


def icon_plate_vest(c):
    """Бронежилет с пластинами."""
    c.fill_rect(4, 3, 11, 12, STEEL_D)
    c.fill_rect(3, 4, 4, 8, STEEL_D)
    c.fill_rect(11, 4, 12, 8, STEEL_D)
    c.fill_rect(5, 5, 10, 11, STEEL)
    c.hline(5, 10, 5, STEEL_L)
    c.hline(5, 10, 8, STEEL_D)
    c.vline(7, 5, 11, STEEL_D)
    c.pixel(6, 3, GOLD)
    c.pixel(9, 3, GOLD)
    c.pixel(6, 10, STEEL_L)


def icon_cracked_helmet(c):
    """Треснувший шлем."""
    c.ellipse(8, 7, 5, 5, STEEL)
    c.fill_rect(3, 7, 13, 11, STEEL)
    c.ellipse(8, 6, 4, 4, STEEL_L)
    c.ellipse(8, 8, 3, 3, (18, 40, 52))
    c.fill_rect(5, 8, 11, 10, (18, 40, 52))
    c.line(6, 7, 8, 10, CYAN_L)
    c.line(8, 10, 10, 8, CYAN_L)
    c.fill_rect(4, 12, 12, 13, STEEL_D)
    c.pixel(5, 5, WHITE)
    c.pixel(12, 9, STEEL_D)


def icon_mag_boots(c):
    """Магнитные ботинки."""
    c.fill_rect(3, 4, 6, 10, CLOTH_D)
    c.fill_rect(2, 10, 7, 12, STEEL_D)
    c.hline(2, 7, 12, CYAN_D)
    c.fill_rect(9, 4, 12, 10, CLOTH_D)
    c.fill_rect(8, 10, 13, 12, STEEL_D)
    c.hline(8, 13, 12, CYAN_D)
    c.hline(3, 6, 5, CLOTH)
    c.hline(9, 12, 5, CLOTH)
    c.pixel(4, 8, STEEL)
    c.pixel(11, 8, STEEL)


def icon_makeshift_backpack(c):
    """Самодельный рюкзак."""
    c.fill_rect(4, 4, 11, 13, RUST_D)
    c.fill_rect(5, 6, 10, 12, RUST)
    c.fill_rect(4, 3, 11, 6, CLOTH_D)
    c.hline(5, 10, 3, CLOTH)
    c.vline(3, 5, 11, CLOTH_D)
    c.vline(12, 5, 11, CLOTH_D)
    c.fill_rect(7, 6, 8, 7, STEEL)
    c.fill_rect(6, 9, 9, 11, CLOTH_D)
    c.pixel(9, 10, GOLD)
    c.pixel(6, 12, RUST_D)


def icon_stim_shot(c):
    """Стимулятор: инъектор с зелёным раствором."""
    c.fill_rect(5, 2, 10, 3, STEEL_L)
    c.fill_rect(7, 3, 8, 4, STEEL)
    c.fill_rect(6, 4, 9, 11, GREY)
    c.fill_rect(6, 6, 9, 11, GREEN)
    c.vline(6, 7, 10, GREEN_L)
    c.hline(6, 9, 11, GREEN_D)
    c.fill_rect(7, 11, 8, 12, STEEL_D)
    c.vline(7, 12, 13, STEEL_L)
    c.pixel(9, 5, WHITE)


def icon_improvised_bandage(c):
    """Самодельная повязка: моток бинта."""
    c.ellipse(8, 8, 5, 5, CLOTH_L)
    c.ellipse(8, 8, 5, 5, CLOTH, filled=False)
    c.line(4, 6, 12, 6, CLOTH)
    c.line(4, 9, 12, 9, CLOTH)
    c.line(5, 11, 11, 11, CLOTH_D)
    c.fill_rect(10, 10, 13, 13, CLOTH_L)
    c.hline(10, 13, 13, CLOTH_D)
    c.pixel(6, 5, WHITE)
    c.pixel(9, 8, RED)
    c.pixel(10, 8, RED)


def icon_hex_key(c):
    """Шестигранный ключ."""
    c.fill_rect(6, 2, 8, 11, STEEL)
    c.vline(6, 2, 11, STEEL_L)
    c.vline(8, 3, 11, STEEL_D)
    c.fill_rect(6, 11, 13, 13, STEEL)
    c.hline(6, 13, 11, STEEL_L)
    c.hline(7, 13, 13, STEEL_D)
    c.pixel(7, 2, STEEL_L)
    c.pixel(13, 12, DARK)
    c.pixel(7, 7, STEEL_L)


def icon_cargo_key(c):
    """Грузовой ключ с бородкой."""
    c.circle(5, 6, 3, GOLD)
    c.circle(5, 6, 3, GOLD_D, filled=False)
    c.circle(5, 6, 1, DARK)
    c.fill_rect(6, 8, 8, 12, GOLD)
    c.vline(6, 8, 12, GOLD_L)
    c.fill_rect(9, 10, 11, 11, GOLD)
    c.fill_rect(9, 12, 12, 13, GOLD_D)
    c.pixel(4, 4, GOLD_L)
    c.pixel(8, 12, GOLD_D)


ITEMS = (
    ("pipe_scrap", icon_pipe_scrap),
    ("medkit", icon_medkit),
    ("o2_canister", icon_o2_canister),
    ("pilot_keycard", icon_pilot_keycard),
    ("station_keycard", icon_station_keycard),
    ("service_pistol", icon_service_pistol),
    ("ration_bar", icon_ration_bar),
    ("duct_tape", icon_duct_tape),
    ("cloth_rags", icon_cloth_rags),
    ("scrap_metal", icon_scrap_metal),
    ("power_cell", icon_power_cell),
    ("ship_map", icon_ship_map),
    ("broken_datapad", icon_broken_datapad),
    ("flight_suit", icon_flight_suit),
    ("plate_vest", icon_plate_vest),
    ("cracked_helmet", icon_cracked_helmet),
    ("mag_boots", icon_mag_boots),
    ("makeshift_backpack", icon_makeshift_backpack),
    ("stim_shot", icon_stim_shot),
    ("improvised_bandage", icon_improvised_bandage),
    ("hex_key", icon_hex_key),
    ("cargo_key", icon_cargo_key),
)


# ----------------------------------------------------------------------------
# Портреты боя 64x64 (силуэт держим в пределах 4..59, чтобы тёмный контур
# лёг внутри холста и рамка осталась прозрачной)
# ----------------------------------------------------------------------------

SUIT_L = (158, 146, 122)
SUIT = (116, 106, 88)
SUIT_D = (72, 66, 56)
GLASS_LIT = (196, 236, 246)
GLASS = (28, 58, 72)
GLASS_D = (16, 34, 44)
GLASS_M = (104, 162, 182)
FACE_L = (152, 138, 122)
FACE = (120, 108, 96)
FACE_D = (68, 60, 58)
RED_DIM = (104, 28, 36)
RED_DARK = (58, 16, 24)
FLESH_L = (232, 220, 210)
FLESH = (198, 176, 172)
FLESH_M = (162, 132, 134)
FLESH_D = (118, 90, 98)
FLESH_LIT = (206, 104, 104)
VEIN = (58, 32, 46)
VEIN_D = (34, 18, 28)


def _blob(c, pts, col):
    """Цепочка кругов по опорным точкам (x, y, r) — для органических форм."""
    for x, y, r in pts:
        c.circle(x, y, r, col)


def _tendril(c, pts, col):
    """Жгут: круги с плавно убывающим радиусом вдоль ломаной (x, y, r)."""
    for i in range(len(pts) - 1):
        x0, y0, r0 = pts[i]
        x1, y1, r1 = pts[i + 1]
        steps = max(abs(x1 - x0), abs(y1 - y0), 1)
        for s in range(steps + 1):
            t = s / float(steps)
            c.circle(int(round(x0 + (x1 - x0) * t)),
                     int(round(y0 + (y1 - y0) * t)),
                     int(round(r0 + (r1 - r0) * t)), col)


def portrait_player(c, rng):
    """Выживший по пояс: потрёпанный лётный скафандр, шлем с треснувшим визором."""
    # рукава и наплечники
    c.fill_rect(10, 46, 21, 59, SUIT)
    c.fill_rect(43, 46, 54, 59, SUIT_D)
    c.ellipse(16, 45, 7, 5, SUIT)
    c.ellipse(48, 45, 7, 5, SUIT_D)
    c.ellipse(14, 45, 3, 2, SUIT_L)
    # корпус: грудь расширяется книзу, правая сторона в тени
    for y in range(40, 60):
        hw = 8 + (y - 40) * 6 // 19
        c.hline(32 - hw, 35, y, SUIT)
        c.hline(36, 32 + hw, y, SUIT_D)
    c.vline(21, 47, 59, SUIT_D)
    c.vline(43, 47, 59, DARK)
    # манжеты и ремни подвесной системы
    c.fill_rect(10, 56, 21, 58, STEEL_D)
    c.fill_rect(43, 56, 54, 58, STEEL_D)
    c.hline(10, 21, 56, STEEL)
    c.hline(43, 54, 56, DARK)
    c.line(27, 41, 30, 59, SUIT_D)
    c.line(37, 41, 34, 59, SUIT)
    c.fill_rect(29, 47, 35, 53, STEEL_D)
    c.rect(29, 47, 35, 53, STEEL)
    c.hline(30, 34, 50, DARK)
    c.pixel(31, 49, AMBER)
    c.pixel(33, 51, CYAN_D)
    # прорехи, подпалины и пыль на ткани
    c.specks_on(rng, 10, 40, 35, 59, SUIT, SUIT_D, 34)
    c.specks_on(rng, 36, 40, 54, 59, SUIT_D, DARK, 20)
    c.specks_on(rng, 10, 44, 30, 55, SUIT, SUIT_L, 12)
    # фланец гермошлема
    c.fill_rect(25, 35, 39, 41, STEEL_D)
    c.hline(25, 39, 35, STEEL)
    c.hline(25, 39, 39, DARK)
    c.pixel(27, 37, CYAN_D)
    c.pixel(37, 37, CYAN_D)
    # купол шлема: тень, основной тон, верхний блик
    c.ellipse(32, 21, 13, 14, STEEL_D)
    c.ellipse(31, 20, 12, 13, STEEL)
    c.ellipse(28, 15, 8, 7, STEEL_L)
    c.specks_on(rng, 20, 8, 44, 20, STEEL_L, STEEL, 12)
    c.specks_on(rng, 20, 8, 45, 34, STEEL, STEEL_D, 16)
    # боковые крепления, полоса пилота и антенна
    c.fill_rect(20, 20, 23, 28, STEEL_D)
    c.fill_rect(41, 20, 44, 28, STEEL_D)
    c.hline(20, 23, 24, STEEL)
    c.hline(41, 44, 24, DARK)
    c.hline(23, 31, 11, GOLD_D)
    c.hline(23, 31, 12, AMBER)
    c.hline(24, 30, 13, GOLD_D)
    c.vline(42, 6, 13, STEEL_D)
    c.pixel(42, 5, CYAN_L)
    # визор
    c.ellipse(32, 24, 10, 7, DARK)
    c.ellipse(32, 24, 9, 6, GLASS_D)
    c.ellipse(32, 25, 8, 5, GLASS)
    # лицо за стеклом
    c.ellipse(33, 28, 4, 3, FACE_D)
    c.ellipse(33, 27, 3, 2, FACE)
    c.pixel(35, 26, FACE_L)
    c.pixel(31, 27, DARK)
    c.pixel(35, 27, DARK)
    c.hline(32, 34, 30, FACE_D)
    # отражение в стекле: сплошной косой блик
    for i in range(7):
        c.vline(25 + i, 26 - i, 28 - i, GLASS_LIT)
    for i in range(5):
        c.pixel(27 + i, 30 - i, GLASS_M)
    # звезда трещины от удара в стекло
    c.pixel(37, 22, WHITE)
    c.pixel(38, 22, WHITE)
    c.line(37, 22, 33, 19, WHITE)
    c.line(38, 22, 40, 26, WHITE)
    c.line(37, 22, 39, 18, GREY)
    c.line(37, 23, 30, 29, GREY)
    c.pixel(35, 20, GREY)


def portrait_drone_cargo(c, rng):
    """Сервисный дрон: овальный корпус, красный окуляр, искрящий манипулятор."""
    # корпус
    c.ellipse(29, 30, 21, 17, STEEL_D)
    c.ellipse(28, 29, 20, 16, STEEL)
    c.ellipse(23, 22, 12, 7, STEEL_L)
    # обшивка: шов, заклёпки, рёбра жёсткости
    c.hline(15, 41, 40, DARK)
    c.hline(15, 41, 41, STEEL_D)
    for x in range(16, 42, 6):
        c.pixel(x, 38, STEEL_L)
    c.line(13, 27, 18, 19, STEEL_D)
    c.line(44, 27, 39, 19, STEEL_D)
    c.specks_on(rng, 10, 16, 46, 44, STEEL, STEEL_D, 28)
    c.specks_on(rng, 13, 16, 34, 27, STEEL_L, STEEL, 12)
    # окуляр: гнездо, линза, блик
    c.circle(27, 28, 10, STEEL_D)
    c.circle(27, 28, 9, DARK)
    c.circle(27, 28, 7, RED_DARK)
    c.circle(27, 28, 5, RED_DIM)
    c.circle(27, 28, 3, RED)
    c.circle(26, 27, 1, RED_LIT)
    c.pixel(27, 17, STEEL_L)
    c.pixel(17, 28, STEEL_L)
    c.pixel(37, 28, STEEL_L)
    c.pixel(27, 39, STEEL_L)
    # антенна с маячком
    c.vline(18, 10, 16, STEEL_D)
    c.pixel(18, 9, AMBER)
    c.pixel(19, 13, STEEL)
    # маневровые сопла и выхлоп
    c.fill_rect(16, 42, 22, 49, STEEL_D)
    c.fill_rect(17, 42, 19, 49, STEEL)
    c.fill_rect(34, 42, 40, 49, STEEL_D)
    c.fill_rect(35, 42, 37, 49, STEEL)
    c.hline(16, 22, 49, DARK)
    c.hline(34, 40, 49, DARK)
    c.fill_rect(17, 50, 21, 52, GOLD_D)
    c.fill_rect(35, 50, 39, 52, GOLD_D)
    c.fill_rect(18, 53, 20, 54, RUST_D)
    c.fill_rect(36, 53, 38, 54, RUST_D)
    # манипулятор: тяга, локоть, предплечье
    for dy, col in ((-1, STEEL_L), (0, STEEL), (1, STEEL_D)):
        c.line(44, 32 + dy, 53, 39 + dy, col)
    for dx, col in ((-1, STEEL_L), (0, STEEL), (1, STEEL_D)):
        c.line(53 + dx, 39, 57 + dx, 30, col)
    c.circle(53, 39, 2, STEEL_D)
    c.pixel(52, 38, STEEL_L)
    # клешня и разряд между жвалами
    c.line(56, 28, 52, 24, STEEL)
    c.line(57, 28, 53, 23, STEEL_D)
    c.line(58, 28, 58, 22, STEEL)
    c.line(59, 28, 59, 23, STEEL_D)
    c.line(54, 22, 56, 19, AMBER)
    c.line(56, 19, 58, 21, GOLD_L)
    c.pixel(55, 17, WHITE)
    c.pixel(57, 25, GOLD_L)
    c.pixel(54, 26, AMBER)


def portrait_station_sentry(c, rng):
    """Потолочная турель охраны: подвес, спаренный ствол, красная линза."""
    # потолочная плита
    c.fill_rect(9, 4, 54, 9, STEEL_D)
    c.fill_rect(9, 4, 54, 5, STEEL)
    c.hline(9, 54, 9, DARK)
    c.pixel(12, 6, STEEL_L)
    c.pixel(51, 6, STEEL_L)
    c.pixel(31, 6, STEEL_L)
    # подвес: две тяги и поворотный узел
    c.fill_rect(22, 9, 26, 16, STEEL_D)
    c.fill_rect(38, 9, 42, 16, STEEL_D)
    c.vline(23, 9, 16, STEEL)
    c.vline(39, 9, 16, STEEL)
    c.fill_rect(20, 16, 44, 21, STEEL_D)
    c.fill_rect(20, 16, 44, 17, STEEL)
    c.hline(20, 44, 21, DARK)
    c.ellipse(32, 19, 5, 3, STEEL)
    c.pixel(30, 18, STEEL_L)
    # корпус турели
    c.ellipse(32, 31, 17, 11, STEEL_D)
    c.ellipse(31, 30, 16, 10, STEEL)
    c.ellipse(24, 25, 8, 3, STEEL_L)
    c.hline(17, 46, 37, DARK)
    c.specks_on(rng, 16, 22, 48, 40, STEEL, STEEL_D, 22)
    # короб подачи слева и кабель к потолку
    c.fill_rect(8, 26, 16, 36, STEEL_D)
    c.rect(8, 26, 16, 36, DARK)
    c.hline(9, 15, 29, STEEL)
    c.hline(9, 15, 33, AMBER)
    c.line(11, 26, 13, 16, STEEL_D)
    c.line(12, 26, 14, 16, DARK)
    c.line(13, 16, 16, 10, STEEL_D)
    c.line(14, 16, 17, 10, DARK)
    # окно выброса гильз справа
    c.fill_rect(45, 28, 50, 34, STEEL_D)
    c.rect(45, 28, 50, 34, DARK)
    c.pixel(47, 31, AMBER)
    # линза сканера
    c.circle(32, 30, 7, STEEL_D)
    c.circle(32, 30, 6, DARK)
    c.circle(32, 30, 5, RED_DARK)
    c.circle(32, 30, 4, RED_DIM)
    c.circle(32, 30, 2, RED)
    c.pixel(31, 29, RED_LIT)
    # спаренный ствол, отведённый вниз-влево
    c.fill_rect(24, 36, 38, 42, STEEL_D)
    c.hline(24, 38, 36, STEEL)
    c.hline(24, 38, 42, DARK)
    for off, col in ((-2, STEEL), (-1, STEEL_L), (0, STEEL_D), (1, DARK)):
        c.line(27 + off, 40, 15 + off, 54, col)
        c.line(34 + off, 40, 22 + off, 54, col)
    c.fill_rect(19, 46, 28, 48, STEEL_D)
    c.hline(19, 28, 46, STEEL)
    c.fill_rect(12, 51, 17, 56, STEEL_D)
    c.fill_rect(19, 51, 24, 56, STEEL_D)
    c.hline(12, 17, 51, STEEL)
    c.hline(19, 24, 51, STEEL)
    c.fill_rect(13, 53, 15, 55, DARK)
    c.fill_rect(20, 53, 22, 55, DARK)


def portrait_strain_l7(c, rng):
    """Штамм Л-7: бледная биомасса с жгутами живой ткани и тёмными прожилками."""
    # тело: сросшиеся доли, тёмный ободок и основной тон
    _blob(c, ((28, 36, 17), (40, 40, 12), (22, 44, 12), (24, 22, 10), (42, 25, 9)), FLESH_D)
    _blob(c, ((26, 34, 15), (38, 38, 10), (20, 42, 10), (22, 20, 8), (40, 23, 7)), FLESH)
    _blob(c, ((23, 28, 8), (20, 18, 4), (37, 20, 4)), FLESH_L)
    _blob(c, ((33, 44, 5), (31, 26, 4), (30, 50, 4)), FLESH_M)
    # тёмные прожилки с ветвлением
    c.line(20, 26, 27, 36, VEIN)
    c.line(21, 26, 28, 36, VEIN)
    c.line(27, 36, 23, 50, VEIN)
    c.line(28, 36, 38, 43, VEIN)
    c.line(38, 43, 45, 38, VEIN)
    c.line(27, 36, 32, 24, VEIN)
    c.line(32, 24, 39, 20, VEIN)
    c.line(27, 36, 16, 40, VEIN)
    c.line(23, 50, 26, 52, VEIN)
    c.line(38, 43, 41, 50, VEIN)
    c.line(32, 24, 30, 16, VEIN)
    c.line(16, 40, 14, 46, VEIN)
    c.line(45, 38, 47, 31, VEIN)
    c.line(28, 36, 34, 33, VEIN)
    # вскрытая полость и мелкие провалы в ткани
    c.ellipse(29, 41, 5, 3, VEIN)
    c.ellipse(29, 41, 4, 2, VEIN_D)
    c.pixel(27, 40, FLESH_LIT)
    c.pixel(31, 41, FLESH_LIT)
    c.ellipse(22, 27, 3, 2, VEIN)
    c.pixel(22, 27, FLESH_LIT)
    c.ellipse(41, 33, 2, 2, VEIN)
    # жгуты живой ткани
    _tendril(c, ((14, 30, 3), (8, 27, 2), (5, 21, 2), (5, 15, 1)), FLESH_D)
    _tendril(c, ((14, 30, 2), (8, 27, 1), (5, 21, 1)), FLESH)
    _tendril(c, ((48, 33, 3), (54, 34, 2), (58, 30, 2), (58, 24, 1)), FLESH_D)
    _tendril(c, ((48, 33, 2), (54, 34, 1), (58, 30, 1)), FLESH)
    _tendril(c, ((22, 51, 3), (18, 56, 2), (13, 58, 1)), FLESH_D)
    _tendril(c, ((40, 48, 2), (46, 51, 2), (50, 56, 1)), FLESH_D)
    _tendril(c, ((44, 20, 2), (50, 14, 1)), FLESH_D)
    _tendril(c, ((30, 19, 2), (33, 12, 1)), FLESH_D)
    _tendril(c, ((17, 47, 2), (11, 49, 1)), FLESH_D)
    _tendril(c, ((45, 43, 2), (52, 45, 1)), FLESH_D)
    # неровная фактура биомассы
    c.specks_on(rng, 12, 14, 52, 54, FLESH, FLESH_L, 44)
    c.specks_on(rng, 12, 14, 52, 54, FLESH, FLESH_M, 30)
    c.specks_on(rng, 12, 14, 52, 54, FLESH_L, FLESH, 14)
    c.specks_on(rng, 12, 30, 52, 56, FLESH_D, VEIN, 18)


PORTRAITS = (
    (PORTRAITS_DIR, "player", portrait_player),
    (ENEMIES_DIR, "drone_cargo", portrait_drone_cargo),
    (ENEMIES_DIR, "station_sentry", portrait_station_sentry),
    (ENEMIES_DIR, "strain_l7", portrait_strain_l7),
)


# ----------------------------------------------------------------------------
# Мелкая математика без импорта math (нужны только синус/косинус по кругу)
# ----------------------------------------------------------------------------

def _sin(a):
    # ряд Тейлора достаточной точности для расстановки заклёпок
    a = a % 6.283185307179586
    if a > 3.141592653589793:
        a -= 6.283185307179586
    a2 = a * a
    return a * (1.0 - a2 / 6.0 * (1.0 - a2 / 20.0 * (1.0 - a2 / 42.0)))


def _cos(a):
    return _sin(a + 1.5707963267948966)


# ----------------------------------------------------------------------------

def main():
    os.makedirs(SCENES_DIR, exist_ok=True)
    os.makedirs(ITEMS_DIR, exist_ok=True)
    os.makedirs(PORTRAITS_DIR, exist_ok=True)
    os.makedirs(ENEMIES_DIR, exist_ok=True)
    written = []

    for i, (name, fn) in enumerate(SCENES):
        rng = random.Random(SEED + i * 101)
        c = Canvas(SCENE_W, SCENE_H, VOID)
        fn(c, rng)
        path = os.path.join(SCENES_DIR, name + ".png")
        write_png(path, c, with_alpha=False)
        written.append((path, c.w, c.h))

    # заглавный кадр главного меню — свой размер, отдельный проход
    rng = random.Random(SEED + 4242)
    title = Canvas(TITLE_W, TITLE_H, VOID)
    scene_title_screen(title, rng)
    title_path = os.path.join(SCENES_DIR, "title_screen.png")
    write_png(title_path, title, with_alpha=False)
    written.append((title_path, title.w, title.h))

    for name, fn in ITEMS:
        c = Canvas(ICON_W, ICON_H, (0, 0, 0, 0))
        fn(c)
        c.outline_alpha(OUTLINE)
        path = os.path.join(ITEMS_DIR, name + ".png")
        write_png(path, c, with_alpha=True)
        written.append((path, c.w, c.h))

    for i, (directory, name, fn) in enumerate(PORTRAITS):
        rng = random.Random(SEED + 7000 + i * 37)
        c = Canvas(PORTRAIT_W, PORTRAIT_H, (0, 0, 0, 0))
        fn(c, rng)
        c.outline_alpha(OUTLINE)
        path = os.path.join(directory, name + ".png")
        write_png(path, c, with_alpha=True)
        written.append((path, c.w, c.h))

    for path, w, h in written:
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        print("%s  %dx%d" % (rel, w, h))


if __name__ == "__main__":
    main()
