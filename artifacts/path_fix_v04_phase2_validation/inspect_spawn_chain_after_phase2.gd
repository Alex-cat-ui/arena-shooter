extends Node

const LEVEL_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")
const ORDER := ["SpawnA1", "SpawnA2", "SpawnB", "SpawnC1", "SpawnC2", "SpawnD"]

func _ready() -> void:
	var level := LEVEL_SCENE.instantiate() as Node
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	var nav := level.get_node_or_null("Systems/NavigationService")
	var spawns_root := level.get_node_or_null("Spawns")
	if nav == null or spawns_root == null:
		print("ERR|missing_nav_or_spawns")
		get_tree().quit(2)
		return
	var spawn_map: Dictionary = {}
	for child_variant in spawns_root.get_children():
		var child := child_variant as Node2D
		if child != null:
			spawn_map[child.name] = child.global_position
	for i in range(ORDER.size() - 1):
		var a := ORDER[i]
		var b := ORDER[i + 1]
		var from_pos := spawn_map.get(a, Vector2.ZERO) as Vector2
		var to_pos := spawn_map.get(b, Vector2.ZERO) as Vector2
		var plan := nav.call("build_policy_valid_path", from_pos, to_pos, null) as Dictionary
		print("CHAIN|%s->%s|status=%s|reason=%s|route_source=%s|pts=%d|inter=%s|obs_inter=%s" % [
			a,
			b,
			String(plan.get("status", "")),
			String(plan.get("reason", "")),
			String(plan.get("route_source", "")),
			(plan.get("path_points", []) as Array).size(),
			str(bool(nav.call("path_intersects_navigation_obstacles", from_pos, plan.get("path_points", []) as Array))),
			str(bool(plan.get("obstacle_intersection_detected", false)))
		])
	level.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
