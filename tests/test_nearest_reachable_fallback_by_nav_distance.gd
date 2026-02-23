extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeNav:
	extends Node

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func can_enemy_traverse_point(_enemy: Node, _point: Vector2) -> bool:
		return true

	func build_policy_valid_path(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null) -> Dictionary:
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
	print("PURSUIT PLAN LOCK NO-TARGET EDGE CASE TEST")
	print("============================================================")

	_test_missing_target_keeps_plan_lock_stable()

	_t.summary("PURSUIT PLAN LOCK NO-TARGET EDGE CASE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_missing_target_keeps_plan_lock_stable() -> void:
	var owner := CharacterBody2D.new()
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	add_child(owner)

	var nav := FakeNav.new()
	add_child(nav)

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	pursuit.configure_navigation(nav, 0)

	var target := Vector2(100.0, 20.0)
	var ctx := {
		"player_pos": target,
		"known_target_pos": Vector2.ZERO,
		"last_seen_pos": Vector2.ZERO,
		"investigate_anchor": Vector2.ZERO,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.CALM,
		"los": false,
		"dist": target.length(),
	}
	var seed_result := pursuit.execute_intent(
		1.0 / 60.0,
		{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT, "target": target},
		ctx
	) as Dictionary
	var seed_plan_id := int(seed_result.get("plan_id", 0))
	var seed_plan_target := seed_result.get("plan_target", Vector2.ZERO) as Vector2

	var missing_target_result := pursuit.execute_intent(
		1.0 / 60.0,
		{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT},
		ctx
	) as Dictionary
	var missing_plan_target := missing_target_result.get("plan_target", Vector2.ZERO) as Vector2
	var snap := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
	var legacy_k1 := "policy_" + "fallback_used"
	var legacy_k2 := "shadow_" + "escape_target"

	_t.run_test("seed move initializes plan lock", seed_plan_id > 0 and seed_plan_target.distance_to(target) <= 0.001)
	_t.run_test("missing target movement reports no_target", String(missing_target_result.get("path_failed_reason", "")) == "no_target")
	_t.run_test("missing target movement sets movement_intent=false", not bool(missing_target_result.get("movement_intent", true)))
	_t.run_test("missing target movement keeps plan_id unchanged", int(missing_target_result.get("plan_id", -1)) == seed_plan_id)
	_t.run_test("missing target movement keeps prior plan_target", missing_plan_target.distance_to(seed_plan_target) <= 0.001)
	_t.run_test("execute output includes phase2 keys", missing_target_result.has("plan_id") and missing_target_result.has("intent_target") and missing_target_result.has("plan_target") and missing_target_result.has("shadow_unreachable_fsm_state"))
	_t.run_test("snapshot includes phase2 keys and omits removed keys", snap.has("plan_id") and snap.has("intent_target") and snap.has("plan_target") and snap.has("shadow_unreachable_fsm_state") and not snap.has(legacy_k1) and not snap.has(legacy_k2))

	owner.queue_free()
	nav.queue_free()
