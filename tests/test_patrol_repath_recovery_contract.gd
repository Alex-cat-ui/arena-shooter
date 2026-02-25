extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeBlockedNav:
	extends Node

	var blocked_point: Vector2 = Vector2(84.0, 0.0)
	var plan_calls: int = 0

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func can_enemy_traverse_point(_enemy: Node, _point: Vector2) -> bool:
		return true

	func build_policy_valid_path(_from_pos: Vector2, _to_pos: Vector2, _enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		plan_calls += 1
		return {
			"status": "unreachable_policy",
			"path_points": [],
			"reason": "policy_blocked",
			"segment_index": 0,
			"blocked_point": blocked_point,
		}


class FakePatrolDecision:
	extends RefCounted

	var fixed_target: Vector2 = Vector2.ZERO

	func _init(target: Vector2) -> void:
		fixed_target = target

	func configure(_nav_system: Node, _home_room_id: int) -> void:
		pass

	func update(_delta: float, _facing_dir: Vector2) -> Dictionary:
		return {
			"waiting": false,
			"target": fixed_target,
			"speed_scale": 1.0,
		}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("PATROL REPATH RECOVERY CONTRACT TEST")
	print("============================================================")

	await _test_repeated_blocked_point_reports_recovery_feedback_without_oscillation()

	_t.summary("PATROL REPATH RECOVERY CONTRACT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_repeated_blocked_point_reports_recovery_feedback_without_oscillation() -> void:
	var root := Node2D.new()
	add_child(root)
	var enemy := TestHelpers.spawn_mover(root, Vector2.ZERO, 1, 1, "enemies")
	var nav := FakeBlockedNav.new()
	root.add_child(nav)

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(enemy, null, 2.4)
	pursuit.configure_navigation(nav, 0)
	var patrol_target := Vector2(180.0, 0.0)
	pursuit.set("_patrol", FakePatrolDecision.new(patrol_target))

	await get_tree().process_frame
	await get_tree().physics_frame

	var max_repeat_count := 0
	var blocked_point_valid_seen := false
	var failure_surface_consistent := true
	var moved_total := 0.0
	var max_step_px := 0.0
	var prev_pos := enemy.global_position
	var bucket_valid_seen := false

	for _i in range(24):
		var result := pursuit.execute_intent(
			1.0 / 60.0,
			{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL},
			_patrol_context(patrol_target)
		) as Dictionary
		await get_tree().physics_frame
		var step_px := enemy.global_position.distance_to(prev_pos)
		moved_total += step_px
		max_step_px = maxf(max_step_px, step_px)
		prev_pos = enemy.global_position

		max_repeat_count = maxi(max_repeat_count, int(result.get("repath_recovery_repeat_count", 0)))
		blocked_point_valid_seen = blocked_point_valid_seen or bool(result.get("repath_recovery_blocked_point_valid", false))
		failure_surface_consistent = (
			failure_surface_consistent
			and bool(result.get("path_failed", false))
			and String(result.get("path_failed_reason", "")) == "policy_blocked"
		)
		var snapshot := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
		bucket_valid_seen = bucket_valid_seen or bool(snapshot.get("blocked_point_repeat_bucket_valid", false))

	_t.run_test("patrol repath recovery: blocked-point repeat counter reaches threshold", max_repeat_count >= 2)
	_t.run_test("patrol repath recovery: blocked-point validity feedback is exposed", blocked_point_valid_seen)
	_t.run_test("patrol repath recovery: blocked path failure surface stays deterministic", failure_surface_consistent)
	_t.run_test("patrol repath recovery: blocked-point bucket state is tracked", bucket_valid_seen)
	_t.run_test("patrol repath recovery: no oscillation with zero-progress spam", moved_total <= 6.0 and max_step_px <= 2.0)
	_t.run_test("patrol repath recovery: planner is retried repeatedly", nav.plan_calls >= 6)

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
