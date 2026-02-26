extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
const LEVEL_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeDetourNav:
	extends Node

	var direct_calls: int = 0
	var detour_calls: int = 0

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func can_enemy_traverse_point(_enemy: Node, _point: Vector2) -> bool:
		return true

	func build_policy_valid_path(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		if direct_calls == 0:
			direct_calls += 1
			return {
				"status": "ok",
				"path_points": [to_pos],
				"reason": "ok",
			}
		detour_calls += 1
		return {
			"status": "ok",
			"path_points": [
				Vector2(52.0, 96.0),
				Vector2(168.0, 96.0),
				to_pos,
			],
			"reason": "ok",
		}


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
	print("PATROL OBSTACLE AVOIDANCE WALL TEST")
	print("============================================================")

	await _test_patrol_detours_wall_and_keeps_progress()
	await _test_integration_nav_service_path_avoids_wall()

	_t.summary("PATROL OBSTACLE AVOIDANCE WALL RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_patrol_detours_wall_and_keeps_progress() -> void:
	var root := Node2D.new()
	add_child(root)
	TestHelpers.add_wall(root, Vector2(100.0, 0.0), Vector2(24.0, 220.0))
	var enemy := TestHelpers.spawn_mover(root, Vector2(0.0, 0.0), 1, 1, "enemies")
	var nav := FakeDetourNav.new()
	root.add_child(nav)

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(enemy, null, 2.4)
	pursuit.configure_navigation(nav, 0)
	var patrol_target := Vector2(220.0, 0.0)
	pursuit.set("_patrol", FakePatrolDecision.new(patrol_target, 1.0))

	await get_tree().process_frame
	await get_tree().physics_frame

	var initial_distance := enemy.global_position.distance_to(patrol_target)
	var moved_total := 0.0
	var prev_pos := enemy.global_position
	var collision_seen := false
	var collision_forced_repath := false
	var detour_lane_seen := false
	var max_stall_streak := 0
	var stall_streak := 0

	for _i in range(300):
		pursuit.execute_intent(
			1.0 / 60.0,
			{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL},
			_patrol_context(patrol_target)
		)
		await get_tree().physics_frame

		var current_pos := enemy.global_position
		var step_px := current_pos.distance_to(prev_pos)
		moved_total += step_px
		if step_px < 0.08 and current_pos.distance_to(patrol_target) > 28.0:
			stall_streak += 1
		else:
			max_stall_streak = maxi(max_stall_streak, stall_streak)
			stall_streak = 0
		prev_pos = current_pos

		var snapshot := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
		if String(snapshot.get("collision_kind", "")) == "non_door":
			collision_seen = true
			collision_forced_repath = collision_forced_repath or bool(snapshot.get("collision_forced_repath", false))
		if current_pos.x >= 40.0 and absf(current_pos.y) >= 24.0:
			detour_lane_seen = true
		if current_pos.distance_to(patrol_target) <= 20.0:
			break

	max_stall_streak = maxi(max_stall_streak, stall_streak)
	var final_distance := enemy.global_position.distance_to(patrol_target)

	_t.run_test("patrol wall: enemy makes progress toward target", final_distance < initial_distance)
	_t.run_test("patrol wall: movement is non-trivial", moved_total > 40.0)
	_t.run_test("patrol wall: enemy enters detour lane around wall", detour_lane_seen)
	_t.run_test("patrol wall: no long wall-grind streak", max_stall_streak <= 45)
	_t.run_test("patrol wall: fallback collision-repath contract holds when collision occurs", (not collision_seen) or collision_forced_repath)
	_t.run_test("patrol wall: planner switches from direct to detour", nav.direct_calls >= 1 and nav.detour_calls >= 1)

	root.queue_free()
	await get_tree().physics_frame


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


func can_enemy_traverse_geometry_point(_enemy: Node, _point: Vector2) -> bool:
	return true


## P1.10/T1: Integration test - real NavigationService on 3-zone scene avoids walls.
func _test_integration_nav_service_path_avoids_wall() -> void:
	var level := LEVEL_SCENE.instantiate() as Node
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame

	var nav := level.get_node_or_null("Systems/NavigationService")
	if nav == null or not nav.has_method("build_policy_valid_path"):
		_t.run_test("integration wall: navigation service available on 3zone scene", false)
		level.queue_free()
		await get_tree().process_frame
		return
	_t.run_test("integration wall: navigation service available on 3zone scene", true)

	var from_node := level.get_node_or_null("Spawns/SpawnA1") as Node2D
	var to_node := level.get_node_or_null("Spawns/SpawnA2") as Node2D
	if from_node == null or to_node == null:
		_t.run_test("integration wall: required spawn nodes exist", false)
		level.queue_free()
		await get_tree().process_frame
		return
	_t.run_test("integration wall: required spawn nodes exist", true)
	var from_pos := from_node.global_position
	var plan := nav.call("build_policy_valid_path", from_pos, to_node.global_position, null) as Dictionary
	var status := String(plan.get("status", ""))
	_t.run_test(
		"integration wall: plan status is contract-valid",
		status == "ok" or status == "unreachable_geometry" or status == "unreachable_policy"
	)
	_t.run_test(
		"integration wall: cross-room path has no obstacle intersection flag",
		not bool(plan.get("obstacle_intersection_detected", false))
	)
	_t.run_test(
		"integration wall: cross-room path has non-empty route_source",
		String(plan.get("route_source", "")) != ""
	)
	_t.run_test(
		"integration wall: non-ok plan has explicit reason",
		status == "ok" or String(plan.get("reason", "")) != ""
	)

	# Independent geometric oracle: path must not cross any nav_obstacle rect.
	if status == "ok":
		var obstacle_rects := _collect_integration_obstacle_rects(level, false)
		_t.run_test("integration wall: independent wall oracle has collision rects", obstacle_rects.size() > 0)
		var path_pts := plan.get("path_points", []) as Array
		var no_intersect := not _check_path_vs_rects(from_pos, path_pts, obstacle_rects)
		_t.run_test("integration wall: path avoids walls (independent oracle)", no_intersect)

	level.queue_free()
	await get_tree().process_frame


func _collect_integration_obstacle_rects(level: Node, include_props: bool) -> Array[Rect2]:
	var result: Array[Rect2] = []
	if level == null:
		return result
	var geometry_root := level.get_node_or_null("Geometry")
	if geometry_root == null:
		return result
	for child_variant in geometry_root.get_children():
		var child := child_variant as Node
		if child == null:
			continue
		if not include_props and child.name == "Props":
			continue
		_collect_static_body_rects_recursive(child, result)
	return result


func _collect_static_body_rects_recursive(node: Node, out: Array[Rect2]) -> void:
	var body := node as StaticBody2D
	if body != null:
		for body_child_variant in body.get_children():
			var col := body_child_variant as CollisionShape2D
			if col == null or not (col.shape is RectangleShape2D):
				continue
			var rs := col.shape as RectangleShape2D
			var half := rs.size * 0.5
			var r := Rect2(body.global_position + col.position - half, rs.size)
			if r.size.x > 0.5 and r.size.y > 0.5:
				out.append(r)
	for child_variant in node.get_children():
		var child := child_variant as Node
		if child == null:
			continue
		_collect_static_body_rects_recursive(child, out)


func _check_path_vs_rects(from_pos: Vector2, path_points: Array, rects: Array[Rect2]) -> bool:
	if rects.is_empty() or path_points.is_empty():
		return false
	const EPSILON := 0.001
	const STEP_PX := 8.0
	var prev := from_pos
	for point_variant in path_points:
		var point := point_variant as Vector2
		for obs in rects:
			if obs.size.x <= 0.5 or obs.size.y <= 0.5:
				continue
			if _seg_vs_rect(obs, prev, point, EPSILON):
				return true
		var seg_len := prev.distance_to(point)
		var steps := maxi(int(ceil(seg_len / STEP_PX)), 1)
		for step in range(1, steps + 1):
			var sample := prev.lerp(point, float(step) / float(steps))
			for obs in rects:
				if obs.size.x <= 0.5 or obs.size.y <= 0.5:
					continue
				if obs.has_point(sample):
					return true
		prev = point
	return false


static func _seg_vs_rect(rect: Rect2, s: Vector2, e: Vector2, eps: float) -> bool:
	if rect.has_point(s) or rect.has_point(e):
		return true
	var tl := rect.position
	var tr := Vector2(rect.end.x, rect.position.y)
	var br := rect.end
	var bl := Vector2(rect.position.x, rect.end.y)
	return _seg_cross(s, e, tl, tr, eps) or _seg_cross(s, e, tr, br, eps) or _seg_cross(s, e, br, bl, eps) or _seg_cross(s, e, bl, tl, eps)


static func _seg_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2, eps: float) -> bool:
	var ab := b - a
	var cd := d - c
	var denom := ab.x * cd.y - ab.y * cd.x
	if absf(denom) < eps:
		return false
	var t := ((c.x - a.x) * cd.y - (c.y - a.y) * cd.x) / denom
	var u := ((c.x - a.x) * ab.y - (c.y - a.y) * ab.x) / denom
	return t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0
