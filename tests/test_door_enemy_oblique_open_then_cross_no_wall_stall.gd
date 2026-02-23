extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LAYOUT_DOOR_SYSTEM_SCRIPT := preload("res://src/systems/layout_door_system.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeLayout:
	extends RefCounted

	var valid: bool = true
	var doors: Array = [Rect2(-60.0, -6.0, 120.0, 12.0)]
	var _entry_gate: Rect2 = Rect2()

	func _door_wall_thickness() -> float:
		return 16.0


class FakeNav:
	extends Node

	func can_enemy_traverse_point(_enemy: Node, _point: Vector2) -> bool:
		return true

	func build_policy_valid_path(_from: Vector2, to: Vector2, _enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		return {"status": "ok", "path_points": [to], "reason": "ok"}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("DOOR: ENEMY OBLIQUE OPEN THEN CROSS WITHOUT WALL STALL TEST")
	print("============================================================")

	await _test_door_open_resets_repath_timer_for_crossing()

	_t.summary("DOOR: ENEMY OBLIQUE OPEN THEN CROSS WITHOUT WALL STALL RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_door_open_resets_repath_timer_for_crossing() -> void:
	var world := await _create_world()
	var door := world.get("door", null) as Node2D
	var door_system := world.get("door_system", null) as Node
	var root := world.get("root", null) as Node2D

	var enemy := TestHelpers.spawn_mover(root, Vector2(26.0, 58.0), 2, 1, "enemies")
	enemy.set_meta("door_system", door_system)
	var nav := FakeNav.new()
	root.add_child(nav)

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(enemy, null, 2.4)
	pursuit.configure_navigation(nav, 0)
	var target := Vector2(-14.0, -120.0)

	var opened := false
	var timer_when_opened := -1.0
	for _i in range(420):
		pursuit.call("_execute_move_to_target", 1.0 / 60.0, target, 1.0, 2.0)
		await get_tree().physics_frame
		var metrics := door.get_debug_metrics() as Dictionary
		var angle_deg := absf(float(metrics.get("angle_deg", 0.0)))
		if angle_deg > 0.5:
			opened = true
			timer_when_opened = float(pursuit.get("_repath_timer"))
			break

	_t.run_test("setup: enemy opens door from oblique approach", opened)
	_t.run_test("door open event forces immediate repath reset", opened and timer_when_opened <= 0.001)

	enemy.queue_free()
	await _free_world(world)


func _create_world() -> Dictionary:
	var root := Node2D.new()
	add_child(root)

	TestHelpers.add_wall(root, Vector2(-180.0, 0.0), Vector2(240.0, 16.0))
	TestHelpers.add_wall(root, Vector2(180.0, 0.0), Vector2(240.0, 16.0))

	var doors_parent := Node2D.new()
	doors_parent.name = "LayoutDoors"
	root.add_child(doors_parent)

	var door_system := LAYOUT_DOOR_SYSTEM_SCRIPT.new()
	door_system.name = "LayoutDoorSystem"
	root.add_child(door_system)
	door_system.initialize(doors_parent)
	door_system.rebuild_for_layout(FakeLayout.new())

	await get_tree().process_frame
	await get_tree().physics_frame

	var door: Node2D = door_system.find_nearest_door(Vector2.ZERO, 9999.0)
	return {
		"root": root,
		"door_system": door_system,
		"door": door,
	}


func _free_world(world: Dictionary) -> void:
	var root := world.get("root", null) as Node
	if root:
		root.queue_free()
	await get_tree().physics_frame
