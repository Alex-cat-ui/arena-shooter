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
	print("ZONE DIRECTOR TEST")
	print("============================================================")

	_test_zone_initial_state_calm()
	_test_lockdown_sets_zone()
	_test_lockdown_never_resets()
	_test_spread_elevated_at_2s()
	_test_spread_far_elevated_at_5s()
	_test_reinforcement_cap_1_wave()
	_test_reinforcement_cap_2_enemies()
	_test_killing_does_not_reset_zone()

	_t.summary("ZONE DIRECTOR RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_zone_initial_state_calm() -> void:
	var director := _new_director(_chain_zone_config(), _chain_zone_edges())
	var ok: bool = director.get_zone_state(0) == CALM and director.get_zone_state(1) == CALM and director.get_zone_state(2) == CALM
	_t.run_test("zone_initial_state_calm", ok)
	director.queue_free()


func _test_lockdown_sets_zone() -> void:
	var director := _new_director(_chain_zone_config(), _chain_zone_edges())
	director.trigger_lockdown(0)
	_t.run_test("lockdown_sets_zone", director.get_zone_state(0) == LOCKDOWN)
	director.queue_free()


func _test_lockdown_never_resets() -> void:
	var director := _new_director(_chain_zone_config(), _chain_zone_edges())
	director.trigger_lockdown(0)
	_advance(director, 999.0)
	_t.run_test("lockdown_never_resets", director.get_zone_state(0) == LOCKDOWN)
	director.queue_free()


func _test_spread_elevated_at_2s() -> void:
	var director := _new_director(_pair_zone_config(), _pair_zone_edges())
	director.trigger_lockdown(0)
	_advance(director, 1.9)
	var before: bool = bool(director.get_zone_state(1) == CALM)
	_advance(director, 0.2)
	var after: bool = bool(director.get_zone_state(1) == ELEVATED)
	_t.run_test("spread_elevated_at_2s", before and after)
	director.queue_free()


func _test_spread_far_elevated_at_5s() -> void:
	var director := _new_director(_chain_zone_config(), _chain_zone_edges())
	director.trigger_lockdown(0)
	_advance(director, 4.9)
	var before: bool = bool(director.get_zone_state(2) == CALM)
	_advance(director, 0.2)
	var after: bool = bool(director.get_zone_state(2) == ELEVATED)
	_t.run_test("spread_far_elevated_at_5s", before and after)
	director.queue_free()


func _test_reinforcement_cap_1_wave() -> void:
	var director := _new_director(_pair_zone_config(), _pair_zone_edges())
	var first_allowed: bool = director.can_spawn_reinforcement(0)
	director.register_reinforcement_wave(0, 1)
	var second_allowed: bool = director.can_spawn_reinforcement(0)
	_t.run_test("reinforcement_cap_1_wave", first_allowed and not second_allowed)
	director.queue_free()


func _test_reinforcement_cap_2_enemies() -> void:
	var original_zone_system := _clone_zone_system()
	if GameConfig:
		GameConfig.zone_system["max_reinforcement_waves_per_zone"] = 99
		GameConfig.zone_system["max_reinforcement_enemies_per_zone"] = 2

	var director := _new_director(_pair_zone_config(), _pair_zone_edges())
	director.register_reinforcement_wave(0, 2)
	var third_blocked: bool = not director.can_spawn_reinforcement(0)
	_t.run_test("reinforcement_cap_2_enemies", third_blocked)
	director.queue_free()

	if GameConfig:
		GameConfig.zone_system = original_zone_system


func _test_killing_does_not_reset_zone() -> void:
	var director := _new_director(_pair_zone_config(), _pair_zone_edges())
	director.trigger_lockdown(0)
	director.register_reinforcement_wave(0, 2)
	_advance(director, 30.0)
	director.trigger_elevated(0)
	_t.run_test("killing_does_not_reset_zone", director.get_zone_state(0) == LOCKDOWN)
	director.queue_free()


func _new_director(zone_config: Array[Dictionary], zone_edges: Array[Array]) -> Node:
	var director := ZONE_DIRECTOR_SCRIPT.new()
	add_child(director)
	director.initialize(zone_config, zone_edges, null)
	return director


func _advance(director: Node, total_sec: float, step_sec: float = 0.1) -> void:
	var remaining := maxf(total_sec, 0.0)
	while remaining > 0.0:
		var dt := minf(step_sec, remaining)
		director.update(dt)
		remaining -= dt


func _clone_zone_system() -> Dictionary:
	if GameConfig and GameConfig.zone_system is Dictionary:
		return (GameConfig.zone_system as Dictionary).duplicate(true)
	return {}


func _pair_zone_config() -> Array[Dictionary]:
	return [
		{"id": 0, "rooms": [0]},
		{"id": 1, "rooms": [1]},
	]


func _pair_zone_edges() -> Array[Array]:
	return [[0, 1]]


func _chain_zone_config() -> Array[Dictionary]:
	return [
		{"id": 0, "rooms": [0]},
		{"id": 1, "rooms": [1]},
		{"id": 2, "rooms": [2]},
	]


func _chain_zone_edges() -> Array[Array]:
	return [[0, 1], [1, 2]]
