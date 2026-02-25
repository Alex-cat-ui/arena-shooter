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
		"SUSPICIOUS + dark shadow target chooses SHADOW_BOUNDARY_SCAN",
		int(intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SHADOW_BOUNDARY_SCAN
	)
	_t.run_test(
		"shadow boundary scan target equals last seen position",
		(intent.get("target", Vector2.ZERO) as Vector2).distance_to(shadow_target) <= 0.001
	)

	GameConfig.reset_to_defaults()
	if GameConfig and GameConfig.stealth_canon is Dictionary:
		var canon := GameConfig.stealth_canon as Dictionary
		canon["flashlight_works_in_alert"] = true
	var enemy := ENEMY_SCRIPT.new()
	enemy.initialize(1501, "zombie")
	enemy.entity_id = 1501
	var detection_runtime := _detection_runtime(enemy)
	_t.run_test("suspicious shadow-scan setup: detection runtime exists", detection_runtime != null)
	if detection_runtime == null:
		enemy.free()
		GameConfig.reset_to_defaults()
		return
	detection_runtime.call("set_state_value", "_flashlight_activation_delay_timer", 0.0)
	enemy.set_shadow_scan_active(true)
	detection_runtime.call("set_state_value", "_debug_tick_id", 0)
	var flashlight_active_bucket_pass := bool(detection_runtime.call("compute_flashlight_active", ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS))
	detection_runtime.call("set_state_value", "_debug_tick_id", 2)
	var flashlight_active_bucket_fail := bool(detection_runtime.call("compute_flashlight_active", ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS))
	_t.run_test(
		"SUSPICIOUS shadow scan flashlight active on deterministic pass bucket (tick 0)",
		flashlight_active_bucket_pass
	)
	_t.run_test(
		"SUSPICIOUS shadow scan flashlight inactive on deterministic fail bucket (tick 2)",
		not flashlight_active_bucket_fail
	)
	enemy.free()
	GameConfig.reset_to_defaults()


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
		"shadow_scan_completed": false,
		"shadow_scan_completed_reason": "none",
	}
	for key_variant in override.keys():
		base[key_variant] = override[key_variant]
	return base


func _detection_runtime(enemy: Enemy) -> Object:
	var refs := enemy.get_runtime_helper_refs()
	return refs.get("detection_runtime", null) as Object
