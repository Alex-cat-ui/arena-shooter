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
	print("ENEMY UTILITY BRAIN TEST")
	print("============================================================")

	_test_core_decisions()
	_test_antichatter_hold()

	_t.summary("ENEMY UTILITY BRAIN RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_core_decisions() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()

	var push_ctx := _ctx({
		"dist": 820.0,
		"los": true,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.COMBAT,
		"player_pos": Vector2(300.0, 0.0),
	})
	var push_intent := brain.update(0.3, push_ctx) as Dictionary
	_t.run_test("Far combat LOS chooses PUSH", int(push_intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH)
	_t.run_test(
		"PUSH intent yields DIRECT_PRESSURE mode",
		brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.DIRECT_PRESSURE
	)

	brain.reset()
	var retreat_ctx := _ctx({
		"dist": 220.0,
		"los": true,
		"hp_ratio": 0.2,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.COMBAT,
		"player_pos": Vector2(100.0, 0.0),
	})
	var retreat_intent := brain.update(0.3, retreat_ctx) as Dictionary
	_t.run_test("Low HP close LOS chooses RETREAT", int(retreat_intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETREAT)
	_t.run_test(
		"RETREAT intent yields DIRECT_PRESSURE mode",
		brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.DIRECT_PRESSURE
	)

	brain.reset()
	var investigate_ctx := _ctx({
		"dist": 999.0,
		"los": false,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.ALERT,
		"last_seen_age": 1.0,
		"last_seen_pos": Vector2(64.0, -16.0),
	})
	var investigate_intent := brain.update(0.3, investigate_ctx) as Dictionary
	_t.run_test("Recent no-LOS alert chooses INVESTIGATE", int(investigate_intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.INVESTIGATE)
	_t.run_test(
		"INVESTIGATE intent yields LOST_CONTACT_SEARCH mode",
		brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.LOST_CONTACT_SEARCH
	)

	brain.reset()
	var patrol_ctx := _ctx({
		"dist": 999.0,
		"los": false,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS,
		"last_seen_age": 9.0,
	})
	var patrol_intent := brain.update(0.3, patrol_ctx) as Dictionary
	_t.run_test("Old no-LOS suspicious chooses PATROL", int(patrol_intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL)
	_t.run_test(
		"PATROL intent yields PATROL mode",
		brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.PATROL
	)

	brain.reset()
	var slot_ctx := _ctx({
		"dist": 470.0,
		"los": true,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.COMBAT,
		"has_slot": true,
		"path_ok": true,
		"slot_position": Vector2(220.0, 10.0),
		"dist_to_slot": 120.0,
		"role": ENEMY_SQUAD_SYSTEM_SCRIPT.Role.FLANK,
	})
	var slot_intent := brain.update(0.3, slot_ctx) as Dictionary
	_t.run_test("Flank role with slot chooses MOVE_TO_SLOT", int(slot_intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT)
	_t.run_test(
		"MOVE_TO_SLOT intent yields CONTAIN mode",
		brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.CONTAIN
	)


func _test_antichatter_hold() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()

	var push_ctx := _ctx({
		"dist": 760.0,
		"los": true,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.COMBAT,
	})
	var retreat_ctx := _ctx({
		"dist": 180.0,
		"los": true,
		"hp_ratio": 0.2,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.COMBAT,
	})

	var first := brain.update(0.3, push_ctx) as Dictionary
	var second := brain.update(0.1, retreat_ctx) as Dictionary
	_t.run_test("Decision hold prevents immediate flip", int(second.get("type", -1)) == int(first.get("type", -2)))

	var elapsed := 0.0
	while elapsed < 0.65:
		brain.update(0.1, retreat_ctx)
		elapsed += 0.1
	var after_hold := brain.update(0.1, retreat_ctx) as Dictionary
	_t.run_test("Intent can switch after hold window", int(after_hold.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETREAT)


func _ctx(override: Dictionary) -> Dictionary:
	var base := {
		"dist": INF,
		"los": false,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.CALM,
		"last_seen_age": INF,
		"last_seen_pos": Vector2.ZERO,
		"role": ENEMY_SQUAD_SYSTEM_SCRIPT.Role.PRESSURE,
		"slot_position": Vector2.ZERO,
		"dist_to_slot": INF,
		"hp_ratio": 1.0,
		"path_ok": false,
		"has_slot": false,
		"player_pos": Vector2.ZERO,
		"home_position": Vector2.ZERO,
	}
	for key_variant in override.keys():
		base[key_variant] = override[key_variant]
	return base
