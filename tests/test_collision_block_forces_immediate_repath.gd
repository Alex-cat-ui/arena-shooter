extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeNav:
	extends Node

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func can_enemy_traverse_point(_enemy: Node, _point: Vector2) -> bool:
		return true

	func build_policy_valid_path(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		return {
			"status": "ok",
			"path_points": [to_pos],
			"reason": "ok",
		}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("COLLISION BLOCK FORCES IMMEDIATE REPATH TEST")
	print("============================================================")

	await _test_non_door_collision_forces_immediate_repath()

	_t.summary("COLLISION BLOCK FORCES IMMEDIATE REPATH RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_non_door_collision_forces_immediate_repath() -> void:
	var root := Node2D.new()
	add_child(root)
	TestHelpers.add_wall(root, Vector2.ZERO, Vector2(240.0, 16.0))
	var enemy := TestHelpers.spawn_mover(root, Vector2(0.0, 56.0), 1, 1, "enemies")
	var nav := FakeNav.new()
	root.add_child(nav)

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(enemy, null, 2.4)
	pursuit.configure_navigation(nav, 0)

	await get_tree().process_frame
	await get_tree().physics_frame

	var target := Vector2(0.0, -120.0)
	var collision_seen := false
	var collision_snapshot: Dictionary = {}
	for _i in range(180):
		pursuit.call("_execute_move_to_target", 1.0 / 60.0, target, 1.0, 2.0)
		collision_snapshot = pursuit.debug_get_navigation_policy_snapshot() as Dictionary
		if String(collision_snapshot.get("collision_kind", "")) == "non_door":
			collision_seen = true
			break
		await get_tree().physics_frame

	var waypoints_variant: Variant = pursuit.get("_waypoints")
	var waypoints := waypoints_variant as Array
	var repath_timer := float(pursuit.get("_repath_timer"))
	_t.run_test("non-door collision occurs against solid wall", collision_seen)
	_t.run_test(
		"collision forces immediate repath timer reset",
		collision_seen and repath_timer <= 0.001
	)
	_t.run_test(
		"collision marks path_failed_reason=collision_blocked",
		collision_seen and String(collision_snapshot.get("path_failed_reason", "")) == "collision_blocked"
	)
	_t.run_test(
		"collision clears active waypoint cache in same tick",
		collision_seen and waypoints.is_empty()
	)
	_t.run_test(
		"debug snapshot exposes collision classification contract",
		collision_snapshot.has("collision_kind")
			and collision_snapshot.has("collision_forced_repath")
			and collision_snapshot.has("collision_reason")
			and collision_snapshot.has("collision_index")
	)
	_t.run_test(
		"non-door collision snapshot reports forced_repath + index",
		collision_seen
			and bool(collision_snapshot.get("collision_forced_repath", false))
			and String(collision_snapshot.get("collision_reason", "")) == "collision_blocked"
			and int(collision_snapshot.get("collision_index", -1)) >= 0
	)

	root.queue_free()
	await get_tree().physics_frame
