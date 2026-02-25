extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const NAV_RUNTIME_QUERIES_SCRIPT = preload("res://src/systems/navigation_runtime_queries.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeService:
	extends Node

	var force_valid_map: bool = false
	var force_obstacle_intersection: bool = false
	var room_graph_path: Array[Vector2] = [Vector2(64.0, 0.0)]
	var _map_rid: RID = RID()
	var layout = null
	var _room_graph: Dictionary = {0: [1], 1: [0]}
	var entities_container: Node = null
	var player_node: Node = null

	func _init() -> void:
		_map_rid = NavigationServer2D.map_create()

	func get_navigation_map_rid() -> RID:
		return _map_rid if force_valid_map else RID()

	func is_navigation_build_valid() -> bool:
		return true

	func _build_room_graph_path_points_reachable(_from_pos: Vector2, _to_pos: Vector2) -> Array[Vector2]:
		return room_graph_path.duplicate()

	func path_intersects_navigation_obstacles(_from_pos: Vector2, _path_points: Array) -> bool:
		return force_obstacle_intersection

	func room_id_at_point(_p: Vector2) -> int:
		return 0

	func get_neighbors(_room_id: int) -> Array[int]:
		return [1]

	func is_adjacent(_a: int, _b: int) -> bool:
		return true

	func get_door_center_between(_a: int, _b: int, _anchor: Vector2) -> Vector2:
		return Vector2(32.0, 0.0)

	func validate_enemy_path_policy(_enemy: Node, _from_pos: Vector2, _path_points: Array, _sample_step_px: float) -> Dictionary:
		return {"valid": true, "segment_index": -1}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("NAVIGATION PATH CONTRACT ROUTE SOURCE TEST")
	print("============================================================")

	await _test_room_graph_fallback_exposes_route_source_and_reason()
	await _test_path_intersection_sets_unreachable_geometry_reason()
	await _test_navmesh_source_reported_when_map_exists()
	await _test_fallback_disabled_without_navmesh_reports_contract_reason()

	_t.summary("NAVIGATION PATH CONTRACT ROUTE SOURCE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_room_graph_fallback_exposes_route_source_and_reason() -> void:
	var original := _set_room_graph_fallback_only(true)
	var service := FakeService.new()
	service.force_valid_map = false
	service.force_obstacle_intersection = false
	var nav = NAV_RUNTIME_QUERIES_SCRIPT.new(service)
	var plan := nav.build_policy_valid_path(Vector2.ZERO, Vector2(96.0, 0.0), null) as Dictionary
	_t.run_test("path contract: fallback status ok", String(plan.get("status", "")) == "ok")
	_t.run_test("path contract: route_source is room_graph on no-navmesh fallback", String(plan.get("route_source", "")) == "room_graph")
	_t.run_test("path contract: route_source_reason is present", String(plan.get("route_source_reason", "")) != "")
	_t.run_test("path contract: obstacle_intersection_detected false on clean fallback", not bool(plan.get("obstacle_intersection_detected", true)))
	_restore_room_graph_fallback_only(original)


func _test_path_intersection_sets_unreachable_geometry_reason() -> void:
	var original := _set_room_graph_fallback_only(true)
	var service := FakeService.new()
	service.force_valid_map = false
	service.force_obstacle_intersection = true
	var nav = NAV_RUNTIME_QUERIES_SCRIPT.new(service)
	var plan := nav.build_policy_valid_path(Vector2.ZERO, Vector2(96.0, 0.0), null) as Dictionary
	_t.run_test("path contract: obstacle intersection returns unreachable_geometry", String(plan.get("status", "")) == "unreachable_geometry")
	_t.run_test("path contract: obstacle intersection reason is explicit", String(plan.get("reason", "")) == "path_intersects_obstacle")
	_t.run_test("path contract: obstacle_intersection_detected true on intersection", bool(plan.get("obstacle_intersection_detected", false)))
	_restore_room_graph_fallback_only(original)


func _test_navmesh_source_reported_when_map_exists() -> void:
	var original := _set_room_graph_fallback_only(true)
	var service := FakeService.new()
	service.force_valid_map = true
	service.force_obstacle_intersection = false
	var nav = NAV_RUNTIME_QUERIES_SCRIPT.new(service)
	var plan := nav.build_policy_valid_path(Vector2.ZERO, Vector2(96.0, 0.0), null) as Dictionary
	_t.run_test("path contract: navmesh map uses navmesh route_source", String(plan.get("route_source", "")) == "navmesh")
	_t.run_test("path contract: navmesh no path keeps reason", String(plan.get("reason", "")) == "navmesh_no_path")
	_restore_room_graph_fallback_only(original)


func _test_fallback_disabled_without_navmesh_reports_contract_reason() -> void:
	var original := _set_room_graph_fallback_only(false)
	var service := FakeService.new()
	service.force_valid_map = false
	service.force_obstacle_intersection = false
	var nav = NAV_RUNTIME_QUERIES_SCRIPT.new(service)
	var plan := nav.build_policy_valid_path(Vector2.ZERO, Vector2(96.0, 0.0), null) as Dictionary
	_t.run_test("path contract: disabling fallback yields unreachable_geometry", String(plan.get("status", "")) == "unreachable_geometry")
	_t.run_test("path contract: disabling fallback reason is room_graph_fallback_disabled", String(plan.get("reason", "")) == "room_graph_fallback_disabled")
	_t.run_test("path contract: disabling fallback keeps room_graph route_source", String(plan.get("route_source", "")) == "room_graph")
	_restore_room_graph_fallback_only(original)


func _set_room_graph_fallback_only(value: bool) -> bool:
	if not GameConfig:
		return true
	if not (GameConfig.ai_balance is Dictionary):
		return true
	var nav_cost := GameConfig.ai_balance.get("nav_cost", {}) as Dictionary
	var prev := bool(nav_cost.get("allow_room_graph_fallback_without_navmesh_only", true))
	nav_cost["allow_room_graph_fallback_without_navmesh_only"] = value
	GameConfig.ai_balance["nav_cost"] = nav_cost
	return prev


func _restore_room_graph_fallback_only(value: bool) -> void:
	if not GameConfig:
		return
	if not (GameConfig.ai_balance is Dictionary):
		return
	var nav_cost := GameConfig.ai_balance.get("nav_cost", {}) as Dictionary
	nav_cost["allow_room_graph_fallback_without_navmesh_only"] = value
	GameConfig.ai_balance["nav_cost"] = nav_cost
