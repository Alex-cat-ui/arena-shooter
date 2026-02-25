extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LEVEL_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")

var embedded_mode: bool = false
var _t := TestHelpers.new()


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("STEALTH NAV POLYGON HOLE INTEGRITY TEST")
	print("============================================================")

	await _test_obstacle_centers_are_not_walkable_after_bake()

	_t.summary("STEALTH NAV POLYGON HOLE INTEGRITY RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_obstacle_centers_are_not_walkable_after_bake() -> void:
	var level := LEVEL_SCENE.instantiate() as Node
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	var nav := level.get_node_or_null("Systems/NavigationService")
	_t.run_test("hole integrity: navigation service exists", nav != null)
	if nav == null:
		level.queue_free()
		await get_tree().process_frame
		return

	# Allow deferred integrity validation to run when nav map iteration becomes available.
	await get_tree().process_frame
	await get_tree().physics_frame

	var layout = nav.get("layout")
	var obstacles: Array = []
	if layout != null and layout is Object and layout.has_method("_navigation_obstacles"):
		obstacles = layout.call("_navigation_obstacles") as Array

	_t.run_test("hole integrity: obstacle source is non-empty", not obstacles.is_empty())
	_t.run_test("hole integrity: navigation build remains valid", bool(nav.call("is_navigation_build_valid")))
	if obstacles.is_empty():
		level.queue_free()
		await get_tree().process_frame
		return

	var centers_blocked := true
	for obstacle_variant in obstacles:
		var obstacle := obstacle_variant as Rect2
		if obstacle == Rect2():
			continue
		var center := obstacle.get_center()
		if bool(nav.call("is_point_on_navigation_map", center, 4.0)):
			centers_blocked = false
			break

	_t.run_test("hole integrity: every obstacle center is non-walkable", centers_blocked)

	level.queue_free()
	await get_tree().process_frame
