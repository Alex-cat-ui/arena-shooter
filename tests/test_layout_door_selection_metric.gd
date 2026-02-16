extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LAYOUT_DOOR_SYSTEM_SCRIPT := preload("res://src/systems/layout_door_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class SingleDoorLayout:
	extends RefCounted

	var valid: bool = true
	var doors: Array = [Rect2(-60.0, -6.0, 120.0, 12.0)]
	var _entry_gate: Rect2 = Rect2()

	func _door_wall_thickness() -> float:
		return 16.0


class TwoDoorLayout:
	extends RefCounted

	var valid: bool = true
	var doors: Array = [
		Rect2(-60.0, -6.0, 120.0, 12.0),
		Rect2(30.0, -6.0, 120.0, 12.0),
	]
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
	print("LAYOUT DOOR SELECTION METRIC TEST")
	print("============================================================")

	await _test_radius_gate_uses_opening_distance()
	await _test_nearest_prefers_opening_metric_over_hinge_metric()

	_t.summary("LAYOUT DOOR SELECTION METRIC RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_radius_gate_uses_opening_distance() -> void:
	var world = await _create_world(SingleDoorLayout.new())
	var door_system = world["door_system"]
	var door = world["doors"][0] as Node2D
	var source = _door_opening_center(door)
	var hinge_distance = source.distance_to(door.global_position)
	var opening_distance = _door_opening_distance(door, source)
	var nearest = door_system.find_nearest_door(source, 20.0)

	_t.run_test("precondition: opening point is outside hinge radius 20px", hinge_distance > 20.0 and opening_distance <= 0.1)
	_t.run_test("radius gate uses opening distance (20px interact)", nearest == door)

	await _free_world(world)


func _test_nearest_prefers_opening_metric_over_hinge_metric() -> void:
	var world = await _create_world(TwoDoorLayout.new())
	var door_system = world["door_system"]
	var doors = world["doors"] as Array
	var door_a = _door_with_closest_opening_x(doors, 0.0)
	var door_b = _door_with_closest_opening_x(doors, 90.0)
	var source = Vector2(10.0, 0.0)

	var hinge_a = source.distance_to(door_a.global_position)
	var hinge_b = source.distance_to(door_b.global_position)
	var opening_a = _door_opening_distance(door_a, source)
	var opening_b = _door_opening_distance(door_b, source)
	var nearest = door_system.find_nearest_door(source, 9999.0)

	_t.run_test("precondition: hinge metric would choose door B", hinge_b < hinge_a)
	_t.run_test("precondition: opening metric should choose door A", opening_a < opening_b)
	_t.run_test("nearest door is selected by opening metric", nearest == door_a)

	await _free_world(world)


func _create_world(layout) -> Dictionary:
	var root = Node2D.new()
	add_child(root)

	var doors_parent = Node2D.new()
	root.add_child(doors_parent)

	var door_system = LAYOUT_DOOR_SYSTEM_SCRIPT.new()
	root.add_child(door_system)
	door_system.initialize(doors_parent)
	door_system.rebuild_for_layout(layout)

	await get_tree().process_frame
	await get_tree().physics_frame

	return {
		"root": root,
		"doors_parent": doors_parent,
		"door_system": door_system,
		"doors": doors_parent.get_children(),
	}


func _free_world(world: Dictionary) -> void:
	var root = world.get("root", null) as Node
	if root:
		root.queue_free()
	await get_tree().physics_frame


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


func _door_with_closest_opening_x(doors: Array, target_x: float) -> Node2D:
	var best: Node2D = null
	var best_delta := INF
	for door_variant in doors:
		var door = door_variant as Node2D
		if not door:
			continue
		var delta = absf(_door_opening_center(door).x - target_x)
		if delta < best_delta:
			best_delta = delta
			best = door
	return best
