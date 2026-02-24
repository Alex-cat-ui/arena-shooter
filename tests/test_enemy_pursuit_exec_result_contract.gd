extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakePursuitOwner:
	extends CharacterBody2D

	var flashlight_active_for_nav: bool = false
	var shadow_check_flashlight: bool = false
	var shadow_scan_active_flag: bool = false

	func is_flashlight_active_for_navigation() -> bool:
		return flashlight_active_for_nav

	func set_shadow_check_flashlight(active: bool) -> void:
		shadow_check_flashlight = active

	func set_shadow_scan_active(active: bool) -> void:
		shadow_scan_active_flag = active


class FakeShadowNav:
	extends Node

	var boundary_point: Vector2 = Vector2(36.0, 0.0)
	var shadow_start_x: float = 48.0

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func is_point_in_shadow(point: Vector2) -> bool:
		return point.x >= shadow_start_x

	func get_nearest_non_shadow_point(_target: Vector2, _radius_px: float) -> Vector2:
		return boundary_point

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
	print("ENEMY PURSUIT EXEC RESULT CONTRACT TEST")
	print("============================================================")

	await _test_exec_result_has_enemy_consumed_keys()
	await _test_shadow_boundary_completion_reason_contract()

	_t.summary("ENEMY PURSUIT EXEC RESULT CONTRACT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_exec_result_has_enemy_consumed_keys() -> void:
	var harness := await _spawn_pursuit_harness()
	var world := harness["world"] as Node2D
	var pursuit = harness["pursuit"]
	var target := Vector2(120.0, 0.0)
	var result := pursuit.execute_intent(
		0.1,
		{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.HOLD_RANGE, "target": target},
		_pursuit_context(target)
	) as Dictionary

	var required_keys := [
		"request_fire",
		"path_failed",
		"movement_intent",
		"shadow_scan_status",
		"shadow_scan_complete_reason",
		"repath_recovery_request_next_search_node",
		"repath_recovery_reason",
		"repath_recovery_blocked_point",
		"repath_recovery_blocked_point_valid",
		"repath_recovery_repeat_count",
		"repath_recovery_preserve_intent",
		"repath_recovery_intent_target",
	]
	var has_all := true
	for key_variant in required_keys:
		var key := String(key_variant)
		if not result.has(key):
			has_all = false
			break

	var type_ok := (
		result.get("request_fire", null) is bool
		and result.get("path_failed", null) is bool
		and result.get("movement_intent", null) is bool
		and result.get("shadow_scan_status", null) is String
		and result.get("shadow_scan_complete_reason", null) is String
		and result.get("repath_recovery_request_next_search_node", null) is bool
		and result.get("repath_recovery_reason", null) is String
		and result.get("repath_recovery_blocked_point", null) is Vector2
		and result.get("repath_recovery_blocked_point_valid", null) is bool
		and result.get("repath_recovery_repeat_count", null) is int
		and result.get("repath_recovery_preserve_intent", null) is bool
		and result.get("repath_recovery_intent_target", null) is Vector2
	)

	_t.run_test("pursuit execute_intent keeps enemy-consumed key contract", has_all)
	_t.run_test("pursuit execute_intent keeps enemy-consumed type contract", type_ok)

	world.queue_free()
	await get_tree().process_frame


func _test_shadow_boundary_completion_reason_contract() -> void:
	var harness := await _spawn_pursuit_harness()
	var world := harness["world"] as Node2D
	var pursuit = harness["pursuit"]
	var nav := harness["nav"] as FakeShadowNav
	var target := Vector2(120.0, 0.0)

	var invalid := pursuit.execute_intent(
		0.1,
		{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SHADOW_BOUNDARY_SCAN},
		_pursuit_context(target)
	) as Dictionary
	var invalid_ok := (
		String(invalid.get("shadow_scan_status", "")) == "completed"
		and String(invalid.get("shadow_scan_complete_reason", "")) == "target_invalid"
		and (invalid.get("shadow_scan_target", Vector2.ZERO) as Vector2) == Vector2.ZERO
	)

	nav.boundary_point = Vector2.ZERO
	var boundary := pursuit.execute_intent(
		0.1,
		{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SHADOW_BOUNDARY_SCAN, "target": target},
		_pursuit_context(target)
	) as Dictionary
	var boundary_ok := (
		String(boundary.get("shadow_scan_status", "")) == "completed"
		and String(boundary.get("shadow_scan_complete_reason", "")) == "boundary_unreachable"
		and (boundary.get("shadow_scan_target", Vector2.ZERO) as Vector2).distance_to(target) <= 0.001
	)

	_t.run_test("shadow scan contract: missing target -> completed/target_invalid", invalid_ok)
	_t.run_test("shadow scan contract: no boundary -> completed/boundary_unreachable", boundary_ok)

	world.queue_free()
	await get_tree().process_frame


func _spawn_pursuit_harness() -> Dictionary:
	var world := Node2D.new()
	add_child(world)

	var nav := FakeShadowNav.new()
	world.add_child(nav)

	var owner := FakePursuitOwner.new()
	owner.global_position = Vector2.ZERO
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	world.add_child(owner)
	await get_tree().physics_frame

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	pursuit.configure_navigation(nav, 0)
	return {
		"world": world,
		"nav": nav,
		"pursuit": pursuit,
	}


func _pursuit_context(target: Vector2) -> Dictionary:
	return {
		"player_pos": target,
		"known_target_pos": target,
		"last_seen_pos": target,
		"investigate_anchor": Vector2.ZERO,
		"home_position": Vector2.ZERO,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.ALERT,
		"los": false,
		"dist": INF,
		"combat_lock": true,
	}
