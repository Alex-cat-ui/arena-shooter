extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_AGGRO_COORDINATOR_SCRIPT := preload("res://src/systems/enemy_aggro_coordinator.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _teammate_calls: int = 0
var _reinforcement_calls: int = 0


class FakeNav:
	extends Node

	var neighbors_by_room: Dictionary = {}

	func get_enemy_room_id(enemy: Node) -> int:
		return int(enemy.get_meta("room_id", -1))

	func get_neighbors(room_id: int) -> Array:
		return neighbors_by_room.get(room_id, [])

	func is_adjacent(a: int, b: int) -> bool:
		return (neighbors_by_room.get(a, []) as Array).has(b)

	func pick_top2_neighbor_rooms_for_reinforcement(source_room: int, _player_pos: Vector2) -> Array:
		return get_neighbors(source_room)

	func get_player_position() -> Vector2:
		return Vector2.ZERO


class FakeEnemy:
	extends Node

	var entity_id: int = 0
	var teammate_accepts: int = 0

	func _init(p_entity_id: int, room_id: int) -> void:
		entity_id = p_entity_id
		set_meta("room_id", room_id)
		set_meta("awareness_state", "CALM")
		add_to_group("enemies")

	func apply_teammate_call(_source_enemy_id: int, _source_room_id: int, _call_id: int = -1, _shot_pos: Vector2 = Vector2.ZERO) -> bool:
		teammate_accepts += 1
		var from_state := String(get_meta("awareness_state", "CALM"))
		set_meta("awareness_state", "ALERT")
		if EventBus:
			EventBus.emit_enemy_state_changed(entity_id, from_state, "ALERT", int(get_meta("room_id", -1)), "teammate_call")
		return true


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ALERT CALL ONLY ON STATE ENTRY TEST")
	print("============================================================")

	await _test_call_only_on_suspicious_to_alert_edge()

	_t.summary("ALERT CALL ONLY ON STATE ENTRY RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_call_only_on_suspicious_to_alert_edge() -> void:
	var fixture := _create_fixture()
	var coordinator := fixture.get("coordinator") as Node
	var source := fixture.get("source") as FakeEnemy

	_teammate_calls = 0
	_reinforcement_calls = 0
	if not EventBus.enemy_teammate_call.is_connected(_on_teammate_call):
		EventBus.enemy_teammate_call.connect(_on_teammate_call)
	if not EventBus.enemy_reinforcement_called.is_connected(_on_reinforcement_call):
		EventBus.enemy_reinforcement_called.connect(_on_reinforcement_call)

	coordinator.call("debug_set_time_override_sec", 0.0)
	EventBus.emit_enemy_state_changed(source.entity_id, "CALM", "ALERT", 10, "vision")
	await _flush_event_bus_frames()
	EventBus.emit_enemy_state_changed(source.entity_id, "ALERT", "ALERT", 10, "vision")
	await _flush_event_bus_frames()
	var calls_after_non_edge := _teammate_calls
	var reinforcement_after_non_edge := _reinforcement_calls

	coordinator.call("debug_set_time_override_sec", 0.2)
	EventBus.emit_enemy_state_changed(source.entity_id, "SUSPICIOUS", "ALERT", 10, "vision")
	await _flush_event_bus_frames()

	coordinator.call("debug_set_time_override_sec", 9.0)
	EventBus.emit_enemy_state_changed(source.entity_id, "SUSPICIOUS", "ALERT", 10, "teammate_call")
	await _flush_event_bus_frames()
	EventBus.emit_enemy_state_changed(source.entity_id, "SUSPICIOUS", "ALERT", 10, "reinforcement")
	await _flush_event_bus_frames()

	_t.run_test("CALM->ALERT and ALERT->ALERT do not emit teammate/reinforcement call", calls_after_non_edge == 0 and reinforcement_after_non_edge == 0)
	_t.run_test("SUSPICIOUS->ALERT emits teammate/reinforcement exactly once", _teammate_calls == 1 and _reinforcement_calls == 1)
	_t.run_test("teammate_call/reinforcement reasons are anti-cascade blocked", _teammate_calls == 1 and _reinforcement_calls == 1)

	if EventBus.enemy_teammate_call.is_connected(_on_teammate_call):
		EventBus.enemy_teammate_call.disconnect(_on_teammate_call)
	if EventBus.enemy_reinforcement_called.is_connected(_on_reinforcement_call):
		EventBus.enemy_reinforcement_called.disconnect(_on_reinforcement_call)
	_cleanup_fixture(fixture)
	await get_tree().process_frame


func _create_fixture() -> Dictionary:
	var entities := Node2D.new()
	add_child(entities)

	var source := FakeEnemy.new(100, 10)
	var teammate := FakeEnemy.new(101, 10)
	var neighbor := FakeEnemy.new(102, 11)
	entities.add_child(source)
	entities.add_child(teammate)
	entities.add_child(neighbor)

	var nav := FakeNav.new()
	add_child(nav)
	nav.neighbors_by_room = {
		10: [11, 12],
		11: [10],
		12: [10],
	}

	var coordinator := ENEMY_AGGRO_COORDINATOR_SCRIPT.new()
	add_child(coordinator)
	coordinator.initialize(entities, nav, null)

	return {
		"entities": entities,
		"nav": nav,
		"coordinator": coordinator,
		"source": source,
	}


func _cleanup_fixture(fixture: Dictionary) -> void:
	var coordinator := fixture.get("coordinator") as Node
	if coordinator:
		coordinator.call("debug_clear_time_override_sec")
		coordinator.queue_free()
	var nav := fixture.get("nav") as Node
	if nav:
		nav.queue_free()
	var entities := fixture.get("entities") as Node
	if entities:
		entities.queue_free()


func _flush_event_bus_frames(frames: int = 4) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _on_teammate_call(_source_enemy_id: int, _source_room_id: int, _call_id: int, _timestamp_sec: float, _shot_pos: Vector2) -> void:
	_teammate_calls += 1


func _on_reinforcement_call(_source_enemy_id: int, _source_room_id: int, _target_room_ids: Array) -> void:
	_reinforcement_calls += 1
