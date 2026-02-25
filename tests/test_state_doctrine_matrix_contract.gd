extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCRIPT := preload("res://src/entities/enemy.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeShadowQueryNav:
	extends Node

	func is_point_in_shadow(point: Vector2) -> bool:
		return point.distance_to(Vector2(300.0, 20.0)) <= 0.001


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("STATE DOCTRINE MATRIX CONTRACT TEST")
	print("============================================================")

	_test_calm_no_los_returns_patrol_only()
	_test_suspicious_no_los_shadow_target_returns_shadow_boundary_scan()
	_test_alert_combat_no_los_with_target_context_never_patrol_or_return_home()
	_test_build_utility_context_shadow_scan_target_priority_known_then_last_seen_then_anchor()

	_t.summary("STATE DOCTRINE MATRIX CONTRACT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_calm_no_los_returns_patrol_only() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()
	var intent := brain.update(0.3, _ctx({})) as Dictionary
	_t.run_test(
		"CALM no-LOS returns PATROL only",
		int(intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL
	)


func _test_suspicious_no_los_shadow_target_returns_shadow_boundary_scan() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()
	var target := Vector2(220.0, 40.0)
	var intent := brain.update(0.3, _ctx({
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS,
		"has_last_seen": true,
		"last_seen_age": 1.0,
		"last_seen_pos": target,
		"dist_to_last_seen": 180.0,
		"has_shadow_scan_target": true,
		"shadow_scan_target": target,
		"shadow_scan_target_in_shadow": true,
	})) as Dictionary
	_t.run_test(
		"SUSPICIOUS no-LOS dark target returns SHADOW_BOUNDARY_SCAN",
		int(intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SHADOW_BOUNDARY_SCAN
	)
	_t.run_test(
		"SUSPICIOUS shadow scan target preserved",
		(intent.get("target", Vector2.ZERO) as Vector2).distance_to(target) <= 0.001
	)


func _test_alert_combat_no_los_with_target_context_never_patrol_or_return_home() -> void:
	var cases := [
		{
			"label": "ALERT",
			"ctx": {
				"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.ALERT,
				"has_known_target": true,
				"known_target_pos": Vector2(240.0, 32.0),
				"shadow_scan_target": Vector2(240.0, 32.0),
				"has_shadow_scan_target": true,
				"shadow_scan_target_in_shadow": false,
			},
		},
		{
			"label": "COMBAT",
			"ctx": {
				"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.COMBAT,
				"combat_lock": false,
				"has_known_target": true,
				"known_target_pos": Vector2(260.0, 48.0),
				"shadow_scan_target": Vector2(260.0, 48.0),
				"has_shadow_scan_target": true,
				"shadow_scan_target_in_shadow": false,
			},
		},
	]
	for case_variant in cases:
		var case := case_variant as Dictionary
		var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
		brain.reset()
		var intent := brain.update(0.3, _ctx(case.get("ctx", {}))) as Dictionary
		var intent_type := int(intent.get("type", -1))
		var label := String(case.get("label", "CASE"))
		_t.run_test(
			"%s no-LOS with target context is not PATROL/RETURN_HOME" % label,
			intent_type != ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL
				and intent_type != ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETURN_HOME
		)


func _test_build_utility_context_shadow_scan_target_priority_known_then_last_seen_then_anchor() -> void:
	var enemy := ENEMY_SCRIPT.new()
	enemy.initialize(9301, "zombie")
	var nav := FakeShadowQueryNav.new()
	enemy.global_position = Vector2.ZERO
	var detection_runtime := _detection_runtime(enemy)
	_t.run_test("context priority setup: detection runtime exists", detection_runtime != null)
	if detection_runtime == null:
		nav.free()
		enemy.free()
		return
	detection_runtime.call("set_state_value", "_current_alert_level", ENEMY_ALERT_LEVELS_SCRIPT.ALERT)
	detection_runtime.call("set_state_value", "_awareness", null)
	detection_runtime.call("set_state_value", "nav_system", nav)
	detection_runtime.call("set_state_value", "_last_seen_pos", Vector2(200.0, 20.0))
	detection_runtime.call("set_state_value", "_investigate_anchor", Vector2(100.0, 20.0))
	detection_runtime.call("set_state_value", "_investigate_anchor_valid", true)

	var assignment := {
		"role": 0,
		"slot_position": Vector2.ZERO,
		"path_ok": false,
		"has_slot": false,
	}

	detection_runtime.call("set_state_value", "_last_seen_age", 0.5)
	var ctx_known := detection_runtime.call("build_utility_context", false, false, assignment, {
		"known_target_pos": Vector2(300.0, 20.0),
		"target_is_last_seen": false,
		"has_known_target": true,
	}) as Dictionary
	_t.run_test(
		"context priority call 1 uses known target",
		bool(ctx_known.get("has_shadow_scan_target", false))
			and (ctx_known.get("shadow_scan_target", Vector2.ZERO) as Vector2).distance_to(Vector2(300.0, 20.0)) <= 0.001
			and bool(ctx_known.get("shadow_scan_target_in_shadow", false))
	)

	var ctx_last_seen := detection_runtime.call("build_utility_context", false, false, assignment, {
		"known_target_pos": Vector2.ZERO,
		"target_is_last_seen": false,
		"has_known_target": false,
	}) as Dictionary
	_t.run_test(
		"context priority call 2 uses last_seen when known target missing",
		bool(ctx_last_seen.get("has_shadow_scan_target", false))
			and (ctx_last_seen.get("shadow_scan_target", Vector2.ZERO) as Vector2).distance_to(Vector2(200.0, 20.0)) <= 0.001
			and not bool(ctx_last_seen.get("shadow_scan_target_in_shadow", true))
	)

	detection_runtime.call("set_state_value", "_last_seen_age", INF)
	var ctx_anchor := detection_runtime.call("build_utility_context", false, false, assignment, {
		"known_target_pos": Vector2.ZERO,
		"target_is_last_seen": false,
		"has_known_target": false,
	}) as Dictionary
	_t.run_test(
		"context priority call 3 uses investigate anchor when known+last_seen missing",
		bool(ctx_anchor.get("has_shadow_scan_target", false))
			and (ctx_anchor.get("shadow_scan_target", Vector2.ZERO) as Vector2).distance_to(Vector2(100.0, 20.0)) <= 0.001
			and not bool(ctx_anchor.get("shadow_scan_target_in_shadow", true))
	)

	nav.free()
	enemy.free()


func _detection_runtime(enemy: Enemy) -> Object:
	var refs := enemy.get_runtime_helper_refs()
	return refs.get("detection_runtime", null) as Object


func _ctx(overrides: Dictionary) -> Dictionary:
	var base := {
		"dist": INF,
		"los": false,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.CALM,
		"combat_lock": false,
		"last_seen_age": INF,
		"last_seen_pos": Vector2.ZERO,
		"has_last_seen": false,
		"dist_to_last_seen": INF,
		"investigate_anchor": Vector2.ZERO,
		"has_investigate_anchor": false,
		"dist_to_investigate_anchor": INF,
		"shadow_scan_target": Vector2.ZERO,
		"has_shadow_scan_target": false,
		"shadow_scan_target_in_shadow": false,
		"known_target_pos": Vector2.ZERO,
		"has_known_target": false,
		"target_is_last_seen": false,
		"role": 0,
		"slot_position": Vector2.ZERO,
		"dist_to_slot": INF,
		"hp_ratio": 1.0,
		"path_ok": false,
		"has_slot": false,
		"player_pos": Vector2.ZERO,
		"home_position": Vector2(16.0, 8.0),
	}
	for key_variant in overrides.keys():
		base[key_variant] = overrides[key_variant]
	return base
