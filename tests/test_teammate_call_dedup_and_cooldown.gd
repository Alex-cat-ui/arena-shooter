extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_AGGRO_COORDINATOR_SCRIPT := preload("res://src/systems/enemy_aggro_coordinator.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _teammate_event_count: int = 0


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
	print("TEAMMATE CALL DEDUP + COOLDOWN TEST")
	print("============================================================")

	await _test_source_cooldown_on_state_entry()
	await _test_target_dedup_and_cooldown()

	_t.summary("TEAMMATE CALL DEDUP + COOLDOWN RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_source_cooldown_on_state_entry() -> void:
	var fixture := _create_fixture()
	var coordinator := fixture.get("coordinator") as Node
	var source := fixture.get("source") as FakeEnemy

	_teammate_event_count = 0
	if not EventBus.enemy_teammate_call.is_connected(_on_teammate_call_counter):
		EventBus.enemy_teammate_call.connect(_on_teammate_call_counter)

	coordinator.call("debug_set_time_override_sec", 0.0)
	EventBus.emit_enemy_state_changed(source.entity_id, "SUSPICIOUS", "ALERT", 10, "vision")
	await _flush_event_bus_frames()

	coordinator.call("debug_set_time_override_sec", 1.0)
	EventBus.emit_enemy_state_changed(source.entity_id, "SUSPICIOUS", "ALERT", 10, "vision")
	await _flush_event_bus_frames()

	coordinator.call("debug_set_time_override_sec", 8.2)
	EventBus.emit_enemy_state_changed(source.entity_id, "SUSPICIOUS", "ALERT", 10, "vision")
	await _flush_event_bus_frames()

	_t.run_test("source cooldown: second call before 8s is blocked", _teammate_event_count == 2)

	if EventBus.enemy_teammate_call.is_connected(_on_teammate_call_counter):
		EventBus.enemy_teammate_call.disconnect(_on_teammate_call_counter)
	_cleanup_fixture(fixture)
	await get_tree().process_frame


func _test_target_dedup_and_cooldown() -> void:
	var fixture := _create_fixture()
	var coordinator := fixture.get("coordinator") as Node
	var target := fixture.get("target") as FakeEnemy

	coordinator.call("debug_set_time_override_sec", 0.0)
	EventBus.emit_enemy_teammate_call(100, 10, 7001, 0.0, Vector2.ZERO)
	EventBus.emit_enemy_teammate_call(100, 10, 7001, 0.0, Vector2.ZERO)
	await _flush_event_bus_frames()
	_force_deliver_pending_calls(coordinator, 1.0)
	var accepts_after_dedup := target.teammate_accepts

	coordinator.call("debug_set_time_override_sec", 1.1)
	EventBus.emit_enemy_teammate_call(100, 10, 7002, 1.1, Vector2.ZERO)
	await _flush_event_bus_frames()
	_force_deliver_pending_calls(coordinator, 2.0)
	var accepts_after_cooldown_block := target.teammate_accepts

	coordinator.call("debug_set_time_override_sec", 7.2)
	EventBus.emit_enemy_teammate_call(100, 10, 7003, 7.2, Vector2.ZERO)
	await _flush_event_bus_frames()
	_force_deliver_pending_calls(coordinator, 8.2)

	_t.run_test("dedup-key(target,call_id): duplicate call is consumed once", accepts_after_dedup == 1)
	_t.run_test("target cooldown 6s blocks immediate re-accept", accepts_after_cooldown_block == 1)
	_t.run_test("target cooldown expires after 6s", target.teammate_accepts == 2)

	_cleanup_fixture(fixture)
	await get_tree().process_frame


func _create_fixture() -> Dictionary:
	var entities := Node2D.new()
	add_child(entities)

	var source := FakeEnemy.new(100, 10)
	var target := FakeEnemy.new(101, 10)
	entities.add_child(source)
	entities.add_child(target)

	var nav := FakeNav.new()
	add_child(nav)
	nav.neighbors_by_room = {
		10: [11],
		11: [10],
	}

	var coordinator := ENEMY_AGGRO_COORDINATOR_SCRIPT.new()
	add_child(coordinator)
	coordinator.initialize(entities, nav, null)

	return {
		"entities": entities,
		"nav": nav,
		"coordinator": coordinator,
		"source": source,
		"target": target,
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


func _force_deliver_pending_calls(coordinator: Node, time_sec: float) -> void:
	coordinator.call("debug_set_time_override_sec", time_sec)
	coordinator.call("_drain_pending_teammate_calls")


func _on_teammate_call_counter(_source_enemy_id: int, _source_room_id: int, _call_id: int, _timestamp_sec: float, _shot_pos: Vector2) -> void:
	_teammate_event_count += 1
