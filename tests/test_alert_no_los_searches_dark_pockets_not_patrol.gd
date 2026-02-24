extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")

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
	print("ALERT NO-LOS DARK POCKET SEARCH TEST")
	print("============================================================")

	_test_alert_no_los_dark_shadow_target_chooses_shadow_boundary_scan()
	_test_alert_no_los_known_target_without_last_seen_returns_search_not_return_home()

	_t.summary("ALERT NO-LOS DARK POCKET SEARCH RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_alert_no_los_dark_shadow_target_chooses_shadow_boundary_scan() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()
	var shadow_target := Vector2(280.0, 40.0)
	var intent := brain.update(0.3, _ctx({
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.ALERT,
		"has_known_target": true,
		"known_target_pos": Vector2(300.0, 60.0),
		"has_shadow_scan_target": true,
		"shadow_scan_target": shadow_target,
		"shadow_scan_target_in_shadow": true,
	})) as Dictionary
	var intent_type := int(intent.get("type", -1))
	_t.run_test(
		"ALERT no-LOS dark target chooses SHADOW_BOUNDARY_SCAN",
		intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SHADOW_BOUNDARY_SCAN
	)
	_t.run_test(
		"ALERT dark target SHADOW_BOUNDARY_SCAN preserves shadow_scan_target",
		(intent.get("target", Vector2.ZERO) as Vector2).distance_to(shadow_target) <= 0.001
	)
	_t.run_test(
		"ALERT dark target path is not PATROL/RETURN_HOME",
		intent_type != ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL
			and intent_type != ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETURN_HOME
	)


func _test_alert_no_los_known_target_without_last_seen_returns_search_not_return_home() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()
	var known_target := Vector2(320.0, 80.0)
	var intent := brain.update(0.3, _ctx({
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.ALERT,
		"has_known_target": true,
		"known_target_pos": known_target,
		"has_shadow_scan_target": true,
		"shadow_scan_target": known_target,
		"shadow_scan_target_in_shadow": false,
		"has_last_seen": false,
		"last_seen_age": INF,
		"last_seen_pos": Vector2.ZERO,
		"has_investigate_anchor": false,
		"investigate_anchor": Vector2.ZERO,
	})) as Dictionary
	var intent_type := int(intent.get("type", -1))
	_t.run_test(
		"ALERT no-LOS known-target-only returns SEARCH",
		intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH
	)
	_t.run_test(
		"ALERT no-LOS known-target-only is not RETURN_HOME/PATROL",
		intent_type != ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETURN_HOME
			and intent_type != ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL
	)
	_t.run_test(
		"ALERT no-LOS known-target-only SEARCH keeps known target",
		(intent.get("target", Vector2.ZERO) as Vector2).distance_to(known_target) <= 0.001
	)


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
