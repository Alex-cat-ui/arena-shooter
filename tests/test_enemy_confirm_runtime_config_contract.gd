extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCRIPT := preload("res://src/entities/enemy.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeZoneDirector:
	extends Node

	var room_to_zone: Dictionary = {}
	var zone_states: Dictionary = {}

	func get_zone_for_room(room_id: int) -> int:
		return int(room_to_zone.get(room_id, -1))

	func get_zone_state(zone_id: int) -> int:
		return int(zone_states.get(zone_id, -1))


func _ready() -> void:
	if embedded_mode:
		return
	var result := run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ENEMY CONFIRM RUNTIME CONFIG CONTRACT TEST")
	print("============================================================")

	_test_config_exposes_required_keys_and_values()
	_test_build_does_not_mutate_base_input()
	_test_lockdown_no_contact_window_contract()

	_t.summary("ENEMY CONFIRM RUNTIME CONFIG CONTRACT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_config_exposes_required_keys_and_values() -> void:
	var enemy := ENEMY_SCRIPT.new()
	enemy.set("_combat_search_progress", 0.37)
	enemy.set("_combat_search_total_elapsed_sec", 4.5)
	enemy.set("_combat_search_room_elapsed_sec", 1.25)
	enemy.set("_combat_search_total_cap_hit", true)

	var config := enemy.call("_build_confirm_runtime_config", {"confirm_time_to_engage": 5.0}) as Dictionary
	var required_keys := [
		"combat_no_contact_window_sec",
		"combat_require_search_progress",
		"combat_search_progress",
		"combat_search_total_elapsed_sec",
		"combat_search_room_elapsed_sec",
		"combat_search_total_cap_sec",
		"combat_search_force_complete",
	]
	var has_all := true
	for key_variant in required_keys:
		var key := String(key_variant)
		if not config.has(key):
			has_all = false
			break

	var values_ok := (
		is_equal_approx(float(config.get("combat_no_contact_window_sec", -1.0)), 8.0)
		and bool(config.get("combat_require_search_progress", false))
		and is_equal_approx(float(config.get("combat_search_progress", -1.0)), 0.37)
		and is_equal_approx(float(config.get("combat_search_total_elapsed_sec", -1.0)), 4.5)
		and is_equal_approx(float(config.get("combat_search_room_elapsed_sec", -1.0)), 1.25)
		and is_equal_approx(float(config.get("combat_search_total_cap_sec", -1.0)), 24.0)
		and bool(config.get("combat_search_force_complete", false))
	)

	_t.run_test("confirm runtime config keeps required key contract", has_all)
	_t.run_test("confirm runtime config reflects enemy search runtime values", values_ok)
	enemy.free()


func _test_build_does_not_mutate_base_input() -> void:
	var enemy := ENEMY_SCRIPT.new()
	var base := {"confirm_time_to_engage": 3.0}
	var before := base.duplicate(true)
	var _cfg := enemy.call("_build_confirm_runtime_config", base) as Dictionary
	var unchanged := base.hash() == before.hash() and not base.has("combat_search_progress")
	_t.run_test("_build_confirm_runtime_config does not mutate caller dictionary", unchanged)
	enemy.free()


func _test_lockdown_no_contact_window_contract() -> void:
	var enemy := ENEMY_SCRIPT.new()
	var zone := FakeZoneDirector.new()
	zone.room_to_zone[7] = 21
	zone.zone_states[21] = 2
	enemy.set("_zone_director", zone)
	enemy.set_meta("room_id", 7)

	var lockdown_config := enemy.call("_build_confirm_runtime_config", {}) as Dictionary
	var lockdown_ok := is_equal_approx(float(lockdown_config.get("combat_no_contact_window_sec", -1.0)), 12.0)

	zone.zone_states[21] = 1
	var normal_config := enemy.call("_build_confirm_runtime_config", {}) as Dictionary
	var normal_ok := is_equal_approx(float(normal_config.get("combat_no_contact_window_sec", -1.0)), 8.0)

	_t.run_test("lockdown contract: no-contact window expands to 12s", lockdown_ok)
	_t.run_test("non-lockdown contract: no-contact window stays 8s", normal_ok)
	enemy.free()
	zone.free()
