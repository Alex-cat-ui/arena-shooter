extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCRIPT := preload("res://src/entities/enemy.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeShadowQueryNav:
	extends Node

	var shadow_center: Vector2 = Vector2(300.0, 20.0)
	var room_centers := {3: Vector2(64.0, 16.0)}

	func is_point_in_shadow(point: Vector2) -> bool:
		return point.distance_to(shadow_center) <= 0.001

	func get_room_center(room_id: int) -> Vector2:
		return room_centers.get(room_id, Vector2.ZERO)


func _ready() -> void:
	if embedded_mode:
		return
	var result := run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ENEMY UTILITY CONTEXT CONTRACT TEST")
	print("============================================================")

	_test_context_exposes_required_contract_fields()
	_test_shadow_scan_target_priority_contract()

	_t.summary("ENEMY UTILITY CONTEXT CONTRACT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_context_exposes_required_contract_fields() -> void:
	var setup := _new_context_harness()
	var enemy := setup["enemy"] as Enemy
	var nav := setup["nav"] as FakeShadowQueryNav
	var runtime := setup.get("runtime", null)
	_t.run_test("utility context setup: detection runtime exists", runtime != null)
	if runtime == null:
		enemy.free()
		nav.free()
		return

	runtime.call("set_state_value", "_last_seen_age", 0.5)
	runtime.call("set_state_value", "_last_seen_pos", Vector2(200.0, 20.0))
	runtime.call("set_state_value", "_investigate_anchor", Vector2(100.0, 20.0))
	runtime.call("set_state_value", "_investigate_anchor_valid", true)

	var assignment := {
		"role": 0,
		"slot_role": 0,
		"slot_position": Vector2(96.0, 0.0),
		"path_ok": true,
		"path_status": "ok",
		"slot_path_eta_sec": 0.75,
		"has_slot": true,
	}
	var context := runtime.call("build_utility_context", false, false, assignment, {
		"known_target_pos": Vector2(300.0, 20.0),
		"target_is_last_seen": false,
		"has_known_target": true,
	}) as Dictionary

	var required_keys := [
		"dist",
		"los",
		"alert_level",
		"combat_lock",
		"last_seen_age",
		"last_seen_pos",
		"has_last_seen",
		"dist_to_last_seen",
		"investigate_anchor",
		"has_investigate_anchor",
		"dist_to_investigate_anchor",
		"role",
		"slot_role",
		"slot_position",
		"dist_to_slot",
		"hp_ratio",
		"path_ok",
		"slot_path_status",
		"slot_path_eta_sec",
		"flank_slot_contract_ok",
		"has_slot",
		"player_pos",
		"known_target_pos",
		"target_is_last_seen",
		"has_known_target",
		"target_context_exists",
		"home_position",
		"shadow_scan_target",
		"has_shadow_scan_target",
		"shadow_scan_target_in_shadow",
		"shadow_scan_source",
		"shadow_scan_completed",
		"shadow_scan_completed_reason",
	]
	var has_all := true
	for key_variant in required_keys:
		var key := String(key_variant)
		if not context.has(key):
			has_all = false
			break

	var home_ok := (context.get("home_position", Vector2.ZERO) as Vector2).distance_to(Vector2(64.0, 16.0)) <= 0.001
	_t.run_test("utility context keeps required field contract", has_all)
	_t.run_test("utility context home_position uses nav room center contract", home_ok)
	enemy.free()
	nav.free()


func _test_shadow_scan_target_priority_contract() -> void:
	var setup := _new_context_harness()
	var enemy := setup["enemy"] as Enemy
	var nav := setup["nav"] as FakeShadowQueryNav
	var runtime := setup.get("runtime", null)
	_t.run_test("shadow priority setup: detection runtime exists", runtime != null)
	if runtime == null:
		enemy.free()
		nav.free()
		return

	runtime.call("set_state_value", "_last_seen_pos", Vector2(200.0, 20.0))
	runtime.call("set_state_value", "_investigate_anchor", Vector2(100.0, 20.0))
	runtime.call("set_state_value", "_investigate_anchor_valid", true)
	runtime.call("set_state_value", "_last_seen_age", 0.5)
	var assignment := {"role": 0, "slot_role": 0, "slot_position": Vector2.ZERO, "path_ok": false, "has_slot": false}

	nav.shadow_center = Vector2(300.0, 20.0)
	var known_ctx := runtime.call("build_utility_context", false, false, assignment, {
		"known_target_pos": Vector2(300.0, 20.0),
		"target_is_last_seen": false,
		"has_known_target": true,
	}) as Dictionary
	var known_ok := (
		String(known_ctx.get("shadow_scan_source", "")) == "known_target_pos"
		and (known_ctx.get("shadow_scan_target", Vector2.ZERO) as Vector2).distance_to(Vector2(300.0, 20.0)) <= 0.001
		and bool(known_ctx.get("shadow_scan_target_in_shadow", false))
	)

	var last_seen_ctx := runtime.call("build_utility_context", false, false, assignment, {
		"known_target_pos": Vector2.ZERO,
		"target_is_last_seen": false,
		"has_known_target": false,
	}) as Dictionary
	var last_seen_ok := (
		String(last_seen_ctx.get("shadow_scan_source", "")) == "last_seen"
		and (last_seen_ctx.get("shadow_scan_target", Vector2.ZERO) as Vector2).distance_to(Vector2(200.0, 20.0)) <= 0.001
	)

	runtime.call("set_state_value", "_last_seen_age", INF)
	var anchor_ctx := runtime.call("build_utility_context", false, false, assignment, {
		"known_target_pos": Vector2.ZERO,
		"target_is_last_seen": false,
		"has_known_target": false,
	}) as Dictionary
	var anchor_ok := (
		String(anchor_ctx.get("shadow_scan_source", "")) == "investigate_anchor"
		and (anchor_ctx.get("shadow_scan_target", Vector2.ZERO) as Vector2).distance_to(Vector2(100.0, 20.0)) <= 0.001
	)

	_t.run_test("shadow scan target priority: known_target_pos first", known_ok)
	_t.run_test("shadow scan target priority: last_seen second", last_seen_ok)
	_t.run_test("shadow scan target priority: investigate_anchor fallback", anchor_ok)
	enemy.free()
	nav.free()


func _new_context_harness() -> Dictionary:
	var enemy := ENEMY_SCRIPT.new()
	var nav := FakeShadowQueryNav.new()
	enemy.initialize(9401, "zombie")
	enemy.global_position = Vector2.ZERO
	var runtime := _detection_runtime(enemy)
	if runtime != null:
		runtime.call("set_state_value", "nav_system", nav)
		runtime.call("set_state_value", "home_room_id", 3)
		runtime.call("set_state_value", "_current_alert_level", ENEMY_ALERT_LEVELS_SCRIPT.ALERT)
		runtime.call("set_state_value", "_awareness", null)
	return {
		"enemy": enemy,
		"nav": nav,
		"runtime": runtime,
	}


func _detection_runtime(enemy: Enemy) -> Object:
	var refs := enemy.get_runtime_helper_refs()
	return refs.get("detection_runtime", null) as Object
