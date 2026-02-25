extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeEnemy:
	extends CharacterBody2D

	var flashlight_active: bool = false

	func is_flashlight_active_for_navigation() -> bool:
		return flashlight_active

	func set_shadow_check_flashlight(_active: bool) -> void:
		pass

	func set_shadow_scan_active(_active: bool) -> void:
		pass


class FakeNav:
	extends Node

	var shadow_edge_x: float = 20.0
	var blocked_deep_shadow_x: float = -60.0

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func is_point_in_shadow(point: Vector2) -> bool:
		return point.x < shadow_edge_x

	func get_nearest_non_shadow_point(target: Vector2, _radius_px: float) -> Vector2:
		return Vector2(shadow_edge_x + 18.0, target.y)

	func can_enemy_traverse_point(enemy: Node, point: Vector2) -> bool:
		var has_grant := false
		if enemy and enemy.has_method("is_flashlight_active_for_navigation"):
			has_grant = bool(enemy.call("is_flashlight_active_for_navigation"))
		if has_grant:
			return true
		return point.x >= blocked_deep_shadow_x

	func build_policy_valid_path(from_pos: Vector2, to_pos: Vector2, enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		var path: Array[Vector2] = [to_pos]
		var prev := from_pos
		for point in path:
			var steps := maxi(int(ceil(prev.distance_to(point) / 12.0)), 1)
			for step in range(1, steps + 1):
				var sample := prev.lerp(point, float(step) / float(steps))
				if not can_enemy_traverse_point(enemy, sample):
					return {
						"status": "unreachable_policy",
						"path_points": [],
						"reason": "policy_blocked",
						"segment_index": 0,
						"blocked_point": sample,
					}
			prev = point
		return {
			"status": "ok",
			"path_points": path,
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
	print("SHADOW STALL ESCAPES TO LIGHT TEST")
	print("============================================================")

	await _test_shadow_stall_uses_scan_search_canon()

	_t.summary("SHADOW STALL ESCAPES TO LIGHT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_shadow_stall_uses_scan_search_canon() -> void:
	var world := Node2D.new()
	add_child(world)

	var nav := FakeNav.new()
	world.add_child(nav)

	var owner := FakeEnemy.new()
	owner.global_position = Vector2(-40.0, 0.0)
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	world.add_child(owner)
	await get_tree().physics_frame

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	pursuit.configure_navigation(nav, 0)

	var blocked_target := Vector2(-140.0, 0.0)
	var intent := {
		"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT,
		"target": blocked_target,
	}
	var ctx := {
		"player_pos": blocked_target,
		"known_target_pos": blocked_target,
		"last_seen_pos": Vector2.ZERO,
		"investigate_anchor": Vector2.ZERO,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.ALERT,
		"los": false,
		"dist": owner.global_position.distance_to(blocked_target),
	}

	var transitions: Array[String] = []
	var escaped_to_light := false
	var first_result: Dictionary = {}
	var policy_blocked_attempts := 0
	var repeated_policy_block_boundary_stays_light := true
	var repeated_policy_block_boundary_checks := 0
	var saw_hard_stall := false
	var saw_repath_recovery_key_population := false
	for i in range(300):
		ctx["dist"] = owner.global_position.distance_to(blocked_target)
		var result := pursuit.execute_intent(1.0 / 60.0, intent, ctx) as Dictionary
		if i == 0:
			first_result = result.duplicate(true)
		if result.has("repath_recovery_reason") and result.has("repath_recovery_request_next_search_node"):
			saw_repath_recovery_key_population = true
		if String(result.get("repath_recovery_reason", "")) == "hard_stall":
			saw_hard_stall = true
		var state := String(result.get("shadow_unreachable_fsm_state", ""))
		if transitions.is_empty() or transitions[transitions.size() - 1] != state:
			transitions.append(state)
		var loop_snap := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
		if String(loop_snap.get("path_plan_reason", "")) == "policy_blocked":
			policy_blocked_attempts += 1
			if policy_blocked_attempts >= 2 and bool(loop_snap.get("shadow_scan_boundary_valid", false)):
				repeated_policy_block_boundary_checks += 1
				var boundary_point := loop_snap.get("shadow_scan_boundary_point", Vector2.ZERO) as Vector2
				if nav.is_point_in_shadow(boundary_point):
					repeated_policy_block_boundary_stays_light = false
		if owner.global_position.x >= nav.shadow_edge_x:
			escaped_to_light = true
		if escaped_to_light and transitions.has("search"):
			break
		await get_tree().physics_frame

	var snap := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
	var k1 := "shadow_" + "escape_active"
	var k2 := "shadow_" + "escape_target"
	var k3 := "policy_" + "fallback_used"
	_t.run_test("setup: owner starts in shadow", nav.is_point_in_shadow(Vector2(-40.0, 0.0)))
	_t.run_test("first failure enters phase2 shadow unreachable fsm", String(first_result.get("shadow_unreachable_fsm_state", "")) == "shadow_boundary_scan")
	_t.run_test("runtime reaches search in canonical sequence", transitions.has("shadow_boundary_scan") and transitions.has("search"))
	_t.run_test("enemy exits shadow to light via boundary movement", escaped_to_light)
	_t.run_test(
		"repeated policy-blocked attempts keep shadow boundary target on light side",
		policy_blocked_attempts >= 2 and repeated_policy_block_boundary_checks >= 1 and repeated_policy_block_boundary_stays_light
	)
	_t.run_test(
		"phase17 execute_intent result carries repath recovery keys during shadow-stall harness",
		saw_repath_recovery_key_population
	)
	_t.run_test(
		"phase17 hard-stall feedback does not break canon recovery (optional path)",
		(not saw_hard_stall) or (escaped_to_light and transitions.has("search"))
	)
	_t.run_test("snapshot omits removed legacy keys", not snap.has(k1) and not snap.has(k2) and not snap.has(k3))
	_t.run_test(
		"snapshot exposes phase17 repath recovery debug keys",
		snap.has("repath_recovery_reason") and snap.has("repath_recovery_request_next_search_node")
	)

	world.queue_free()
	await get_tree().process_frame


func can_enemy_traverse_geometry_point(_enemy: Node, _point: Vector2) -> bool:
	return true
