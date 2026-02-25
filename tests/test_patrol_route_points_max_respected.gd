extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PATROL_SYSTEM_SCRIPT = preload("res://src/systems/enemy_patrol_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeNav:
	extends Node

	var _cursor: int = 0
	var _points: Array[Vector2] = [
		Vector2(12.0, 16.0),
		Vector2(28.0, -14.0),
		Vector2(-44.0, 26.0),
		Vector2(56.0, 22.0),
		Vector2(-62.0, -24.0),
		Vector2(84.0, -18.0),
	]

	func get_room_center(_room_id: int) -> Vector2:
		return Vector2.ZERO

	func get_room_rect(_room_id: int) -> Rect2:
		return Rect2(Vector2(-128.0, -96.0), Vector2(256.0, 192.0))

	func get_neighbors(_room_id: int) -> Array:
		return [1, 2, 3]

	func get_door_center_between(_room_a: int, room_b: int, _anchor: Vector2) -> Vector2:
		return Vector2(48.0 * float(room_b), 0.0)

	func random_point_in_room(_room_id: int, _margin: float = 20.0) -> Vector2:
		var point := _points[_cursor % _points.size()]
		_cursor += 1
		return point

	func is_point_in_shadow(_point: Vector2) -> bool:
		return false

	func build_policy_valid_path(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		return {
			"status": "ok",
			"path_points": [to_pos],
			"reason": "ok",
			"route_source": "navmesh",
			"route_source_reason": "stub_navmesh",
			"obstacle_intersection_detected": false,
		}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("PATROL ROUTE POINTS MAX RESPECTED TEST")
	print("============================================================")

	await _test_patrol_route_size_never_exceeds_route_points_max()

	_t.summary("PATROL ROUTE POINTS MAX RESPECTED RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_patrol_route_size_never_exceeds_route_points_max() -> void:
	if not GameConfig or not (GameConfig.ai_balance is Dictionary):
		_t.run_test("route_points_max: GameConfig is available", false)
		return

	var patrol_cfg := (GameConfig.ai_balance.get("patrol", {}) as Dictionary).duplicate(true)
	var original_cfg := patrol_cfg.duplicate(true)
	patrol_cfg["route_points_min"] = 3
	patrol_cfg["route_points_max"] = 4
	patrol_cfg["cross_room_patrol_chance"] = 1.0
	GameConfig.ai_balance["patrol"] = patrol_cfg

	var owner := CharacterBody2D.new()
	owner.global_position = Vector2.ZERO
	var nav := FakeNav.new()
	var patrol = ENEMY_PATROL_SYSTEM_SCRIPT.new(owner)
	patrol.configure(nav, 0)

	var first_route := patrol.get("_route") as Array
	patrol.call("_rebuild_route", false)
	var second_route := patrol.get("_route") as Array
	var route_points_max := int((GameConfig.ai_balance.get("patrol", {}) as Dictionary).get("route_points_max", 4))

	_t.run_test("route_points_max: first rebuild respects max", first_route.size() <= route_points_max)
	_t.run_test("route_points_max: second rebuild respects max", second_route.size() <= route_points_max)
	_t.run_test("route_points_max: route is not empty", not second_route.is_empty())

	GameConfig.ai_balance["patrol"] = original_cfg
