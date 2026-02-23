extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
const ENEMY_SQUAD_SYSTEM_SCRIPT := preload("res://src/systems/enemy_squad_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("PURSUIT MODE SELECTION BY CONTEXT TEST")
	print("============================================================")

	_test_push_intent_maps_to_direct_pressure()
	_test_retreat_intent_maps_to_direct_pressure()
	_test_move_to_slot_intent_maps_to_contain()
	_test_hold_range_intent_maps_to_contain()
	_test_shadow_boundary_scan_maps_to_shadow_aware_sweep()
	_test_investigate_maps_to_lost_contact_search()
	_test_patrol_maps_to_patrol()

	_t.summary("PURSUIT MODE SELECTION BY CONTEXT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_push_intent_maps_to_direct_pressure() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()
	brain.update(0.3, _ctx({
		"dist": 820.0,
		"los": true,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.COMBAT,
		"player_pos": Vector2(300.0, 0.0),
	}))
	_t.run_test(
		"PUSH intent maps to DIRECT_PRESSURE",
		brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.DIRECT_PRESSURE
	)


func _test_retreat_intent_maps_to_direct_pressure() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()
	brain.update(0.3, _ctx({
		"dist": 220.0,
		"los": true,
		"hp_ratio": 0.2,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.COMBAT,
		"player_pos": Vector2(100.0, 0.0),
	}))
	_t.run_test(
		"RETREAT intent maps to DIRECT_PRESSURE",
		brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.DIRECT_PRESSURE
	)


func _test_move_to_slot_intent_maps_to_contain() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()
	brain.update(0.3, _ctx({
		"dist": 470.0,
		"los": true,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.COMBAT,
		"has_slot": true,
		"path_ok": true,
		"slot_position": Vector2(220.0, 10.0),
		"dist_to_slot": 120.0,
		"role": ENEMY_SQUAD_SYSTEM_SCRIPT.Role.FLANK,
	}))
	_t.run_test(
		"MOVE_TO_SLOT intent maps to CONTAIN",
		brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.CONTAIN
	)


func _test_hold_range_intent_maps_to_contain() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()
	brain.update(0.3, _ctx({
		"dist": 500.0,
		"los": true,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.COMBAT,
		"has_slot": false,
		"player_pos": Vector2(160.0, 0.0),
	}))
	_t.run_test(
		"HOLD_RANGE intent maps to CONTAIN",
		brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.CONTAIN
	)


func _test_shadow_boundary_scan_maps_to_shadow_aware_sweep() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()
	var shadow_target := Vector2(64.0, -32.0)
	var intent := brain.update(0.3, _ctx({
		"dist": 300.0,
		"los": false,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.ALERT,
		"has_shadow_scan_target": true,
		"shadow_scan_target": shadow_target,
		"shadow_scan_target_in_shadow": true,
		"has_last_seen": true,
		"last_seen_age": 1.0,
		"last_seen_pos": shadow_target,
		"dist_to_last_seen": 180.0,
	}))
	_t.run_test(
		"ALERT shadow boundary scan intent selected",
		int(intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SHADOW_BOUNDARY_SCAN
	)
	_t.run_test(
		"SHADOW_BOUNDARY_SCAN intent maps to SHADOW_AWARE_SWEEP",
		brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.SHADOW_AWARE_SWEEP
	)


func _test_investigate_maps_to_lost_contact_search() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()
	brain.update(0.3, _ctx({
		"dist": 999.0,
		"los": false,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.ALERT,
		"has_last_seen": true,
		"last_seen_age": 1.0,
		"last_seen_pos": Vector2(64.0, -16.0),
		"dist_to_last_seen": 120.0,
	}))
	_t.run_test(
		"INVESTIGATE intent maps to LOST_CONTACT_SEARCH",
		brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.LOST_CONTACT_SEARCH
	)


func _test_patrol_maps_to_patrol() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()
	brain.update(0.3, _ctx({
		"dist": 999.0,
		"los": false,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.CALM,
		"last_seen_age": INF,
	}))
	_t.run_test(
		"PATROL intent maps to PATROL",
		brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.PATROL
	)


func _ctx(override: Dictionary) -> Dictionary:
	var base := {
		"dist": INF,
		"los": false,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.CALM,
		"last_seen_age": INF,
		"last_seen_pos": Vector2.ZERO,
		"has_last_seen": false,
		"dist_to_last_seen": INF,
		"role": ENEMY_SQUAD_SYSTEM_SCRIPT.Role.PRESSURE,
		"slot_position": Vector2.ZERO,
		"dist_to_slot": INF,
		"hp_ratio": 1.0,
		"path_ok": false,
		"has_slot": false,
		"player_pos": Vector2.ZERO,
		"known_target_pos": Vector2.ZERO,
		"has_known_target": false,
		"home_position": Vector2.ZERO,
		"investigate_anchor": Vector2.ZERO,
		"has_investigate_anchor": false,
		"dist_to_investigate_anchor": INF,
		"target_is_last_seen": false,
		"has_shadow_scan_target": false,
		"shadow_scan_target": Vector2.ZERO,
		"shadow_scan_target_in_shadow": false,
		"shadow_scan_completed": false,
		"shadow_scan_completed_reason": "none",
	}
	for key_variant in override.keys():
		base[key_variant] = override[key_variant]
	return base
