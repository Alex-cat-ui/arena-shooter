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
		# Dark pocket around room center + left side band; deterministic enough for builder samples.
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
	print("DARK SEARCH GRAPH PROGRESSIVE COVERAGE TEST")
	print("============================================================")

	await _test_room_dark_search_coverage_monotonic_non_decreasing()
	await _test_select_next_dark_node_prefers_uncovered_then_shorter_policy_path()
	await _test_tie_break_same_score_resolves_by_lexical_node_key()
	await _test_boundary_only_room_builds_nodes_and_completes_by_coverage()

	_t.summary("DARK SEARCH GRAPH PROGRESSIVE COVERAGE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _spawn_enemy(world: Node2D, nav: FakeNav, pos: Vector2 = Vector2.ZERO) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = pos
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(16101, "zombie")
	enemy.set_room_navigation(nav, nav.room_id_at_point(pos))
	enemy.debug_force_awareness_state("COMBAT")
	enemy.set_process(false)
	enemy.set_physics_process(false)
	return enemy


func _install_fake_stage_pursuit(enemy: Enemy, stage: int = 0) -> FakeStagePursuit:
	var fake := FakeStagePursuit.new()
	fake.stage = stage
	enemy.set("_pursuit", fake)
	return fake


func _advance_active_node_to_searchable(enemy: Enemy, fake_pursuit: FakeStagePursuit, target_hint: Vector2) -> void:
	if String(enemy.get("_combat_search_current_node_key")) == "":
		enemy.call("_update_combat_search_runtime", 0.1, false, target_hint, true)
	if not bool(enemy.get("_combat_search_current_node_requires_shadow_scan")):
		return
	if bool(enemy.get("_combat_search_current_node_shadow_scan_done")):
		return
	fake_pursuit.stage = 2
	enemy.call("_update_combat_search_runtime", 0.1, false, target_hint, true)
	fake_pursuit.stage = 0
	enemy.call("_update_combat_search_runtime", 0.1, false, target_hint, true)


func _complete_active_node_with_search(enemy: Enemy, target_hint: Vector2) -> void:
	var active_key := String(enemy.get("_combat_search_current_node_key"))
	if active_key == "":
		return
	var safety := 0
	while safety < 8 and String(enemy.get("_combat_search_current_node_key")) == active_key:
		safety += 1
		var target := enemy.get("_combat_search_target_pos") as Vector2
		enemy.call("_record_combat_search_execution_feedback", {
			"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH,
			"target": target,
		}, 0.5)
		enemy.call("_update_combat_search_runtime", 0.1, false, target_hint, true)


func _test_room_dark_search_coverage_monotonic_non_decreasing() -> void:
	var world := Node2D.new()
	add_child(world)
	var nav := FakeNav.new()
	world.add_child(nav)
	var enemy := await _spawn_enemy(world, nav, Vector2(0.0, 0.0))
	var fake_pursuit := _install_fake_stage_pursuit(enemy)
	var combat_target := Vector2(40.0, 0.0)

	enemy.call("_update_combat_search_runtime", 0.1, false, combat_target, true)
	enemy.set("_combat_search_room_budget_sec", 999.0)

	var have_active_room_samples := 0
	var monotonic_room_coverage := true
	var monotonic_progress := true
	var prev_room := int(enemy.get_debug_detection_snapshot().get("combat_search_current_room_id", -1))
	var prev_cov := float(enemy.get_debug_detection_snapshot().get("combat_search_room_coverage_raw", 0.0))
	var prev_progress := float(enemy.get_debug_detection_snapshot().get("combat_search_progress", 0.0))

	for _i in range(16):
		enemy.set("_combat_search_room_budget_sec", 999.0)
		_advance_active_node_to_searchable(enemy, fake_pursuit, combat_target)
		_complete_active_node_with_search(enemy, combat_target)
		var snap := enemy.get_debug_detection_snapshot() as Dictionary
		var room_id := int(snap.get("combat_search_current_room_id", -1))
		var coverage_raw := float(snap.get("combat_search_room_coverage_raw", 0.0))
		var progress := float(snap.get("combat_search_progress", 0.0))
		if room_id == prev_room and not bool(snap.get("combat_search_total_cap_hit", false)):
			have_active_room_samples += 1
			if coverage_raw + 0.0001 < prev_cov:
				monotonic_room_coverage = false
			if progress + 0.0001 < prev_progress:
				monotonic_progress = false
		prev_room = room_id
		prev_cov = coverage_raw
		prev_progress = progress

	_t.run_test("room coverage raw is non-decreasing inside active room windows", monotonic_room_coverage)
	_t.run_test("combat_search_progress is non-decreasing inside active room windows", monotonic_progress)
	_t.run_test("monotonic test collected same-room samples", have_active_room_samples >= 3)

	world.queue_free()
	await get_tree().process_frame


func _test_select_next_dark_node_prefers_uncovered_then_shorter_policy_path() -> void:
	var world := Node2D.new()
	add_child(world)
	var nav := FakeNav.new()
	world.add_child(nav)
	var enemy := await _spawn_enemy(world, nav, Vector2.ZERO)
	_install_fake_stage_pursuit(enemy)
	nav.path_length_overrides = {
		nav._path_key(Vector2(80.0, 0.0)): 300.0,
		nav._path_key(Vector2(40.0, 0.0)): 10.0,
	}
	enemy.set("_combat_search_room_nodes", {
		5: [
			{
				"key": "r5:dark:0",
				"kind": "dark_pocket",
				"target_pos": Vector2(64.0, 0.0),
				"approach_pos": Vector2(80.0, 0.0),
				"target_in_shadow": true,
				"requires_shadow_boundary_scan": true,
				"coverage_weight": 1.0,
			},
			{
				"key": "r5:boundary:0",
				"kind": "boundary_point",
				"target_pos": Vector2(32.0, 0.0),
				"approach_pos": Vector2(40.0, 0.0),
				"target_in_shadow": false,
				"requires_shadow_boundary_scan": false,
				"coverage_weight": 0.5,
			},
		],
	})
	enemy.set("_combat_search_room_node_visited", {5: {}})

	var first_pick := enemy.call("_select_next_combat_dark_search_node", 5, Vector2(100.0, 0.0)) as Dictionary
	var visited: Dictionary = {String(first_pick.get("node_key", "")): true}
	enemy.set("_combat_search_room_node_visited", {5: visited})
	var second_pick := enemy.call("_select_next_combat_dark_search_node", 5, Vector2(100.0, 0.0)) as Dictionary

	_t.run_test(
		"selector prefers higher uncovered score (dark pocket) over shorter path boundary node",
		String(first_pick.get("node_key", "")) == "r5:dark:0" and String(first_pick.get("status", "")) == "ok"
	)
	_t.run_test(
		"selector picks remaining unvisited node after first is marked visited",
		String(second_pick.get("node_key", "")) == "r5:boundary:0" and String(second_pick.get("status", "")) == "ok"
	)

	world.queue_free()
	await get_tree().process_frame


func _test_tie_break_same_score_resolves_by_lexical_node_key() -> void:
	var world := Node2D.new()
	add_child(world)
	var nav := FakeNav.new()
	world.add_child(nav)
	var enemy := await _spawn_enemy(world, nav, Vector2.ZERO)
	_install_fake_stage_pursuit(enemy)
	enemy.set("_combat_search_room_nodes", {
		5: [
			{
				"key": "r5:boundary:2",
				"kind": "boundary_point",
				"target_pos": Vector2(96.0, 0.0),
				"approach_pos": Vector2(96.0, 0.0),
				"target_in_shadow": false,
				"requires_shadow_boundary_scan": false,
				"coverage_weight": 0.5,
			},
			{
				"key": "r5:boundary:1",
				"kind": "boundary_point",
				"target_pos": Vector2(-96.0, 0.0),
				"approach_pos": Vector2(-96.0, 0.0),
				"target_in_shadow": false,
				"requires_shadow_boundary_scan": false,
				"coverage_weight": 0.5,
			},
		],
	})
	enemy.set("_combat_search_room_node_visited", {5: {}})
	var pick := enemy.call("_select_next_combat_dark_search_node", 5, Vector2(100.0, 0.0)) as Dictionary
	_t.run_test(
		"equal-score tie resolves by lexical node_key ascending",
		String(pick.get("node_key", "")) == "r5:boundary:1" and int(pick.get("score_tactical_priority", -1)) == 1
	)

	world.queue_free()
	await get_tree().process_frame


func _test_boundary_only_room_builds_nodes_and_completes_by_coverage() -> void:
	var world := Node2D.new()
	add_child(world)
	var nav := FakeNav.new()
	nav.force_no_shadow = true
	world.add_child(nav)
	var enemy := await _spawn_enemy(world, nav, Vector2(0.0, 0.0))
	var fake_pursuit := _install_fake_stage_pursuit(enemy)
	var combat_target := Vector2(60.0, 0.0)

	var built_nodes := enemy.call("_build_combat_dark_search_nodes", 0, combat_target) as Array
	var boundary_only := not built_nodes.is_empty()
	for node_variant in built_nodes:
		var node := node_variant as Dictionary
		if String(node.get("kind", "")) != "boundary_point":
			boundary_only = false
			break

	enemy.call("_update_combat_search_runtime", 0.1, false, combat_target, true)
	enemy.set("_combat_search_room_budget_sec", 999.0)
	var coverage_reached := false
	for _i in range(40):
		enemy.set("_combat_search_room_budget_sec", 999.0)
		_advance_active_node_to_searchable(enemy, fake_pursuit, combat_target)
		_complete_active_node_with_search(enemy, combat_target)
		var snap := enemy.get_debug_detection_snapshot() as Dictionary
		var coverage_raw := float(snap.get("combat_search_room_coverage_raw", 0.0))
		if coverage_raw >= 0.8:
			coverage_reached = true
			break

	var room_visited := bool((enemy.get("_combat_search_visited_rooms") as Dictionary).get(0, false))
	var current_room := int(enemy.get_debug_detection_snapshot().get("combat_search_current_room_id", -1))
	_t.run_test("boundary-only room builder emits only boundary nodes", boundary_only)
	_t.run_test("boundary-only room reaches >= 0.8 coverage", coverage_reached)
	_t.run_test("boundary-only room completes by coverage and advances/marks visited", room_visited or current_room != 0)

	world.queue_free()
	await get_tree().process_frame
