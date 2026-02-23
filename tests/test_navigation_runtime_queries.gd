extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const NAVIGATION_SERVICE_SCRIPT := preload("res://src/systems/navigation_service.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeLayout:
	extends RefCounted
	var valid: bool = true
	var rooms: Array = [
		{
			"center": Vector2(50.0, 50.0),
			"rects": [Rect2(0.0, 0.0, 80.0, 80.0), Rect2(10.0, 10.0, 120.0, 120.0)],
		},
		{
			"center": Vector2(170.0, 50.0),
			"rects": [Rect2(120.0, 0.0, 100.0, 100.0)],
		},
	]
	var doors: Array = []
	var _door_adj: Dictionary = {
		0: [1],
		1: [0],
	}

	func _room_id_at_point(p: Vector2) -> int:
		if p.x < 120.0:
			return 0
		return 1


class FakeEnemy:
	extends Node2D
	var entity_id: int = 0
	var is_dead: bool = false


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("NAVIGATION RUNTIME QUERIES TEST")
	print("============================================================")

	await _test_runtime_query_contracts()

	_t.summary("NAVIGATION RUNTIME QUERIES RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_runtime_query_contracts() -> void:
	var nav := NAVIGATION_SERVICE_SCRIPT.new()
	add_child(nav)
	await get_tree().process_frame

	var layout := FakeLayout.new()
	var entities := Node2D.new()
	add_child(entities)
	var player := Node2D.new()
	player.global_position = Vector2(42.0, 24.0)
	add_child(player)

	nav.layout = layout
	nav.entities_container = entities
	nav.player_node = player
	var stub_region := NavigationRegion2D.new()
	nav._nav_regions = [stub_region]
	nav._room_graph = {0: [1], 1: [0]}
	nav._pair_doors = {
		"0|1": [Vector2(90.0, 50.0), Vector2(110.0, 50.0)],
	}

	var enemy := FakeEnemy.new()
	enemy.entity_id = 1101
	enemy.global_position = Vector2(150.0, 30.0)
	enemy.add_to_group("enemies")
	entities.add_child(enemy)

	_t.run_test("room_id_at_point resolves by layout method", nav.room_id_at_point(Vector2(10.0, 10.0)) == 0 and nav.room_id_at_point(Vector2(180.0, 20.0)) == 1)
	_t.run_test("get_neighbors returns sorted room graph neighbors", nav.get_neighbors(0) == [1] and nav.get_neighbors(1) == [0])
	_t.run_test("get_enemy_room_id_by_id resolves from entities container", nav.get_enemy_room_id_by_id(1101) == 1)
	_t.run_test("get_room_rect chooses largest room rect", nav.get_room_rect(0).size == Vector2(120.0, 120.0))
	_t.run_test("get_door_center_between picks closest center to anchor", nav.get_door_center_between(0, 1, Vector2(70.0, 50.0)) == Vector2(90.0, 50.0))
	_t.run_test("build_path_points always ends at target", (nav.build_path_points(Vector2(10.0, 10.0), Vector2(190.0, 30.0)) as Array).back() == Vector2(190.0, 30.0))
	_t.run_test(
		"build_policy_valid_path enemy=null reports direct route_type",
		String((nav.build_policy_valid_path(Vector2(10.0, 10.0), Vector2(190.0, 30.0)) as Dictionary).get("route_type", "")) == "direct"
	)
	_t.run_test("get_player_position uses player_node when available", nav.get_player_position() == Vector2(42.0, 24.0))

	nav._nav_regions.clear()
	stub_region.free()
	nav.queue_free()
	entities.queue_free()
	player.queue_free()
	await get_tree().process_frame
