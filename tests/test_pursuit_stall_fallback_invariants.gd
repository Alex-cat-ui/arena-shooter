extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeNav:
	extends Node

	var plan_contracts: Dictionary = {}

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func can_enemy_traverse_point(_enemy: Node, _point: Vector2) -> bool:
		return true

	func build_policy_valid_path(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null) -> Dictionary:
		var key := _key(to_pos)
		if plan_contracts.has(key):
			return (plan_contracts.get(key, {}) as Dictionary).duplicate(true)
		return {
			"status": "ok",
			"path_points": [to_pos],
			"reason": "ok",
		}

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
	print("PURSUIT STALL + PLAN LOCK INVARIANTS TEST")
	print("============================================================")

	_test_stall_and_plan_lock_invariants()

	_t.summary("PURSUIT STALL + PLAN LOCK INVARIANTS RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_stall_and_plan_lock_invariants() -> void:
	var owner := CharacterBody2D.new()
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	add_child(owner)

	var nav := FakeNav.new()
	add_child(nav)
	_t.run_test(
		"fake nav omits legacy path planner APIs",
		not nav.has_method("build_reachable_path_points") and not nav.has_method("build_path_points")
	)

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	pursuit.configure_navigation(nav, 0)
	pursuit.call("_reset_stall_monitor")

	var w1 := pursuit.debug_feed_stall_window(7.0, 10.0) as Dictionary
	var w2 := pursuit.debug_feed_stall_window(6.5, 11.0) as Dictionary
	var w3 := pursuit.debug_feed_stall_window(12.0, 25.0) as Dictionary
	_t.run_test("two consecutive stalled windows trigger hard_stall", bool(w1.get("stalled_window", false)) and bool(w2.get("hard_stall", false)))
	_t.run_test("non-stalled window clears hard_stall", not bool(w3.get("hard_stall", true)) and int(w3.get("consecutive_windows", -1)) == 0)

	var base_target := Vector2(100.0, 40.0)
	var near_target := base_target + Vector2(6.0, 0.0)
	var far_target := base_target + Vector2(20.0, 0.0)
	var ctx := {
		"player_pos": base_target,
		"known_target_pos": Vector2.ZERO,
		"last_seen_pos": Vector2.ZERO,
		"investigate_anchor": Vector2.ZERO,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.CALM,
		"los": false,
		"dist": base_target.length(),
	}

	var r1 := pursuit.execute_intent(1.0 / 60.0, {"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT, "target": base_target}, ctx) as Dictionary
	var r2 := pursuit.execute_intent(1.0 / 60.0, {"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT, "target": near_target}, ctx) as Dictionary
	var r3 := pursuit.execute_intent(1.0 / 60.0, {"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT, "target": far_target}, ctx) as Dictionary
	var plan_target_1 := r1.get("plan_target", Vector2.ZERO) as Vector2
	var plan_target_2 := r2.get("plan_target", Vector2.ZERO) as Vector2
	var plan_target_3 := r3.get("plan_target", Vector2.ZERO) as Vector2
	_t.run_test("plan_id initializes on first movement target", int(r1.get("plan_id", 0)) > 0)
	_t.run_test("plan_id stays stable for <=8px target jitter", int(r2.get("plan_id", -1)) == int(r1.get("plan_id", -2)))
	_t.run_test("plan_target stays locked for <=8px target jitter", plan_target_2.distance_to(plan_target_1) <= 0.001)
	_t.run_test("plan_id increments by exactly one when target changes >8px", int(r3.get("plan_id", -1)) == int(r2.get("plan_id", -2)) + 1)
	_t.run_test("plan_target updates on >8px target change", plan_target_3.distance_to(far_target) <= 0.001)

	var snap := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
	var legacy_k1 := "policy_" + "fallback_used"
	var legacy_k2 := "shadow_" + "escape_active"
	_t.run_test("snapshot exposes phase2 plan/fsm keys", snap.has("plan_id") and snap.has("intent_target") and snap.has("plan_target") and snap.has("shadow_unreachable_fsm_state"))
	_t.run_test("snapshot omits removed legacy keys", not snap.has(legacy_k1) and not snap.has(legacy_k2))

	owner.queue_free()
	nav.queue_free()
