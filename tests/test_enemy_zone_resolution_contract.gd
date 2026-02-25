extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")

const ZONE_STATE_ELEVATED := 1
const ZONE_STATE_LOCKDOWN := 2

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
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ENEMY ZONE RESOLUTION CONTRACT TEST")
	print("============================================================")

	await _test_zone_resolution_contract_via_alert_latch_runtime()

	_t.summary("ENEMY ZONE RESOLUTION CONTRACT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_zone_resolution_contract_via_alert_latch_runtime() -> void:
	var world := Node2D.new()
	add_child(world)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame

	enemy.initialize(84811, "zombie")
	enemy.set_process(false)
	enemy.set_physics_process(false)
	enemy.set_meta("room_id", 7)

	var zone := FakeZoneDirector.new()
	zone.room_to_zone[7] = 21
	zone.zone_states[21] = ZONE_STATE_LOCKDOWN
	world.add_child(zone)
	enemy.set_zone_director(zone)

	var runtime: Variant = (enemy.get_runtime_helper_refs() as Dictionary).get("alert_latch_runtime", null)
	_t.run_test("zone runtime: helper is available", runtime != null)
	if runtime == null:
		world.queue_free()
		await get_tree().process_frame
		return

	var runtime_zone_state := int(runtime.call("get_zone_state"))
	var explicit_room_zone_state := int(runtime.call("resolve_zone_state_for_room", 7))
	var ui_snapshot := enemy.get_ui_awareness_snapshot() as Dictionary
	_t.run_test(
		"zone runtime: room->zone lookup resolves LOCKDOWN state",
		runtime_zone_state == ZONE_STATE_LOCKDOWN
		and explicit_room_zone_state == ZONE_STATE_LOCKDOWN
		and int(ui_snapshot.get("zone_state", -1)) == ZONE_STATE_LOCKDOWN
	)
	_t.run_test(
		"zone runtime: lockdown predicate is true for LOCKDOWN",
		bool(runtime.call("is_zone_lockdown"))
	)

	zone.zone_states[21] = ZONE_STATE_ELEVATED
	ui_snapshot = enemy.get_ui_awareness_snapshot() as Dictionary
	_t.run_test(
		"zone runtime: state updates reflect ELEVATED and clear lockdown predicate",
		int(runtime.call("get_zone_state")) == ZONE_STATE_ELEVATED
		and int(ui_snapshot.get("zone_state", -1)) == ZONE_STATE_ELEVATED
		and not bool(runtime.call("is_zone_lockdown"))
	)

	enemy.set_zone_director(null)
	_t.run_test(
		"zone runtime: null zone_director returns -1 state",
		int(runtime.call("get_zone_state")) == -1
		and int(runtime.call("resolve_zone_state_for_room", 7)) == -1
	)

	world.queue_free()
	await get_tree().process_frame
