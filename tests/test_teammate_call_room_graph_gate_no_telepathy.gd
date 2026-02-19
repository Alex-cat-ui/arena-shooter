extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_AGGRO_COORDINATOR_SCRIPT := preload("res://src/systems/enemy_aggro_coordinator.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


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

	func apply_teammate_call(_source_enemy_id: int, _source_room_id: int, _call_id: int = -1) -> bool:
		teammate_accepts += 1
		set_meta("awareness_state", "ALERT")
		return true


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("TEAMMATE CALL ROOM-GRAPH GATE TEST")
	print("============================================================")

	await _test_room_graph_gate_blocks_telepathy()

	_t.summary("TEAMMATE CALL ROOM-GRAPH GATE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_room_graph_gate_blocks_telepathy() -> void:
	var fixture := _create_fixture()
	var source := fixture.get("source") as FakeEnemy
	var same_room := fixture.get("same_room") as FakeEnemy
	var adjacent_room := fixture.get("adjacent_room") as FakeEnemy
	var far_room := fixture.get("far_room") as FakeEnemy

	EventBus.emit_enemy_teammate_call(source.entity_id, 10, 8801, 0.0)
	await _flush_event_bus_frames()

	_t.run_test("same-room teammate call accepted", same_room.teammate_accepts == 1)
	_t.run_test("adjacent-room teammate call accepted", adjacent_room.teammate_accepts == 1)
	_t.run_test("non-adjacent room call blocked (no telepathy)", far_room.teammate_accepts == 0)

	_cleanup_fixture(fixture)
	await get_tree().process_frame


func _create_fixture() -> Dictionary:
	var entities := Node2D.new()
	add_child(entities)

	var source := FakeEnemy.new(100, 10)
	var same_room := FakeEnemy.new(101, 10)
	var adjacent_room := FakeEnemy.new(102, 11)
	var far_room := FakeEnemy.new(103, 12)
	entities.add_child(source)
	entities.add_child(same_room)
	entities.add_child(adjacent_room)
	entities.add_child(far_room)

	var nav := FakeNav.new()
	add_child(nav)
	nav.neighbors_by_room = {
		10: [11],
		11: [10],
		12: [],
	}

	var coordinator := ENEMY_AGGRO_COORDINATOR_SCRIPT.new()
	add_child(coordinator)
	coordinator.initialize(entities, nav, null)
	coordinator.call("debug_set_time_override_sec", 0.0)

	return {
		"entities": entities,
		"nav": nav,
		"coordinator": coordinator,
		"source": source,
		"same_room": same_room,
		"adjacent_room": adjacent_room,
		"far_room": far_room,
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
