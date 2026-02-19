extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ZONE_DIRECTOR_SCRIPT := preload("res://src/systems/zone_director.gd")

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
	print("ZONE REINFORCEMENT BUDGET CONTRACT TEST")
	print("============================================================")

	await _test_zone_reinforcement_budget_contract()

	_t.summary("ZONE REINFORCEMENT BUDGET CONTRACT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_zone_reinforcement_budget_contract() -> void:
	var director := ZONE_DIRECTOR_SCRIPT.new()
	add_child(director)
	director.initialize([{"id": 0, "rooms": [0]}], [], null)

	director.trigger_elevated(0)
	_t.run_test("ELEVATED starts with reinforcement budget available", director.can_spawn_reinforcement(0))

	director.register_reinforcement_wave(0, 2)
	var after_wave := director.debug_get_zone_budget_snapshot(0)
	_t.run_test("register_reinforcement_wave consumes wave+enemy credits", int(after_wave.get("reinforcement_waves", -1)) == 1 and int(after_wave.get("reinforcement_enemies", -1)) == 2)
	_t.run_test("after consuming ELEVATED cap, can_spawn_reinforcement becomes false", not director.can_spawn_reinforcement(0))

	director.update(2.1)
	director.trigger_lockdown(0)
	_t.run_test("LOCKDOWN state expands caps and restores spawn capability", director.can_spawn_reinforcement(0))

	var accepted := director.validate_reinforcement_call(8201, 0, "COMBAT", 101, 10.0) as Dictionary
	var dedup_block := director.validate_reinforcement_call(8201, 0, "COMBAT", 101, 10.5) as Dictionary
	_t.run_test("LOCKDOWN accepts valid COMBAT reinforcement call", bool(accepted.get("accepted", false)))
	_t.run_test("dedup TTL blocks repeated call_id", not bool(dedup_block.get("accepted", true)))

	director.queue_free()
	await get_tree().process_frame
