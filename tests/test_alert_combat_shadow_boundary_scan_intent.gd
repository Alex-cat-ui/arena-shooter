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
	print("ALERT/COMBAT SHADOW BOUNDARY SCAN INTENT TEST")
	print("============================================================")

	_test_alert_and_combat_choose_shadow_boundary_scan()
	_test_completion_reasons_handoff_to_search()
	await _test_pursuit_shadow_scan_execution_result_contract()

	_t.summary("ALERT/COMBAT SHADOW BOUNDARY SCAN INTENT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_alert_and_combat_choose_shadow_boundary_scan() -> void:
	var shadow_target := Vector2(220.0, 24.0)
	for alert_level in [ENEMY_ALERT_LEVELS_SCRIPT.ALERT, ENEMY_ALERT_LEVELS_SCRIPT.COMBAT]:
		var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
		brain.reset()
		var intent := brain.update(0.3, _brain_ctx({
			"los": false,
			"alert_level": alert_level,
			"combat_lock": true,
			"has_known_target": true,
			"known_target_pos": shadow_target,
			"player_pos": shadow_target,
			"has_last_seen": true,
			"last_seen_age": 0.2,
			"last_seen_pos": shadow_target,
			"dist_to_last_seen": 160.0,
			"target_context_exists": true,
			"has_shadow_scan_target": true,
			"shadow_scan_target": shadow_target,
			"shadow_scan_target_in_shadow": true,
		})) as Dictionary
		var label := "ALERT" if alert_level == ENEMY_ALERT_LEVELS_SCRIPT.ALERT else "COMBAT"
		_t.run_test(
			"%s no-LOS + in-shadow target chooses SHADOW_BOUNDARY_SCAN" % label,
			int(intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SHADOW_BOUNDARY_SCAN
		)
		_t.run_test(
			"%s shadow scan target preserved" % label,
			(intent.get("target", Vector2.ZERO) as Vector2).distance_to(shadow_target) <= 0.001
		)


func _test_completion_reasons_handoff_to_search() -> void:
	var handoff_target := Vector2(196.0, -12.0)
	for reason in ["timeout", "boundary_unreachable", "target_invalid"]:
		var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
		brain.reset()
		var intent := brain.update(0.3, _brain_ctx({
			"los": false,
			"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.COMBAT,
			"combat_lock": true,
			"has_known_target": true,
			"known_target_pos": handoff_target,
			"player_pos": handoff_target,
			"has_last_seen": true,
			"last_seen_age": 0.5,
			"last_seen_pos": handoff_target,
			"dist_to_last_seen": 120.0,
			"target_context_exists": true,
			"has_shadow_scan_target": true,
			"shadow_scan_target": handoff_target,
			"shadow_scan_target_in_shadow": true,
			"shadow_scan_completed": true,
			"shadow_scan_completed_reason": reason,
		})) as Dictionary
		_t.run_test(
			"completion reason %s hands off to SEARCH before rescan" % reason,
			int(intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH
		)
		_t.run_test(
			"completion reason %s keeps same target" % reason,
			(intent.get("target", Vector2.ZERO) as Vector2).distance_to(handoff_target) <= 0.001
		)
		_t.run_test(
			"completion reason %s marks branch-A handoff for Enemy consumption" % reason,
			bool(brain.consume_shadow_scan_handoff_selected())
		)
		_t.run_test(
			"completion reason %s handoff marker is one-shot" % reason,
			not bool(brain.consume_shadow_scan_handoff_selected())
		)


func _test_pursuit_shadow_scan_execution_result_contract() -> void:
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
	var shadow_target := Vector2(120.0, 0.0)
	var ctx := _pursuit_ctx(shadow_target)

	var invalid_result := pursuit.execute_intent(
		0.1,
		{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SHADOW_BOUNDARY_SCAN},
		ctx
	) as Dictionary
	_t.run_test(
		"pursuit result target_invalid -> completed status",
		String(invalid_result.get("shadow_scan_status", "")) == "completed"
	)
	_t.run_test(
		"pursuit result target_invalid -> reason target_invalid",
		String(invalid_result.get("shadow_scan_complete_reason", "")) == "target_invalid"
	)
	_t.run_test(
		"pursuit result target_invalid -> shadow_scan_target is zero",
		(invalid_result.get("shadow_scan_target", Vector2.ZERO) as Vector2) == Vector2.ZERO
	)

	nav.boundary_point = Vector2.ZERO
	var boundary_result := pursuit.execute_intent(
		0.1,
		{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SHADOW_BOUNDARY_SCAN, "target": shadow_target},
		ctx
	) as Dictionary
	_t.run_test(
		"pursuit result boundary_unreachable -> completed status",
		String(boundary_result.get("shadow_scan_status", "")) == "completed"
	)
	_t.run_test(
		"pursuit result boundary_unreachable -> reason boundary_unreachable",
		String(boundary_result.get("shadow_scan_complete_reason", "")) == "boundary_unreachable"
	)
	_t.run_test(
		"pursuit result boundary_unreachable keeps requested target",
		(boundary_result.get("shadow_scan_target", Vector2.ZERO) as Vector2).distance_to(shadow_target) <= 0.001
	)

	nav.boundary_point = Vector2(36.0, 0.0)
	pursuit.set("_shadow_scan_active", true)
	pursuit.set("_shadow_scan_timer", 0.01)
	pursuit.set("_shadow_scan_target", shadow_target)
	var timeout_result := pursuit.execute_intent(
		0.1,
		{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SHADOW_BOUNDARY_SCAN, "target": shadow_target},
		ctx
	) as Dictionary
	_t.run_test(
		"pursuit result timeout -> completed status",
		String(timeout_result.get("shadow_scan_status", "")) == "completed"
	)
	_t.run_test(
		"pursuit result timeout -> reason timeout",
		String(timeout_result.get("shadow_scan_complete_reason", "")) == "timeout"
	)
	_t.run_test(
		"pursuit result timeout keeps requested target",
		(timeout_result.get("shadow_scan_target", Vector2.ZERO) as Vector2).distance_to(shadow_target) <= 0.001
	)

	world.queue_free()
	await get_tree().process_frame


func _brain_ctx(override: Dictionary) -> Dictionary:
	var base := {
		"dist": INF,
		"los": false,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.CALM,
		"last_seen_age": INF,
		"last_seen_pos": Vector2.ZERO,
		"has_last_seen": false,
		"dist_to_last_seen": INF,
		"investigate_anchor": Vector2.ZERO,
		"has_investigate_anchor": false,
		"dist_to_investigate_anchor": INF,
		"role": 0,
		"slot_position": Vector2.ZERO,
		"dist_to_slot": INF,
		"hp_ratio": 1.0,
		"path_ok": false,
		"has_slot": false,
		"combat_lock": false,
		"player_pos": Vector2.ZERO,
		"known_target_pos": Vector2.ZERO,
		"has_known_target": false,
		"target_context_exists": false,
		"home_position": Vector2.ZERO,
		"has_shadow_scan_target": false,
		"shadow_scan_target": Vector2.ZERO,
		"shadow_scan_target_in_shadow": false,
		"shadow_scan_source": "none",
		"shadow_scan_completed": false,
		"shadow_scan_completed_reason": "none",
	}
	for key_variant in override.keys():
		base[key_variant] = override[key_variant]
	return base


func _pursuit_ctx(target: Vector2) -> Dictionary:
	return {
		"player_pos": target,
		"known_target_pos": target,
		"last_seen_pos": target,
		"investigate_anchor": Vector2.ZERO,
		"home_position": Vector2.ZERO,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.ALERT,
		"los": false,
		"dist": target.length(),
		"combat_lock": false,
	}
