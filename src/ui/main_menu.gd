## main_menu.gd
## Main menu screen.
## CANON: UI changes ONLY GameConfig, does NOT control gameplay entities.
extends Control


func _ready() -> void:
	print("[MainMenu] Ready")


func _on_new_game_pressed() -> void:
	if StateManager:
		StateManager.change_state(GameState.State.LEVEL_SETUP)


func _on_settings_pressed() -> void:
	if StateManager:
		StateManager.change_state(GameState.State.SETTINGS)


func _on_exit_pressed() -> void:
	if StateManager:
		StateManager.change_state(GameState.State.EXIT)
