#!/usr/bin/env python3
"""
Переносит звуки игры из сторонней библиотеки «400 Sounds Pack» в assets/sounds.

Запуск из корня проекта:
    python tools/import_sounds.py "D:/Repos/400 Sounds Pack"

Каждый звук из SOUNDS сводится в моно 16 бит 44.1 кГц, у него срезается тишина
в начале и в хвосте, а громкость выравнивается к целевому RMS (не выше пика
-1 dBFS), чтобы щелчок интерфейса не заглушал удар, а удар — фанфару.
Результат — assets/sounds/<id>.wav; id звука используют SoundSystem и docs.
Файлы перезаписываются, таблица записанного печатается в stdout.
Только стандартная библиотека.
"""

import array
import math
import os
import sys
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "sounds")

RATE = 44100
PEAK_LIMIT_DB = -1.0
## Порог тишины относительно пика и запас, который остаётся в хвосте.
SILENCE_DB = -50.0
TAIL_KEEP = 0.06
FADE_OUT = 0.03

# id -> (файл в библиотеке, целевой RMS активной части, dBFS)
SOUNDS = {
    # интерфейс
    "ui_click": ("UI/select_1.wav", -26.0),
    "map_open": ("Items/map_open.wav", -22.0),
    # перемещение
    "door": ("Machines/industrial_door_open.wav", -20.0),
    "elevator": ("Machines/hydraulic_down.wav", -20.0),
    # предметы и ресурсы
    "pickup": ("UI/pop_3.wav", -20.0),
    "equip": ("Items/item_equip.wav", -20.0),
    "craft": ("Weapons/weapon_upgrade.wav", -19.0),
    "heal": ("Items/air_pump.wav", -20.0),
    "o2_refill": ("Environment/air_burst.wav", -20.0),
    "unlock": ("Environment/lock_unlock.wav", -20.0),
    "locked": ("Environment/lock_quick.wav", -21.0),
    "lore": ("Items/page_turn.wav", -22.0),
    "low_o2": ("UI/synth_warning.wav", -22.0),
    # бой
    "hurt": ("Combat and Gore/punch_2.wav", -16.0),
    "hit": ("Combat and Gore/punch.wav", -16.0),
    "shot": ("Weapons/shot_muffled.wav", -16.0),
    "miss": ("Other/whoosh_1.wav", -20.0),
    "combat_start": ("Musical Effects/horror_sting.wav", -20.0),
    "combat_won": ("Musical Effects/synth_bass_chime_positive.wav", -20.0),
    # итог забега
    "death": ("Musical Effects/synth_bass_defeated.wav", -20.0),
    "victory": ("Musical Effects/synth_bass_level_complete.wav", -20.0),
}


def db(value):
    return 20.0 * math.log10(max(value, 1e-9))


def read_mono(path):
    with wave.open(path, "rb") as w:
        if w.getsampwidth() != 2:
            raise ValueError("%s: нужен 16-битный PCM" % path)
        if w.getframerate() != RATE:
            raise ValueError("%s: нужна частота %d Гц" % (path, RATE))
        channels = w.getnchannels()
        raw = array.array("h", w.readframes(w.getnframes()))
    if sys.byteorder == "big":
        raw.byteswap()
    if channels == 1:
        return [x / 32768.0 for x in raw]
    return [sum(raw[i:i + channels]) / (channels * 32768.0) for i in range(0, len(raw), channels)]


def trim(samples):
    """Срезает тишину по краям; в хвосте оставляет TAIL_KEEP с плавным затуханием."""
    peak = max(abs(x) for x in samples)
    threshold = peak * (10.0 ** (SILENCE_DB / 20.0))
    loud = [i for i, x in enumerate(samples) if abs(x) > threshold]
    if not loud:
        return samples
    end = min(len(samples), loud[-1] + int(TAIL_KEEP * RATE))
    out = samples[loud[0]:end]
    fade = min(len(out), int(FADE_OUT * RATE))
    for k in range(fade):
        out[len(out) - fade + k] *= 1.0 - (k + 1) / float(fade)
    return out


def normalize(samples, target_rms_db):
    peak = max(abs(x) for x in samples)
    active = [x for x in samples if abs(x) > peak * 0.01]
    rms = math.sqrt(sum(x * x for x in active) / len(active))
    gain_db = min(target_rms_db - db(rms), PEAK_LIMIT_DB - db(peak))
    gain = 10.0 ** (gain_db / 20.0)
    return [x * gain for x in samples], gain_db


def write_mono(path, samples):
    data = array.array("h", (max(-32768, min(32767, int(round(x * 32767.0)))) for x in samples))
    if sys.byteorder == "big":
        data.byteswap()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    pack = sys.argv[1]
    os.makedirs(OUT_DIR, exist_ok=True)
    for sound_id, (rel, target) in SOUNDS.items():
        samples = trim(read_mono(os.path.join(pack, rel)))
        samples, gain_db = normalize(samples, target)
        out = os.path.join(OUT_DIR, sound_id + ".wav")
        write_mono(out, samples)
        print("assets/sounds/%s.wav  %.2fs  %+.1f dB  <- %s" % (sound_id, len(samples) / RATE, gain_db, rel))


if __name__ == "__main__":
    main()
