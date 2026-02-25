extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const NAVIGATION_SERVICE_SCRIPT := preload("res://src/systems/navigation_service.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
const LAYOUT_DOOR_SYSTEM_SCRIPT := preload("res://src/systems/layout_door_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeLayout:
	extends RefCounted

	var valid: bool = true
	var rooms: Array = []
	var doors: Array = []
	var _door_adj: Dictionary = {}
	var _void_ids: Array = []

	func _init(p_rooms: Array = [], p_doors: Array = [], p_door_adj: Dictionary = {}) -> void:
		rooms = p_rooms
		doors = p_doors
		_door_adj = p_door_adj

	func _room_id_at_point(p: Vector2) -> int:
		for i in range(rooms.size()):
			if i in _void_ids:
				continue
			var room := rooms[i] as Dictionary
			for rect_variant in (room.get("rects", []) as Array):
				var r := rect_variant as Rect2
				if r.grow(0.1).has_point(p):
					return i
		return -1

	func _door_adjacent_room_ids(door: Rect2) -> Array:
		var ids: Dictionary = {}
		var center := door.get_center()
		var probe := 8.0
		if door.size.y >= door.size.x:
			var left_id := _room_id_at_point(Vector2(center.x - probe, center.y))
			var right_id := _room_id_at_point(Vector2(center.x + probe, center.y))
			if left_id >= 0:
				ids[left_id] = true
			if right_id >= 0:
				ids[right_id] = true
		else:
			var top_id := _room_id_at_point(Vector2(center.x, center.y - probe))
			var bottom_id := _room_id_at_point(Vector2(center.x, center.y + probe))
			if top_id >= 0:
				ids[top_id] = true
			if bottom_id >= 0:
				ids[bottom_id] = true
		return ids.keys()


class FakeLayoutWithNavObstacles:
	extends FakeLayout

	var nav_obstacles_override: Array[Rect2] = []

	func _navigation_obstacles() -> Array[Rect2]:
		return nav_obstacles_override.duplicate()


class FakePatrolDecision:
	extends RefCounted

	var fixed_target: Vector2 = Vector2.ZERO
	var fixed_speed_scale: float = 1.0

	func _init(target: Vector2, speed_scale: float = 1.0) -> void:
		fixed_target = target
		fixed_speed_scale = speed_scale

	func configure(_nav_system: Node, _home_room_id: int) -> void:
		pass

	func update(_delta: float, _facing_dir: Vector2) -> Dictionary:
		return {
			"waiting": false,
			"target": fixed_target,
			"speed_scale": fixed_speed_scale,
		}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("NAVMESH MIGRATION TEST")
	print("============================================================")

	await _test_navmesh_built_from_layout()
	await _test_nav_agent_finds_path()
	await _test_enemy_navigates_to_target()
	await _test_enemy_navigates_to_target_via_patrol_execute_intent()
	await _test_door_traversal_via_navmesh()
	_test_l1_detour_removed()
	await _test_navmesh_single_rect_room()
	await _test_navmesh_l_shaped_room()
	await _test_navmesh_disjoint_rects()
	await _test_navmesh_door_overlap_connects_regions()
	await _test_navmesh_notched_room()
	await _test_obstacle_extraction_fallback()
	await _test_layout_obstacle_api_priority()
	await _test_clearance_margin_applied()

	_t.summary("NAVMESH MIGRATION RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_navmesh_built_from_layout() -> void:
	var fixture := await _create_two_room_fixture()
	var service = fixture.get("service")
	var map_rid: RID = service.call("get_navigation_map_rid")
	var regions := NavigationServer2D.map_get_regions(map_rid)
	var room_to_region := service.get("_room_to_region") as Dictionary
	_t.run_test("navmesh_built_from_layout", room_to_region.size() == 2 and regions.size() >= 2)
	await _cleanup_fixture(fixture)


func _test_nav_agent_finds_path() -> void:
	var fixture := await _create_two_room_fixture()
	var service = fixture.get("service")
	var actor := await _create_actor(fixture, service, Vector2(120.0, 100.0), 0)
	var nav_agent := actor.get("nav_agent") as NavigationAgent2D
	var pursuit := actor.get("pursuit") as Object
	var target := Vector2(280.0, 100.0)
	pursuit.call("_plan_path_to", target)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var next_point := nav_agent.get_next_path_position()
	var valid_next := next_point.distance_to(target) < Vector2(120.0, 100.0).distance_to(target)
	_t.run_test("nav_agent_finds_path", not nav_agent.is_navigation_finished() and valid_next)
	await _cleanup_fixture(fixture)


func _test_enemy_navigates_to_target() -> void:
	var fixture := await _create_two_room_fixture()
	var service = fixture.get("service")
	var actor := await _create_actor(fixture, service, Vector2(150.0, 100.0), 0)
	var owner := actor.get("owner") as CharacterBody2D
	var pursuit := actor.get("pursuit") as Object
	var target := Vector2(210.0, 100.0)
	for _i in range(60):
		pursuit.call("_execute_move_to_target", 1.0 / 60.0, target, 1.0, false)
		await get_tree().physics_frame
	_t.run_test("enemy_navigates_to_target", owner.global_position.distance_to(target) <= 20.0)
	await _cleanup_fixture(fixture)


func _test_enemy_navigates_to_target_via_patrol_execute_intent() -> void:
	var fixture := await _create_two_room_fixture()
	var service = fixture.get("service")
	var actor := await _create_actor(fixture, service, Vector2(150.0, 100.0), 0)
	var owner := actor.get("owner") as CharacterBody2D
	var pursuit := actor.get("pursuit") as Object
	var target := Vector2(280.0, 100.0)
	pursuit.set("_patrol", FakePatrolDecision.new(target, 1.0))

	var initial_distance := owner.global_position.distance_to(target)
	var moved_total := 0.0
	var prev_pos := owner.global_position
	var saw_plan_status_ok := false
	for _i in range(120):
		pursuit.execute_intent(
			1.0 / 60.0,
			{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL},
			_patrol_context(target)
		)
		await get_tree().physics_frame
		var current_pos := owner.global_position
		moved_total += current_pos.distance_to(prev_pos)
		prev_pos = current_pos
		var snapshot := pursuit.call("debug_get_navigation_policy_snapshot") as Dictionary
		if String(snapshot.get("path_plan_status", "")) == "ok":
			saw_plan_status_ok = true
	var final_distance := owner.global_position.distance_to(target)

	_t.run_test(
		"enemy_navigates_to_target_via_patrol_execute_intent",
		moved_total > 8.0 and final_distance < initial_distance
	)
	_t.run_test("patrol_execute_intent_updates_nav_plan_snapshot", saw_plan_status_ok)
	await _cleanup_fixture(fixture)


func _test_door_traversal_via_navmesh() -> void:
	var fixture := await _create_two_room_fixture(true)
	var service = fixture.get("service")
	var actor := await _create_actor(fixture, service, Vector2(150.0, 100.0), 0)
	var owner := actor.get("owner") as CharacterBody2D
	var pursuit := actor.get("pursuit") as Object
	var door_system := fixture.get("door_system") as Node
	owner.set_meta("door_system", door_system)
	var target := Vector2(260.0, 100.0)
	var door_opened := false
	var arrived := false
	for _i in range(240):
		pursuit.call("_execute_move_to_target", 1.0 / 60.0, target, 1.0, false)
		await get_tree().physics_frame
		var doors_parent := fixture.get("doors_parent") as Node2D
		if doors_parent and doors_parent.get_child_count() > 0:
			var door := doors_parent.get_child(0)
			if door and door.has_method("get_debug_metrics"):
				var metrics := door.get_debug_metrics() as Dictionary
				if absf(float(metrics.get("angle_deg", 0.0))) > 1.0:
					door_opened = true
		var in_room_b: bool = false
		if service.has_method("room_id_at_point"):
			in_room_b = int(service.room_id_at_point(owner.global_position)) == 1
		if in_room_b and owner.global_position.x >= 200.0:
			arrived = true
		if door_opened and arrived:
			break
	_t.run_test("door_traversal_via_navmesh", door_opened and arrived)
	await _cleanup_fixture(fixture)


func _test_l1_detour_removed() -> void:
	var owner := CharacterBody2D.new()
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	var pursuit := ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	_t.run_test("l1_detour_removed", not pursuit.has_method("_resolve_combat_l1_move_target"))
	owner.queue_free()


func _test_navmesh_single_rect_room() -> void:
	var fixture := await _create_single_room_fixture([Rect2(0.0, 0.0, 100.0, 80.0)])
	var service = fixture.get("service")
	var room_to_region := service.get("_room_to_region") as Dictionary
	var region := room_to_region.get(0, null) as NavigationRegion2D
	var nav_poly := region.navigation_polygon if region else null
	var ok := nav_poly != null and nav_poly.get_outline_count() == 1 and nav_poly.get_outline(0).size() == 4
	_t.run_test("navmesh_single_rect_room", ok)
	await _cleanup_fixture(fixture)


func _test_navmesh_l_shaped_room() -> void:
	var fixture := await _create_single_room_fixture([
		Rect2(0.0, 0.0, 100.0, 40.0),
		Rect2(0.0, 0.0, 40.0, 100.0),
	])
	var service = fixture.get("service")
	var room_to_region := service.get("_room_to_region") as Dictionary
	var region := room_to_region.get(0, null) as NavigationRegion2D
	var nav_poly := region.navigation_polygon if region else null
	var outline_size := nav_poly.get_outline(0).size() if nav_poly and nav_poly.get_outline_count() > 0 else -1
	_t.run_test("navmesh_l_shaped_room", nav_poly != null and nav_poly.get_outline_count() == 1 and outline_size == 6)
	await _cleanup_fixture(fixture)


func _test_navmesh_disjoint_rects() -> void:
	var fixture := await _create_single_room_fixture([
		Rect2(0.0, 0.0, 60.0, 60.0),
		Rect2(120.0, 0.0, 60.0, 60.0),
	])
	var service = fixture.get("service")
	var room_to_region := service.get("_room_to_region") as Dictionary
	var region := room_to_region.get(0, null) as NavigationRegion2D
	var nav_poly := region.navigation_polygon if region else null
	_t.run_test("navmesh_disjoint_rects", nav_poly != null and nav_poly.get_outline_count() == 2)
	await _cleanup_fixture(fixture)


func _test_navmesh_door_overlap_connects_regions() -> void:
	var fixture := await _create_two_room_fixture()
	var service = fixture.get("service")
	await get_tree().physics_frame
	var map_rid: RID = service.call("get_navigation_map_rid")
	var path := PackedVector2Array()
	for _i in range(4):
		path = NavigationServer2D.map_get_path(map_rid, Vector2(100.0, 100.0), Vector2(300.0, 100.0), true)
		if not path.is_empty():
			break
		await get_tree().physics_frame
	_t.run_test("navmesh_door_overlap_connects_regions", not path.is_empty())
	await _cleanup_fixture(fixture)


func _test_navmesh_notched_room() -> void:
	var fixture := await _create_single_room_fixture([
		Rect2(0.0, 0.0, 120.0, 32.0),
		Rect2(0.0, 32.0, 32.0, 96.0),
		Rect2(88.0, 32.0, 32.0, 96.0),
	])
	var service = fixture.get("service")
	var room_to_region := service.get("_room_to_region") as Dictionary
	var region := room_to_region.get(0, null) as NavigationRegion2D
	var nav_poly := region.navigation_polygon if region else null
	var ok := nav_poly != null and nav_poly.get_polygon_count() > 0
	_t.run_test("navmesh_notched_room", ok)
	await _cleanup_fixture(fixture)


func _test_obstacle_extraction_fallback() -> void:
	var fixture := await _create_single_room_fixture([Rect2(0.0, 0.0, 200.0, 200.0)])
	var service = fixture.get("service") as Node
	var world := fixture.get("world") as Node2D
	var raw_obstacle := Rect2(80.0, 80.0, 40.0, 40.0)
	var clearance := float(service.get("OBSTACLE_CLEARANCE_PX"))
	var baseline_points := _collect_nav_outline_points(service, 0)
	var grown := raw_obstacle.grow(clearance)
	_spawn_grouped_nav_obstacle(world, raw_obstacle)
	service.call("build_from_layout", fixture.get("layout"), world)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var extracted := service.call("_extract_scene_obstacles") as Array
	var points := _collect_nav_outline_points(service, 0)
	var ok := (
		extracted.size() == 1
		and _rect_approx_eq(extracted[0] as Rect2, raw_obstacle)
		and not _has_point_near(baseline_points, grown.position)
		and _has_point_near(points, grown.position)
		and _has_point_near(points, grown.end)
	)
	_t.run_test("navmesh_scene_obstacle_fallback", ok)
	await _cleanup_fixture(fixture)


func _test_layout_obstacle_api_priority() -> void:
	var room_rect := Rect2(0.0, 0.0, 220.0, 200.0)
	var room := {
		"center": room_rect.get_center(),
		"rects": [room_rect],
	}
	var layout_obstacle := Rect2(30.0, 80.0, 24.0, 40.0)
	var scene_obstacle := Rect2(150.0, 80.0, 24.0, 40.0)
	var layout := FakeLayoutWithNavObstacles.new([room], [], {})
	layout.nav_obstacles_override = [layout_obstacle]
	var fixture := await _create_fixture(layout, false)
	var service := fixture.get("service") as Node
	var world := fixture.get("world") as Node2D
	_spawn_grouped_nav_obstacle(world, scene_obstacle)
	service.call("build_from_layout", layout, world)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var source := String(service.call("debug_get_nav_obstacle_source"))
	var clearance := float(service.get("OBSTACLE_CLEARANCE_PX"))
	var points := _collect_nav_outline_points(service, 0)
	var layout_grown := layout_obstacle.grow(clearance)
	var scene_grown := scene_obstacle.grow(clearance)
	var ok := (
		source == "layout_api"
		and _has_point_near(points, layout_grown.position)
		and _has_point_near(points, layout_grown.end)
		and not _has_point_near(points, scene_grown.position)
		and not _has_point_near(points, scene_grown.end)
	)
	_t.run_test("navmesh_layout_obstacle_api_priority", ok)
	await _cleanup_fixture(fixture)


func _test_clearance_margin_applied() -> void:
	var room_rect := Rect2(0.0, 0.0, 200.0, 200.0)
	var room := {
		"center": room_rect.get_center(),
		"rects": [room_rect],
	}
	var raw_obstacle := Rect2(90.0, 90.0, 20.0, 20.0)
	var layout := FakeLayoutWithNavObstacles.new([room], [], {})
	layout.nav_obstacles_override = [raw_obstacle]
	var fixture := await _create_fixture(layout, false)
	var service = fixture.get("service") as Node
	var clearance := float(service.get("OBSTACLE_CLEARANCE_PX"))
	var points := _collect_nav_outline_points(service, 0)
	var min_distance := _min_distance_to_rect(points, raw_obstacle)
	var grown := raw_obstacle.grow(clearance)
	var ok := min_distance >= (clearance - 0.1) and _has_point_near(points, grown.position)
	_t.run_test("navmesh_clearance_margin_applied", ok)
	await _cleanup_fixture(fixture)


func _create_single_room_fixture(rects: Array) -> Dictionary:
	var room := {
		"center": (rects[0] as Rect2).get_center() if not rects.is_empty() else Vector2.ZERO,
		"rects": rects,
	}
	var layout := FakeLayout.new([room], [], {})
	return await _create_fixture(layout, false)


func _create_two_room_fixture(with_door_system: bool = false) -> Dictionary:
	var room_a := {
		"center": Vector2(100.0, 100.0),
		"rects": [Rect2(0.0, 0.0, 200.0, 200.0)],
	}
	var room_b := {
		"center": Vector2(300.0, 100.0),
		"rects": [Rect2(200.0, 0.0, 200.0, 200.0)],
	}
	var doors: Array = [Rect2(184.0, 50.0, 32.0, 100.0)]
	var adj := {
		0: [1],
		1: [0],
	}
	var layout := FakeLayout.new([room_a, room_b], doors, adj)
	return await _create_fixture(layout, with_door_system)


func _create_fixture(layout: FakeLayout, with_door_system: bool) -> Dictionary:
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
	service.build_from_layout(layout, world)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var doors_parent: Node2D = null
	var door_system: Node = null
	if with_door_system:
		doors_parent = Node2D.new()
		doors_parent.name = "LayoutDoors"
		world.add_child(doors_parent)
		door_system = LAYOUT_DOOR_SYSTEM_SCRIPT.new()
		door_system.name = "LayoutDoorSystem"
		world.add_child(door_system)
		door_system.initialize(doors_parent)
		door_system.rebuild_for_layout(layout)
		_add_boundary_walls_for_door_test(world, layout)
		await get_tree().physics_frame
		await get_tree().physics_frame

	return {
		"world": world,
		"layout": layout,
		"entities": entities,
		"player": player,
		"service": service,
		"doors_parent": doors_parent,
		"door_system": door_system,
	}


func _create_actor(fixture: Dictionary, service: Node, start_pos: Vector2, home_room: int) -> Dictionary:
	var world := fixture.get("world") as Node2D
	var entities := fixture.get("entities") as Node2D

	var owner := CharacterBody2D.new()
	owner.global_position = start_pos
	owner.collision_layer = 2
	owner.collision_mask = 1
	var body_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	body_shape.shape = circle
	owner.add_child(body_shape)
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	var nav_agent := NavigationAgent2D.new()
	nav_agent.path_desired_distance = 12.0
	nav_agent.target_desired_distance = 12.0
	nav_agent.avoidance_enabled = false
	nav_agent.debug_enabled = false
	owner.add_child(nav_agent)
	entities.add_child(owner)

	var pursuit := ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	pursuit.configure_nav_agent(nav_agent)
	pursuit.configure_navigation(service, home_room)
	await get_tree().physics_frame

	return {
		"world": world,
		"owner": owner,
		"nav_agent": nav_agent,
		"pursuit": pursuit,
	}


func _cleanup_fixture(fixture: Dictionary) -> void:
	var world := fixture.get("world", null) as Node
	if world and is_instance_valid(world):
		world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _add_boundary_walls_for_door_test(world: Node2D, layout: FakeLayout) -> void:
	if layout.rooms.size() < 2 or layout.doors.is_empty():
		return
	var room_a := layout.rooms[0] as Dictionary
	var primary_rect := (room_a.get("rects", []) as Array)[0] as Rect2
	var door := layout.doors[0] as Rect2
	var boundary_x := door.position.x
	var wall_width := door.size.x
	var top_h := door.position.y - primary_rect.position.y
	if top_h > 1.0:
		_spawn_static_wall(world, Rect2(boundary_x, primary_rect.position.y, wall_width, top_h))
	var bottom_y := door.end.y
	var bottom_h := primary_rect.end.y - bottom_y
	if bottom_h > 1.0:
		_spawn_static_wall(world, Rect2(boundary_x, bottom_y, wall_width, bottom_h))


func _spawn_static_wall(parent: Node2D, wall_rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	body.position = wall_rect.get_center()
	var shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = wall_rect.size
	shape.shape = rect_shape
	body.add_child(shape)
	parent.add_child(body)


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


func _rect_approx_eq(a: Rect2, b: Rect2, epsilon: float = 0.01) -> bool:
	return a.position.distance_to(b.position) <= epsilon and a.size.distance_to(b.size) <= epsilon


func _patrol_context(player_pos: Vector2) -> Dictionary:
	return {
		"player_pos": player_pos,
		"known_target_pos": Vector2.ZERO,
		"last_seen_pos": Vector2.ZERO,
		"investigate_anchor": Vector2.ZERO,
		"home_position": Vector2.ZERO,
		"alert_level": 0,
		"los": false,
		"combat_lock": false,
	}
