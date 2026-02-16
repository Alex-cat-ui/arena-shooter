## music_system.gd
## MusicSystem - context playlists for menu / ambient / battle.
## Ambient starts on level load, battle starts on first enemy detection.
## Uses 2s crossfade on context switches and non-repeating random playlist bags.
class_name MusicSystem
extends Node

const MENU_MUSIC_PATH := "res://assets/audio/music/menu/"
const AMBIENT_MUSIC_PATH := "res://assets/audio/music/level/Ambient/"
const BATTLE_MUSIC_PATH := "res://assets/audio/music/level/Battle_music/"
const CONTEXT_CROSSFADE_SEC := 2.0
const SILENT_DB := -80.0
const ENEMY_CHECK_INTERVAL_SEC := 0.25

enum MusicContext {
	NONE,
	MENU,
	AMBIENT,
	BATTLE,
}

var _player_a: AudioStreamPlayer = null
var _player_b: AudioStreamPlayer = null
var _active_player: AudioStreamPlayer = null
var _inactive_player: AudioStreamPlayer = null
var _crossfade_tween: Tween = null

var _current_context: MusicContext = MusicContext.NONE
var _current_track_path: String = ""
var _enabled: bool = true
var _enemy_check_timer: float = 0.0
var _battle_lock_active: bool = false

var _menu_tracks: Array[String] = []
var _ambient_tracks: Array[String] = []
var _battle_tracks: Array[String] = []
var _menu_bag: Array[String] = []
var _ambient_bag: Array[String] = []
var _battle_bag: Array[String] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_init_players()
	_scan_tracks()
	_subscribe_events()
	print("[MusicSystem] Ready: menu=%d ambient=%d battle=%d" % [
		_menu_tracks.size(),
		_ambient_tracks.size(),
		_battle_tracks.size(),
	])


func _process(delta: float) -> void:
	if not _enabled:
		return
	if _current_context != MusicContext.BATTLE or not _battle_lock_active:
		return
	_enemy_check_timer -= delta
	if _enemy_check_timer > 0.0:
		return
	_enemy_check_timer = ENEMY_CHECK_INTERVAL_SEC
	if _count_alive_enemies() <= 0:
		_switch_to_ambient(true)


func _init_players() -> void:
	_player_a = AudioStreamPlayer.new()
	_player_a.name = "MusicPlayerA"
	_player_a.bus = "Master"
	add_child(_player_a)
	_player_a.finished.connect(_on_player_finished.bind(_player_a))

	_player_b = AudioStreamPlayer.new()
	_player_b.name = "MusicPlayerB"
	_player_b.bus = "Master"
	add_child(_player_b)
	_player_b.finished.connect(_on_player_finished.bind(_player_b))

	_active_player = _player_a
	_inactive_player = _player_b


func _subscribe_events() -> void:
	if not EventBus:
		return
	EventBus.state_changed.connect(_on_state_changed)
	EventBus.level_started.connect(_on_level_started)
	EventBus.mission_transitioned.connect(_on_mission_transitioned)
	EventBus.enemy_player_spotted.connect(_on_enemy_player_spotted)
	EventBus.enemy_killed.connect(_on_enemy_killed)


func _scan_tracks() -> void:
	_menu_tracks = _get_tracks_in_folder(MENU_MUSIC_PATH)
	_ambient_tracks = _get_tracks_in_folder(AMBIENT_MUSIC_PATH)
	_battle_tracks = _get_tracks_in_folder(BATTLE_MUSIC_PATH)
	_menu_bag.clear()
	_ambient_bag.clear()
	_battle_bag.clear()


func _get_tracks_in_folder(path: String) -> Array[String]:
	var tracks: Array[String] = []
	var dir := DirAccess.open(path)
	if not dir:
		return tracks
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var lower := file_name.to_lower()
			if lower.ends_with(".mp3") or lower.ends_with(".wav") or lower.ends_with(".ogg"):
				tracks.append(path + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	tracks.sort()
	return tracks


func play_context(context: MusicContext, force_restart: bool = false) -> void:
	if not _enabled:
		return
	if context == _current_context and not force_restart and _is_active_playing():
		return

	var next_track := _pick_track_for_context(context)
	_current_context = context

	if next_track.is_empty():
		stop()
		return

	_play_track_with_crossfade(next_track)


func stop() -> void:
	_stop_crossfade_tween()
	_current_track_path = ""
	if _player_a:
		_player_a.stop()
		_player_a.volume_db = SILENT_DB
	if _player_b:
		_player_b.stop()
		_player_b.volume_db = SILENT_DB


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not _enabled:
		stop()


func get_current_track_name() -> String:
	if _current_track_path.is_empty():
		return "-"
	var file_name := _current_track_path.get_file()
	var dot_idx := file_name.rfind(".")
	if dot_idx <= 0:
		return file_name
	return file_name.substr(0, dot_idx)


func get_current_context_name() -> String:
	match _current_context:
		MusicContext.MENU:
			return "MENU"
		MusicContext.AMBIENT:
			return "AMBIENT"
		MusicContext.BATTLE:
			return "BATTLE"
		_:
			return "NONE"


func _pick_track_for_context(context: MusicContext) -> String:
	match context:
		MusicContext.MENU:
			return _take_random_track(_menu_tracks, _menu_bag)
		MusicContext.AMBIENT:
			return _take_random_track(_ambient_tracks, _ambient_bag)
		MusicContext.BATTLE:
			return _take_random_track(_battle_tracks, _battle_bag)
		_:
			return ""


func _take_random_track(tracks: Array[String], bag: Array[String]) -> String:
	if tracks.is_empty():
		return ""
	if bag.is_empty():
		bag.append_array(tracks)
		_shuffle_tracks(bag)
	if bag.is_empty():
		return ""
	return bag.pop_back()


func _shuffle_tracks(arr: Array[String]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _play_track_with_crossfade(path: String) -> void:
	var stream := load(path) as AudioStream
	if not stream:
		push_warning("[MusicSystem] Failed to load track: %s" % path)
		return

	_stop_crossfade_tween()
	_current_track_path = path
	var target_db := _target_music_volume_db()

	if _is_active_playing():
		_inactive_player.stop()
		_inactive_player.stream = stream
		_inactive_player.volume_db = SILENT_DB
		_inactive_player.play()
		_crossfade_tween = create_tween()
		_crossfade_tween.set_parallel(true)
		_crossfade_tween.tween_property(_active_player, "volume_db", SILENT_DB, CONTEXT_CROSSFADE_SEC)
		_crossfade_tween.tween_property(_inactive_player, "volume_db", target_db, CONTEXT_CROSSFADE_SEC)
		_crossfade_tween.set_parallel(false)
		_crossfade_tween.tween_callback(_on_context_crossfade_finished)
		return

	_active_player.stop()
	_active_player.stream = stream
	_active_player.volume_db = SILENT_DB
	_active_player.play()
	_crossfade_tween = create_tween()
	_crossfade_tween.tween_property(_active_player, "volume_db", target_db, CONTEXT_CROSSFADE_SEC)


func _on_context_crossfade_finished() -> void:
	if _active_player:
		_active_player.stop()
		_active_player.volume_db = SILENT_DB
	var prev_active := _active_player
	_active_player = _inactive_player
	_inactive_player = prev_active
	_crossfade_tween = null


func _play_next_track_in_current_context() -> void:
	if _current_context == MusicContext.NONE:
		return
	var next_track := _pick_track_for_context(_current_context)
	if next_track.is_empty():
		return
	var stream := load(next_track) as AudioStream
	if not stream:
		push_warning("[MusicSystem] Failed to load track: %s" % next_track)
		return
	_stop_crossfade_tween()
	_current_track_path = next_track
	_active_player.stop()
	_active_player.stream = stream
	_active_player.volume_db = _target_music_volume_db()
	_active_player.play()


func _target_music_volume_db() -> float:
	var volume := GameConfig.music_volume if GameConfig else 0.7
	volume = clampf(volume, 0.0, 1.0)
	if volume <= 0.0001:
		return SILENT_DB
	return linear_to_db(volume)


func _stop_crossfade_tween() -> void:
	if _crossfade_tween and _crossfade_tween.is_running():
		_crossfade_tween.kill()
	_crossfade_tween = null


func _is_active_playing() -> bool:
	return _active_player != null and _active_player.playing


func _count_alive_enemies() -> int:
	if not get_tree():
		return 0
	var nodes := get_tree().get_nodes_in_group("enemies")
	var alive := 0
	for node_variant in nodes:
		var node := node_variant as Node
		if not node:
			continue
		if "is_dead" in node and bool(node.is_dead):
			continue
		alive += 1
	return alive


func _switch_to_ambient(force_restart: bool = false) -> void:
	_battle_lock_active = false
	_enemy_check_timer = ENEMY_CHECK_INTERVAL_SEC
	play_context(MusicContext.AMBIENT, force_restart)


func _on_player_finished(player: AudioStreamPlayer) -> void:
	if player != _active_player:
		return
	_play_next_track_in_current_context()


func _on_state_changed(_old_state: GameState.State, new_state: GameState.State) -> void:
	match new_state:
		GameState.State.MAIN_MENU, GameState.State.SETTINGS, GameState.State.LEVEL_SETUP:
			_battle_lock_active = false
			play_context(MusicContext.MENU, false)
		GameState.State.PLAYING:
			if _current_context == MusicContext.MENU or _current_context == MusicContext.NONE:
				_switch_to_ambient(true)
		_:
			pass


func _on_level_started() -> void:
	_battle_lock_active = false
	_switch_to_ambient(true)


func _on_mission_transitioned(_mission_index: int) -> void:
	_battle_lock_active = false
	_switch_to_ambient(true)


func _on_enemy_player_spotted(_enemy_id: int, _position: Vector3) -> void:
	if _count_alive_enemies() <= 0:
		return
	_enemy_check_timer = ENEMY_CHECK_INTERVAL_SEC
	if _battle_lock_active:
		return
	_battle_lock_active = true
	play_context(MusicContext.BATTLE, false)


func _on_enemy_killed(_enemy_id: int, _enemy_type: String) -> void:
	if _battle_lock_active and _count_alive_enemies() <= 0:
		_switch_to_ambient(true)
