extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PATROL_SYSTEM_SCRIPT := preload("res://src/systems/enemy_patrol_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class ShadowRouteNavStub:
	extends Node

	var _sample_counter: int = 0

	func get_room_center(_room_id: int) -> Vector2:
		return Vector2(128.0, 128.0)

	func get_room_rect(_room_id: int) -> Rect2:
		return Rect2(Vector2(32.0, 32.0), Vector2(224.0, 224.0))

	func get_neighbors(_room_id: int) -> Array[int]:
		return []

	func get_door_center_between(_a: int, _b: int, _anchor: Vector2) -> Vector2:
		return Vector2.ZERO

	func random_point_in_room(_room_id: int, _margin: float = 20.0) -> Vector2:
		_sample_counter += 1
		return Vector2(212.0 + float((_sample_counter % 5) * 6), 120.0 + float((_sample_counter % 4) * 5))

	func is_point_in_shadow(point: Vector2) -> bool:
		return point.x < 180.0

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
	print("SHADOW ROUTE FILTER TEST")
	print("============================================================")

	_test_patrol_route_avoids_shadow_points()

	_t.summary("SHADOW ROUTE FILTER RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_patrol_route_avoids_shadow_points() -> void:
	var owner := CharacterBody2D.new()
	owner.global_position = Vector2(120.0, 120.0)
	var nav := ShadowRouteNavStub.new()
	var patrol = ENEMY_PATROL_SYSTEM_SCRIPT.new(owner)
	patrol.configure(nav, 0)
	patrol._rebuild_route()

	var route: Array[Vector2] = patrol._route
	var all_safe := true
	for point in route:
		if nav.is_point_in_shadow(point):
			all_safe = false
			break

	_t.run_test("route is not empty after rebuild", not route.is_empty())
	_t.run_test("all patrol points are outside shadow", all_safe)

	owner.free()
	nav.free()
