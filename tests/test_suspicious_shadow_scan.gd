extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCRIPT := preload("res://src/entities/enemy.gd")
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
	print("SUSPICIOUS SHADOW SCAN TEST")
	print("============================================================")

	_test_suspicious_shadow_scan_intent_and_flashlight()

	_t.summary("SUSPICIOUS SHADOW SCAN RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_suspicious_shadow_scan_intent_and_flashlight() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()

	var shadow_target := Vector2(220.0, 40.0)
	var intent := brain.update(0.3, _ctx({
		"los": false,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS,
		"has_last_seen": true,
		"last_seen_age": 1.0,
		"last_seen_pos": shadow_target,
		"dist_to_last_seen": 180.0,
		"has_shadow_scan_target": true,
		"shadow_scan_target": shadow_target,
		"shadow_scan_target_in_shadow": true,
	})) as Dictionary

	_t.run_test(
		"SUSPICIOUS + shadow target chooses SHADOW_BOUNDARY_SCAN",
		int(intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SHADOW_BOUNDARY_SCAN
	)
	_t.run_test(
		"shadow scan target equals last seen position",
		(intent.get("target", Vector2.ZERO) as Vector2).distance_to(shadow_target) <= 0.001
	)

	var enemy := ENEMY_SCRIPT.new()
	enemy.set("_flashlight_activation_delay_timer", 0.0)
	enemy.set_shadow_scan_active(true)
	var flashlight_active := bool(enemy.call("_compute_flashlight_active", ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS))
	_t.run_test("SUSPICIOUS shadow scan activates flashlight", flashlight_active)
	enemy.free()


func _ctx(override: Dictionary) -> Dictionary:
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
		"player_pos": Vector2.ZERO,
		"home_position": Vector2.ZERO,
		"has_shadow_scan_target": false,
		"shadow_scan_target": Vector2.ZERO,
		"shadow_scan_target_in_shadow": false,
	}
	for key_variant in override.keys():
		base[key_variant] = override[key_variant]
	return base
