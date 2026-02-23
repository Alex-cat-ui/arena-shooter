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
	print("MODE TRANSITION GUARD NO JITTER TEST")
	print("============================================================")

	_test_mode_does_not_flip_before_hold_expires()
	_test_mode_can_change_after_hold_expires()
	_test_reset_clears_mode_and_timer()

	_t.summary("MODE TRANSITION GUARD NO JITTER RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_mode_does_not_flip_before_hold_expires() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()

	brain.update(0.3, _push_ctx())
	_t.run_test(
		"Mode starts as DIRECT_PRESSURE after PUSH",
		brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.DIRECT_PRESSURE
	)

	brain.update(0.1, _investigate_ctx())
	_t.run_test(
		"Mode does not flip before mode hold expires",
		brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.DIRECT_PRESSURE
	)


func _test_mode_can_change_after_hold_expires() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()

	brain.update(0.3, _push_ctx())
	brain.update(1.0, _investigate_ctx())
	_t.run_test(
		"Mode can change after hold expires",
		brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.LOST_CONTACT_SEARCH
	)


func _test_reset_clears_mode_and_timer() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()

	brain.update(0.3, _push_ctx())
	_t.run_test(
		"Precondition: mode becomes DIRECT_PRESSURE",
		brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.DIRECT_PRESSURE
	)

	brain.reset()
	_t.run_test(
		"reset() clears mode to PATROL",
		brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.PATROL
	)

	brain.update(0.3, _investigate_ctx())
	_t.run_test(
		"reset() clears mode hold timer (mode can switch immediately)",
		brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.LOST_CONTACT_SEARCH
	)


func _push_ctx() -> Dictionary:
	return _ctx({
		"dist": 820.0,
		"los": true,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.COMBAT,
		"player_pos": Vector2(300.0, 0.0),
	})


func _investigate_ctx() -> Dictionary:
	return _ctx({
		"dist": 999.0,
		"los": false,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.ALERT,
		"has_last_seen": true,
		"last_seen_age": 1.0,
		"last_seen_pos": Vector2(64.0, -16.0),
		"dist_to_last_seen": 120.0,
	})


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
