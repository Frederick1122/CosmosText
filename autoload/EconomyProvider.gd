class_name EconomyProvider
extends RefCounted
## Базовый интерфейс платёжного/рекламного провайдера — см. tech-spec-v1.md
## раздел 9. Реальные Android/iOS-провайдеры наследуются от этого класса и
## подставляются в EconomyManager без изменения кода систем-потребителей.


func purchase_full_access() -> bool:
	push_warning("EconomyProvider: purchase_full_access не реализован")
	return false


func watch_rewarded_ad() -> bool:
	push_warning("EconomyProvider: watch_rewarded_ad не реализован")
	return false
