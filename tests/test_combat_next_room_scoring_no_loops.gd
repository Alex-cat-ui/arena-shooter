extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeNav:
	extends Node

	var room_centers: Dictionary = {}
	var neighbors: Dictionary = {}

	func get_neighbors(room_id: int) -> Array:
		return neighbors.get(room_id, [])

	func get_room_center(room_id: int) -> Vector2:
		return room_centers.get(room_id, Vector2.ZERO)


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("COMBAT NEXT ROOM SCORING NO LOOPS TEST")
	print("============================================================")

	await _test_scoring_and_loop_avoidance()

	_t.summary("COMBAT NEXT ROOM SCORING NO LOOPS RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_scoring_and_loop_avoidance() -> void:
	var world := Node2D.new()
	add_child(world)
	var nav := FakeNav.new()
	world.add_child(nav)
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(6301, "zombie")
	enemy.debug_force_awareness_state("COMBAT")
	enemy.nav_system = nav

	nav.neighbors = {10: [11, 12, 13], 11: [10], 12: [10], 13: [10]}
	nav.room_centers = {
		10: Vector2(0.0, 0.0),
		11: Vector2(120.0, 0.0),
		12: Vector2(170.0, 0.0),
		13: Vector2(90.0, 0.0),
	}
	enemy.set("_combat_search_visited_rooms", {13: true})
	var first_pick := int(enemy.call("_select_next_combat_search_room", 10, Vector2(100.0, 0.0)))

	enemy.set("_combat_search_visited_rooms", {13: true, 11: true})
	var second_pick := int(enemy.call("_select_next_combat_search_room", 10, Vector2(100.0, 0.0)))

	nav.neighbors = {20: [21, 22], 21: [20], 22: [20]}
	nav.room_centers = {
		20: Vector2.ZERO,
		21: Vector2(100.0, 0.0),
		22: Vector2(100.0, 0.0),
	}
	enemy.set("_combat_search_visited_rooms", {})
	var tie_pick := int(enemy.call("_select_next_combat_search_room", 20, Vector2(100.0, 0.0)))

	_t.run_test("visited room penalty prevents immediate loop to visited room", first_pick == 11)
	_t.run_test("after marking first pick visited, next unvisited room is chosen", second_pick == 12)
	_t.run_test("score tie resolves by smaller room_id", tie_pick == 21)

	world.queue_free()
	await get_tree().process_frame
