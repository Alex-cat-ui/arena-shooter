extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeStagePursuit:
	extends RefCounted

	var stage: int = 0

	func get_shadow_search_stage() -> int:
		return stage


class FakeNav:
	extends Node

	var room_centers := {
		0: Vector2(0.0, 0.0),
		1: Vector2(220.0, 0.0),
	}
	var room_rects := {
		0: Rect2(Vector2(-96.0, -96.0), Vector2(192.0, 192.0)),
		1: Rect2(Vector2(124.0, -96.0), Vector2(192.0, 192.0)),
	}
	var neighbors := {
		0: [1],
		1: [0],
	}
	var force_no_shadow: bool = false
	var path_length_overrides: Dictionary = {}

	func room_id_at_point(point: Vector2) -> int:
		return 0 if point.x < 110.0 else 1

	func get_neighbors(room_id: int) -> Array:
		return neighbors.get(room_id, [])

	func get_room_center(room_id: int) -> Vector2:
		return room_centers.get(room_id, Vector2.ZERO)

	func get_room_rect(room_id: int) -> Rect2:
		return room_rects.get(room_id, Rect2())

	func is_point_in_shadow(point: Vector2) -> bool:
		if force_no_shadow:
			return false
		var room_id := room_id_at_point(point)
		var center := get_room_center(room_id)
		return point.distance_to(center) <= 18.0 or point.x <= center.x - 40.0

	func get_nearest_non_shadow_point(target: Vector2, radius_px: float) -> Vector2:
		return Vector2(target.x + minf(radius_px, 32.0), target.y)

	func nav_path_length(from_pos: Vector2, to_pos: Vector2, _enemy: Node = null) -> float:
		var key := _path_key(to_pos)
		if path_length_overrides.has(key):
			return float(path_length_overrides[key])
		return from_pos.distance_to(to_pos)

	func _path_key(pos: Vector2) -> String:
		return "%d:%d" % [int(round(pos.x)), int(round(pos.y))]


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ENEMY COMBAT SEARCH RUNTIME UNIT TEST")
	print("============================================================")

	await _test_next_room_scoring_prefers_unvisited_and_stable_tie_break()
	await _test_progress_is_monotonic_within_active_room_windows()
	await _test_total_cap_forces_progress_threshold()

	_t.summary("ENEMY COMBAT SEARCH RUNTIME UNIT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _spawn_enemy(world: Node2D, nav: FakeNav, pos: Vector2 = Vector2.ZERO) -> Dictionary:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = pos
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(56011, "zombie")
	enemy.set_room_navigation(nav, nav.room_id_at_point(pos))
	enemy.debug_force_awareness_state("COMBAT")
	enemy.set_process(false)
	enemy.set_physics_process(false)
	var runtime: Variant = (enemy.get_runtime_helper_refs() as Dictionary).get("combat_search_runtime", null)
	return {"enemy": enemy, "runtime": runtime}


func _install_fake_stage_pursuit(runtime, stage: int = 0) -> FakeStagePursuit:
	var fake := FakeStagePursuit.new()
	fake.stage = stage
	if runtime != null:
		runtime.call("set_state_value", "_pursuit", fake)
	return fake


func _advance_and_complete_active_node(runtime, fake_pursuit: FakeStagePursuit, target_hint: Vector2) -> void:
	if runtime == null:
		return
	if String(runtime.call("get_state_value", "_combat_search_current_node_key", "")) == "":
		runtime.call("update_runtime", 0.1, false, target_hint, true)
	if (
		bool(runtime.call("get_state_value", "_combat_search_current_node_requires_shadow_scan", false))
		and not bool(runtime.call("get_state_value", "_combat_search_current_node_shadow_scan_done", false))
	):
		fake_pursuit.stage = 2
		runtime.call("update_runtime", 0.1, false, target_hint, true)
		fake_pursuit.stage = 0
		runtime.call("update_runtime", 0.1, false, target_hint, true)
	var active_key := String(runtime.call("get_state_value", "_combat_search_current_node_key", ""))
	if active_key == "":
		return
	var safety := 0
	while safety < 8 and String(runtime.call("get_state_value", "_combat_search_current_node_key", "")) == active_key:
		safety += 1
		var target := runtime.call("get_state_value", "_combat_search_target_pos", Vector2.ZERO) as Vector2
		runtime.call("record_execution_feedback", {
			"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH,
			"target": target,
		}, 0.5)
		runtime.call("update_runtime", 0.1, false, target_hint, true)


func _test_next_room_scoring_prefers_unvisited_and_stable_tie_break() -> void:
	var world := Node2D.new()
	add_child(world)
	var nav := FakeNav.new()
	world.add_child(nav)
	var refs: Dictionary = await _spawn_enemy(world, nav, Vector2.ZERO)
	var runtime: Variant = refs.get("runtime", null)

	_t.run_test("combat-search runtime is available", runtime != null)
	if runtime == null:
		world.queue_free()
		await get_tree().process_frame
		return

	nav.neighbors = {10: [11, 12, 13], 11: [10], 12: [10], 13: [10]}
	nav.room_centers = {
		10: Vector2(0.0, 0.0),
		11: Vector2(120.0, 0.0),
		12: Vector2(170.0, 0.0),
		13: Vector2(90.0, 0.0),
	}
	runtime.call("set_state_value", "_combat_search_visited_rooms", {13: true})
	var first_pick := int(runtime.call("select_next_room", 10, Vector2(100.0, 0.0)))

	runtime.call("set_state_value", "_combat_search_visited_rooms", {13: true, 11: true})
	var second_pick := int(runtime.call("select_next_room", 10, Vector2(100.0, 0.0)))

	nav.neighbors = {20: [21, 22], 21: [20], 22: [20]}
	nav.room_centers = {
		20: Vector2.ZERO,
		21: Vector2(100.0, 0.0),
		22: Vector2(100.0, 0.0),
	}
	runtime.call("set_state_value", "_combat_search_visited_rooms", {})
	var tie_pick := int(runtime.call("select_next_room", 20, Vector2(100.0, 0.0)))

	_t.run_test("visited-room penalty avoids immediate loop", first_pick == 11)
	_t.run_test("next unvisited room chosen after first is marked visited", second_pick == 12)
	_t.run_test("equal score tie uses smallest room_id", tie_pick == 21)

	world.queue_free()
	await get_tree().process_frame


func _test_progress_is_monotonic_within_active_room_windows() -> void:
	var world := Node2D.new()
	add_child(world)
	var nav := FakeNav.new()
	world.add_child(nav)
	var refs: Dictionary = await _spawn_enemy(world, nav, Vector2.ZERO)
	var enemy := refs.get("enemy", null) as Enemy
	var runtime: Variant = refs.get("runtime", null)

	_t.run_test("runtime available for progress monotonicity test", runtime != null)
	if runtime == null or enemy == null:
		world.queue_free()
		await get_tree().process_frame
		return

	var fake_pursuit := _install_fake_stage_pursuit(runtime)
	var combat_target := Vector2(48.0, 0.0)
	runtime.call("update_runtime", 0.1, false, combat_target, true)
	runtime.call("set_state_value", "_combat_search_room_budget_sec", 999.0)

	var samples := 0
	var coverage_monotonic := true
	var progress_monotonic := true
	var prev_room := int(enemy.get_debug_detection_snapshot().get("combat_search_current_room_id", -1))
	var prev_cov := float(enemy.get_debug_detection_snapshot().get("combat_search_room_coverage_raw", 0.0))
	var prev_progress := float(enemy.get_debug_detection_snapshot().get("combat_search_progress", 0.0))

	for _i in range(16):
		runtime.call("set_state_value", "_combat_search_room_budget_sec", 999.0)
		_advance_and_complete_active_node(runtime, fake_pursuit, combat_target)
		var snap := enemy.get_debug_detection_snapshot() as Dictionary
		var room_id := int(snap.get("combat_search_current_room_id", -1))
		var coverage_raw := float(snap.get("combat_search_room_coverage_raw", 0.0))
		var progress := float(snap.get("combat_search_progress", 0.0))
		if room_id == prev_room and not bool(snap.get("combat_search_total_cap_hit", false)):
			samples += 1
			if coverage_raw + 0.0001 < prev_cov:
				coverage_monotonic = false
			if progress + 0.0001 < prev_progress:
				progress_monotonic = false
		prev_room = room_id
		prev_cov = coverage_raw
		prev_progress = progress

	_t.run_test("room coverage is monotonic inside active-room windows", coverage_monotonic)
	_t.run_test("search progress is monotonic inside active-room windows", progress_monotonic)
	_t.run_test("monotonic checks collected same-room samples", samples >= 3)

	world.queue_free()
	await get_tree().process_frame


func _test_total_cap_forces_progress_threshold() -> void:
	var world := Node2D.new()
	add_child(world)
	var nav := FakeNav.new()
	world.add_child(nav)
	var refs: Dictionary = await _spawn_enemy(world, nav, Vector2.ZERO)
	var enemy := refs.get("enemy", null) as Enemy
	var runtime: Variant = refs.get("runtime", null)

	_t.run_test("runtime available for total-cap test", runtime != null)
	if runtime == null or enemy == null:
		world.queue_free()
		await get_tree().process_frame
		return

	var target := Vector2(64.0, 0.0)
	for _i in range(26):
		runtime.call("update_runtime", 1.0, false, target, true)

	var snap := enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test("total cap raises combat_search_total_cap_hit", bool(snap.get("combat_search_total_cap_hit", false)))
	_t.run_test("total cap clamps progress to 0.8 threshold", absf(float(snap.get("combat_search_progress", 0.0)) - 0.8) <= 0.0001)

	world.queue_free()
	await get_tree().process_frame
