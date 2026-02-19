extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ZONE_DIRECTOR_SCRIPT := preload("res://src/systems/zone_director.gd")

const CALM := 0
const ELEVATED := 1
const LOCKDOWN := 2

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _events: Array[Dictionary] = []


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ZONE STATE MACHINE CONTRACT TEST")
	print("============================================================")

	await _test_zone_state_machine_contract()

	_t.summary("ZONE STATE MACHINE CONTRACT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_zone_state_machine_contract() -> void:
	_events.clear()
	if EventBus and not EventBus.zone_state_changed.is_connected(_on_zone_state_changed):
		EventBus.zone_state_changed.connect(_on_zone_state_changed)

	var director := ZONE_DIRECTOR_SCRIPT.new()
	add_child(director)
	director.initialize([{"id": 0, "rooms": [0]}], [], null)

	_t.run_test("initial state is CALM", director.get_zone_state(0) == CALM)

	EventBus.emit_enemy_state_changed(8101, "CALM", "ALERT", 0, "vision")
	await _flush_event_bus_frames()
	_t.run_test("ALERT event promotes CALM->ELEVATED", director.get_zone_state(0) == ELEVATED)

	director.update(2.1)
	EventBus.emit_enemy_state_changed(8101, "ALERT", "COMBAT", 0, "confirmed_contact")
	await _flush_event_bus_frames()
	_t.run_test("COMBAT event promotes ELEVATED->LOCKDOWN", director.get_zone_state(0) == LOCKDOWN)

	_advance(director, 24.2)
	await _flush_event_bus_frames()
	_t.run_test("LOCKDOWN decays to ELEVATED after hold/no-events", director.get_zone_state(0) == ELEVATED)
	_advance(director, 16.2)
	await _flush_event_bus_frames()
	_t.run_test("ELEVATED decays to CALM after hold/no-events", director.get_zone_state(0) == CALM)

	var transition_trace: PackedStringArray = []
	for event_variant in _events:
		var event := event_variant as Dictionary
		if int(event.get("zone_id", -1)) != 0:
			continue
		transition_trace.append("%d>%d" % [int(event.get("old", -1)), int(event.get("new", -1))])

	var required := PackedStringArray([
		"0>1",
		"1>2",
		"2>1",
		"1>0",
	])
	var has_expected_sequence := true
	var cursor := -1
	for step in required:
		var idx := transition_trace.find(step, cursor + 1)
		if idx < 0:
			has_expected_sequence = false
			break
		cursor = idx
	_t.run_test("zone_state_changed emits canonical transition sequence", has_expected_sequence)

	if EventBus and EventBus.zone_state_changed.is_connected(_on_zone_state_changed):
		EventBus.zone_state_changed.disconnect(_on_zone_state_changed)
	director.queue_free()
	await get_tree().process_frame


func _on_zone_state_changed(zone_id: int, old_state: int, new_state: int) -> void:
	_events.append({
		"zone_id": zone_id,
		"old": old_state,
		"new": new_state,
	})


func _advance(director: Node, total_sec: float, step_sec: float = 0.1) -> void:
	var remaining := maxf(total_sec, 0.0)
	while remaining > 0.0:
		var dt := minf(step_sec, remaining)
		director.update(dt)
		remaining -= dt


func _flush_event_bus_frames(frames: int = 3) -> void:
	for _i in range(frames):
		await get_tree().process_frame
