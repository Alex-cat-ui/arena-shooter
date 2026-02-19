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
	print("ZONE HYSTERESIS HOLD AND NO-EVENT DECAY TEST")
	print("============================================================")

	await _test_hysteresis_hold_and_no_event_decay()
	await _test_no_event_timer_resets_only_on_zone_events()

	_t.summary("ZONE HYSTERESIS HOLD AND NO-EVENT DECAY RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_hysteresis_hold_and_no_event_decay() -> void:
	var director := _new_director()
	EventBus.emit_enemy_state_changed(7101, "ALERT", "COMBAT", 0, "confirmed_contact")
	await _flush_event_bus_frames()

	_advance(director, 23.9)
	var before_lockdown_decay: bool = director.get_zone_state(0) == LOCKDOWN
	_advance(director, 0.2)
	var after_lockdown_decay: bool = director.get_zone_state(0) == ELEVATED
	_advance(director, 15.9)
	var before_elevated_decay: bool = director.get_zone_state(0) == ELEVATED
	_advance(director, 0.2)
	var after_elevated_decay: bool = director.get_zone_state(0) == CALM

	_t.run_test(
		"hysteresis hold gates LOCKDOWN->ELEVATED->CALM decay",
		before_lockdown_decay and after_lockdown_decay and before_elevated_decay and after_elevated_decay
	)
	director.queue_free()
	await get_tree().process_frame


func _test_no_event_timer_resets_only_on_zone_events() -> void:
	var director := _new_director()
	EventBus.emit_enemy_state_changed(7102, "CALM", "ALERT", 0, "vision")
	await _flush_event_bus_frames()
	_advance(director, 11.5)
	director.record_accepted_teammate_call(0, 0)
	_advance(director, 1.0)
	var held_after_reset: bool = director.get_zone_state(0) == ELEVATED
	_advance(director, 11.2)
	var decayed_after_reset_window: bool = director.get_zone_state(0) == CALM
	_t.run_test("zone event resets no-event timer before ELEVATED->CALM decay", held_after_reset and decayed_after_reset_window)
	director.queue_free()
	await get_tree().process_frame


func _new_director() -> Node:
	var director := ZONE_DIRECTOR_SCRIPT.new()
	add_child(director)
	director.initialize([{"id": 0, "rooms": [0]}], [], null)
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
