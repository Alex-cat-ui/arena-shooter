extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LEVEL_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")

var embedded_mode: bool = false
var _t := TestHelpers.new()

const REQUIRED_SPAWN_ORDER := ["SpawnA1", "SpawnA2", "SpawnB", "SpawnC1", "SpawnC2", "SpawnD"]


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("STEALTH NAV PATH SEGMENTS AVOID PROPS TEST")
	print("============================================================")

	await _test_spawn_chain_paths_do_not_intersect_props()
	await _test_policy_aware_path_with_enemy_node()

	_t.summary("STEALTH NAV PATH SEGMENTS AVOID PROPS RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_spawn_chain_paths_do_not_intersect_props() -> void:
	var level := LEVEL_SCENE.instantiate() as Node
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame

	var nav := level.get_node_or_null("Systems/NavigationService")
	var spawns_root := level.get_node_or_null("Spawns")
	_t.run_test("segments avoid props: navigation service exists", nav != null)
	_t.run_test("segments avoid props: spawns root exists", spawns_root != null)
	if nav == null or spawns_root == null:
		level.queue_free()
		await get_tree().process_frame
		return

	var spawn_map: Dictionary = {}
	for child_variant in spawns_root.get_children():
		var child := child_variant as Node2D
		if child == null:
			continue
		spawn_map[child.name] = child.global_position

	var all_names_present := true
	for spawn_name in REQUIRED_SPAWN_ORDER:
		if not spawn_map.has(spawn_name):
			all_names_present = false
			break
	_t.run_test("segments avoid props: required spawn chain exists", all_names_present)
	if not all_names_present:
		level.queue_free()
		await get_tree().process_frame
		return

	# P1.7: Collect obstacle rects independently from nav_obstacles group.
	var obstacle_rects := _collect_obstacle_rects(level)
	_t.run_test("segments avoid props: independent obstacle oracle has props", obstacle_rects.size() > 0)

	var contract_ok := true
	var no_intersections := true
	for i in range(REQUIRED_SPAWN_ORDER.size() - 1):
		var from_pos := spawn_map[REQUIRED_SPAWN_ORDER[i]] as Vector2
		var to_pos := spawn_map[REQUIRED_SPAWN_ORDER[i + 1]] as Vector2
		var plan := nav.call("build_policy_valid_path", from_pos, to_pos, null) as Dictionary
		if String(plan.get("status", "")) != "ok":
			contract_ok = false
			continue
		if bool(plan.get("obstacle_intersection_detected", false)):
			no_intersections = false
		var path_points := plan.get("path_points", []) as Array
		# P1.7: Use independent geometric oracle instead of production helper.
		if _check_path_intersects_rects(from_pos, path_points, obstacle_rects):
			no_intersections = false

	_t.run_test("segments avoid props: spawn chain plans are ok", contract_ok)
	_t.run_test("segments avoid props: path segments do not intersect props", no_intersections)

	var outside_plan := nav.call("build_policy_valid_path", Vector2(1300.0, 780.0), Vector2(2500.0, 1400.0), null) as Dictionary
	_t.run_test(
		"segments avoid props: outside-navmesh target is unreachable_geometry",
		String(outside_plan.get("status", "")) == "unreachable_geometry"
	)
	_t.run_test(
		"segments avoid props: outside-navmesh reason is navmesh_target_unreachable",
		String(outside_plan.get("reason", "")) == "navmesh_target_unreachable"
	)

	# Coarse-step intersection via independent oracle on a known obstacle-crossing segment.
	var coarse_rects_for_probe := _collect_obstacle_rects(level)
	var coarse_step_intersection := _check_path_intersects_rects(
		Vector2(900.0, 700.0),
		[Vector2(1100.0, 700.0)],
		coarse_rects_for_probe,
		512.0
	)
	_t.run_test(
		"segments avoid props: coarse-step segment intersection is detected",
		coarse_step_intersection
	)

	level.queue_free()
	await get_tree().process_frame


## T2: Policy-aware scenarios with enemy != null.
func _test_policy_aware_path_with_enemy_node() -> void:
	var level := LEVEL_SCENE.instantiate() as Node
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame

	var nav := level.get_node_or_null("Systems/NavigationService")
	var spawns_root := level.get_node_or_null("Spawns")
	var controller := level.get_node_or_null("Stealth3ZoneTestController")
	if nav == null or spawns_root == null or controller == null:
		_t.run_test("segments avoid props (T2): prerequisites available", false)
		level.queue_free()
		await get_tree().process_frame
		return
	_t.run_test("segments avoid props (T2): prerequisites available", true)

	# Ensure at least one enemy exists for policy validation.
	if controller.has_method("debug_spawn_enemy_duplicates_for_tests"):
		controller.call("debug_spawn_enemy_duplicates_for_tests", 1)
	await get_tree().process_frame

	# Find an enemy node in the level.
	var enemy_node: Node = null
	for node_variant in get_tree().get_nodes_in_group("enemies"):
		var node := node_variant as Node
		if node != null and level.is_ancestor_of(node):
			enemy_node = node
			break

	var spawn_a1 := level.get_node_or_null("Spawns/SpawnA1") as Node2D
	if spawn_a1 == null:
		_t.run_test("segments avoid props (T2): spawn nodes exist", false)
		level.queue_free()
		await get_tree().process_frame
		return
	_t.run_test("segments avoid props (T2): spawn nodes exist", true)

	if enemy_node == null:
		_t.run_test("segments avoid props (T2): enemy node available for policy test", false)
		level.queue_free()
		await get_tree().process_frame
		return
	_t.run_test("segments avoid props (T2): enemy node available for policy test", true)

	if enemy_node is Node2D:
		(enemy_node as Node2D).global_position = spawn_a1.global_position
	if enemy_node.has_method("set_shadow_check_flashlight"):
		enemy_node.call("set_shadow_check_flashlight", false)
	if enemy_node.has_method("debug_force_awareness_state"):
		enemy_node.call("debug_force_awareness_state", "CALM")

	var blocked_target := Vector2(215.0, 320.0) # Inside ShadowA1 but outside its prop obstacle.
	var blocked_geom_plan := nav.call("build_policy_valid_path", spawn_a1.global_position, blocked_target, null) as Dictionary
	var blocked_policy_plan := nav.call("build_policy_valid_path", spawn_a1.global_position, blocked_target, enemy_node) as Dictionary
	_t.run_test(
		"segments avoid props (T2): geometry-only plan can enter target shadow pocket",
		String(blocked_geom_plan.get("status", "")) == "ok"
	)
	_t.run_test(
		"segments avoid props (T2): enemy-aware plan blocks entering shadow pocket from light",
		String(blocked_policy_plan.get("status", "")) == "unreachable_policy"
			and String(blocked_policy_plan.get("reason", "")) == "policy_blocked"
	)

	if enemy_node is Node2D:
		(enemy_node as Node2D).global_position = Vector2(1070.0, 760.0)
	var in_shadow_from := (enemy_node as Node2D).global_position if enemy_node is Node2D else Vector2(1070.0, 760.0)
	var in_shadow_to := Vector2(1060.0, 780.0)
	var in_shadow_policy_plan := nav.call("build_policy_valid_path", in_shadow_from, in_shadow_to, enemy_node) as Dictionary
	var in_shadow_status := String(in_shadow_policy_plan.get("status", ""))
	_t.run_test(
		"segments avoid props (T2): enemy already in shadow can keep moving inside shadow",
		in_shadow_status == "ok"
	)
	if in_shadow_status == "ok":
		var obstacle_rects := _collect_obstacle_rects(level)
		var in_shadow_pts := in_shadow_policy_plan.get("path_points", []) as Array
		_t.run_test(
			"segments avoid props (T2): in-shadow policy path avoids props (independent oracle)",
			not _check_path_intersects_rects(in_shadow_from, in_shadow_pts, obstacle_rects)
		)

	level.queue_free()
	await get_tree().process_frame


## P1.7: Collect Rect2 obstacles from scene collision geometry (not via NavigationService helper).
func _collect_obstacle_rects(level: Node) -> Array[Rect2]:
	var result: Array[Rect2] = []
	if level == null:
		return result
	var props_root := level.get_node_or_null("Geometry/Props")
	if props_root != null:
		for body_variant in props_root.get_children():
			var body := body_variant as StaticBody2D
			if body == null:
				continue
			for child_variant in body.get_children():
				var col := child_variant as CollisionShape2D
				if col == null or not (col.shape is RectangleShape2D):
					continue
				var rect_shape := col.shape as RectangleShape2D
				var half := rect_shape.size * 0.5
				var obs_rect := Rect2(body.global_position + col.position - half, rect_shape.size)
				if obs_rect.size.x > 0.5 and obs_rect.size.y > 0.5:
					result.append(obs_rect)
	if not result.is_empty():
		return result
	if not is_inside_tree():
		return result
	for node_variant in get_tree().get_nodes_in_group("nav_obstacles"):
		var grouped_body := node_variant as StaticBody2D
		if grouped_body == null:
			continue
		if grouped_body != level and not level.is_ancestor_of(grouped_body):
			continue
		for child_variant in grouped_body.get_children():
			var grouped_col := child_variant as CollisionShape2D
			if grouped_col == null or not (grouped_col.shape is RectangleShape2D):
				continue
			var grouped_shape := grouped_col.shape as RectangleShape2D
			var grouped_half := grouped_shape.size * 0.5
			var grouped_rect := Rect2(grouped_body.global_position + grouped_col.position - grouped_half, grouped_shape.size)
			if grouped_rect.size.x > 0.5 and grouped_rect.size.y > 0.5:
				result.append(grouped_rect)
	return result


## P1.7: Independent segment/point intersection check against a list of obstacle rects.
func _check_path_intersects_rects(
	from_pos: Vector2,
	path_points: Array,
	rects: Array[Rect2],
	sample_step: float = 8.0
) -> bool:
	if rects.is_empty() or path_points.is_empty():
		return false
	const EPSILON := 0.001
	var effective_step := maxf(sample_step, 1.0)
	var prev := from_pos
	for point_variant in path_points:
		var point := point_variant as Vector2
		for obs in rects:
			if obs.size.x <= 0.5 or obs.size.y <= 0.5:
				continue
			if _rect_seg_intersects(obs, prev, point, EPSILON):
				return true
		var seg_len := prev.distance_to(point)
		var steps := maxi(int(ceil(seg_len / effective_step)), 1)
		for step in range(1, steps + 1):
			var sample := prev.lerp(point, float(step) / float(steps))
			for obs in rects:
				if obs.size.x <= 0.5 or obs.size.y <= 0.5:
					continue
				if obs.has_point(sample):
					return true
		prev = point
	return false


static func _rect_seg_intersects(rect: Rect2, s: Vector2, e: Vector2, epsilon: float) -> bool:
	if rect.has_point(s) or rect.has_point(e):
		return true
	var tl := rect.position
	var tr := Vector2(rect.end.x, rect.position.y)
	var br := rect.end
	var bl := Vector2(rect.position.x, rect.end.y)
	return (
		_segs_cross(s, e, tl, tr, epsilon)
		or _segs_cross(s, e, tr, br, epsilon)
		or _segs_cross(s, e, br, bl, epsilon)
		or _segs_cross(s, e, bl, tl, epsilon)
	)


static func _segs_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2, epsilon: float) -> bool:
	var ab := b - a
	var cd := d - c
	var denom := ab.x * cd.y - ab.y * cd.x
	if absf(denom) < epsilon:
		return false
	var t := ((c.x - a.x) * cd.y - (c.y - a.y) * cd.x) / denom
	var u := ((c.x - a.x) * ab.y - (c.y - a.y) * ab.x) / denom
	return t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0
