extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ROOM_NAV_SYSTEM_SCRIPT := preload("res://src/systems/navigation_service.gd")
const ZONE_DIRECTOR_SCRIPT := preload("res://src/systems/zone_director.gd")

const LOCKDOWN := 2

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeLayout:
	extends RefCounted

	var valid: bool = true
	var _door_adj: Dictionary = {}
	var doors: Array = []
	var rooms: Array = [
		{
			"center": Vector2.ZERO,
			"rects": [Rect2(-64.0, -64.0, 128.0, 128.0)],
		}
	]

	func _room_id_at_point(_p: Vector2) -> int:
		return 0


class FakeEnemy:
	extends Node2D

	var _zone_director_internal: Node = null
	var _room_id: int = 0

	func _init(room_id: int = 0) -> void:
		_room_id = room_id
		add_to_group("enemies")
		set_meta("room_id", room_id)

	func set_room_navigation(_nav_system: Node, home_room_id: int) -> void:
		_room_id = home_room_id
		set_meta("room_id", home_room_id)

	func set_tactical_systems(_alert_system: Node = null, _squad_system: Node = null) -> void:
		pass

	func set_zone_director(director: Node) -> void:
		_zone_director_internal = director

	func has_zone_director() -> bool:
		return _zone_director_internal != null

	func enter_combat() -> void:
		if not _zone_director_internal:
			return
		if not _zone_director_internal.has_method("get_zone_for_room") or not _zone_director_internal.has_method("trigger_lockdown"):
			return
		var room_id := int(get_meta("room_id", _room_id))
		var zone_id := int(_zone_director_internal.get_zone_for_room(room_id))
		_zone_director_internal.trigger_lockdown(zone_id)

	func get_zone_state_for_debug() -> int:
		if not _zone_director_internal:
			return -1
		if not _zone_director_internal.has_method("get_zone_for_room") or not _zone_director_internal.has_method("get_zone_state"):
			return -1
		var room_id := int(get_meta("room_id", _room_id))
		var zone_id := int(_zone_director_internal.get_zone_for_room(room_id))
		return int(_zone_director_internal.get_zone_state(zone_id))


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ZONE ENEMY WIRING TEST")
	print("============================================================")

	await _test_enemy_receives_zone_director()
	await _test_combat_triggers_lockdown()
	await _test_null_zone_director_no_crash()
	await _test_dynamically_spawned_enemy_gets_director()

	_t.summary("ZONE ENEMY WIRING RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_enemy_receives_zone_director() -> void:
	var fixture: Dictionary = await _create_fixture(true)
	var nav: Node = fixture["nav"] as Node
	var enemy: FakeEnemy = fixture["enemy"] as FakeEnemy
	nav.call("_configure_enemy", enemy)
	_t.run_test("enemy_receives_zone_director", enemy.has_zone_director())
	await _cleanup_fixture(fixture)


func _test_combat_triggers_lockdown() -> void:
	var fixture: Dictionary = await _create_fixture(true)
	var nav: Node = fixture["nav"] as Node
	var enemy: FakeEnemy = fixture["enemy"] as FakeEnemy
	var zone_director: Node = fixture["zone_director"] as Node
	nav.call("_configure_enemy", enemy)
	enemy.enter_combat()
	var zone_id := int(zone_director.get_zone_for_room(0))
	var state := int(zone_director.get_zone_state(zone_id))
	_t.run_test("combat_triggers_lockdown", state == LOCKDOWN)
	await _cleanup_fixture(fixture)


func _test_null_zone_director_no_crash() -> void:
	var fixture: Dictionary = await _create_fixture(false)
	var nav: Node = fixture["nav"] as Node
	var enemy: FakeEnemy = fixture["enemy"] as FakeEnemy
	nav.call("_configure_enemy", enemy)
	enemy.enter_combat()
	_t.run_test("null_zone_director_no_crash", enemy.get_zone_state_for_debug() == -1)
	await _cleanup_fixture(fixture)


func _test_dynamically_spawned_enemy_gets_director() -> void:
	var fixture: Dictionary = await _create_fixture(true)
	var entities_container: Node2D = fixture["entities_container"] as Node2D
	var dynamic_enemy := FakeEnemy.new(0)
	entities_container.add_child(dynamic_enemy)
	await get_tree().process_frame
	await get_tree().process_frame
	_t.run_test("dynamically_spawned_enemy_gets_director", dynamic_enemy.has_zone_director())
	dynamic_enemy.queue_free()
	await _cleanup_fixture(fixture)


func _create_fixture(with_zone_director: bool) -> Dictionary:
	await _remove_zone_director_from_root()

	var entities_container := Node2D.new()
	add_child(entities_container)

	var player := Node2D.new()
	add_child(player)

	var nav := ROOM_NAV_SYSTEM_SCRIPT.new()
	add_child(nav)
	nav.initialize(FakeLayout.new(), entities_container, player)

	var zone_director: Node = null
	if with_zone_director:
		zone_director = await _add_zone_director_to_root()

	var enemy := FakeEnemy.new(0)
	entities_container.add_child(enemy)
	await get_tree().process_frame
	await get_tree().process_frame

	return {
		"nav": nav,
		"player": player,
		"enemy": enemy,
		"entities_container": entities_container,
		"zone_director": zone_director,
	}


func _add_zone_director_to_root() -> Node:
	var director := ZONE_DIRECTOR_SCRIPT.new()
	director.name = "ZoneDirector"
	get_tree().root.call_deferred("add_child", director)
	await get_tree().process_frame
	var zone_config: Array[Dictionary] = [{"id": 0, "rooms": [0]}]
	var zone_edges: Array[Array] = []
	director.initialize(zone_config, zone_edges, null)
	return director


func _cleanup_fixture(fixture: Dictionary) -> void:
	var nav := fixture.get("nav", null) as Node
	if nav and is_instance_valid(nav):
		nav.queue_free()
	var player := fixture.get("player", null) as Node
	if player and is_instance_valid(player):
		player.queue_free()
	var entities_container := fixture.get("entities_container", null) as Node
	if entities_container and is_instance_valid(entities_container):
		entities_container.queue_free()
	var zone_director := fixture.get("zone_director", null) as Node
	if zone_director and is_instance_valid(zone_director):
		zone_director.queue_free()
	await _remove_zone_director_from_root()
	await get_tree().process_frame


func _remove_zone_director_from_root() -> void:
	if not get_tree() or not get_tree().root:
		return
	var existing := get_tree().root.get_node_or_null("ZoneDirector")
	if existing and is_instance_valid(existing):
		existing.queue_free()
		await get_tree().process_frame
