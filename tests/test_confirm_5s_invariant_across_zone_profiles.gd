extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")
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
	print("CONFIRM 5S INVARIANT ACROSS ZONE PROFILES TEST")
	print("============================================================")

	await _test_confirm_5s_invariant()

	_t.summary("CONFIRM 5S INVARIANT ACROSS ZONE PROFILES RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_confirm_5s_invariant() -> void:
	var director := ZONE_DIRECTOR_SCRIPT.new()
	add_child(director)
	director.initialize([{"id": 0, "rooms": [0]}], [], null)

	var calm_time: float = _time_to_confirm_combat(director.get_zone_profile_for_state(CALM))
	var elevated_time: float = _time_to_confirm_combat(director.get_zone_profile_for_state(ELEVATED))
	var lockdown_time: float = _time_to_confirm_combat(director.get_zone_profile_for_state(LOCKDOWN))
	var spread: float = maxf(calm_time, maxf(elevated_time, lockdown_time)) - minf(calm_time, minf(elevated_time, lockdown_time))

	_t.run_test("CALM profile keeps confirm->combat at 5.0±0.2s", calm_time >= 4.8 and calm_time <= 5.2)
	_t.run_test("ELEVATED profile keeps confirm->combat at 5.0±0.2s", elevated_time >= 4.8 and elevated_time <= 5.2)
	_t.run_test("LOCKDOWN profile keeps confirm->combat at 5.0±0.2s", lockdown_time >= 4.8 and lockdown_time <= 5.2)
	_t.run_test("confirm timing spread across profiles is <= 0.2s", spread <= 0.2)

	director.queue_free()
	await get_tree().process_frame


func _time_to_confirm_combat(zone_profile: Dictionary) -> float:
	var config: Dictionary = {}
	if GameConfig and GameConfig.stealth_canon is Dictionary:
		config = (GameConfig.stealth_canon as Dictionary).duplicate(true)
	config["confirm_time_to_engage"] = 5.0
	config["confirm_decay_rate"] = 1.25
	config["confirm_grace_window"] = 0.50
	# These zone-profile fields must not affect confirm timing.
	config["alert_sweep_budget_scale"] = zone_profile.get("alert_sweep_budget_scale", 1.0)
	config["role_weights_profiled"] = zone_profile.get("role_weights_profiled", {})
	config["reinforcement_cooldown_scale"] = zone_profile.get("reinforcement_cooldown_scale", 1.0)
	config["flashlight_active_cap"] = zone_profile.get("flashlight_active_cap", 1)
	config["zone_refill_scale"] = zone_profile.get("zone_refill_scale", 0.0)

	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	var elapsed: float = 0.0
	for _i in range(80):
		elapsed += 0.1
		var transitions := awareness.process_confirm(0.1, true, false, false, config)
		if _has_confirmed_contact_transition(transitions):
			return elapsed
	return INF


func _has_confirmed_contact_transition(transitions: Array[Dictionary]) -> bool:
	for tr_variant in transitions:
		var tr := tr_variant as Dictionary
		if String(tr.get("to_state", "")) != "COMBAT":
			continue
		if String(tr.get("reason", "")) == "confirmed_contact":
			return true
	return false
