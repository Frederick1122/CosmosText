class_name MockEconomyProvider
extends "res://autoload/EconomyProvider.gd"
## Провайдер для вертикального среза: покупка и просмотр рекламы всегда
## мгновенно успешны. Годится для обкатки потока, не для билда в сторы —
## см. tech-spec-v1.md раздел 13 (реальные SDK вне скоупа этого ТЗ).


func purchase_full_access() -> bool:
	return true


func watch_rewarded_ad() -> bool:
	return true
