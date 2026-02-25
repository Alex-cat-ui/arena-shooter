extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeShadowScanNav:
	extends Node

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func is_point_in_shadow(_point: Vector2) -> bool:
		return false

	func get_nearest_non_shadow_point(target: Vector2, _radius_px: float) -> Vector2:
		return target + Vector2(32.0, 0.0)

	func can_enemy_traverse_point(_enemy: Node, _point: Vector2) -> bool:
		return true

	func build_policy_valid_path(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		return {
			"status": "ok",
			"path_points": [to_pos],
			"reason": "ok",
		}


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
	print("SHADOW STUCK WATCHDOG ESCALATES TO NEXT NODE TEST")
	print("============================================================")

	await _test_hard_stall_sets_recovery_feedback_for_shadow_scan_intent()
	await _test_non_search_intent_collision_blocked_does_not_request_next_node()
	_test_shadow_escape_keys_absent_from_navigation_snapshot()

	_t.summary("SHADOW STUCK WATCHDOG ESCALATES TO NEXT NODE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_hard_stall_sets_recovery_feedback_for_shadow_scan_intent() -> void:
	var world := Node2D.new()
	add_child(world)
	var nav := FakeShadowScanNav.new()
	world.add_child(nav)
	var owner := CharacterBody2D.new()
	owner.global_position = Vector2.ZERO
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	world.add_child(owner)
	await get_tree().physics_frame

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	pursuit.configure_navigation(nav, 0)
	pursuit.set_speed_tiles(0.0)

	var target := Vector2(96.0, 0.0)
	var intent := {
		"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SHADOW_BOUNDARY_SCAN,
		"target": target,
	}
	var ctx := {
		"player_pos": target,
		"known_target_pos": target,
		"last_seen_pos": Vector2.ZERO,
		"investigate_anchor": Vector2.ZERO,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.ALERT,
		"los": false,
		"dist": target.length(),
	}

	var saw_hard_stall_feedback := false
	var last_result: Dictionary = {}
	for _i in range(30):
		last_result = pursuit.execute_intent(0.1, intent, ctx) as Dictionary
		if String(last_result.get("repath_recovery_reason", "")) == "hard_stall":
			saw_hard_stall_feedback = true
			break

	_t.run_test(
		"hard stall on shadow-scan movement emits recovery next-node request",
		saw_hard_stall_feedback
			and bool(last_result.get("repath_recovery_request_next_search_node", false))
			and bool(last_result.get("repath_recovery_preserve_intent", false))
	)
	_t.run_test(
		"hard stall recovery keeps gameplay intent target (not movement subtarget)",
		saw_hard_stall_feedback
			and ((last_result.get("repath_recovery_intent_target", Vector2.ZERO) as Vector2).distance_to(target) <= 0.001)
	)

	world.queue_free()
	await get_tree().process_frame


func _test_non_search_intent_collision_blocked_does_not_request_next_node() -> void:
	var root := Node2D.new()
	add_child(root)
	TestHelpers.add_wall(root, Vector2.ZERO, Vector2(240.0, 16.0))
	var owner := TestHelpers.spawn_mover(root, Vector2(0.0, 56.0), 1, 1, "enemies")
	var nav := FakeNav.new()
	root.add_child(nav)
	await get_tree().process_frame
	await get_tree().physics_frame

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, null, 2.4)
	pursuit.configure_navigation(nav, 0)

	var blocked_target := Vector2(0.0, -120.0)
	var intent := {
		"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH,
		"target": blocked_target,
	}
	var ctx := {
		"player_pos": blocked_target,
		"known_target_pos": blocked_target,
		"last_seen_pos": Vector2.ZERO,
		"investigate_anchor": Vector2.ZERO,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.COMBAT,
		"los": false,
		"dist": owner.global_position.distance_to(blocked_target),
	}

	var collision_feedback: Dictionary = {}
	var saw_collision := false
	for _i in range(180):
		ctx["dist"] = owner.global_position.distance_to(blocked_target)
		var result := pursuit.execute_intent(1.0 / 60.0, intent, ctx) as Dictionary
		if String(result.get("path_failed_reason", "")) == "collision_blocked":
			collision_feedback = result.duplicate(true)
			saw_collision = true
			break
		await get_tree().physics_frame

	_t.run_test("setup: non-search collision_blocked occurs", saw_collision)
	_t.run_test(
		"collision_blocked on PUSH does not request next dark-search node",
		saw_collision
			and String(collision_feedback.get("repath_recovery_reason", "")) == "collision_blocked"
			and not bool(collision_feedback.get("repath_recovery_request_next_search_node", true))
			and not bool(collision_feedback.get("repath_recovery_preserve_intent", true))
	)

	root.queue_free()
	await get_tree().physics_frame


func _test_shadow_escape_keys_absent_from_navigation_snapshot() -> void:
	var owner := CharacterBody2D.new()
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	add_child(owner)

	var nav := FakeNav.new()
	add_child(nav)

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	pursuit.configure_navigation(nav, 0)
	var snap := pursuit.debug_get_navigation_policy_snapshot() as Dictionary

	_t.run_test(
		"snapshot omits removed shadow_escape_* keys",
		not snap.has("shadow_escape_active")
			and not snap.has("shadow_escape_target")
			and not snap.has("shadow_escape_target_valid")
	)
	_t.run_test(
		"snapshot exposes phase17 repath recovery keys",
		snap.has("repath_recovery_reason")
			and snap.has("repath_recovery_request_next_search_node")
			and snap.has("repath_recovery_blocked_point")
			and snap.has("repath_recovery_repeat_count")
	)

	owner.queue_free()
	nav.queue_free()


func can_enemy_traverse_geometry_point(_enemy: Node, _point: Vector2) -> bool:
	return true
