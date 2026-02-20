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
	print("ALERT INVESTIGATE ANCHOR TEST")
	print("============================================================")

	_test_alert_uses_investigate_anchor_without_last_seen()

	_t.summary("ALERT INVESTIGATE ANCHOR RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_alert_uses_investigate_anchor_without_last_seen() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()

	var anchor := Vector2(420.0, 64.0)
	var intent := brain.update(0.3, _ctx({
		"los": false,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.ALERT,
		"has_last_seen": false,
		"last_seen_age": INF,
		"last_seen_pos": Vector2.ZERO,
		"dist_to_last_seen": INF,
		"has_investigate_anchor": true,
		"investigate_anchor": anchor,
		"dist_to_investigate_anchor": 220.0,
	})) as Dictionary

	_t.run_test(
		"ALERT without last_seen but with investigate_anchor chooses INVESTIGATE",
		int(intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.INVESTIGATE
	)
	_t.run_test(
		"investigate target equals investigate_anchor",
		(intent.get("target", Vector2.ZERO) as Vector2).distance_to(anchor) <= 0.001
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
		"home_position": Vector2(16.0, 8.0),
	}
	for key_variant in override.keys():
		base[key_variant] = override[key_variant]
	return base
