extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LAYOUT_DOOR_SYSTEM_SCRIPT := preload("res://src/systems/layout_door_system.gd")
const LEVEL_MVP_SCENE := preload("res://scenes/levels/level_mvp.tscn")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeLayout:
	extends RefCounted

	var valid: bool = true
	var doors: Array = [Rect2(-60.0, -6.0, 120.0, 12.0)]
	var _entry_gate: Rect2 = Rect2()

	func _door_wall_thickness() -> float:
		return 16.0


func _ready() -> void:
	if embedded_mode:
		return
	var result = await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("DOOR INTERACTION FLOW TEST")
	print("============================================================")

	await _test_interact_toggle_flow()
	await _test_kick_flow()
	await _test_out_of_range_commands()
	await _test_level_input_controller_integration()

	_t.summary("DOOR INTERACTION FLOW RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_interact_toggle_flow() -> void:
	var world = await _create_door_world()
	var door_system = world["door_system"]
	var door = world["door"]
	var source_pos = _door_opening_center(door)
	var hinge_distance = source_pos.distance_to(door.global_position)
	var opening_distance = _door_opening_distance(door, source_pos)
	_t.run_test("precondition: interact point uses opening (outside 20px hinge)", hinge_distance > 20.0 and opening_distance <= 0.1)

	var nearest = door_system.find_nearest_door(source_pos, 20.0)
	_t.run_test("find_nearest_door returns reachable door", nearest == door)

	var opened_cmd_ok = door_system.interact_toggle(source_pos, 20.0)
	var opened = await _wait_for_angle_at_least(door, 10.0, 200)
	_t.run_test("door_interact opens closed door", opened_cmd_ok and opened)

	var closed_cmd_ok = door_system.interact_toggle(source_pos, 20.0)
	var closed = await _wait_for_closed(door, 420)
	_t.run_test("door_interact toggles opened door to close", closed_cmd_ok and closed)

	await _free_world(world)


func _test_kick_flow() -> void:
	var world = await _create_door_world()
	var door_system = world["door_system"]
	var door = world["door"]
	var source_pos = _door_opening_center(door)
	var hinge_distance = source_pos.distance_to(door.global_position)
	var opening_distance = _door_opening_distance(door, source_pos)
	_t.run_test("precondition: kick point uses opening (outside 40px hinge)", hinge_distance > 40.0 and opening_distance <= 0.1)

	door.reset_to_closed()
	await get_tree().physics_frame
	var kick_ok = door_system.kick(source_pos, 40.0)
	var opened = await _wait_for_angle_at_least(door, 10.0, 200)
	_t.run_test("door_kick force-opens door", kick_ok and opened)

	await _free_world(world)


func _test_out_of_range_commands() -> void:
	var world = await _create_door_world()
	var door_system = world["door_system"]
	var door = world["door"]
	var far_pos = _door_opening_center(door) + Vector2(300.0, 300.0)

	door.reset_to_closed()
	await get_tree().physics_frame

	var nearest_far = door_system.find_nearest_door(far_pos, 20.0)
	var interact_ok = door_system.interact_toggle(far_pos, 20.0)
	var kick_ok = door_system.kick(far_pos, 40.0)

	for _i in range(60):
		await get_tree().physics_frame

	var m = door.get_debug_metrics() as Dictionary
	var angle_deg = absf(float(m.get("angle_deg", 0.0)))
	_t.run_test("find_nearest_door returns null outside radius", nearest_far == null)
	_t.run_test("door_interact does nothing outside 20px", not interact_ok)
	_t.run_test("door_kick does nothing outside 40px", not kick_ok)
	_t.run_test("Out-of-range commands keep door closed", angle_deg <= 1.2)

	await _free_world(world)


func _create_door_world() -> Dictionary:
	var root = Node2D.new()
	add_child(root)

	var doors_parent = Node2D.new()
	root.add_child(doors_parent)

	var door_system = LAYOUT_DOOR_SYSTEM_SCRIPT.new()
	root.add_child(door_system)
	door_system.initialize(doors_parent)
	door_system.rebuild_for_layout(FakeLayout.new())

	await get_tree().process_frame
	await get_tree().physics_frame

	var door = door_system.find_nearest_door(Vector2.ZERO, 9999.0)
	return {
		"root": root,
		"door_system": door_system,
		"door": door,
	}


func _door_opening_center(door: Node2D) -> Vector2:
	if door and door.has_method("get_opening_center_world"):
		return door.get_opening_center_world()
	return door.global_position if door else Vector2.ZERO


func _door_opening_distance(door: Node2D, source_pos: Vector2) -> float:
	if door and door.has_method("get_opening_distance_px"):
		return float(door.get_opening_distance_px(source_pos))
	if door:
		return source_pos.distance_to(door.global_position)
	return INF


func _wait_for_angle_at_least(door, min_angle_deg: float, frames: int) -> bool:
	for _i in range(frames):
		await get_tree().physics_frame
		var m = door.get_debug_metrics() as Dictionary
		if absf(float(m.get("angle_deg", 0.0))) >= min_angle_deg:
			return true
	return false


func _wait_for_closed(door, frames: int) -> bool:
	for _i in range(frames):
		await get_tree().physics_frame
		var m = door.get_debug_metrics() as Dictionary
		var angle_deg = absf(float(m.get("angle_deg", 0.0)))
		var av = absf(float(m.get("angular_velocity", 0.0)))
		if angle_deg <= 1.2 and av <= 0.1:
			return true
	return false


func _free_world(world: Dictionary) -> void:
	var root = world.get("root", null) as Node
	if root:
		root.queue_free()
	await get_tree().physics_frame


func _test_level_input_controller_integration() -> void:
	if embedded_mode:
		return
	var level = LEVEL_MVP_SCENE.instantiate()
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame

	var door_system = level.find_child("LayoutDoorSystem", true, false)
	var door = door_system.find_nearest_door(level.player.global_position, 9999.0)
	_t.run_test("level integration: LayoutDoorSystem available", door_system != null and door != null)
	if door_system == null or door == null:
		level.queue_free()
		await get_tree().process_frame
		return

	level.player.global_position = _door_opening_center(door)
	var door_selection_ok = door_system.find_nearest_door(level.player.global_position, 20.0) == door
	_t.run_test("level integration: opening-based nearest-door selection works at 20px", door_selection_ok)
	door.reset_to_closed()
	await get_tree().physics_frame

	Input.action_press("door_interact")
	await get_tree().process_frame
	await get_tree().physics_frame
	Input.action_release("door_interact")
	var opened = await _wait_for_angle_at_least(door, 10.0, 240)
	_t.run_test("level integration: door_interact route opens door end-to-end", opened)

	door.reset_to_closed()
	await get_tree().physics_frame

	Input.action_press("door_kick")
	await get_tree().process_frame
	Input.action_release("door_kick")
	var kicked_open = await _wait_for_angle_at_least(door, 10.0, 240)
	_t.run_test("level integration: door_kick route opens door end-to-end", kicked_open)

	level.queue_free()
	await get_tree().process_frame
