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
	print("COLLISION BLOCK PRESERVES INTENT CONTEXT TEST")
	print("============================================================")

	await _test_collision_repath_preserves_intent_and_target()

	_t.summary("COLLISION BLOCK PRESERVES INTENT CONTEXT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_collision_repath_preserves_intent_and_target() -> void:
	var root := Node2D.new()
	add_child(root)
	TestHelpers.add_wall(root, Vector2.ZERO, Vector2(240.0, 16.0))
	var owner := TestHelpers.spawn_mover(root, Vector2(0.0, 56.0), 1, 1, "enemies")
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	var nav := FakeNav.new()
	root.add_child(nav)

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.4)
	pursuit.configure_navigation(nav, 0)

	await get_tree().process_frame
	await get_tree().physics_frame

	var target := Vector2(0.0, -120.0)
	var intent := {
		"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH,
		"target": target,
	}
	var context := {
		"player_pos": target,
		"known_target_pos": target,
		"last_seen_pos": Vector2.ZERO,
		"investigate_anchor": Vector2.ZERO,
		"home_position": Vector2.ZERO,
		"los": false,
		"dist": owner.global_position.distance_to(target),
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.COMBAT,
		"combat_lock": true,
	}

	var collision_tick_seen := false
	var collision_snapshot: Dictionary = {}
	var collision_result: Dictionary = {}
	var intent_type_before := -1
	var active_target_before := Vector2.ZERO
	var active_target_valid_before := false
	for _i in range(120):
		context["dist"] = owner.global_position.distance_to(target)
		collision_result = pursuit.execute_intent(1.0 / 60.0, intent, context) as Dictionary
		collision_snapshot = pursuit.debug_get_navigation_policy_snapshot() as Dictionary
		if String(collision_snapshot.get("collision_kind", "")) == "non_door":
			collision_tick_seen = true
			intent_type_before = int(pursuit.get("_last_intent_type"))
			active_target_before = collision_snapshot.get("active_move_target", Vector2.ZERO) as Vector2
			active_target_valid_before = bool(collision_snapshot.get("active_move_target_valid", false))
			break
		await get_tree().physics_frame

	var after_result: Dictionary = {}
	var after_snapshot: Dictionary = {}
	var intent_type_after := -1
	if collision_tick_seen:
		await get_tree().physics_frame
		context["dist"] = owner.global_position.distance_to(target)
		after_result = pursuit.execute_intent(1.0 / 60.0, intent, context) as Dictionary
		after_snapshot = pursuit.debug_get_navigation_policy_snapshot() as Dictionary
		intent_type_after = int(pursuit.get("_last_intent_type"))

	_t.run_test("non-door collision occurs during PUSH intent", collision_tick_seen)
	_t.run_test(
		"collision tick reports collision_blocked without mutating PUSH intent type",
		collision_tick_seen
			and bool(collision_result.get("path_failed", false))
			and String(collision_result.get("path_failed_reason", "")) == "collision_blocked"
			and intent_type_before == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH
	)
	_t.run_test(
		"active target remains valid across collision-triggered repath cycle",
		collision_tick_seen
			and active_target_valid_before
			and bool(after_snapshot.get("active_move_target_valid", false))
	)
	_t.run_test(
		"active target vector preserved across collision-triggered repath cycle",
		collision_tick_seen
			and active_target_before.distance_to(after_snapshot.get("active_move_target", Vector2.ZERO) as Vector2) <= 0.001
	)
	_t.run_test(
		"intent type preserved on next tick after collision-triggered repath",
		collision_tick_seen
			and intent_type_after == intent_type_before
			and intent_type_after == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH
	)
	_t.run_test(
		"collision debug contract stays consistent for non-door path",
		collision_tick_seen
			and String(collision_snapshot.get("collision_kind", "")) == "non_door"
			and bool(collision_snapshot.get("collision_forced_repath", false))
			and String(collision_snapshot.get("collision_reason", "")) == "collision_blocked"
			and int(collision_snapshot.get("collision_index", -1)) >= 0
			and bool(after_result.get("movement_intent", false))
	)

	root.queue_free()
	await get_tree().physics_frame


func can_enemy_traverse_geometry_point(_enemy: Node, _point: Vector2) -> bool:
	return true
