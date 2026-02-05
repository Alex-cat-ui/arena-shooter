## pause_menu.gd
## Pause menu screen.
## CANON: ESC in PLAYING => PAUSED (full freeze).
extends Control

@onready var confirm_dialog: ConfirmationDialog = $ConfirmDialog


func _ready() -> void:
	print("[PauseMenu] Ready")


func _on_resume_button_pressed() -> void:
	if StateManager:
		StateManager.change_state(GameState.State.PLAYING)


func _on_exit_button_pressed() -> void:
	# Show confirmation dialog
	confirm_dialog.popup_centered()


func _on_confirm_dialog_confirmed() -> void:
	if StateManager:
		StateManager.change_state(GameState.State.MAIN_MENU)
