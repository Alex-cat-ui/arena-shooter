extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LEVEL_CONTEXT_SCRIPT := preload("res://src/levels/level_context.gd")
const LEVEL_INPUT_CONTROLLER_SCRIPT := preload("res://src/levels/level_input_controller.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _regen_calls: int = 0
var _god_toggle_calls: int = 0
var _open_test_scene_calls: int = 0


class FakeDoorSystem:
	extends Node

	var interact_calls: Array = []
	var kick_calls: Array = []

	func interact_toggle(pos: Vector2, radius: float) -> bool:
		interact_calls.append({"pos": pos, "radius": radius})
		return true

	func kick(pos: Vector2, radius: float) -> bool:
		kick_calls.append({"pos": pos, "radius": radius})
		return true


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("LEVEL INPUT CONTROLLER TEST")
	print("============================================================")

	await _test_pause_toggle()
	await _test_debug_toggle_and_door_actions()
	_test_unhandled_key_callbacks()

	_t.summary("LEVEL INPUT CONTROLLER RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_pause_toggle() -> void:
	var ctx = LEVEL_CONTEXT_SCRIPT.new()
	var controller = LEVEL_INPUT_CONTROLLER_SCRIPT.new()

	if StateManager.current_state != GameState.State.MAIN_MENU:
		StateManager.change_state(GameState.State.MAIN_MENU)
	StateManager.change_state(GameState.State.LEVEL_SETUP)
	StateManager.change_state(GameState.State.PLAYING)

	Input.action_press("pause")
	controller.handle_input(ctx)
	Input.action_release("pause")
	_t.run_test("pause action toggles PLAYING -> PAUSED", StateManager.current_state == GameState.State.PAUSED)

	Input.action_press("pause")
	controller.handle_input(ctx)
	Input.action_release("pause")
	_t.run_test("pause action toggles PAUSED -> PLAYING", StateManager.current_state == GameState.State.PLAYING)

	StateManager.change_state(GameState.State.MAIN_MENU)


func _test_debug_toggle_and_door_actions() -> void:
	var ctx = LEVEL_CONTEXT_SCRIPT.new()
	ctx.debug_container = VBoxContainer.new()
	ctx.player = CharacterBody2D.new()
	ctx.player.global_position = Vector2(10.0, 20.0)
	ctx.layout_door_system = FakeDoorSystem.new()
	add_child(ctx.player)
	add_child(ctx.layout_door_system)

	var controller = LEVEL_INPUT_CONTROLLER_SCRIPT.new()
	ctx.debug_overlay_visible = false
	GameConfig.debug_overlay_visible = false

	Input.action_press("debug_toggle")
	controller.handle_input(ctx)
	Input.action_release("debug_toggle")
	_t.run_test("debug_toggle flips context visibility", ctx.debug_overlay_visible == true)
	_t.run_test("debug_toggle updates debug container visibility", ctx.debug_container.visible == true)
	_t.run_test("debug_toggle syncs GameConfig flag", GameConfig.debug_overlay_visible == true)

	Input.action_press("door_interact")
	controller.handle_input(ctx)
	Input.action_release("door_interact")
	var interact_calls := (ctx.layout_door_system as FakeDoorSystem).interact_calls
	_t.run_test("door_interact routed with strict 20px radius",
		interact_calls.size() == 1 and is_equal_approx(float(interact_calls[0]["radius"]), 20.0))

	Input.action_press("door_kick")
	controller.handle_input(ctx)
	Input.action_release("door_kick")
	var kick_calls := (ctx.layout_door_system as FakeDoorSystem).kick_calls
	_t.run_test("door_kick routed with strict 40px radius",
		kick_calls.size() == 1 and is_equal_approx(float(kick_calls[0]["radius"]), 40.0))

	ctx.player.queue_free()
	ctx.layout_door_system.queue_free()
	ctx.debug_container.free()
	await get_tree().process_frame


func _test_unhandled_key_callbacks() -> void:
	_regen_calls = 0
	_god_toggle_calls = 0
	_open_test_scene_calls = 0

	var controller = LEVEL_INPUT_CONTROLLER_SCRIPT.new()
	controller.configure_callbacks(
		Callable(self, "_on_regen_callback"),
		Callable(self, "_on_god_toggle_callback"),
		Callable(self, "_on_open_test_scene_callback")
	)

	controller.handle_unhandled_key_input(null, _key_event(KEY_F4))
	var f8_bound_before := controller._is_key_assigned_in_input_map(KEY_F8)
	controller.handle_unhandled_key_input(null, _key_event(KEY_F8))

	_t.run_test("F4 triggers on_regenerate_layout callback", _regen_calls == 1)
	_t.run_test(
		"F8 uses fallback when key is free",
		(f8_bound_before and _god_toggle_calls == 1 and _open_test_scene_calls == 0) or
		(not f8_bound_before and _god_toggle_calls == 0 and _open_test_scene_calls == 1)
	)

	var temp_f8_action: StringName = &"test_level_input_controller_temp_f8_binding"
	if InputMap.has_action(temp_f8_action):
		InputMap.erase_action(temp_f8_action)
	InputMap.add_action(temp_f8_action)
	var f8_event := InputEventKey.new()
	f8_event.keycode = KEY_F8
	InputMap.action_add_event(temp_f8_action, f8_event)

	controller.handle_unhandled_key_input(null, _key_event(KEY_F8))
	_t.run_test("F8 triggers on_toggle_god_mode callback when key is assigned", _god_toggle_calls >= 1)

	InputMap.erase_action(temp_f8_action)


func _key_event(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = false
	return event


func _on_regen_callback() -> void:
	_regen_calls += 1


func _on_god_toggle_callback() -> void:
	_god_toggle_calls += 1


func _on_open_test_scene_callback() -> void:
	_open_test_scene_calls += 1
