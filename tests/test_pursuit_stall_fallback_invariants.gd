extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeNavByDistance:
	extends Node

	var nav_lengths: Dictionary = {}
	var plan_contracts: Dictionary = {}

	func build_policy_valid_path(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null) -> Dictionary:
		var key := _key(to_pos)
		if plan_contracts.has(key):
			return (plan_contracts.get(key, {}) as Dictionary).duplicate(true)
		return {
			"status": "unreachable_geometry",
			"path_points": [],
			"reason": "stub_unreachable",
		}

	func nav_path_length(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null) -> float:
		return float(nav_lengths.get(_key(to_pos), INF))

	func _key(point: Vector2) -> String:
		return "%d:%d" % [int(round(point.x)), int(round(point.y))]


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("PURSUIT STALL/FALLBACK INVARIANTS TEST")
	print("============================================================")

	_test_stall_and_fallback_invariants()

	_t.summary("PURSUIT STALL/FALLBACK INVARIANTS RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_stall_and_fallback_invariants() -> void:
	var owner := CharacterBody2D.new()
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	add_child(owner)

	var nav := FakeNavByDistance.new()
	add_child(nav)
	_t.run_test(
		"fake nav omits legacy build_reachable_path_points API",
		not nav.has_method("build_reachable_path_points")
	)
	_t.run_test(
		"fake nav omits legacy build_path_points API",
		not nav.has_method("build_path_points")
	)

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	pursuit.configure_navigation(nav, 0)
	pursuit.call("_reset_stall_monitor")

	var w1 := pursuit.debug_feed_stall_window(7.0, 10.0) as Dictionary
	var w2 := pursuit.debug_feed_stall_window(6.5, 11.0) as Dictionary
	var w3 := pursuit.debug_feed_stall_window(12.0, 25.0) as Dictionary
	_t.run_test("two consecutive stalled windows trigger hard_stall", bool(w1.get("stalled_window", false)) and bool(w2.get("hard_stall", false)))
	_t.run_test("non-stalled window clears hard_stall", not bool(w3.get("hard_stall", true)) and int(w3.get("consecutive_windows", -1)) == 0)

	var target := Vector2(100.0, 100.0)
	var a := Vector2(110.0, 100.0)
	var b := Vector2(150.0, 100.0)
	var c := Vector2(90.0, 130.0)
	nav.nav_lengths[nav._key(a)] = 300.0
	nav.nav_lengths[nav._key(b)] = 120.0
	nav.nav_lengths[nav._key(c)] = 120.0

	var result1 := pursuit.debug_select_nearest_reachable_fallback(target, [a, b, c]) as Dictionary
	var result2 := pursuit.debug_select_nearest_reachable_fallback(target, [a, b, c]) as Dictionary
	var point1 := result1.get("point", Vector2.ZERO) as Vector2
	var point2 := result2.get("point", Vector2.ZERO) as Vector2
	_t.run_test("fallback selection deterministic for same inputs", point1 == point2)
	_t.run_test("fallback selects reachable candidate", bool(result1.get("found", false)) and point1 != Vector2.ZERO)

	var blocked_target := Vector2(220.0, 100.0)
	var fallback_target := blocked_target + Vector2(48.0, 0.0)
	nav.plan_contracts[nav._key(blocked_target)] = {
		"status": "unreachable_geometry",
		"path_points": [],
		"reason": "primary_unreachable",
	}
	nav.plan_contracts[nav._key(fallback_target)] = {
		"status": "ok",
		"path_points": [fallback_target],
		"reason": "ok",
	}
	nav.nav_lengths[nav._key(fallback_target)] = owner.global_position.distance_to(fallback_target)

	pursuit.call("_execute_move_to_target", 0.2, blocked_target, 1.0)
	var snap := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
	var picked_target := snap.get("policy_fallback_target", Vector2.ZERO) as Vector2
	var legacy_retry_key := "policy_" + "replan_attempts"
	_t.run_test("contract fallback starts after first failed plan", bool(snap.get("policy_fallback_used", false)) and picked_target.distance_to(fallback_target) <= 0.001)
	_t.run_test("planner contract reason is surfaced in snapshot", String(snap.get("path_failed_reason", "")) == "primary_unreachable")
	_t.run_test("planner snapshot exposes last contract status", String(snap.get("path_plan_status", "")) == "ok")
	_t.run_test("legacy retry counter key removed from snapshot", not snap.has(legacy_retry_key))

	owner.queue_free()
	nav.queue_free()
