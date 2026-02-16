## app_root.gd
## Main application controller.
## Manages UI screens and level loading based on GameState.
extends Node

const GAME_STATE_SCRIPT := preload("res://src/core/game_state.gd")
const MUSIC_SYSTEM_SCRIPT := preload("res://src/systems/music_system.gd")
const SFX_SYSTEM_SCRIPT := preload("res://src/systems/sfx_system.gd")

## UI scene paths
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const SETTINGS_MENU_SCENE := "res://scenes/ui/settings_menu.tscn"
const LEVEL_SETUP_SCENE := "res://scenes/ui/level_setup.tscn"
const PAUSE_MENU_SCENE := "res://scenes/ui/pause_menu.tscn"
const GAME_OVER_SCENE := "res://scenes/ui/game_over.tscn"
const LEVEL_COMPLETE_SCENE := "res://scenes/ui/level_complete.tscn"

## Level scene path
const LEVEL_MVP_SCENE := "res://scenes/levels/level_mvp.tscn"

## Node references
@onready var ui_root: CanvasLayer = $UIRoot
@onready var level_root: Node = $LevelRoot

## Currently active UI screen
var _current_ui: Control = null

## Currently active level
var _current_level: Node = null

## Music system (Phase 2)
var music_system: MUSIC_SYSTEM_SCRIPT = null

## SFX system (Phase 4)
var sfx_system: SFX_SYSTEM_SCRIPT = null

## Prevent overlapping level load calls while waiting for queue_free to complete.
var _is_level_loading: bool = false


func _ready() -> void:
	print("[AppRoot] Initializing...")

	# Connect to EventBus state changes
	if EventBus:
		EventBus.state_changed.connect(_on_state_changed)

	# Initialize MusicSystem (Phase 2)
	music_system = MUSIC_SYSTEM_SCRIPT.new()
	music_system.name = "MusicSystem"
	add_child(music_system)

	# Initialize SFXSystem (Phase 4)
	sfx_system = SFX_SYSTEM_SCRIPT.new()
	sfx_system.name = "SFXSystem"
	add_child(sfx_system)

	# Start with main menu
	_show_main_menu()

	# Start menu music
	if music_system:
		music_system.play_context(MUSIC_SYSTEM_SCRIPT.MusicContext.MENU)

	print("[AppRoot] Ready (Phase 4: Music + SFX enabled)")


func _on_state_changed(old_state: GAME_STATE_SCRIPT.State, new_state: GAME_STATE_SCRIPT.State) -> void:
	print("[AppRoot] State changed: %s -> %s" % [
		GAME_STATE_SCRIPT.state_to_string(old_state),
		GAME_STATE_SCRIPT.state_to_string(new_state)
	])

	match new_state:
		GAME_STATE_SCRIPT.State.MAIN_MENU:
			_unload_level()
			_show_main_menu()
		GAME_STATE_SCRIPT.State.SETTINGS:
			_show_settings()
		GAME_STATE_SCRIPT.State.LEVEL_SETUP:
			_unload_level()
			_show_level_setup()
		GAME_STATE_SCRIPT.State.PLAYING:
			if old_state == GAME_STATE_SCRIPT.State.LEVEL_SETUP:
				_clear_ui()
				_load_level()
			elif old_state == GAME_STATE_SCRIPT.State.PAUSED:
				_clear_ui()
				_resume_level()
		GAME_STATE_SCRIPT.State.PAUSED:
			_pause_level()
			_show_pause_menu()
		GAME_STATE_SCRIPT.State.GAME_OVER:
			_pause_level()
			_show_game_over()
		GAME_STATE_SCRIPT.State.LEVEL_COMPLETE:
			_pause_level()
			_show_level_complete()


## ============================================================================
## UI MANAGEMENT
## ============================================================================

func _clear_ui() -> void:
	if _current_ui:
		_current_ui.queue_free()
		_current_ui = null


func _load_ui_scene(scene_path: String) -> Control:
	_clear_ui()
	var scene := load(scene_path) as PackedScene
	if scene:
		_current_ui = scene.instantiate() as Control
		ui_root.add_child(_current_ui)
		return _current_ui
	else:
		push_error("Failed to load UI scene: %s" % scene_path)
		return null


func _show_main_menu() -> void:
	_load_ui_scene(MAIN_MENU_SCENE)


func _show_settings() -> void:
	_load_ui_scene(SETTINGS_MENU_SCENE)


func _show_level_setup() -> void:
	_load_ui_scene(LEVEL_SETUP_SCENE)


func _show_pause_menu() -> void:
	_load_ui_scene(PAUSE_MENU_SCENE)


func _show_game_over() -> void:
	_load_ui_scene(GAME_OVER_SCENE)


func _show_level_complete() -> void:
	_load_ui_scene(LEVEL_COMPLETE_SCENE)


## ============================================================================
## LEVEL MANAGEMENT
## ============================================================================

func _load_level() -> void:
	if _is_level_loading:
		return
	_is_level_loading = true

	var old_level := _current_level
	if old_level and is_instance_valid(old_level):
		_current_level = null
		old_level.queue_free()
		await old_level.tree_exited
		print("[AppRoot] Level unloaded")

	var scene := load(LEVEL_MVP_SCENE) as PackedScene
	if scene:
		_current_level = scene.instantiate()
		level_root.add_child(_current_level)

		# Emit level started event
		if EventBus:
			EventBus.emit_level_started()

		print("[AppRoot] Level loaded")
	else:
		push_error("Failed to load level scene: %s" % LEVEL_MVP_SCENE)
	_is_level_loading = false


func _unload_level() -> void:
	if _current_level:
		_current_level.queue_free()
		_current_level = null
		print("[AppRoot] Level unloaded")


func _pause_level() -> void:
	if _current_level and _current_level.has_method("pause"):
		_current_level.pause()


func _resume_level() -> void:
	if _current_level and _current_level.has_method("resume"):
		_current_level.resume()
