## level_complete.gd
## Level complete screen.
## CANON: Retry (to LEVEL_SETUP) / Exit to Menu (GameConfig not reset).
extends Control

@onready var stats_label: Label = $VBoxContainer/StatsLabel


func _ready() -> void:
	print("[LevelComplete] Ready")
	_show_stats()


func _show_stats() -> void:
	if RuntimeState:
		stats_label.text = """VICTORY!

Time: %.1f sec
Total Kills: %d
Damage Dealt: %d
Damage Received: %d""" % [
			RuntimeState.time_elapsed,
			RuntimeState.kills,
			RuntimeState.damage_dealt,
			RuntimeState.damage_received
		]


func _on_retry_button_pressed() -> void:
	# CANON: GameConfig NOT reset on retry
	if StateManager:
		StateManager.change_state(GameState.State.LEVEL_SETUP)


func _on_exit_button_pressed() -> void:
	if StateManager:
		StateManager.change_state(GameState.State.MAIN_MENU)
