extends Node
## Монетизация: без премиум-валюты, одна разовая покупка (контент-гейт +
## снятие суточного лимита на откат) + rewarded ad как бесплатная мерси-механика.
## См. gdd-v1.md раздел 5.6 и tech-spec-v1.md раздел 9.

signal purchase_completed(success: bool)
signal ad_completed(success: bool)
signal full_access_changed(value: bool)

const DAILY_AD_LIMIT: int = 1

var has_full_access: bool = false

var _provider: EconomyProvider = MockEconomyProvider.new()
var _last_ad_rollback_date: String = ""
var _ad_rollbacks_used_today: int = 0
var _paid_rollback_used_this_run: bool = false


func reset_for_new_run() -> void:
	_paid_rollback_used_this_run = false


func purchase_full_access() -> void:
	var success: bool = _provider.purchase_full_access()
	if success:
		has_full_access = true
		full_access_changed.emit(true)
		EventBus.full_access_changed.emit(true)
	purchase_completed.emit(success)


func can_use_rollback_today() -> bool:
	if has_full_access and not _paid_rollback_used_this_run:
		return true
	_roll_daily_counter()
	return _ad_rollbacks_used_today < DAILY_AD_LIMIT


func use_rollback() -> void:
	if has_full_access and not _paid_rollback_used_this_run:
		_paid_rollback_used_this_run = true
		return
	_roll_daily_counter()
	_ad_rollbacks_used_today += 1


func watch_rollback_ad() -> void:
	var success: bool = _provider.watch_rewarded_ad()
	ad_completed.emit(success)
	if success:
		use_rollback()


func _roll_daily_counter() -> void:
	var today := _today_string()
	if _last_ad_rollback_date != today:
		_last_ad_rollback_date = today
		_ad_rollbacks_used_today = 0


func _today_string() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


func to_save_data() -> Dictionary:
	return {
		"has_full_access": has_full_access,
		"last_ad_rollback_date": _last_ad_rollback_date,
		"ad_rollbacks_used_today": _ad_rollbacks_used_today,
	}


func load_save_data(data: Dictionary) -> void:
	has_full_access = bool(data.get("has_full_access", false))
	_last_ad_rollback_date = str(data.get("last_ad_rollback_date", ""))
	_ad_rollbacks_used_today = int(data.get("ad_rollbacks_used_today", 0))


func to_run_save_data() -> Dictionary:
	return {
		"paid_rollback_used_this_run": _paid_rollback_used_this_run,
	}


func load_run_save_data(data: Dictionary) -> void:
	_paid_rollback_used_this_run = bool(data.get("paid_rollback_used_this_run", false))
