extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCRIPT := preload("res://src/entities/enemy.gd")
const ENEMY_COMBAT_ROLE_RUNTIME_SCRIPT := preload("res://src/entities/enemy_combat_role_runtime.gd")

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
	print("TACTIC FLANK REQUIRES PATH AND TIME BUDGET TEST")
	print("============================================================")

	_test_flank_allowed_when_within_budget()
	_test_flank_blocked_when_time_exceeds_budget()
	_test_flank_blocked_when_path_exceeds_max_px()
	_test_flank_fallback_to_pressure_when_blocked()

	_t.summary("TACTIC FLANK BUDGET GUARD RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _new_runtime():
	return ENEMY_COMBAT_ROLE_RUNTIME_SCRIPT.new()


func _test_flank_allowed_when_within_budget() -> void:
	var runtime = _new_runtime()
	var assignment := {
		"role": Enemy.SQUAD_ROLE_FLANK,
		"has_slot": true,
		"path_ok": true,
		"slot_path_length": 500.0,
	}
	var ok := bool(runtime.call("assignment_supports_flank_role", assignment))
	_t.run_test("FLANK allowed within distance/time budget", ok)
	runtime = null


func _test_flank_blocked_when_time_exceeds_budget() -> void:
	var runtime = _new_runtime()
	var assignment := {
		"role": Enemy.SQUAD_ROLE_FLANK,
		"has_slot": true,
		"path_ok": true,
		"slot_path_length": 600.0,
	}
	var ok := not bool(runtime.call("assignment_supports_flank_role", assignment))
	_t.run_test("FLANK blocked when ETA exceeds budget", ok)
	runtime = null


func _test_flank_blocked_when_path_exceeds_max_px() -> void:
	var runtime = _new_runtime()
	var assignment := {
		"role": Enemy.SQUAD_ROLE_FLANK,
		"has_slot": true,
		"path_ok": true,
		"slot_path_length": 950.0,
	}
	var ok := not bool(runtime.call("assignment_supports_flank_role", assignment))
	_t.run_test("FLANK blocked when path length exceeds max", ok)
	runtime = null


func _test_flank_fallback_to_pressure_when_blocked() -> void:
	var runtime = _new_runtime()
	var bad_assignment := {
		"role": Enemy.SQUAD_ROLE_FLANK,
		"has_slot": true,
		"path_ok": true,
		"slot_path_length": INF,
	}
	# Phase 10 spec fixture had a valid-contact contradiction; this uses no-contact fallback, matching current runtime logic.
	var role := int(
		runtime.call("resolve_contextual_combat_role", Enemy.SQUAD_ROLE_FLANK, false, 500.0, bad_assignment)
	)
	_t.run_test("Invalid FLANK falls back to PRESSURE in no-contact path", role == Enemy.SQUAD_ROLE_PRESSURE)
	runtime = null
