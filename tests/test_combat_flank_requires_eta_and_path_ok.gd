extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCRIPT := preload("res://src/entities/enemy.gd")
const ENEMY_COMBAT_ROLE_RUNTIME_SCRIPT := preload("res://src/entities/enemy_combat_role_runtime.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
const ENEMY_SQUAD_SYSTEM_SCRIPT := preload("res://src/systems/enemy_squad_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


func _ready() -> void:
	if embedded_mode:
		return
	var result := run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("COMBAT FLANK REQUIRES ETA AND PATH OK TEST")
	print("============================================================")

	_test_assignment_supports_flank_requires_path_status_ok()
	_test_assignment_supports_flank_requires_eta_within_budget()
	_test_utility_move_to_slot_blocked_when_flank_contract_false()
	_test_utility_flank_move_to_slot_allowed_when_contract_true()

	_t.summary("COMBAT FLANK REQUIRES ETA AND PATH OK RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_assignment_supports_flank_requires_path_status_ok() -> void:
	var runtime = ENEMY_COMBAT_ROLE_RUNTIME_SCRIPT.new()
	var assignment := {
		"role": Enemy.SQUAD_ROLE_FLANK,
		"slot_role": Enemy.SQUAD_ROLE_FLANK,
		"has_slot": true,
		"path_ok": true,
		"path_status": "unreachable_policy",
		"slot_path_length": 420.0,
		"slot_path_eta_sec": 2.8,
	}
	var ok := not bool(runtime.call("assignment_supports_flank_role", assignment))
	_t.run_test("FLANK requires path_status=ok", ok)
	runtime = null


func _test_assignment_supports_flank_requires_eta_within_budget() -> void:
	var runtime = ENEMY_COMBAT_ROLE_RUNTIME_SCRIPT.new()
	var assignment := {
		"role": Enemy.SQUAD_ROLE_FLANK,
		"slot_role": Enemy.SQUAD_ROLE_FLANK,
		"has_slot": true,
		"path_ok": true,
		"path_status": "ok",
		"slot_path_length": 600.0,
		"slot_path_eta_sec": 4.0,
	}
	var ok := not bool(runtime.call("assignment_supports_flank_role", assignment))
	_t.run_test("FLANK requires ETA within budget", ok)
	runtime = null


func _test_utility_move_to_slot_blocked_when_flank_contract_false() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()
	var intent := brain.update(0.3, _utility_ctx(false)) as Dictionary
	_t.run_test(
		"Utility blocks FLANK MOVE_TO_SLOT when flank_slot_contract_ok=false",
		int(intent.get("type", -1)) != ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT
	)


func _test_utility_flank_move_to_slot_allowed_when_contract_true() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()
	var intent := brain.update(0.3, _utility_ctx(true)) as Dictionary
	_t.run_test(
		"Utility allows FLANK MOVE_TO_SLOT when flank_slot_contract_ok=true",
		int(intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT
	)


func _utility_ctx(flank_slot_contract_ok: bool) -> Dictionary:
	return {
		"dist": 470.0,
		"los": true,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.COMBAT,
		"role": ENEMY_SQUAD_SYSTEM_SCRIPT.Role.FLANK,
		"slot_position": Vector2(220.0, 10.0),
		"dist_to_slot": 120.0,
		"hp_ratio": 1.0,
		"path_ok": true,
		"has_slot": true,
		"player_pos": Vector2(300.0, 0.0),
		"known_target_pos": Vector2(300.0, 0.0),
		"home_position": Vector2.ZERO,
		"flank_slot_contract_ok": flank_slot_contract_ok,
	}
