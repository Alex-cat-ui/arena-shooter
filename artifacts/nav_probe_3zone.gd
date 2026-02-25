extends SceneTree

const LEVEL_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")

func _init() -> void:
	call_deferred("_run")

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

func _run() -> void:
	var level := LEVEL_SCENE.instantiate() as Node
	root.add_child(level)
	await process_frame
	await physics_frame
	await process_frame

	var nav := level.get_node_or_null("Systems/NavigationService")
	if nav == null:
		print("ERR|nav_missing")
		quit(2)
		return

	print("NAV|build_valid=%s|obst_source=%s" % [
		str(bool(nav.call("is_navigation_build_valid"))),
		String(nav.call("debug_get_nav_obstacle_source"))
	])

	var probe_points := [
		{"label": "around_shadowC1_horizontal", "from": Vector2(900.0, 700.0), "to": Vector2(1100.0, 700.0)},
		{"label": "around_shadowC1_diag", "from": Vector2(850.0, 650.0), "to": Vector2(1150.0, 850.0)},
		{"label": "B_to_C1", "from": Vector2(400.0, 820.0), "to": Vector2(1300.0, 780.0)},
		{"label": "A2_to_C1", "from": Vector2(960.0, 240.0), "to": Vector2(1300.0, 780.0)},
		{"label": "C1_to_D", "from": Vector2(1300.0, 780.0), "to": Vector2(1910.0, 400.0)},
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
		print("POINT|p=%s|on_nav=%s" % [str(p), str(on_nav)])

	level.queue_free()
	await process_frame
	quit(0)
