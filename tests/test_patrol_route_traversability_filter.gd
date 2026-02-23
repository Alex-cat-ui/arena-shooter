extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PATROL_SYSTEM_SCRIPT := preload("res://src/systems/enemy_patrol_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class ReachNavStub:
	extends Node

	var mode: String = "all_ok"
	var _random_calls: int = 0

	func _init(p_mode: String = "all_ok") -> void:
		mode = p_mode

	func get_room_center(_room_id: int) -> Vector2:
		return Vector2(128.0, 128.0)

	func get_room_rect(_room_id: int) -> Rect2:
		return Rect2()

	func get_neighbors(_room_id: int) -> Array[int]:
		return []

	func get_door_center_between(_a: int, _b: int, _anchor: Vector2) -> Vector2:
		return Vector2.ZERO

	func random_point_in_room(_room_id: int, _margin: float = 20.0) -> Vector2:
		_random_calls += 1
		match mode:
			"refill_reachable_only":
				if _random_calls <= 2:
					return Vector2(72.0 + float(_random_calls), 96.0)
				if _random_calls == 3:
					return Vector2(240.0, 180.0)
				return Vector2(304.0, 180.0)
			"all_unreachable":
				return Vector2(72.0 + float((_random_calls * 5) % 13), 96.0 + float((_random_calls * 7) % 11))
			"center_only":
				return Vector2(72.0 + float((_random_calls * 11) % 17), 96.0 + float((_random_calls * 13) % 19))
			_:
				if _random_calls % 2 == 0:
					return Vector2(236.0 + float((_random_calls % 3) * 60), 184.0)
				return Vector2(128.0, 128.0)

	func is_point_in_shadow(_point: Vector2) -> bool:
		return false

	func build_policy_valid_path(_from: Vector2, to: Vector2, _enemy: Node = null) -> Dictionary:
		var status := "ok"
		match mode:
			"center_only":
				if to.distance_to(Vector2(128.0, 128.0)) > 0.1:
					status = "unreachable_geometry"
			"all_unreachable":
				status = "unreachable_geometry"
			"refill_reachable_only":
				if to.distance_to(Vector2(128.0, 128.0)) <= 0.1:
					status = "ok"
				elif to.x >= 200.0:
					status = "ok"
				else:
					status = "unreachable_geometry"
			_:
				status = "ok"
		return {"status": status, "path_points": [Vector2.ZERO], "reason": status}


class ReachNavNoMethodStub:
	extends Node

	var _random_calls: int = 0

	func get_room_center(_room_id: int) -> Vector2:
		return Vector2(128.0, 128.0)

	func get_room_rect(_room_id: int) -> Rect2:
		return Rect2()

	func get_neighbors(_room_id: int) -> Array[int]:
		return []

	func get_door_center_between(_a: int, _b: int, _anchor: Vector2) -> Vector2:
		return Vector2.ZERO

	func random_point_in_room(_room_id: int, _margin: float = 20.0) -> Vector2:
		_random_calls += 1
		if _random_calls == 1:
			return Vector2(220.0, 160.0)
		if _random_calls == 2:
			return Vector2(280.0, 160.0)
		return Vector2(340.0, 160.0)

	func is_point_in_shadow(_point: Vector2) -> bool:
		return false


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("PATROL ROUTE TRAVERSABILITY FILTER TEST")
	print("============================================================")

	_test_reachability_filter_excludes_unreachable_points()
	_test_reachability_filter_passes_all_when_all_ok()
	_test_reachability_filter_skipped_when_method_absent()
	_test_refill_accepts_only_reachable_points()
	_test_all_candidates_unreachable_route_degrades_gracefully()

	_t.summary("PATROL ROUTE TRAVERSABILITY FILTER RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_reachability_filter_excludes_unreachable_points() -> void:
	var owner := CharacterBody2D.new()
	owner.global_position = Vector2(120.0, 120.0)
	var nav := ReachNavStub.new("center_only")
	var patrol = ENEMY_PATROL_SYSTEM_SCRIPT.new(owner)
	patrol.configure(nav, 0)
	patrol._rebuild_route()

	var route: Array[Vector2] = patrol._route
	var only_center: bool = not route.is_empty()
	for point in route:
		if point.distance_to(Vector2(128.0, 128.0)) > 0.1:
			only_center = false
			break

	_t.run_test("reachability filter excludes unreachable points", only_center)
	_t.run_test("center-only route remains non-empty", not route.is_empty())

	owner.free()
	nav.free()


func _test_reachability_filter_passes_all_when_all_ok() -> void:
	var owner := CharacterBody2D.new()
	owner.global_position = Vector2(120.0, 120.0)
	var nav := ReachNavStub.new("all_ok")
	var patrol = ENEMY_PATROL_SYSTEM_SCRIPT.new(owner)
	patrol.configure(nav, 0)
	patrol._rebuild_route()

	var route: Array[Vector2] = patrol._route
	var all_ok: bool = not route.is_empty()
	for point in route:
		var result := nav.build_policy_valid_path(owner.global_position, point, null)
		if String(result.get("status", "")) != "ok":
			all_ok = false
			break

	_t.run_test("reachability filter passes all when all ok", all_ok)

	owner.free()
	nav.free()


func _test_reachability_filter_skipped_when_method_absent() -> void:
	var owner := CharacterBody2D.new()
	owner.global_position = Vector2(120.0, 120.0)
	var nav := ReachNavNoMethodStub.new()
	var patrol = ENEMY_PATROL_SYSTEM_SCRIPT.new(owner)
	patrol.configure(nav, 0)
	patrol._rebuild_route()

	_t.run_test("reachability filter skipped when method absent", not patrol._route.is_empty())

	owner.free()
	nav.free()


func _test_refill_accepts_only_reachable_points() -> void:
	var owner := CharacterBody2D.new()
	owner.global_position = Vector2(120.0, 120.0)
	var nav := ReachNavStub.new("refill_reachable_only")
	var patrol = ENEMY_PATROL_SYSTEM_SCRIPT.new(owner)
	patrol.configure(nav, 0)
	patrol._rebuild_route()

	var route: Array[Vector2] = patrol._route
	var has_refill_point: bool = false
	for point in route:
		if point.x >= 200.0:
			has_refill_point = true
			break

	_t.run_test("reachability refill adds reachable points", has_refill_point)
	_t.run_test("refill path route is not empty", not route.is_empty())

	owner.free()
	nav.free()


func _test_all_candidates_unreachable_route_degrades_gracefully() -> void:
	var owner := CharacterBody2D.new()
	owner.global_position = Vector2(120.0, 120.0)
	var nav := ReachNavStub.new("all_unreachable")
	var patrol = ENEMY_PATROL_SYSTEM_SCRIPT.new(owner)
	patrol.configure(nav, 0)
	patrol._rebuild_route()

	_t.run_test("all-unreachable rebuild returns route container", patrol._route != null)
	_t.run_test("all-unreachable rebuild does not crash", true)

	owner.free()
	nav.free()
