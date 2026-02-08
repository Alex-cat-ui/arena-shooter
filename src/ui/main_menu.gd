## main_menu.gd
## Main menu screen with hover animations and subtle animated background.
## CANON: UI changes ONLY GameConfig, does NOT control gameplay entities.
extends Control

## Button references (resolved dynamically)
var _buttons: Array[Button] = []


func _ready() -> void:
	print("[MainMenu] Ready")

	# Find all buttons in the menu
	_find_buttons(self)

	# Setup hover animations for each button
	for btn in _buttons:
		btn.mouse_entered.connect(_on_button_hover.bind(btn))
		btn.mouse_exited.connect(_on_button_unhover.bind(btn))
		# Initial state: slightly transparent
		btn.modulate = Color(0.85, 0.85, 0.85, 0.9)

	# Start subtle background animation
	var bg := get_node_or_null("Background")
	if bg and bg is ColorRect:
		_animate_background(bg as ColorRect)


func _find_buttons(node: Node) -> void:
	if node is Button:
		_buttons.append(node as Button)
	for child in node.get_children():
		_find_buttons(child)


func _on_button_hover(btn: Button) -> void:
	var tween := btn.create_tween()
	tween.tween_property(btn, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15).set_ease(Tween.EASE_OUT)


func _on_button_unhover(btn: Button) -> void:
	var tween := btn.create_tween()
	tween.tween_property(btn, "modulate", Color(0.85, 0.85, 0.85, 0.9), 0.2).set_ease(Tween.EASE_IN)


func _animate_background(bg: ColorRect) -> void:
	# Subtle pulsing background color
	var base_color := bg.color
	var tween := bg.create_tween()
	tween.set_loops()
	var darker := Color(base_color.r * 0.85, base_color.g * 0.85, base_color.b * 0.85, 1.0)
	tween.tween_property(bg, "color", darker, 3.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(bg, "color", base_color, 3.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _on_new_game_pressed() -> void:
	if StateManager:
		StateManager.change_state(GameState.State.LEVEL_SETUP)


func _on_settings_pressed() -> void:
	if StateManager:
		StateManager.change_state(GameState.State.SETTINGS)


func _on_exit_pressed() -> void:
	if StateManager:
		StateManager.change_state(GameState.State.EXIT)
