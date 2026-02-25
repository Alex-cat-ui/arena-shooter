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
		if nav.has_method("path_intersects_navigation_obstacles"):
			if bool(nav.call("path_intersects_navigation_obstacles", from_pos, path_points)):
				no_intersections = false

	_t.run_test("segments avoid props: spawn chain plans are ok", contract_ok)
	_t.run_test("segments avoid props: path segments do not intersect props", no_intersections)

	level.queue_free()
	await get_tree().process_frame
