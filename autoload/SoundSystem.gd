extends Node
## Звуки игры. Ничего не решает: слушает сигналы систем и проигрывает короткие
## эффекты из assets/sounds/<id>.wav (их переносит и выравнивает по громкости
## tools/import_sounds.py). UI вызывает play() напрямую для своих действий:
## щелчок кнопки, карта, надевание предмета, удары в бою (синхронно с эффектами
## CombatView). Включение и громкость — SettingsSystem.
##
## Что звучит по сигналам:
##   EffectResolver.change_reported — урон, лечение и пополнение кислорода;
##   получение предметов запускает Game синхронно с появлением строки ленты;
##   LocationSystem.location_entered / MapSystem.elevator_used / player_moved — перемещение;
##   ArchiveSystem.fragment_unlocked, CraftingSystem.crafted;
##   ProgressionSystem.xp_gained — опыт и новый уровень (в бою их озвучивает
##   экран победы, в такт своей анимации);
##   ResourceSystem.o2_changed — тревога при падении ниже low_o2();
##   NeedsSystem.changed — периодический сигнал при усталости или голоде.

const SOUND_DIR := "res://assets/sounds/"
const SOUNDS := [
	"ui_click", "map_open", "door", "shuttle_door", "elevator", "step",
	"pickup", "equip", "craft", "heal", "o2_refill", "unlock", "locked", "lore",
	"low_o2", "low_need", "xp", "level_up",
	"hurt", "hit", "shot", "miss", "combat_start", "combat_won",
	"death", "victory",
]
## Сколько звуков может звучать одновременно; лишний вытесняет самый старый.
const VOICES := 8
## Один и тот же звук не повторяется чаще: россыпь находок звучит один раз.
const REPEAT_GUARD_MS := 80
## Пока силы или питание в критической зоне, тревога повторяется редко:
## игрок замечает состояние, но звук не превращается в постоянную сирену.
const NEED_WARNING_INTERVAL := 8.0

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _last_played: Dictionary = {}  # id -> Time.get_ticks_msec()
var _o2_low: bool = false
var _need_warning_timer: Timer
var _needs_low: bool = false


## Без экрана (--headless, смоук-тест) звуки не грузятся и не
## играют: выводить их некуда, а тест завершается в том же кадре, и
## недоигранные звуки остаются в AudioServer утечкой.
func _ready() -> void:
	_need_warning_timer = Timer.new()
	_need_warning_timer.name = "NeedWarningTimer"
	_need_warning_timer.wait_time = NEED_WARNING_INTERVAL
	_need_warning_timer.one_shot = false
	_need_warning_timer.timeout.connect(_warn_low_needs)
	add_child(_need_warning_timer)
	if DisplayServer.get_name() != "headless":
		for id in SOUNDS:
			var path: String = SOUND_DIR + id + ".wav"
			if ResourceLoader.exists(path):
				_streams[id] = load(path)
			else:
				push_warning("SoundSystem: нет звука %s" % path)
		for i in range(VOICES):
			var player := AudioStreamPlayer.new()
			add_child(player)
			_players.append(player)
	_o2_low = ResourceSystem.o2 <= ResourceSystem.low_o2()
	_needs_low = NeedsSystem.is_tired() or NeedsSystem.is_hungry()
	EffectResolver.change_reported.connect(_on_change_reported)
	EffectResolver.lock_opened.connect(func(_lock_id: String) -> void: play("unlock"))
	MapSystem.node_blocked.connect(func(_node_id: String, _message: String) -> void: play("locked"))
	MapSystem.elevator_used.connect(func(_floor_id: String) -> void: play("elevator"))
	MapSystem.player_moved.connect(func(_from_id: String, _to_id: String) -> void: play("step"))
	LocationSystem.location_entered.connect(func(_id: String) -> void: play("door"))
	ArchiveSystem.fragment_unlocked.connect(func(_id: String) -> void: play("lore"))
	CraftingSystem.crafted.connect(func(_recipe_id: String, _item_id: String) -> void: play("craft"))
	ProgressionSystem.xp_gained.connect(_on_xp_gained)
	ResourceSystem.o2_changed.connect(_on_o2_changed)
	NeedsSystem.changed.connect(_on_needs_changed)
	GameState.screen_changed.connect(_on_screen_changed)


func play(id: String) -> void:
	if not SettingsSystem.sound_enabled or SettingsSystem.sound_volume_percent <= 0 or not _streams.has(id):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(id, -REPEAT_GUARD_MS)) < REPEAT_GUARD_MS:
		return
	_last_played[id] = now
	var player := _free_voice()
	player.stream = _streams[id]
	player.volume_db = linear_to_db(SettingsSystem.sound_volume())
	player.play()


func _free_voice() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	var stolen := _players[_next_voice]
	_next_voice = (_next_voice + 1) % _players.size()
	return stolen


## Убыль кислорода — цена каждого действия, она не озвучивается.
func _on_change_reported(kind: String, amount: float) -> void:
	match kind:
		"hp":
			play("hurt" if amount < 0.0 else "heal")
		"o2":
			if amount > 0.0:
				play("o2_refill")
		"item", "ammo":
			pass  # Game проиграет pickup, когда соответствующая строка станет видимой.
		"hunger":
			if amount < 0.0:
				play("heal")  # поел


## Опыт за ход боя звучит на экране победы, а не в момент удара.
func _on_xp_gained(_amount: int, levels: int) -> void:
	if GameState.current_screen == GameState.Screen.COMBAT:
		return
	play("level_up" if levels > 0 else "xp")


## Тревога — один раз при переходе через порог. Проверка отложена: если
## баллон опустел совсем, к этому моменту уже выставлена смерть и звучит она.
func _on_o2_changed(value: float) -> void:
	var low := value <= ResourceSystem.low_o2()
	if low and not _o2_low:
		_warn_low_o2.call_deferred()
	_o2_low = low


func _warn_low_o2() -> void:
	if not ResourceSystem.is_dead():
		play("low_o2")


## Силы и питание меняются только от действий. Предупреждаем на переходе в
## критическую зону, но не держим периодическую сирену поверх чтения ленты.
func _on_needs_changed() -> void:
	var low := NeedsSystem.is_tired() or NeedsSystem.is_hungry()
	if low and not _needs_low:
		_warn_low_needs.call_deferred()
	_needs_low = low
	_sync_need_warning_timer()


func _warn_low_needs() -> void:
	if _needs_low and _is_active_run_screen() and not ResourceSystem.is_dead():
		play("low_need")


func _sync_need_warning_timer() -> void:
	_need_warning_timer.stop()

func _is_active_run_screen() -> bool:
	return GameState.current_screen != GameState.Screen.MAIN_MENU \
		and GameState.current_screen != GameState.Screen.DEATH \
		and GameState.current_screen != GameState.Screen.VICTORY


func _on_screen_changed(screen: int) -> void:
	_sync_need_warning_timer()
	match screen:
		GameState.Screen.COMBAT:
			play("combat_start")
		GameState.Screen.DEATH:
			play("death")
		GameState.Screen.VICTORY:
			play("victory")
