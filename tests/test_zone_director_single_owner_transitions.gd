extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ZONE_DIRECTOR_SCRIPT := preload("res://src/systems/zone_director.gd")

const CALM := 0
const ELEVATED := 1
const LOCKDOWN := 2

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _zone_state_events: Array[Dictionary] = []


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ZONE DIRECTOR SINGLE OWNER TRANSITIONS TEST")
	print("============================================================")

	await _test_owner_transitions_by_zone_events_only()
	await _test_elevated_to_lockdown_on_confirmed_contacts_window()

	_t.summary("ZONE DIRECTOR SINGLE OWNER TRANSITIONS RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_owner_transitions_by_zone_events_only() -> void:
	_zone_state_events.clear()
	if EventBus and not EventBus.zone_state_changed.is_connected(_on_zone_state_changed):
		EventBus.zone_state_changed.connect(_on_zone_state_changed)

	var director := ZONE_DIRECTOR_SCRIPT.new()
	add_child(director)
	director.initialize([{"id": 0, "rooms": [0]}], [], null)

	_t.run_test("initial zone state is CALM", director.get_zone_state(0) == CALM)
	EventBus.emit_enemy_state_changed(7001, "CALM", "ALERT", 0, "vision")
	await _flush_event_bus_frames()
	_t.run_test("CALM -> ELEVATED on room ALERT event", director.get_zone_state(0) == ELEVATED)

	director.update(2.1)
	EventBus.emit_enemy_state_changed(7001, "ALERT", "COMBAT", 0, "confirmed_contact")
	await _flush_event_bus_frames()
	_t.run_test("ELEVATED -> LOCKDOWN on room COMBAT event", director.get_zone_state(0) == LOCKDOWN)

	var sequence_ok: bool = _zone_state_events.size() == 2
	if sequence_ok:
		sequence_ok = int(_zone_state_events[0].get("old", -1)) == CALM and int(_zone_state_events[0].get("new", -1)) == ELEVATED
		sequence_ok = sequence_ok and int(_zone_state_events[1].get("old", -1)) == ELEVATED and int(_zone_state_events[1].get("new", -1)) == LOCKDOWN
	_t.run_test("zone_state_changed sequence owned by ZoneDirector", sequence_ok)

	if EventBus and EventBus.zone_state_changed.is_connected(_on_zone_state_changed):
		EventBus.zone_state_changed.disconnect(_on_zone_state_changed)
	director.queue_free()
	await get_tree().process_frame


func _test_elevated_to_lockdown_on_confirmed_contacts_window() -> void:
	var director := ZONE_DIRECTOR_SCRIPT.new()
	add_child(director)
	director.initialize([{"id": 0, "rooms": [0]}], [], null)

	EventBus.emit_enemy_state_changed(7002, "CALM", "ALERT", 0, "vision")
	await _flush_event_bus_frames()
	director.update(2.1)
	EventBus.emit_enemy_player_spotted(7002, Vector3.ZERO)
	EventBus.emit_enemy_player_spotted(7002, Vector3.ZERO)
	EventBus.emit_enemy_player_spotted(7002, Vector3.ZERO)
	await _flush_event_bus_frames()
	_t.run_test("ELEVATED -> LOCKDOWN on 3 confirmed contacts in 8s", director.get_zone_state(0) == LOCKDOWN)

	director.queue_free()
	await get_tree().process_frame


func _on_zone_state_changed(zone_id: int, old_state: int, new_state: int) -> void:
	_zone_state_events.append({
		"zone_id": zone_id,
		"old": old_state,
		"new": new_state,
	})


func _flush_event_bus_frames(frames: int = 3) -> void:
	for _i in range(frames):
		await get_tree().process_frame
