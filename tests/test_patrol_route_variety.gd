extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PATROL_SYSTEM_SCRIPT := preload("res://src/systems/enemy_patrol_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class PatrolNavStub:
	extends Node

	var _sample_counter: int = 0

	func get_room_center(_room_id: int) -> Vector2:
		return Vector2(160.0, 160.0)

	func get_room_rect(_room_id: int) -> Rect2:
		return Rect2(Vector2(32.0, 32.0), Vector2(256.0, 256.0))

	func get_neighbors(_room_id: int) -> Array[int]:
		return []

	func get_door_center_between(_a: int, _b: int, _anchor: Vector2) -> Vector2:
		return Vector2.ZERO

	func random_point_in_room(_room_id: int, _margin: float = 20.0) -> Vector2:
		_sample_counter += 1
		return Vector2(
			96.0 + float((_sample_counter * 37) % 120),
			96.0 + float((_sample_counter * 53) % 120)
		)

	func is_point_in_shadow(_point: Vector2) -> bool:
		return false

	func build_policy_valid_path(_from: Vector2, _to: Vector2, _enemy: Node = null) -> Dictionary:
		return {"status": "ok", "path_points": [Vector2.ZERO], "reason": "ok"}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("PATROL ROUTE VARIETY TEST")
	print("============================================================")

	_test_sequential_rebuilds_produce_variety()

	_t.summary("PATROL ROUTE VARIETY RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_sequential_rebuilds_produce_variety() -> void:
	var owner := CharacterBody2D.new()
	owner.global_position = Vector2(128.0, 128.0)
	var nav := PatrolNavStub.new()
	var patrol = ENEMY_PATROL_SYSTEM_SCRIPT.new(owner)
	patrol.configure(nav, 0)

	var route_a: Array[Vector2] = patrol._route.duplicate()
	OS.delay_msec(3)
	patrol._rebuild_route()
	var route_b: Array[Vector2] = patrol._route.duplicate()

	_t.run_test("route A is not empty", not route_a.is_empty())
	_t.run_test("route B is not empty", not route_b.is_empty())
	_t.run_test("two rebuilds produce different route points", _routes_different(route_a, route_b))

	owner.free()
	nav.free()


func _routes_different(a: Array[Vector2], b: Array[Vector2]) -> bool:
	if a.size() != b.size():
		return true
	for i in range(a.size()):
		if a[i].distance_to(b[i]) > 0.1:
			return true
	return false
