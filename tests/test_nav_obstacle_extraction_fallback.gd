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
	print("NAV OBSTACLE EXTRACTION FALLBACK TEST")
	print("============================================================")

	await _test_scene_fallback_used_when_layout_api_missing()
	await _test_layout_obstacles_take_priority_over_scene_fallback()

	_t.summary("NAV OBSTACLE EXTRACTION FALLBACK RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_scene_fallback_used_when_layout_api_missing() -> void:
	var room_rect := Rect2(0.0, 0.0, 200.0, 200.0)
	var raw_obstacle := Rect2(80.0, 80.0, 40.0, 40.0)
	var layout := FakeLayoutBase.new(room_rect)
	var fixture := await _create_fixture(layout)
	var world := fixture.get("world") as Node2D
	var service := fixture.get("service") as Node
	_spawn_grouped_nav_obstacle(world, raw_obstacle)

	service.call("build_from_layout", layout, world)
	await _settle_frames()

	var extracted := service.call("_extract_scene_obstacles") as Array
	var clearance := float(service.get("OBSTACLE_CLEARANCE_PX"))
	var grown := raw_obstacle.grow(clearance)
	var points := _collect_nav_outline_points(service, 0)
	var ok := (
		extracted.size() == 1
		and _rect_approx_eq(extracted[0] as Rect2, raw_obstacle)
		and _has_point_near(points, grown.position)
		and _has_point_near(points, grown.end)
	)
	_t.run_test("scene_fallback_used_when_layout_api_missing", ok)

	await _cleanup_fixture(fixture)


func _test_layout_obstacles_take_priority_over_scene_fallback() -> void:
	var room_rect := Rect2(0.0, 0.0, 220.0, 200.0)
	var layout_obstacle := Rect2(36.0, 80.0, 20.0, 40.0)
	var scene_obstacle := Rect2(144.0, 80.0, 20.0, 40.0)
	var layout := FakeLayoutWithObstacleApi.new(room_rect)
	layout.nav_obstacles_override = [layout_obstacle]
	var fixture := await _create_fixture(layout)
	var world := fixture.get("world") as Node2D
	var service := fixture.get("service") as Node
	_spawn_grouped_nav_obstacle(world, scene_obstacle)

	service.call("build_from_layout", layout, world)
	await _settle_frames()

	var extracted := service.call("_extract_scene_obstacles") as Array
	var clearance := float(service.get("OBSTACLE_CLEARANCE_PX"))
	var layout_grown := layout_obstacle.grow(clearance)
	var scene_grown := scene_obstacle.grow(clearance)
	var points := _collect_nav_outline_points(service, 0)
	var ok := (
		extracted.size() == 1
		and _rect_approx_eq(extracted[0] as Rect2, scene_obstacle)
		and _has_point_near(points, layout_grown.position)
		and _has_point_near(points, layout_grown.end)
		and not _has_point_near(points, scene_grown.position)
		and not _has_point_near(points, scene_grown.end)
	)
	_t.run_test("layout_obstacles_take_priority_over_scene_fallback", ok)

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


func _spawn_grouped_nav_obstacle(parent: Node2D, obstacle_rect: Rect2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = obstacle_rect.get_center()
	body.add_to_group("nav_obstacles")
	var shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = obstacle_rect.size
	shape.shape = rect_shape
	body.add_child(shape)
	parent.add_child(body)
	return body


func _collect_nav_outline_points(service: Node, room_id: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var room_to_region := service.get("_room_to_region") as Dictionary
	var region := room_to_region.get(room_id, null) as NavigationRegion2D
	if region == null:
		return points
	var nav_poly := region.navigation_polygon
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


func _rect_approx_eq(a: Rect2, b: Rect2, epsilon: float = 0.01) -> bool:
	return a.position.distance_to(b.position) <= epsilon and a.size.distance_to(b.size) <= epsilon
