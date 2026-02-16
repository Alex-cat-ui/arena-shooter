## main_menu.gd
## Main menu screen with hover animations and subtle animated background.
## CANON: UI changes ONLY GameConfig, does NOT control gameplay entities.
extends Control

const GameState = preload("res://src/core/game_state.gd")
const STEALTH_TEST_SCENE_PATH := "res://src/levels/stealth_test_room.tscn"

## Button references (resolved dynamically)
var _buttons: Array[Button] = []
@onready var _status_label: Label = $VBoxContainer/StatusLabel


func _ready() -> void:
	print("[MainMenu] Ready")
	_set_status_message("")

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


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null:
		return
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_F8:
		open_stealth_test_scene(true)


func _on_stealth_test_pressed() -> void:
	open_stealth_test_scene(true)


func _on_settings_pressed() -> void:
	if StateManager:
		StateManager.change_state(GameState.State.SETTINGS)


func _on_exit_pressed() -> void:
	if StateManager:
		StateManager.change_state(GameState.State.EXIT)


func open_stealth_test_scene(perform_change: bool = true) -> int:
	_set_status_message("")
	var validation := _validate_stealth_scene_load()
	var load_code := int(validation.get("code", ERR_CANT_OPEN))
	if load_code != OK:
		_report_stealth_scene_error(String(validation.get("message", "Unknown load error.")), load_code)
		return load_code

	if not perform_change:
		return OK

	var tree := get_tree()
	if tree == null:
		_report_stealth_scene_error("SceneTree is unavailable, cannot switch to Stealth Test.", ERR_UNAVAILABLE)
		return ERR_UNAVAILABLE

	var err := tree.change_scene_to_file(STEALTH_TEST_SCENE_PATH)
	if err != OK:
		_report_stealth_scene_error("Scene switch failed while opening Stealth Test.", err)
		return err
	return OK


func _validate_stealth_scene_load() -> Dictionary:
	if not ResourceLoader.exists(STEALTH_TEST_SCENE_PATH):
		return {
			"code": ERR_FILE_NOT_FOUND,
			"message": "Scene file missing: %s" % STEALTH_TEST_SCENE_PATH,
		}

	var scene_res := load(STEALTH_TEST_SCENE_PATH)
	if scene_res == null:
		return {
			"code": ERR_PARSE_ERROR,
			"message": "Scene parse/import failed. Check Godot errors in console for missing assets/scripts.",
		}
	if not (scene_res is PackedScene):
		return {
			"code": ERR_CANT_OPEN,
			"message": "Resource loaded, but it is not a PackedScene: %s" % STEALTH_TEST_SCENE_PATH,
		}
	return {"code": OK, "message": ""}


func _report_stealth_scene_error(message: String, err_code: int) -> void:
	var full := "[MainMenu] Stealth Test unavailable: %s (err=%d)" % [message, err_code]
	push_error(full)
	_set_status_message("Stealth Test unavailable.\n%s\n(code=%d)" % [message, err_code], true)


func _set_status_message(message: String, is_error: bool = false) -> void:
	if _status_label == null:
		return
	_status_label.text = message
	_status_label.visible = message != ""
	_status_label.modulate = Color(1.0, 0.35, 0.35, 1.0) if is_error else Color(0.75, 0.8, 0.9, 1.0)
