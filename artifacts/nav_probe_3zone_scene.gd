extends Node

const LEVEL_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")

func _path_len(from_pos: Vector2, pts: Array) -> float:
	var total := 0.0
	var prev := from_pos
	for p_var in pts:
		var p := p_var as Vector2
		total += prev.distance_to(p)
		prev = p
	return total

func _print_plan(nav: Node, from_pos: Vector2, to_pos: Vector2, label: String) -> void:
	var plan := nav.call("build_policy_valid_path", from_pos, to_pos, null) as Dictionary
	var status := String(plan.get("status", ""))
	var reason := String(plan.get("reason", ""))
	var route_source := String(plan.get("route_source", ""))
	var route_reason := String(plan.get("route_source_reason", ""))
	var pts := plan.get("path_points", []) as Array
	var intersects := false
	if nav.has_method("path_intersects_navigation_obstacles"):
		intersects = bool(nav.call("path_intersects_navigation_obstacles", from_pos, pts))
	print("PLAN|%s|status=%s|reason=%s|route_source=%s|route_reason=%s|pts=%d|len=%.2f|intersects=%s|obst_inter=%s" % [
		label,
		status,
		reason,
		route_source,
		route_reason,
		pts.size(),
		_path_len(from_pos, pts),
		str(intersects),
		str(bool(plan.get("obstacle_intersection_detected", false)))
	])

func _ready() -> void:
	var level := LEVEL_SCENE.instantiate() as Node
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	var nav := level.get_node_or_null("Systems/NavigationService")
	if nav == null:
		print("ERR|nav_missing")
		get_tree().quit(2)
		return

	var map_rid: RID = nav.call("get_navigation_map_rid") as RID
	var map_iteration := NavigationServer2D.map_get_iteration_id(map_rid) if map_rid.is_valid() else -1

	print("NAV|build_valid=%s|obst_source=%s" % [
		str(bool(nav.call("is_navigation_build_valid"))),
		String(nav.call("debug_get_nav_obstacle_source"))
	])
	print("NAVMAP|rid_valid=%s|iteration=%d" % [str(map_rid.is_valid()), map_iteration])

	var probe_points := [
		{"label": "around_shadowC1_horizontal", "from": Vector2(900.0, 700.0), "to": Vector2(1100.0, 700.0)},
		{"label": "around_shadowC1_diag", "from": Vector2(850.0, 650.0), "to": Vector2(1150.0, 850.0)},
		{"label": "B_to_C1", "from": Vector2(400.0, 820.0), "to": Vector2(1300.0, 780.0)},
		{"label": "A2_to_C1", "from": Vector2(960.0, 240.0), "to": Vector2(1300.0, 780.0)},
		{"label": "C1_to_D", "from": Vector2(1300.0, 780.0), "to": Vector2(1910.0, 400.0)},
		{"label": "to_outside_navmesh", "from": Vector2(1300.0, 780.0), "to": Vector2(2500.0, 1400.0)},
	]

	for row_var in probe_points:
		var row := row_var as Dictionary
		_print_plan(nav, row.get("from", Vector2.ZERO) as Vector2, row.get("to", Vector2.ZERO) as Vector2, String(row.get("label", "")))

	var center := Vector2(1000.0, 700.0)
	var offsets := [Vector2.ZERO, Vector2(20,0), Vector2(-20,0), Vector2(0,20), Vector2(0,-20), Vector2(40,40)]
	for off_var in offsets:
		var off := off_var as Vector2
		var p := center + off
		var on_nav := bool(nav.call("is_point_on_navigation_map", p, 4.0))
		var closest := NavigationServer2D.map_get_closest_point(map_rid, p) if map_rid.is_valid() else Vector2.ZERO
		var d := p.distance_to(closest)
		print("POINT|p=%s|on_nav=%s|closest=%s|dist=%.3f" % [str(p), str(on_nav), str(closest), d])

	var layout: Variant = nav.get("layout")
	if layout != null and layout.has_method("_navigation_obstacles"):
		var obstacles: Array = layout.call("_navigation_obstacles") as Array
		for i in range(obstacles.size()):
			var obs: Rect2 = obstacles[i] as Rect2
			var c: Vector2 = obs.get_center()
			var closest_obs: Vector2 = NavigationServer2D.map_get_closest_point(map_rid, c) if map_rid.is_valid() else Vector2.ZERO
			print("OBS|idx=%d|center=%s|closest=%s|dist=%.3f" % [i, str(c), str(closest_obs), c.distance_to(closest_obs)])

	var room_to_region_var: Variant = nav.get("_room_to_region")
	if room_to_region_var is Dictionary:
		var room_to_region: Dictionary = room_to_region_var as Dictionary
		if room_to_region.has(3):
			var region := room_to_region.get(3, null) as NavigationRegion2D
			if region != null and region.navigation_polygon != null:
				var poly := region.navigation_polygon
				print("ROOMC|outline_count=%d|polygon_count=%d" % [poly.get_outline_count(), poly.get_polygon_count()])
				var center_c1 := Vector2(1000.0, 700.0)
				for i in range(poly.get_outline_count()):
					var outline: PackedVector2Array = poly.get_outline(i)
					var inside := Geometry2D.is_point_in_polygon(center_c1, outline)
					print("ROOMC_OUTLINE|idx=%d|pts=%d|contains_center=%s" % [i, outline.size(), str(inside)])
					if i == 0:
						for j in range(outline.size()):
							print("ROOMC_OUTLINE0_PT|%d|%s" % [j, str(outline[j])])

	var raw_cases := [
		{"label": "raw_horizontal", "from": Vector2(900.0, 700.0), "to": Vector2(1100.0, 700.0)},
		{"label": "raw_diag", "from": Vector2(850.0, 650.0), "to": Vector2(1150.0, 850.0)},
		{"label": "raw_to_outside", "from": Vector2(1300.0, 780.0), "to": Vector2(2500.0, 1400.0)},
	]
	for case_var in raw_cases:
		var case := case_var as Dictionary
		if not map_rid.is_valid():
			print("RAW|%s|rid_invalid" % String(case.get("label", "")))
			continue
		var raw_path: PackedVector2Array = NavigationServer2D.map_get_path(
			map_rid,
			case.get("from", Vector2.ZERO) as Vector2,
			case.get("to", Vector2.ZERO) as Vector2,
			true
		)
		print("RAW|%s|pts=%d" % [String(case.get("label", "")), raw_path.size()])
		for i in range(raw_path.size()):
			print("RAWPT|%s|%d|%s" % [String(case.get("label", "")), i, str(raw_path[i])])

	var enemies := get_tree().get_nodes_in_group("enemies")
	if not enemies.is_empty():
		var enemy := enemies[0] as Node
		if enemy != null and enemy.has_method("debug_get_pursuit_system_for_test"):
			var pursuit = enemy.call("debug_get_pursuit_system_for_test")
			if pursuit != null:
				var target_outside := Vector2(2500.0, 1400.0)
				var owner := pursuit.get("owner") as CharacterBody2D
				var prev_process := enemy.is_physics_processing()
				enemy.set_physics_process(false)
				owner.global_position = Vector2(1300.0, 780.0)
				owner.velocity = Vector2.ZERO
				await get_tree().physics_frame
				var moved_total := 0.0
				var start_pos := owner.global_position
				var prev_pos := owner.global_position
				for _i in range(120):
					pursuit.call(
						"execute_intent",
						1.0 / 60.0,
						{"type": 3, "target": target_outside}, # MOVE_TO_SLOT
						{
							"player_pos": target_outside,
							"known_target_pos": Vector2.ZERO,
							"last_seen_pos": Vector2.ZERO,
							"investigate_anchor": Vector2.ZERO,
							"home_position": Vector2.ZERO,
							"alert_level": 0,
							"los": false,
							"combat_lock": false,
						}
					)
					await get_tree().physics_frame
					var cur := owner.global_position
					moved_total += cur.distance_to(prev_pos)
					prev_pos = cur
				enemy.set_physics_process(prev_process)
				var snap := pursuit.call("debug_get_navigation_policy_snapshot") as Dictionary
				print("OUTSIDE_EXEC|start=%s|end=%s|moved=%.2f|dist_to_target=%.2f|plan_status=%s|plan_reason=%s|path_failed_reason=%s|hard_stall=%s" % [
					str(start_pos),
					str(owner.global_position),
					moved_total,
					owner.global_position.distance_to(target_outside),
					String(snap.get("path_plan_status", "")),
					String(snap.get("path_plan_reason", "")),
					String(snap.get("path_failed_reason", "")),
					str(bool(snap.get("hard_stall", false)))
				])

	level.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
