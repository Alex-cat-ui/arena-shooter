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

	await _test_zone_initial_state_calm()
	await _test_room_alert_event_promotes_to_elevated()
	await _test_room_combat_event_promotes_to_lockdown()
	await _test_lockdown_and_elevated_decay_hysteresis()
	await _test_transition_throttle_no_multiple_transitions_within_2s()

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
	await get_tree().process_frame


func _test_room_alert_event_promotes_to_elevated() -> void:
	var director := _new_director(_pair_zone_config(), _pair_zone_edges())
	EventBus.emit_enemy_state_changed(1001, "CALM", "ALERT", 0, "vision")
	await _flush_event_bus_frames()
	_t.run_test("room_alert_event_promotes_to_elevated", director.get_zone_state(0) == ELEVATED)
	director.queue_free()
	await get_tree().process_frame


func _test_room_combat_event_promotes_to_lockdown() -> void:
	var director := _new_director(_pair_zone_config(), _pair_zone_edges())
	EventBus.emit_enemy_state_changed(1002, "ALERT", "COMBAT", 0, "confirmed_contact")
	await _flush_event_bus_frames()
	_t.run_test("room_combat_event_promotes_to_lockdown", director.get_zone_state(0) == LOCKDOWN)
	director.queue_free()
	await get_tree().process_frame


func _test_lockdown_and_elevated_decay_hysteresis() -> void:
	var director := _new_director(_pair_zone_config(), _pair_zone_edges())
	EventBus.emit_enemy_state_changed(1003, "ALERT", "COMBAT", 0, "confirmed_contact")
	await _flush_event_bus_frames()
	_advance(director, 23.9)
	var before_lockdown_decay: bool = director.get_zone_state(0) == LOCKDOWN
	_advance(director, 0.2)
	var after_lockdown_decay: bool = director.get_zone_state(0) == ELEVATED
	_advance(director, 15.9)
	var before_calm_decay: bool = director.get_zone_state(0) == ELEVATED
	_advance(director, 0.2)
	var after_calm_decay: bool = director.get_zone_state(0) == CALM
	_t.run_test(
		"lockdown_and_elevated_decay_hysteresis",
		before_lockdown_decay and after_lockdown_decay and before_calm_decay and after_calm_decay
	)
	director.queue_free()
	await get_tree().process_frame


func _test_transition_throttle_no_multiple_transitions_within_2s() -> void:
	var director := _new_director(_pair_zone_config(), _pair_zone_edges())
	EventBus.emit_enemy_state_changed(1004, "CALM", "ALERT", 0, "vision")
	await _flush_event_bus_frames()
	EventBus.emit_enemy_state_changed(1004, "ALERT", "COMBAT", 0, "confirmed_contact")
	await _flush_event_bus_frames()
	var blocked_by_throttle: bool = director.get_zone_state(0) == ELEVATED
	_advance(director, 2.1)
	EventBus.emit_enemy_state_changed(1004, "ALERT", "COMBAT", 0, "confirmed_contact")
	await _flush_event_bus_frames()
	var accepted_after_window: bool = director.get_zone_state(0) == LOCKDOWN
	_t.run_test("transition_throttle_no_multiple_transitions_within_2s", blocked_by_throttle and accepted_after_window)
	director.queue_free()
	await get_tree().process_frame


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


func _flush_event_bus_frames(frames: int = 3) -> void:
	for _i in range(frames):
		await get_tree().process_frame


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
