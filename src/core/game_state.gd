## game_state.gd
## Enum definitions for game states.
## CANON: States must match ТЗ exactly.
class_name GameState
extends RefCounted

## All possible game states per CANON spec
enum State {
	MAIN_MENU,
	LEVEL_SETUP,
	PLAYING,
	PAUSED,
	SETTINGS,
	GAME_OVER,
	LEVEL_COMPLETE,
	EXIT
}

## Helper to convert state to string for debug
static func state_to_string(state: State) -> String:
	match state:
		State.MAIN_MENU: return "MAIN_MENU"
		State.LEVEL_SETUP: return "LEVEL_SETUP"
		State.PLAYING: return "PLAYING"
		State.PAUSED: return "PAUSED"
		State.SETTINGS: return "SETTINGS"
		State.GAME_OVER: return "GAME_OVER"
		State.LEVEL_COMPLETE: return "LEVEL_COMPLETE"
		State.EXIT: return "EXIT"
		_: return "UNKNOWN"
