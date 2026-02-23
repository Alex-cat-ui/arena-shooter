extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const NAV_RUNTIME_QUERIES_SCRIPT := preload("res://src/systems/navigation_runtime_queries.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeEnemy:
	extends Node2D
	var flashlight_active: bool = false

	func is_flashlight_active_for_navigation() -> bool:
		return flashlight_active


class FakeLayout:
	extends RefCounted
	var valid: bool = true
	var rooms: Array = [
		{"center": Vector2(40.0, 0.0), "rects": [Rect2(-20.0, -120.0, 120.0, 240.0)]},
		{"center": Vector2(150.0, 0.0), "rects": [Rect2(90.0, -120.0, 120.0, 240.0)]},
		{"center": Vector2(260.0, 0.0), "rects": [Rect2(200.0, -120.0, 120.0, 240.0)]},
	]

	func _room_id_at_point(p: Vector2) -> int:
		if p.x < 100.0:
			return 0
		if p.x < 200.0:
			return 1
		if p.x < 320.0:
			return 2
		return -1


class FakeService:
	extends Node

	var layout = FakeLayout.new()
	var _room_graph: Dictionary = {
		0: [1],
		1: [0, 2],
		2: [1],
	}
	var _pair_doors: Dictionary = {
		"0|1": [Vector2(100.0, 80.0)],
		"1|2": [Vector2(200.0, 80.0)],
	}
	var geometry_path_points: Array[Vector2] = []
	var blocked_rects: Array[Rect2] = []

	func get_navigation_map_rid() -> RID:
		return RID()

	func _build_room_graph_path_points_reachable(_from_pos: Vector2, _to_pos: Vector2) -> Array[Vector2]:
		return geometry_path_points.duplicate()

	func _select_door_center(a: int, b: int, anchor: Vector2) -> Vector2:
		var key := _pair_key(a, b)
		if _pair_doors.has(key):
			var centers := _pair_doors[key] as Array
			if not centers.is_empty():
				var best := centers[0] as Vector2
				var best_dist := best.distance_to(anchor)
				for center_variant in centers:
					var center := center_variant as Vector2
					var dist := center.distance_to(anchor)
					if dist < best_dist:
						best = center
						best_dist = dist
				return best
		return anchor

	func validate_enemy_path_policy(enemy: Node, from_pos: Vector2, path_points: Array, sample_step_px: float = 12.0) -> Dictionary:
		var pts: Array[Vector2] = []
		for point_variant in path_points:
			pts.append(point_variant as Vector2)
		var prev := from_pos
		var segment_index := 0
		var step_px := maxf(sample_step_px, 1.0)
		for point in pts:
			var segment_len := prev.distance_to(point)
			var steps := maxi(int(ceil(segment_len / step_px)), 1)
			for step in range(1, steps + 1):
				var t := float(step) / float(steps)
				var sample := prev.lerp(point, t)
				if not can_enemy_traverse_point(enemy, sample):
					return {
						"valid": false,
						"segment_index": segment_index,
						"blocked_point": sample,
					}
			prev = point
			segment_index += 1
		return {
			"valid": true,
			"segment_index": -1,
		}

	func can_enemy_traverse_point(enemy: Node, point: Vector2) -> bool:
		if not _is_point_blocked(point):
			return true
		if enemy != null and enemy.has_method("is_flashlight_active_for_navigation"):
			if bool(enemy.call("is_flashlight_active_for_navigation")):
				return true
		var enemy_node := enemy as Node2D
		if enemy_node != null and _is_point_blocked(enemy_node.global_position):
			return true
		return false

	func _is_point_blocked(point: Vector2) -> bool:
		for rect_variant in blocked_rects:
			var rect := rect_variant as Rect2
			if rect.has_point(point):
				return true
		return false

	func _pair_key(a: int, b: int) -> String:
		if a <= b:
			return "%d|%d" % [a, b]
		return "%d|%d" % [b, a]


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("NAVIGATION POLICY DETOUR (DIRECT BLOCKED -> 1WP) TEST")
	print("============================================================")

	_test_one_waypoint_detour_and_exhausted_policy()

	_t.summary("NAVIGATION POLICY DETOUR (DIRECT BLOCKED -> 1WP) RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_one_waypoint_detour_and_exhausted_policy() -> void:
	var service := FakeService.new()
	add_child(service)
	var queries = NAV_RUNTIME_QUERIES_SCRIPT.new(service)

	var enemy := FakeEnemy.new()
	enemy.global_position = Vector2(0.0, 0.0)
	add_child(enemy)

	var from_pos := Vector2(0.0, 0.0)
	var to_pos := Vector2(280.0, 0.0)
	service.geometry_path_points = [to_pos]
	service.blocked_rects = [Rect2(40.0, -20.0, 220.0, 40.0)]

	var one_wp := queries.build_policy_valid_path(from_pos, to_pos, enemy) as Dictionary
	var one_wp_path := one_wp.get("path_points", []) as Array
	_t.run_test(
		"direct blocked returns valid 1wp detour",
		String(one_wp.get("status", "")) == "ok"
			and String(one_wp.get("reason", "")) == "ok"
			and String(one_wp.get("route_type", "")) == "1wp"
			and not one_wp_path.is_empty()
			and (one_wp_path.back() as Vector2).distance_to(to_pos) <= 0.001
	)

	service.blocked_rects = [Rect2(20.0, -40.0, 300.0, 180.0)]
	var exhausted := queries.build_policy_valid_path(from_pos, to_pos, enemy) as Dictionary
	_t.run_test(
		"all routes blocked returns unreachable_policy without blocked_point",
		String(exhausted.get("status", "")) == "unreachable_policy"
			and String(exhausted.get("reason", "")) == "policy_blocked"
			and (exhausted.get("path_points", []) as Array).is_empty()
			and not exhausted.has("blocked_point")
	)

	enemy.queue_free()
	service.queue_free()

