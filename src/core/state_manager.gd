## state_manager.gd
## Singleton for game state transitions.
## CANON: Transitions only via GameStateManager.
## CANON: UI does NOT control gameplay entities directly.
extends Node

## Current game state
var current_state: GameState.State = GameState.State.MAIN_MENU

## Previous state (for back navigation)
var previous_state: GameState.State = GameState.State.MAIN_MENU

## Valid state transitions map
## Key: from state, Value: array of valid target states
var _valid_transitions: Dictionary = {
	GameState.State.MAIN_MENU: [
		GameState.State.LEVEL_SETUP,
		GameState.State.SETTINGS,
		GameState.State.EXIT
	],
	GameState.State.SETTINGS: [
		GameState.State.MAIN_MENU
	],
	GameState.State.LEVEL_SETUP: [
		GameState.State.MAIN_MENU,
		GameState.State.PLAYING
	],
	GameState.State.PLAYING: [
		GameState.State.PAUSED,
		GameState.State.GAME_OVER,
		GameState.State.LEVEL_COMPLETE,
		GameState.State.MAIN_MENU
	],
	GameState.State.PAUSED: [
		GameState.State.PLAYING,
		GameState.State.MAIN_MENU
	],
	GameState.State.GAME_OVER: [
		GameState.State.LEVEL_SETUP,
		GameState.State.MAIN_MENU
	],
	GameState.State.LEVEL_COMPLETE: [
		GameState.State.LEVEL_SETUP,
		GameState.State.MAIN_MENU
	],
	GameState.State.EXIT: []
}


func _ready() -> void:
	current_state = GameState.State.MAIN_MENU


## Request state transition
## Returns true if transition was valid and executed
func change_state(new_state: GameState.State) -> bool:
	# Check if transition is valid
	if not _is_valid_transition(current_state, new_state):
		push_warning("Invalid state transition: %s -> %s" % [
			GameState.state_to_string(current_state),
			GameState.state_to_string(new_state)
		])
		return false

	# Handle EXIT specially
	if new_state == GameState.State.EXIT:
		_handle_exit()
		return true

	# Store previous state
	previous_state = current_state
	var old_state := current_state
	current_state = new_state

	# Handle state-specific logic
	_on_state_changed(old_state, new_state)

	# Emit event via EventBus
	if EventBus:
		EventBus.emit_state_changed(old_state, new_state)

	print("[StateManager] %s -> %s" % [
		GameState.state_to_string(old_state),
		GameState.state_to_string(new_state)
	])

	return true


## Check if transition is valid
func _is_valid_transition(from: GameState.State, to: GameState.State) -> bool:
	if not _valid_transitions.has(from):
		return false
	return to in _valid_transitions[from]


## Handle state-specific logic on transition
func _on_state_changed(old_state: GameState.State, new_state: GameState.State) -> void:
	# Reset RuntimeState when going to MAIN_MENU
	if new_state == GameState.State.MAIN_MENU:
		if RuntimeState:
			RuntimeState.reset()

	# Reset RuntimeState when starting level
	if new_state == GameState.State.PLAYING and old_state == GameState.State.LEVEL_SETUP:
		if RuntimeState:
			RuntimeState.reset()
			RuntimeState.is_level_active = true

	# Freeze on pause
	if new_state == GameState.State.PAUSED:
		if RuntimeState:
			RuntimeState.is_frozen = true

	# Unfreeze on resume
	if new_state == GameState.State.PLAYING and old_state == GameState.State.PAUSED:
		if RuntimeState:
			RuntimeState.is_frozen = false

	# Freeze on game over / level complete
	if new_state in [GameState.State.GAME_OVER, GameState.State.LEVEL_COMPLETE]:
		if RuntimeState:
			RuntimeState.is_frozen = true
			RuntimeState.is_level_active = false


## Handle application exit
func _handle_exit() -> void:
	print("[StateManager] Exiting application...")
	get_tree().quit()


## Helper: is game currently in playable state
func is_playing() -> bool:
	return current_state == GameState.State.PLAYING


## Helper: is game paused
func is_paused() -> bool:
	return current_state == GameState.State.PAUSED


## Helper: is game frozen (paused, game over, level complete)
func is_frozen() -> bool:
	return current_state in [
		GameState.State.PAUSED,
		GameState.State.GAME_OVER,
		GameState.State.LEVEL_COMPLETE
	]


## Helper: is in menu state
func is_in_menu() -> bool:
	return current_state in [
		GameState.State.MAIN_MENU,
		GameState.State.SETTINGS,
		GameState.State.LEVEL_SETUP
	]
