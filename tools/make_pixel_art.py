#!/usr/bin/env python3
"""
Генератор пиксель-арта для CosmosText: иллюстрации сцен и иконки предметов.
Всё рисуется кодом на чистой стандартной библиотеке (без Pillow), PNG собирается
вручную через zlib. Результат детерминирован (фиксированный seed).

Запуск из корня проекта: python tools/make_pixel_art.py
Пишет:
  assets/art/scenes/<name>.png  — 160x96, RGB (цветовой тип 2), без альфы;
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

def scene_capsule(c, rng):
    """Спасательная капсула изнутри: треснувший иллюминатор, аварийная лампа, пульт."""
    p = {
        "void": VOID,
        "hull_d": (22, 27, 36),
        "hull": (34, 42, 55),
        "hull_l": (52, 63, 80),
        "rim": (78, 92, 112),
        "glass": (13, 19, 34),
        "star": STAR,
        "crack": (150, 163, 185),
        "red_d": (104, 30, 40),
        "red": RED,
        "red_l": RED_LIT,
        "panel": (26, 33, 44),
        "cyan": CYAN,
        "amber": AMBER,
    }
    c.fill(p["hull"])
    # изогнутый потолок и пол капсулы
    c.fill_rect(0, 0, 159, 11, p["hull_d"])
    c.dither_rect(0, 12, 159, 15, p["hull_d"], p["hull"])
    c.fill_rect(0, 82, 159, 95, p["hull_d"])
    c.dither_rect(0, 78, 159, 81, p["hull"], p["hull_d"], 1)
    # боковые рёбра корпуса
    for x in (6, 14, 145, 153):
        c.vline(x, 8, 84, p["hull_l"])
        c.vline(x + 1, 8, 84, p["hull_d"])
    for y in range(12, 82, 8):
        c.pixel(10, y, p["rim"])
        c.pixel(149, y, p["rim"])
    # иллюминатор
    cx, cy, r = 80, 41, 27
    c.circle(cx, cy, r + 4, p["hull_l"])
    c.ring(cx, cy, r, r + 4, p["rim"])
    c.circle(cx, cy, r, p["glass"])
    c.specks_on(rng, cx - r, cy - r, cx + r, cy + r, p["glass"], p["star"], 90)
    c.specks_on(rng, cx - r, cy - r, cx + r, cy + r, p["glass"], STAR_DIM, 70)
    # планета за стеклом: красим только пиксели «неба», чтобы не выйти за обод
    ox, oy, orr = cx + 13, cy + 18, 16
    sky = (rgba(p["glass"]), rgba(p["star"]), rgba(STAR_DIM))
    for y in range(oy - orr, oy + orr + 1):
        for x in range(ox - orr, ox + orr + 1):
            d = (x - ox) ** 2 + (y - oy) ** 2
            if d > orr * orr or c.get(x, y) not in sky:
                continue
            if (x - ox) + (y - oy) < -10:
                col = p["crack"]
            elif d > (orr - 3) ** 2:
                col = p["hull_d"]
            elif (y - oy) % 5 == 0:
                col = p["hull_l"]
            else:
                col = p["rim"]
            c.pixel(x, y, col)
    # трещины от края стекла
    c.line(cx - 26, cy - 6, cx + 4, cy + 3, p["crack"])
    c.line(cx + 4, cy + 3, cx + 18, cy - 10, p["crack"])
    c.line(cx + 4, cy + 3, cx + 12, cy + 17, p["crack"])
    c.line(cx - 8, cy - 1, cx - 12, cy + 16, p["crack"])
    c.line(cx - 2, cy + 1, cx + 9, cy - 19, p["crack"])
    # заклёпки по ободу
    for k in range(12):
        a = k * 3.14159 * 2.0 / 12.0
        c.pixel(int(cx + (r + 2) * _cos(a)), int(cy + (r + 2) * _sin(a)), p["hull_d"])
    # аварийная лампа слева сверху
    c.dither_disc(24, 20, 13, p["red_d"], 1)
    c.circle(24, 20, 5, p["red"])
    c.circle(24, 19, 2, p["red_l"])
    c.fill_rect(21, 12, 27, 14, p["hull_l"])
    # отсвет лампы на потолке и стене
    c.dither_over(8, 8, 46, 12, p["red_d"])
    # пульт управления
    c.fill_rect(16, 66, 143, 95, p["panel"])
    c.hline(16, 143, 66, p["hull_l"])
    c.hline(16, 143, 67, p["hull_d"])
    c.fill_rect(22, 71, 62, 89, p["glass"])
    c.rect(21, 70, 63, 90, p["hull_l"])
    for i, yy in enumerate(range(74, 88, 4)):
        c.hline(25, 25 + 8 + i * 9, yy, p["cyan"])
    c.hline(25, 58, 86, p["amber"])
    for row, yy in enumerate((73, 80, 87)):
        for i in range(7):
            xx = 74 + i * 9
            col = p["amber"] if (i + row) % 3 == 0 else (p["cyan"] if (i + row) % 3 == 1 else p["red"])
            c.fill_rect(xx, yy, xx + 4, yy + 3, col)
            c.hline(xx, xx + 4, yy + 4, p["hull_d"])
    # рукоятка катапульты
    c.fill_rect(130, 40, 136, 64, p["hull_l"])
    c.fill_rect(127, 36, 139, 41, p["red"])
    c.noise_specks(rng, 0, 84, 159, 95, p["hull"], 40)


def scene_wreckage(c, rng):
    """Разорванный коридор корабля: обломки дрейфуют, за пробоиной звёзды."""
    p = {
        "d0": (39, 47, 60), "d1": (28, 35, 45), "d2": (20, 25, 33),
        "f0": (38, 44, 54), "f1": (29, 34, 43), "f2": (20, 25, 33),
        "w0": (52, 61, 76), "w1": (39, 47, 60), "w2": (28, 35, 45),
        "far": (18, 23, 31),
        "seam": (14, 18, 24),
        "hot": (86, 98, 118),
        "void": VOID,
        "star": STAR,
        "amber": AMBER,
        "red": RED,
        "cyan": CYAN,
    }
    draw_room(c, (58, 30, 100, 64),
              {"ceil": (p["d0"], p["d1"], p["d2"]),
               "floor": (p["f0"], p["f1"], p["f2"]),
               "left": (p["w0"], p["w1"], p["w2"]),
               "right": (p["w0"], p["w1"], p["w2"]),
               "far": p["far"]}, p["seam"])
    # рёбра жёсткости на левой стене
    for k, xx in enumerate((6, 22, 40)):
        top = 6 + k * 6
        bot = 89 - k * 6
        c.vline(xx, top, bot, p["hot"])
        c.vline(xx + 1, top, bot, p["seam"])
    # дальний проём с тусклым светом
    c.fill_rect(70, 40, 88, 64, p["w2"])
    c.rect(70, 40, 88, 64, p["hot"])
    c.dither_over(72, 42, 86, 50, p["cyan"], 1)
    # пробоина: рваный край справа
    edge = 96
    for y in range(0, 96):
        edge += rng.randint(-3, 3)
        edge = max(92, min(118, edge))
        if 8 <= y <= 86:
            c.hline(edge, 159, y, p["void"])
            c.pixel(edge - 1, y, p["hot"])
    c.specks_on(rng, 96, 8, 159, 86, p["void"], p["star"], 110)
    c.specks_on(rng, 96, 8, 159, 86, p["void"], STAR_DIM, 80)
    # загнутые лепестки обшивки по краю пробоины
    for y0 in (14, 34, 58, 76):
        c.line(96, y0, 108, y0 - 6, p["hot"])
        c.line(108, y0 - 6, 112, y0 + 2, p["w1"])
        c.line(96, y0, 112, y0 + 2, p["w2"])
    # дрейфующие обломки
    for (bx, by, bw, bh) in ((118, 22, 9, 5), (132, 46, 7, 7), (104, 68, 11, 4),
                             (140, 14, 5, 9), (126, 70, 6, 5), (148, 58, 6, 4)):
        c.fill_rect(bx, by, bx + bw, by + bh, p["w1"])
        c.hline(bx, bx + bw, by, p["hot"])
        c.rect(bx - 1, by - 1, bx + bw + 1, by + bh + 1, p["seam"])
    # оборванные кабели с искрами
    c.line(30, 4, 34, 26, p["seam"])
    c.line(34, 26, 28, 38, p["seam"])
    c.line(48, 4, 52, 20, p["seam"])
    c.pixel(28, 39, p["amber"])
    c.noise_specks(rng, 24, 36, 34, 44, p["amber"], 6)
    c.noise_specks(rng, 46, 18, 56, 26, p["red"], 4)
    # мусор на полу
    c.noise_specks(rng, 4, 74, 92, 95, p["w2"], 50)
    c.noise_specks(rng, 4, 78, 92, 95, p["hot"], 18)


def scene_cargo_drone(c, rng):
    """Грузовой отсек: контейнеры, в центре сервисный дрон с красным окуляром."""
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
    # разбросанный груз на полу
    c.noise_specks(rng, 40, 76, 120, 95, p["crate_d"], 40)
    c.noise_specks(rng, 40, 80, 120, 95, p["metal_d"], 20)


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


def scene_comms_sentry(c, rng):
    """Зал связи: антенные стойки, турель охраны на потолке с красным лучом."""
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
    # блики и мусор на полу
    c.dither_over(56, 70, 104, 78, p["cyan"], 1)
    c.noise_specks(rng, 0, 76, 159, 95, p["f2"], 30)
    c.noise_specks(rng, 30, 80, 130, 95, p["rack_d"], 16)


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


def scene_base_bay(c, rng):
    """Обжитой модуль-база: верстак, ящики-склад, лампа, спальник."""
    p = {
        "d0": (45, 40, 36), "d1": (33, 30, 27), "d2": (25, 23, 23),
        "f0": (52, 45, 38), "f1": (40, 35, 30), "f2": (25, 23, 23),
        "w0": (58, 52, 46), "w1": (45, 40, 36), "w2": (33, 30, 27),
        "far": (24, 22, 22),
        "seam": (16, 14, 14),
        "wood": (126, 92, 52),
        "wood_d": (80, 58, 34),
        "metal": (120, 128, 142),
        "metal_d": (62, 68, 80),
        "amber": AMBER,
        "lamp": (252, 226, 168),
        "cloth": (92, 116, 132),
        "cyan": CYAN,
    }
    draw_room(c, (44, 22, 118, 70),
              {"ceil": (p["d0"], p["d1"], p["d2"]),
               "floor": (p["f0"], p["f1"], p["f2"]),
               "left": (p["w0"], p["w1"], p["w2"]),
               "right": (p["w0"], p["w1"], p["w2"]),
               "far": p["far"]}, p["seam"])
    # подвесная лампа и конус света
    c.vline(80, 0, 8, p["metal_d"])
    c.fill_rect(72, 8, 88, 12, p["metal"])
    c.hline(72, 88, 13, p["lamp"])
    for i in range(1, 22):
        half = 8 + i * 2
        if (i % 2) == 0:
            c.dither_over(80 - half, 13 + i, 80 + half, 13 + i, p["amber"], i)
    c.dither_disc(80, 14, 12, p["lamp"], 0)
    # верстак справа
    c.fill_rect(96, 52, 150, 58, p["wood"])
    c.hline(96, 150, 52, p["amber"])
    c.hline(96, 150, 58, p["seam"])
    c.fill_rect(100, 58, 104, 78, p["wood_d"])
    c.fill_rect(142, 58, 146, 78, p["wood_d"])
    c.hline(100, 146, 68, p["wood_d"])
    # инструменты на щите за верстаком
    c.fill_rect(98, 28, 150, 50, p["w2"])
    c.rect(98, 28, 150, 50, p["seam"])
    for i in range(6):
        xx = 104 + i * 8
        c.vline(xx, 32, 40 + (i % 3) * 3, p["metal"])
        c.pixel(xx, 31, p["metal_d"])
        c.fill_rect(xx - 1, 41 + (i % 3) * 3, xx + 1, 44 + (i % 3) * 3, p["metal_d"])
    c.fill_rect(108, 46, 122, 52, p["metal_d"])
    c.fill_rect(128, 44, 138, 52, p["wood_d"])
    # ящики-склад слева
    for (bx, by, bw, bh) in ((6, 44, 26, 22), (6, 66, 26, 22), (34, 56, 20, 32)):
        c.fill_rect(bx, by, bx + bw, by + bh, p["wood"])
        c.rect(bx, by, bx + bw, by + bh, p["seam"])
        c.hline(bx + 1, bx + bw - 1, by + 1, p["amber"])
        c.hline(bx, bx + bw, by + bh // 2, p["wood_d"])
        c.fill_rect(bx + 4, by + 4, bx + 10, by + 8, p["wood_d"])
    # спальник на полу слева
    c.ellipse(34, 88, 26, 7, p["cloth"])
    c.ellipse(34, 87, 24, 5, p["cyan"])
    c.ellipse(12, 87, 6, 5, p["lamp"])
    c.hline(16, 56, 90, p["seam"])
    # канистры и бочка у дальней стены
    c.fill_rect(58, 56, 68, 70, p["metal_d"])
    c.rect(58, 56, 68, 70, p["seam"])
    c.hline(59, 67, 60, p["metal"])
    c.fill_rect(72, 60, 80, 70, p["wood_d"])
    c.rect(72, 60, 80, 70, p["seam"])
    # табличка-экран у двери
    c.fill_rect(120, 34, 134, 42, p["seam"])
    c.rect(120, 34, 134, 42, p["metal_d"])
    c.hline(122, 130, 37, p["cyan"])
    c.hline(122, 127, 39, p["cyan"])
    c.noise_specks(rng, 0, 74, 159, 95, p["f2"], 36)
    c.noise_specks(rng, 56, 74, 120, 95, p["wood_d"], 14)


SCENES = (
    ("capsule", scene_capsule),
    ("wreckage", scene_wreckage),
    ("cargo_drone", scene_cargo_drone),
    ("shuttle_bay", scene_shuttle_bay),
    ("reactor_core", scene_reactor_core),
    ("service_corridor", scene_service_corridor),
    ("dock_bay", scene_dock_bay),
    ("comms_sentry", scene_comms_sentry),
    ("antenna_mast", scene_antenna_mast),
    ("base_bay", scene_base_bay),
)


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
    """Лётный комбинезон."""
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
