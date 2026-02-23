extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const NAVIGATION_SERVICE_SCRIPT := preload("res://src/systems/navigation_service.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeLayoutBase:
	extends RefCounted

	var valid: bool = true
	var rooms: Array = []
	var doors: Array = []
	var _door_adj: Dictionary = {}
	var _void_ids: Array = []

	func _init(room_rect: Rect2) -> void:
		rooms = [{
			"center": room_rect.get_center(),
			"rects": [room_rect],
		}]


class FakeLayoutWithObstacleApi:
	extends FakeLayoutBase

	var nav_obstacles_override: Array[Rect2] = []

	func _navigation_obstacles() -> Array[Rect2]:
		return nav_obstacles_override.duplicate()


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("NAV CLEARANCE MARGIN TEST")
	print("============================================================")

	await _test_clearance_margin_keeps_nav_vertices_away_from_raw_obstacle()
	await _test_no_obstacles_keeps_room_outline_unchanged()

	_t.summary("NAV CLEARANCE MARGIN RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_clearance_margin_keeps_nav_vertices_away_from_raw_obstacle() -> void:
	var room_rect := Rect2(0.0, 0.0, 200.0, 200.0)
	var raw_obstacle := Rect2(80.0, 80.0, 40.0, 40.0)
	var layout := FakeLayoutWithObstacleApi.new(room_rect)
	layout.nav_obstacles_override = [raw_obstacle]
	var fixture := await _create_fixture(layout)
	var world := fixture.get("world") as Node2D
	var service := fixture.get("service") as Node

	service.call("build_from_layout", layout, world)
	await _settle_frames()

	var points := _collect_nav_outline_points(service, 0)
	var clearance := float(service.get("OBSTACLE_CLEARANCE_PX"))
	var grown := raw_obstacle.grow(clearance)
	var min_distance := _min_distance_to_rect(points, raw_obstacle)
	var ok := (
		min_distance >= (clearance - 0.1)
		and _has_point_near(points, grown.position)
		and _has_point_near(points, grown.end)
	)
	_t.run_test("clearance_margin_keeps_nav_vertices_away_from_raw_obstacle", ok)

	await _cleanup_fixture(fixture)


func _test_no_obstacles_keeps_room_outline_unchanged() -> void:
	var room_rect := Rect2(0.0, 0.0, 200.0, 200.0)
	var layout := FakeLayoutBase.new(room_rect)
	var fixture := await _create_fixture(layout)
	var world := fixture.get("world") as Node2D
	var service := fixture.get("service") as Node

	service.call("build_from_layout", layout, world)
	await _settle_frames()

	var nav_poly := _room_nav_poly(service, 0)
	var points := _collect_nav_outline_points(service, 0)
	var outline_bounds := _bounds_for_points(points)
	var ok := (
		nav_poly != null
		and nav_poly.get_outline_count() == 1
		and points.size() == 4
		and _rect_approx_eq(outline_bounds, room_rect)
	)
	_t.run_test("no_obstacles_keeps_room_outline_unchanged", ok)

	await _cleanup_fixture(fixture)


func _create_fixture(layout) -> Dictionary:
	var world := Node2D.new()
	add_child(world)

	var entities := Node2D.new()
	entities.name = "Entities"
	world.add_child(entities)

	var player := Node2D.new()
	player.name = "Player"
	world.add_child(player)

	var service := NAVIGATION_SERVICE_SCRIPT.new()
	service.name = "NavigationService"
	world.add_child(service)
	service.initialize(layout, entities, player)
	await _settle_frames()

	return {
		"world": world,
		"entities": entities,
		"player": player,
		"service": service,
	}


func _cleanup_fixture(fixture: Dictionary) -> void:
	var world := fixture.get("world", null) as Node
	if world and is_instance_valid(world):
		world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _settle_frames() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _room_nav_poly(service: Node, room_id: int) -> NavigationPolygon:
	var room_to_region := service.get("_room_to_region") as Dictionary
	var region := room_to_region.get(room_id, null) as NavigationRegion2D
	if region == null:
		return null
	return region.navigation_polygon


func _collect_nav_outline_points(service: Node, room_id: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var nav_poly := _room_nav_poly(service, room_id)
	if nav_poly == null:
		return points
	for outline_idx in range(nav_poly.get_outline_count()):
		var outline := nav_poly.get_outline(outline_idx)
		for point in outline:
			points.append(point)
	return points


func _has_point_near(points: Array[Vector2], target: Vector2, epsilon: float = 0.25) -> bool:
	for point in points:
		if point.distance_to(target) <= epsilon:
			return true
	return false


func _distance_to_rect(point: Vector2, rect: Rect2) -> float:
	var cx := clampf(point.x, rect.position.x, rect.end.x)
	var cy := clampf(point.y, rect.position.y, rect.end.y)
	return point.distance_to(Vector2(cx, cy))


func _min_distance_to_rect(points: Array[Vector2], rect: Rect2) -> float:
	if points.is_empty():
		return INF
	var min_distance := INF
	for point in points:
		min_distance = minf(min_distance, _distance_to_rect(point, rect))
	return min_distance


func _bounds_for_points(points: Array[Vector2]) -> Rect2:
	if points.is_empty():
		return Rect2()
	var min_x := points[0].x
	var min_y := points[0].y
	var max_x := points[0].x
	var max_y := points[0].y
	for point in points:
		min_x = minf(min_x, point.x)
		min_y = minf(min_y, point.y)
		max_x = maxf(max_x, point.x)
		max_y = maxf(max_y, point.y)
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)


func _rect_approx_eq(a: Rect2, b: Rect2, epsilon: float = 0.01) -> bool:
	return a.position.distance_to(b.position) <= epsilon and a.size.distance_to(b.size) <= epsilon
