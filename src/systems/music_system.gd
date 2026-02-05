## music_system.gd
## MusicSystem - handles background music for menu and level.
## CANON: Loads OGG from assets/audio/music/menu/ and /level/.
## CANON: Deterministic selection - first alphabetical track in folder.
## CANON: Loop + fade in/out via GameConfig.
## CANON: Reacts to OnGameStateChanged, OnLevelStarted, OnGameOver, OnBossSpawned.
class_name MusicSystem
extends Node

## Audio paths
const MENU_MUSIC_PATH := "res://assets/audio/music/menu/"
const LEVEL_MUSIC_PATH := "res://assets/audio/music/level/"

## Current music context
enum MusicContext {
	NONE,
	MENU,
	LEVEL,
	BOSS
}

## AudioStreamPlayer for music
var _player: AudioStreamPlayer = null

## Current context
var _current_context: MusicContext = MusicContext.NONE

## Current track path
var _current_track: String = ""

## Fade state
var _is_fading: bool = false
var _fade_direction: int = 0  # 1 = in, -1 = out
var _fade_timer: float = 0.0
var _target_volume_db: float = 0.0

## Cached tracks
var _menu_tracks: Array[String] = []
var _level_tracks: Array[String] = []

## Is music enabled
var _enabled: bool = true


func _ready() -> void:
	# Create AudioStreamPlayer
	_player = AudioStreamPlayer.new()
	_player.name = "MusicPlayer"
	_player.bus = "Master"  # Or "Music" if you have a dedicated bus
	add_child(_player)

	# Subscribe to events
	if EventBus:
		EventBus.state_changed.connect(_on_state_changed)
		EventBus.level_started.connect(_on_level_started)
		EventBus.player_died.connect(_on_player_died)
		EventBus.boss_spawned.connect(_on_boss_spawned)

	# Scan for tracks
	_scan_tracks()

	print("[MusicSystem] Initialized")


func _scan_tracks() -> void:
	_menu_tracks = _get_tracks_in_folder(MENU_MUSIC_PATH)
	_level_tracks = _get_tracks_in_folder(LEVEL_MUSIC_PATH)

	print("[MusicSystem] Found %d menu tracks, %d level tracks" % [_menu_tracks.size(), _level_tracks.size()])


func _get_tracks_in_folder(path: String) -> Array[String]:
	var tracks: Array[String] = []
	var dir := DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".ogg"):
				tracks.append(path + file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

	# Sort alphabetically for deterministic selection
	tracks.sort()
	return tracks


func _process(delta: float) -> void:
	if not _is_fading:
		return

	_fade_timer -= delta

	if _fade_timer <= 0:
		_is_fading = false
		if _fade_direction < 0:
			# Fade out complete - stop playback
			_player.stop()
			_player.volume_db = _target_volume_db
		else:
			# Fade in complete
			_player.volume_db = _target_volume_db
		return

	# Calculate current volume
	var fade_duration: float
	if _fade_direction > 0:
		fade_duration = GameConfig.music_fade_in_sec if GameConfig else 0.5
	else:
		fade_duration = GameConfig.music_fade_out_sec if GameConfig else 0.7

	var progress := 1.0 - (_fade_timer / fade_duration)
	if _fade_direction > 0:
		# Fade in: from -80db to target
		_player.volume_db = lerp(-80.0, _target_volume_db, progress)
	else:
		# Fade out: from target to -80db
		_player.volume_db = lerp(_target_volume_db, -80.0, progress)


## Play music for context
func play_context(context: MusicContext) -> void:
	if context == _current_context and _player.playing:
		return

	# Get track for context
	var track := _get_track_for_context(context)
	if track.is_empty():
		# No track available - just stop current
		if _player.playing:
			_fade_out()
		_current_context = context
		return

	# If already playing, fade out first then play new
	if _player.playing:
		_fade_out()
		# Queue the new track after fade
		await get_tree().create_timer(GameConfig.music_fade_out_sec if GameConfig else 0.7).timeout
		if not _enabled:
			return

	_current_context = context
	_current_track = track
	_play_track(track)


func _get_track_for_context(context: MusicContext) -> String:
	match context:
		MusicContext.MENU:
			return _menu_tracks[0] if not _menu_tracks.is_empty() else ""
		MusicContext.LEVEL, MusicContext.BOSS:
			return _level_tracks[0] if not _level_tracks.is_empty() else ""
		_:
			return ""


func _play_track(path: String) -> void:
	var stream := load(path) as AudioStream
	if not stream:
		push_warning("[MusicSystem] Failed to load track: %s" % path)
		return

	_player.stream = stream
	_player.volume_db = -80.0  # Start silent
	_player.play()

	# Calculate target volume from config
	var volume: float = GameConfig.music_volume if GameConfig else 0.7
	_target_volume_db = linear_to_db(volume)

	# Start fade in
	_fade_in()

	print("[MusicSystem] Playing: %s" % path)


func _fade_in() -> void:
	_is_fading = true
	_fade_direction = 1
	_fade_timer = GameConfig.music_fade_in_sec if GameConfig else 0.5


func _fade_out() -> void:
	if not _player.playing:
		return
	_is_fading = true
	_fade_direction = -1
	_fade_timer = GameConfig.music_fade_out_sec if GameConfig else 0.7


func stop() -> void:
	_fade_out()


## Set enabled state
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		_player.stop()


## ============================================================================
## EVENT HANDLERS
## ============================================================================

func _on_state_changed(old_state: GameState.State, new_state: GameState.State) -> void:
	match new_state:
		GameState.State.MAIN_MENU, GameState.State.SETTINGS:
			play_context(MusicContext.MENU)
		GameState.State.LEVEL_SETUP:
			# Keep menu music
			if _current_context != MusicContext.MENU:
				play_context(MusicContext.MENU)
		GameState.State.PLAYING:
			if old_state == GameState.State.LEVEL_SETUP:
				# Starting level - switch to level music
				play_context(MusicContext.LEVEL)
			elif old_state == GameState.State.PAUSED:
				# Resuming - keep current
				pass
		GameState.State.PAUSED:
			# Keep current music but could lower volume
			pass
		GameState.State.GAME_OVER:
			# Could play game over jingle or fade out
			_fade_out()
		GameState.State.LEVEL_COMPLETE:
			# Victory - could play victory music
			_fade_out()


func _on_level_started() -> void:
	play_context(MusicContext.LEVEL)


func _on_player_died() -> void:
	# Music handled by state change to GAME_OVER
	pass


func _on_boss_spawned(boss_id: int, pos: Vector3) -> void:
	# Could switch to boss music here
	# For MVP, keep level music but hook is ready
	_current_context = MusicContext.BOSS
	print("[MusicSystem] Boss context activated (same track for MVP)")
