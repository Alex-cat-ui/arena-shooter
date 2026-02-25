extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeDetourNav:
	extends Node

	var direct_calls: int = 0
	var detour_calls: int = 0

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func can_enemy_traverse_point(_enemy: Node, _point: Vector2) -> bool:
		return true

	func build_policy_valid_path(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		if direct_calls == 0:
			direct_calls += 1
			return {
				"status": "ok",
				"path_points": [to_pos],
				"reason": "ok",
			}
		detour_calls += 1
		return {
			"status": "ok",
			"path_points": [
				Vector2(52.0, 96.0),
				Vector2(168.0, 96.0),
				to_pos,
			],
			"reason": "ok",
		}


class FakePatrolDecision:
	extends RefCounted

	var fixed_target: Vector2 = Vector2.ZERO
	var fixed_speed_scale: float = 1.0

	func _init(target: Vector2, speed_scale: float = 1.0) -> void:
		fixed_target = target
		fixed_speed_scale = speed_scale

	func configure(_nav_system: Node, _home_room_id: int) -> void:
		pass

	func update(_delta: float, _facing_dir: Vector2) -> Dictionary:
		return {
			"waiting": false,
			"target": fixed_target,
			"speed_scale": fixed_speed_scale,
		}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("PATROL OBSTACLE AVOIDANCE WALL TEST")
	print("============================================================")

	await _test_patrol_detours_wall_and_keeps_progress()

	_t.summary("PATROL OBSTACLE AVOIDANCE WALL RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_patrol_detours_wall_and_keeps_progress() -> void:
	var root := Node2D.new()
	add_child(root)
	TestHelpers.add_wall(root, Vector2(100.0, 0.0), Vector2(24.0, 220.0))
	var enemy := TestHelpers.spawn_mover(root, Vector2(0.0, 0.0), 1, 1, "enemies")
	var nav := FakeDetourNav.new()
	root.add_child(nav)

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(enemy, null, 2.4)
	pursuit.configure_navigation(nav, 0)
	var patrol_target := Vector2(220.0, 0.0)
	pursuit.set("_patrol", FakePatrolDecision.new(patrol_target, 1.0))

	await get_tree().process_frame
	await get_tree().physics_frame

	var initial_distance := enemy.global_position.distance_to(patrol_target)
	var moved_total := 0.0
	var prev_pos := enemy.global_position
	var collision_seen := false
	var collision_forced_repath := false
	var detour_lane_seen := false
	var max_stall_streak := 0
	var stall_streak := 0

	for _i in range(300):
		pursuit.execute_intent(
			1.0 / 60.0,
			{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL},
			_patrol_context(patrol_target)
		)
		await get_tree().physics_frame

		var current_pos := enemy.global_position
		var step_px := current_pos.distance_to(prev_pos)
		moved_total += step_px
		if step_px < 0.08 and current_pos.distance_to(patrol_target) > 28.0:
			stall_streak += 1
		else:
			max_stall_streak = maxi(max_stall_streak, stall_streak)
			stall_streak = 0
		prev_pos = current_pos

		var snapshot := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
		if String(snapshot.get("collision_kind", "")) == "non_door":
			collision_seen = true
			collision_forced_repath = collision_forced_repath or bool(snapshot.get("collision_forced_repath", false))
		if current_pos.x >= 40.0 and absf(current_pos.y) >= 24.0:
			detour_lane_seen = true
		if current_pos.distance_to(patrol_target) <= 20.0:
			break

	max_stall_streak = maxi(max_stall_streak, stall_streak)
	var final_distance := enemy.global_position.distance_to(patrol_target)

	_t.run_test("patrol wall: enemy makes progress toward target", final_distance < initial_distance)
	_t.run_test("patrol wall: movement is non-trivial", moved_total > 40.0)
	_t.run_test("patrol wall: enemy enters detour lane around wall", detour_lane_seen)
	_t.run_test("patrol wall: no long wall-grind streak", max_stall_streak <= 45)
	_t.run_test("patrol wall: fallback collision-repath contract holds when collision occurs", (not collision_seen) or collision_forced_repath)
	_t.run_test("patrol wall: planner switches from direct to detour", nav.direct_calls >= 1 and nav.detour_calls >= 1)

	root.queue_free()
	await get_tree().physics_frame


func _patrol_context(player_pos: Vector2) -> Dictionary:
	return {
		"player_pos": player_pos,
		"known_target_pos": Vector2.ZERO,
		"last_seen_pos": Vector2.ZERO,
		"investigate_anchor": Vector2.ZERO,
		"home_position": Vector2.ZERO,
		"alert_level": 0,
		"los": false,
		"combat_lock": false,
	}
