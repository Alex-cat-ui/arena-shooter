extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_AGGRO_COORDINATOR_SCRIPT := preload("res://src/systems/enemy_aggro_coordinator.gd")

const ZONE_CALM := 0
const ZONE_ELEVATED := 1
const ZONE_LOCKDOWN := 2

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _reinforcement_calls_counter: int = 0


class FakeRoomNav:
	extends Node

	var neighbors_by_room: Dictionary = {}
	var room_centers: Dictionary = {}
	var player_pos: Vector2 = Vector2.ZERO

	func get_neighbors(room_id: int) -> Array:
		return neighbors_by_room.get(room_id, [])

	func get_player_position() -> Vector2:
		return player_pos

	func get_room_center(room_id: int) -> Vector2:
		return room_centers.get(room_id, Vector2.ZERO)

	func get_enemy_room_id(enemy: Node) -> int:
		return int(enemy.get_meta("room_id", -1))

	func pick_top2_neighbor_rooms_for_reinforcement(source_room: int, target_player_pos: Vector2) -> Array:
		var neighbors := get_neighbors(source_room)
		if neighbors.size() <= 2:
			return neighbors.duplicate()
		var scored: Array[Dictionary] = []
		for rid_variant in neighbors:
			var rid := int(rid_variant)
			scored.append({
				"room_id": rid,
				"dist": get_room_center(rid).distance_to(target_player_pos),
			})
		scored.sort_custom(func(a, b):
			var da := float(a.get("dist", INF))
			var db := float(b.get("dist", INF))
			if is_equal_approx(da, db):
				return int(a.get("room_id", -1)) < int(b.get("room_id", -1))
			return da < db
		)
		return [int(scored[0].get("room_id", -1)), int(scored[1].get("room_id", -1))]


class FakeEnemy:
	extends Node

	var entity_id: int = 0
	var teammate_calls: int = 0
	var last_teammate_shot_pos: Vector2 = Vector2.ZERO
	var _investigate_anchor: Vector2 = Vector2.ZERO
	var _investigate_anchor_valid: bool = false

	func _init(p_entity_id: int, room_id: int, awareness_state: String = "CALM") -> void:
		entity_id = p_entity_id
		set_meta("room_id", room_id)
		set_meta("awareness_state", awareness_state)
		add_to_group("enemies")

	func apply_teammate_call(_source_enemy_id: int, _source_room_id: int, _call_id: int = -1, shot_pos: Vector2 = Vector2.ZERO) -> bool:
		var state := String(get_meta("awareness_state", "CALM"))
		if state == "COMBAT" or state == "ALERT":
			return false
		last_teammate_shot_pos = shot_pos
		teammate_calls += 1
		set_meta("awareness_state", "ALERT")
		if EventBus:
			EventBus.emit_enemy_state_changed(entity_id, state, "ALERT", int(get_meta("room_id", -1)), "teammate_call")
		return true


class FakeZoneDirector:
	extends Node

	var room_to_zone: Dictionary = {}
	var zone_states: Dictionary = {}
	var validation_calls: int = 0
	var accepted_teammate_calls: Array[Dictionary] = []
	var registered_waves: int = 0

	func get_zone_for_room(room_id: int) -> int:
		return int(room_to_zone.get(room_id, -1))

	func can_spawn_reinforcement(_zone_id: int) -> bool:
		return true

	func register_reinforcement_wave(_zone_id: int, _count: int) -> void:
		registered_waves += 1

	func record_accepted_teammate_call(source_room_id: int, target_room_id: int) -> bool:
		accepted_teammate_calls.append({
			"source_room_id": source_room_id,
			"target_room_id": target_room_id,
		})
		return true

	func validate_reinforcement_call(
		_source_enemy_id: int,
		source_room_id: int,
		source_awareness_state: String,
		call_id: int,
		_now_sec: float = -1.0
	) -> Dictionary:
		validation_calls += 1
		if call_id <= 0:
			return {"accepted": false, "reason": "invalid_call_id", "zone_id": -1}
		var zone_id := get_zone_for_room(source_room_id)
		var state := int(zone_states.get(zone_id, ZONE_CALM))
		if state == ZONE_CALM:
			return {"accepted": false, "reason": "permission_calm", "zone_id": zone_id}
		if state == ZONE_ELEVATED and source_awareness_state != "ALERT":
			return {"accepted": false, "reason": "permission_elevated_requires_alert", "zone_id": zone_id}
		if state == ZONE_LOCKDOWN and source_awareness_state != "ALERT" and source_awareness_state != "COMBAT":
			return {"accepted": false, "reason": "permission_lockdown_requires_alert_or_combat", "zone_id": zone_id}
		return {"accepted": true, "reason": "ok", "zone_id": zone_id}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ENEMY AGGRO COORDINATOR TEST")
	print("============================================================")

	await _test_teammate_call_acceptance_reported_to_zone_director()
	await _test_teammate_call_forwards_source_anchor()
	await _test_reinforcement_blocked_in_calm_zone()
	await _test_reinforcement_allowed_in_elevated_zone()

	_t.summary("ENEMY AGGRO COORDINATOR RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_teammate_call_acceptance_reported_to_zone_director() -> void:
	var fixture := _create_fixture(ZONE_ELEVATED)
	var source := fixture["source"] as FakeEnemy
	var same_room_calm := fixture["same_room_calm"] as FakeEnemy
	var director := fixture["director"] as FakeZoneDirector

	EventBus.emit_enemy_state_changed(source.entity_id, "SUSPICIOUS", "ALERT", 10, "vision")
	await _flush_event_bus_frames(5)

	_t.run_test("teammate call accepted by calm target", same_room_calm.teammate_calls == 1)
	_t.run_test("accepted teammate call reported to ZoneDirector", director.accepted_teammate_calls.size() >= 1)
	_cleanup_fixture(fixture)
	await get_tree().process_frame


func _test_teammate_call_forwards_source_anchor() -> void:
	var fixture := _create_fixture(ZONE_ELEVATED)
	var source := fixture["source"] as FakeEnemy
	var same_room_calm := fixture["same_room_calm"] as FakeEnemy
	var anchor := Vector2(320.0, 144.0)

	source._investigate_anchor = anchor
	source._investigate_anchor_valid = true
	EventBus.emit_enemy_state_changed(source.entity_id, "SUSPICIOUS", "ALERT", 10, "vision")
	await _flush_event_bus_frames(5)

	_t.run_test(
		"teammate call forwards source investigate anchor as shot_pos",
		same_room_calm.last_teammate_shot_pos.distance_to(anchor) <= 0.001
	)
	_cleanup_fixture(fixture)
	await get_tree().process_frame


func _test_reinforcement_blocked_in_calm_zone() -> void:
	var fixture := _create_fixture(ZONE_CALM)
	var source := fixture["source"] as FakeEnemy
	var director := fixture["director"] as FakeZoneDirector
	_reinforcement_calls_counter = 0
	if not EventBus.enemy_reinforcement_called.is_connected(_on_reinforcement_counter):
		EventBus.enemy_reinforcement_called.connect(_on_reinforcement_counter)

	EventBus.emit_enemy_state_changed(source.entity_id, "SUSPICIOUS", "ALERT", 10, "vision")
	await _flush_event_bus_frames(5)

	if EventBus.enemy_reinforcement_called.is_connected(_on_reinforcement_counter):
		EventBus.enemy_reinforcement_called.disconnect(_on_reinforcement_counter)

	_t.run_test("reinforcement blocked in CALM zone by ZoneDirector", _reinforcement_calls_counter == 0)
	_t.run_test("ZoneDirector validation was called", director.validation_calls == 1)
	_cleanup_fixture(fixture)
	await get_tree().process_frame


func _test_reinforcement_allowed_in_elevated_zone() -> void:
	var fixture := _create_fixture(ZONE_ELEVATED)
	var source := fixture["source"] as FakeEnemy
	var director := fixture["director"] as FakeZoneDirector
	_reinforcement_calls_counter = 0
	if not EventBus.enemy_reinforcement_called.is_connected(_on_reinforcement_counter):
		EventBus.enemy_reinforcement_called.connect(_on_reinforcement_counter)

	EventBus.emit_enemy_state_changed(source.entity_id, "SUSPICIOUS", "ALERT", 10, "vision")
	await _flush_event_bus_frames(5)

	if EventBus.enemy_reinforcement_called.is_connected(_on_reinforcement_counter):
		EventBus.enemy_reinforcement_called.disconnect(_on_reinforcement_counter)

	_t.run_test("reinforcement allowed in ELEVATED zone with source ALERT", _reinforcement_calls_counter == 1)
	_t.run_test("ZoneDirector validation called once for allowed call", director.validation_calls == 1)
	_cleanup_fixture(fixture)
	await get_tree().process_frame


func _create_fixture(source_zone_state: int) -> Dictionary:
	var entities := Node2D.new()
	add_child(entities)

	var source := FakeEnemy.new(100, 10, "CALM")
	var same_room_calm := FakeEnemy.new(101, 10, "CALM")
	var same_room_combat := FakeEnemy.new(102, 10, "COMBAT")
	var room11_enemy := FakeEnemy.new(103, 11, "CALM")
	var room12_enemy := FakeEnemy.new(104, 12, "CALM")
	var room13_enemy := FakeEnemy.new(105, 13, "CALM")
	entities.add_child(source)
	entities.add_child(same_room_calm)
	entities.add_child(same_room_combat)
	entities.add_child(room11_enemy)
	entities.add_child(room12_enemy)
	entities.add_child(room13_enemy)

	var nav := FakeRoomNav.new()
	add_child(nav)
	nav.neighbors_by_room = {
		10: [12, 13],
		11: [10],
		12: [10],
		13: [10],
	}
	nav.room_centers = {
		11: Vector2(100.0, 0.0),
		12: Vector2(10.0, 0.0),
		13: Vector2(-10.0, 0.0),
	}
	nav.player_pos = Vector2.ZERO

	var director := FakeZoneDirector.new()
	add_child(director)
	director.room_to_zone = {
		10: 1,
		11: 1,
		12: 1,
		13: 1,
	}
	director.zone_states = {
		1: source_zone_state,
	}

	var coordinator: Node = ENEMY_AGGRO_COORDINATOR_SCRIPT.new()
	add_child(coordinator)
	coordinator.initialize(entities, nav, null)
	coordinator.set_zone_director(director)

	return {
		"entities": entities,
		"nav": nav,
		"coordinator": coordinator,
		"director": director,
		"source": source,
		"same_room_calm": same_room_calm,
	}


func _cleanup_fixture(fixture: Dictionary) -> void:
	var coordinator := fixture.get("coordinator", null) as Node
	if coordinator:
		coordinator.queue_free()
	var director := fixture.get("director", null) as Node
	if director:
		director.queue_free()
	var nav := fixture.get("nav", null) as Node
	if nav:
		nav.queue_free()
	var entities := fixture.get("entities", null) as Node
	if entities:
		entities.queue_free()


func _flush_event_bus_frames(frames: int = 3) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _on_reinforcement_counter(_source_enemy_id: int, _source_room_id: int, _target_room_ids: Array) -> void:
	_reinforcement_calls_counter += 1
