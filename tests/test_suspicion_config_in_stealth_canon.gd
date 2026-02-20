extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")

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
	print("SUSPICION CONFIG IN STEALTH CANON TEST")
	print("============================================================")

	_test_suspicion_defaults_in_stealth_canon()

	_t.summary("SUSPICION CONFIG IN STEALTH CANON RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_suspicion_defaults_in_stealth_canon() -> void:
	var canon := GameConfig.DEFAULT_STEALTH_CANON as Dictionary
	var has_all_keys := (
		canon.has("suspicion_decay_rate")
		and canon.has("suspicion_gain_partial")
		and canon.has("suspicion_gain_silhouette")
		and canon.has("suspicion_gain_flashlight_glimpse")
	)
	_t.run_test("stealth canon contains all 4 suspicion keys", has_all_keys)
	if not has_all_keys:
		return

	var has_expected_values := (
		is_equal_approx(float(canon.get("suspicion_decay_rate", -1.0)), 0.55)
		and is_equal_approx(float(canon.get("suspicion_gain_partial", -1.0)), 0.24)
		and is_equal_approx(float(canon.get("suspicion_gain_silhouette", -1.0)), 0.18)
		and is_equal_approx(float(canon.get("suspicion_gain_flashlight_glimpse", -1.0)), 0.30)
	)
	_t.run_test("stealth canon suspicion values match expected defaults", has_expected_values)

	var matches_awareness_defaults := (
		is_equal_approx(
			float(canon.get("suspicion_decay_rate", -1.0)),
			float(ENEMY_AWARENESS_SYSTEM_SCRIPT.DEFAULT_SUSPICION_DECAY_RATE)
		)
		and is_equal_approx(
			float(canon.get("suspicion_gain_partial", -1.0)),
			float(ENEMY_AWARENESS_SYSTEM_SCRIPT.DEFAULT_SUSPICION_GAIN_PARTIAL)
		)
		and is_equal_approx(
			float(canon.get("suspicion_gain_silhouette", -1.0)),
			float(ENEMY_AWARENESS_SYSTEM_SCRIPT.DEFAULT_SUSPICION_GAIN_SILHOUETTE)
		)
		and is_equal_approx(
			float(canon.get("suspicion_gain_flashlight_glimpse", -1.0)),
			float(ENEMY_AWARENESS_SYSTEM_SCRIPT.DEFAULT_SUSPICION_GAIN_FLASHLIGHT_GLIMPSE)
		)
	)
	_t.run_test("stealth canon suspicion values stay in sync with awareness defaults", matches_awareness_defaults)
