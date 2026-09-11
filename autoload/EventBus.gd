extends Node
## Глобальная шина сигналов. Не хранит состояние — только те события,
## которые слушают несколько независимых систем одновременно.
## Локальные события одной системы (например, situation_started) живут
## на самой этой системе, не здесь — см. ТЗ раздел 0, принцип 3.

signal player_died(cause: String)          # cause: "hp" | "o2"
signal returned_to_hub()                    # эпизод завершён, игрок в хабе
signal full_access_changed(value: bool)
