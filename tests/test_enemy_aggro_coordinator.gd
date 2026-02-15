extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_AGGRO_COORDINATOR_SCRIPT := preload("res://src/systems/enemy_aggro_coordinator.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _reinforcement_calls_counter: int = 0
var _last_reinforcement_targets: Array = []


class FakeRoomNav:
	extends Node

	var enemies_by_room: Dictionary = {}
	var neighbors_by_room: Dictionary = {}
	var room_centers: Dictionary = {}
	var player_pos: Vector2 = Vector2.ZERO

	func get_enemies_in_room(room_id: int) -> Array:
		return enemies_by_room.get(room_id, [])

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
	var alert_calls: int = 0
	var reinforcement_combat_calls: int = 0

	func _init(p_entity_id: int, room_id: int, awareness_state: String = "CALM") -> void:
		entity_id = p_entity_id
		set_meta("room_id", room_id)
		set_meta("awareness_state", awareness_state)
		add_to_group("enemies")

	func apply_room_alert_propagation(_source_enemy_id: int, _source_room_id: int) -> void:
		alert_calls += 1
		set_meta("awareness_state", "ALERT")

	func connect_reinforcement_listener() -> void:
		if EventBus and not EventBus.enemy_reinforcement_called.is_connected(_on_enemy_reinforcement_called):
			EventBus.enemy_reinforcement_called.connect(_on_enemy_reinforcement_called)

	func _on_enemy_reinforcement_called(_source_enemy_id: int, _source_room_id: int, target_room_ids: Array) -> void:
		var room_id := int(get_meta("room_id", -1))
		if not target_room_ids.has(room_id):
			return
		reinforcement_combat_calls += 1
		var from_state := String(get_meta("awareness_state", "CALM"))
		set_meta("awareness_state", "COMBAT")
		if EventBus:
			EventBus.emit_enemy_state_changed(entity_id, from_state, "COMBAT", room_id, "reinforcement")


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

	await _test_room_alert_only_own_room()
	await _test_combat_reinforcement_max_two_neighbors_and_no_chain()

	_t.summary("ENEMY AGGRO COORDINATOR RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_room_alert_only_own_room() -> void:
	var fixture := _create_fixture()
	var source := fixture["source"] as FakeEnemy
	var same_room_calm := fixture["same_room_calm"] as FakeEnemy
	var same_room_combat := fixture["same_room_combat"] as FakeEnemy
	var other_room := fixture["other_room"] as FakeEnemy

	EventBus.emit_enemy_state_changed(source.entity_id, "CALM", "ALERT", 10, "vision")
	await _flush_event_bus_frames()

	_t.run_test("ALERT propagates to calm enemy in source room", same_room_calm.alert_calls == 1)
	_t.run_test("ALERT does not re-apply to COMBAT enemy in source room", same_room_combat.alert_calls == 0)
	_t.run_test("ALERT does not affect enemies outside source room", other_room.alert_calls == 0)

	_cleanup_fixture(fixture)
	await get_tree().process_frame


func _test_combat_reinforcement_max_two_neighbors_and_no_chain() -> void:
	var fixture := _create_fixture()
	var source := fixture["source"] as FakeEnemy
	var room12_enemy := fixture["room12_enemy"] as FakeEnemy
	var room13_enemy := fixture["room13_enemy"] as FakeEnemy
	var room11_enemy := fixture["other_room"] as FakeEnemy

	room12_enemy.connect_reinforcement_listener()
	room13_enemy.connect_reinforcement_listener()
	room11_enemy.connect_reinforcement_listener()

	_reinforcement_calls_counter = 0
	_last_reinforcement_targets = []
	if not EventBus.enemy_reinforcement_called.is_connected(_on_reinforcement_counter):
		EventBus.enemy_reinforcement_called.connect(_on_reinforcement_counter)

	EventBus.emit_enemy_state_changed(source.entity_id, "ALERT", "COMBAT", 10, "vision")
	await _flush_event_bus_frames(6)

	if EventBus.enemy_reinforcement_called.is_connected(_on_reinforcement_counter):
		EventBus.enemy_reinforcement_called.disconnect(_on_reinforcement_counter)

	var last_targets := _last_reinforcement_targets.duplicate()
	last_targets.sort()
	_t.run_test("COMBAT emits exactly one reinforcement wave", _reinforcement_calls_counter == 1)
	_t.run_test("Reinforcement targets max two rooms", last_targets.size() <= 2)
	_t.run_test("Reinforcement picks nearest two neighbors with tie-break", last_targets == [12, 13])
	_t.run_test("reason=reinforcement does not create secondary waves", _reinforcement_calls_counter == 1)

	_cleanup_fixture(fixture)
	await get_tree().process_frame


func _create_fixture() -> Dictionary:
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
	nav.enemies_by_room = {
		10: [source, same_room_calm, same_room_combat],
		11: [room11_enemy],
		12: [room12_enemy],
		13: [room13_enemy],
	}
	nav.neighbors_by_room = {
		10: [11, 12, 13],
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

	var coordinator := ENEMY_AGGRO_COORDINATOR_SCRIPT.new()
	add_child(coordinator)
	coordinator.initialize(entities, nav, null)

	return {
		"entities": entities,
		"nav": nav,
		"coordinator": coordinator,
		"source": source,
		"same_room_calm": same_room_calm,
		"same_room_combat": same_room_combat,
		"other_room": room11_enemy,
		"room12_enemy": room12_enemy,
		"room13_enemy": room13_enemy,
	}


func _cleanup_fixture(fixture: Dictionary) -> void:
	var coordinator := fixture.get("coordinator", null) as Node
	if coordinator:
		coordinator.queue_free()
	var nav := fixture.get("nav", null) as Node
	if nav:
		nav.queue_free()
	var entities := fixture.get("entities", null) as Node
	if entities:
		entities.queue_free()


func _flush_event_bus_frames(frames: int = 3) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _on_reinforcement_counter(_source_enemy_id: int, _source_room_id: int, target_room_ids: Array) -> void:
	_reinforcement_calls_counter += 1
	_last_reinforcement_targets = target_room_ids.duplicate()
