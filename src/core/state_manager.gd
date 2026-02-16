## state_manager.gd
## Singleton for game state transitions.
## CANON: Transitions only via GameStateManager.
## CANON: UI does NOT control gameplay entities directly.
extends Node

const GAME_STATE_SCRIPT := preload("res://src/core/game_state.gd")

## Current game state
var current_state: GAME_STATE_SCRIPT.State = GAME_STATE_SCRIPT.State.MAIN_MENU

## Previous state (for back navigation)
var previous_state: GAME_STATE_SCRIPT.State = GAME_STATE_SCRIPT.State.MAIN_MENU

## Valid state transitions map
## Key: from state, Value: array of valid target states
var _valid_transitions: Dictionary = {
	GAME_STATE_SCRIPT.State.MAIN_MENU: [
		GAME_STATE_SCRIPT.State.LEVEL_SETUP,
		GAME_STATE_SCRIPT.State.SETTINGS,
		GAME_STATE_SCRIPT.State.EXIT
	],
	GAME_STATE_SCRIPT.State.SETTINGS: [
		GAME_STATE_SCRIPT.State.MAIN_MENU
	],
	GAME_STATE_SCRIPT.State.LEVEL_SETUP: [
		GAME_STATE_SCRIPT.State.MAIN_MENU,
		GAME_STATE_SCRIPT.State.PLAYING
	],
	GAME_STATE_SCRIPT.State.PLAYING: [
		GAME_STATE_SCRIPT.State.PAUSED,
		GAME_STATE_SCRIPT.State.GAME_OVER,
		GAME_STATE_SCRIPT.State.LEVEL_COMPLETE,
		GAME_STATE_SCRIPT.State.MAIN_MENU
	],
	GAME_STATE_SCRIPT.State.PAUSED: [
		GAME_STATE_SCRIPT.State.PLAYING,
		GAME_STATE_SCRIPT.State.MAIN_MENU
	],
	GAME_STATE_SCRIPT.State.GAME_OVER: [
		GAME_STATE_SCRIPT.State.LEVEL_SETUP,
		GAME_STATE_SCRIPT.State.MAIN_MENU
	],
	GAME_STATE_SCRIPT.State.LEVEL_COMPLETE: [
		GAME_STATE_SCRIPT.State.LEVEL_SETUP,
		GAME_STATE_SCRIPT.State.MAIN_MENU
	],
	GAME_STATE_SCRIPT.State.EXIT: []
}


func _ready() -> void:
	current_state = GAME_STATE_SCRIPT.State.MAIN_MENU


## Request state transition
## Returns true if transition was valid and executed
func change_state(new_state: GAME_STATE_SCRIPT.State) -> bool:
	# Check if transition is valid
	if not _is_valid_transition(current_state, new_state):
		push_warning("Invalid state transition: %s -> %s" % [
			GAME_STATE_SCRIPT.state_to_string(current_state),
			GAME_STATE_SCRIPT.state_to_string(new_state)
		])
		return false

	# Handle EXIT specially
	if new_state == GAME_STATE_SCRIPT.State.EXIT:
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
		GAME_STATE_SCRIPT.state_to_string(old_state),
		GAME_STATE_SCRIPT.state_to_string(new_state)
	])

	return true


## Check if transition is valid
func _is_valid_transition(from: GAME_STATE_SCRIPT.State, to: GAME_STATE_SCRIPT.State) -> bool:
	if not _valid_transitions.has(from):
		return false
	return to in _valid_transitions[from]


## Handle state-specific logic on transition
func _on_state_changed(old_state: GAME_STATE_SCRIPT.State, new_state: GAME_STATE_SCRIPT.State) -> void:
	# Reset RuntimeState when going to MAIN_MENU
	if new_state == GAME_STATE_SCRIPT.State.MAIN_MENU:
		if RuntimeState:
			RuntimeState.reset()

	# Reset RuntimeState when starting level
	if new_state == GAME_STATE_SCRIPT.State.PLAYING and old_state == GAME_STATE_SCRIPT.State.LEVEL_SETUP:
		if RuntimeState:
			RuntimeState.reset()
			RuntimeState.is_level_active = true

	# Freeze on pause
	if new_state == GAME_STATE_SCRIPT.State.PAUSED:
		if RuntimeState:
			RuntimeState.is_frozen = true

	# Unfreeze on resume
	if new_state == GAME_STATE_SCRIPT.State.PLAYING and old_state == GAME_STATE_SCRIPT.State.PAUSED:
		if RuntimeState:
			RuntimeState.is_frozen = false

	# Freeze on game over / level complete
	if new_state in [GAME_STATE_SCRIPT.State.GAME_OVER, GAME_STATE_SCRIPT.State.LEVEL_COMPLETE]:
		if RuntimeState:
			RuntimeState.is_frozen = true
			RuntimeState.is_level_active = false


## Handle application exit
func _handle_exit() -> void:
	print("[StateManager] Exiting application...")
	get_tree().quit()


## Helper: is game currently in playable state
func is_playing() -> bool:
	return current_state == GAME_STATE_SCRIPT.State.PLAYING


## Helper: is game paused
func is_paused() -> bool:
	return current_state == GAME_STATE_SCRIPT.State.PAUSED


## Helper: is game frozen (paused, game over, level complete)
func is_frozen() -> bool:
	return current_state in [
		GAME_STATE_SCRIPT.State.PAUSED,
		GAME_STATE_SCRIPT.State.GAME_OVER,
		GAME_STATE_SCRIPT.State.LEVEL_COMPLETE
	]


## Helper: is in menu state
func is_in_menu() -> bool:
	return current_state in [
		GAME_STATE_SCRIPT.State.MAIN_MENU,
		GAME_STATE_SCRIPT.State.SETTINGS,
		GAME_STATE_SCRIPT.State.LEVEL_SETUP
	]
