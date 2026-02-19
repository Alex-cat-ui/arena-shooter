extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ZONE_DIRECTOR_SCRIPT := preload("res://src/systems/zone_director.gd")

const CALM := 0
const ELEVATED := 1
const LOCKDOWN := 2

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
	print("ZONE PROFILE MODIFIERS EXACT VALUES TEST")
	print("============================================================")

	await _test_zone_profile_exact_values()

	_t.summary("ZONE PROFILE MODIFIERS EXACT VALUES RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_zone_profile_exact_values() -> void:
	var director := ZONE_DIRECTOR_SCRIPT.new()
	add_child(director)
	director.initialize([{"id": 0, "rooms": [0]}], [], null)

	var calm_ok: bool = _profile_equals(
		director.get_zone_profile_for_state(CALM),
		0.85,
		0.30,
		0.60,
		0.10,
		1.25,
		1,
		0.0
	)
	var elevated_ok: bool = _profile_equals(
		director.get_zone_profile_for_state(ELEVATED),
		1.10,
		0.45,
		0.40,
		0.15,
		0.90,
		2,
		0.35
	)
	var lockdown_ok: bool = _profile_equals(
		director.get_zone_profile_for_state(LOCKDOWN),
		1.45,
		0.60,
		0.25,
		0.15,
		0.65,
		4,
		1.00
	)

	var cfg_profiles_ok: bool = false
	if GameConfig and GameConfig.zone_system is Dictionary:
		var zone_system := GameConfig.zone_system as Dictionary
		var profiles_variant: Variant = zone_system.get("zone_profiles", {})
		if profiles_variant is Dictionary:
			var profiles := profiles_variant as Dictionary
			cfg_profiles_ok = profiles.has("CALM") and profiles.has("ELEVATED") and profiles.has("LOCKDOWN")

	_t.run_test("zone profile values for CALM are exact", calm_ok)
	_t.run_test("zone profile values for ELEVATED are exact", elevated_ok)
	_t.run_test("zone profile values for LOCKDOWN are exact", lockdown_ok)
	_t.run_test("GameConfig.zone_system stores all 3 zone profiles", cfg_profiles_ok)

	director.queue_free()
	await get_tree().process_frame


func _profile_equals(
	profile: Dictionary,
	sweep: float,
	pressure: float,
	hold: float,
	flank: float,
	reinforcement_scale: float,
	flashlight_cap: int,
	refill: float
) -> bool:
	var weights := profile.get("role_weights_profiled", {}) as Dictionary
	return (
		is_equal_approx(float(profile.get("alert_sweep_budget_scale", -1.0)), sweep)
		and is_equal_approx(float(weights.get("PRESSURE", -1.0)), pressure)
		and is_equal_approx(float(weights.get("HOLD", -1.0)), hold)
		and is_equal_approx(float(weights.get("FLANK", -1.0)), flank)
		and is_equal_approx(float(profile.get("reinforcement_cooldown_scale", -1.0)), reinforcement_scale)
		and int(profile.get("flashlight_active_cap", -1)) == flashlight_cap
		and is_equal_approx(float(profile.get("zone_refill_scale", -1.0)), refill)
	)
