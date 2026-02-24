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
		0: Vector2(32.0, 0.0),
		1: Vector2(232.0, 0.0),
	}
	var room_rects := {
		0: Rect2(Vector2(-64.0, -96.0), Vector2(192.0, 192.0)),
		1: Rect2(Vector2(136.0, -96.0), Vector2(192.0, 192.0)),
	}
	var neighbors := {
		0: [1],
		1: [0],
	}
	var force_no_shadow: bool = false

	func room_id_at_point(point: Vector2) -> int:
		return 0 if point.x < 100.0 else 1

	func get_neighbors(room_id: int) -> Array:
		return neighbors.get(room_id, [])

	func get_room_center(room_id: int) -> Vector2:
		return room_centers.get(room_id, Vector2.ZERO)

	func get_room_rect(room_id: int) -> Rect2:
		return room_rects.get(room_id, Rect2())

	func is_point_in_shadow(point: Vector2) -> bool:
		if force_no_shadow:
			return false
		var center := get_room_center(room_id_at_point(point))
		return point.distance_to(center) <= 18.0

	func get_nearest_non_shadow_point(target: Vector2, radius_px: float) -> Vector2:
		return Vector2(target.x + minf(radius_px, 32.0), target.y)

	func nav_path_length(from_pos: Vector2, to_pos: Vector2, _enemy: Node = null) -> float:
		return from_pos.distance_to(to_pos)


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ALERT/COMBAT SEARCH SESSION COMPLETION CONTRACT TEST")
	print("============================================================")

	await _test_session_stays_active_while_coverage_below_threshold_and_budget_open()
	await _test_room_completion_advances_to_next_room_or_marks_room_visited()
	await _test_total_cap_forces_progress_threshold_and_cap_flag()
	await _test_confirm_runtime_config_keeps_awareness_field_names()

	_t.summary("ALERT/COMBAT SEARCH SESSION COMPLETION CONTRACT RESULTS")
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
	enemy.initialize(16201, "zombie")
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


func _advance_scan_if_needed(enemy: Enemy, fake_pursuit: FakeStagePursuit, target_hint: Vector2) -> void:
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


func _complete_one_node(enemy: Enemy, fake_pursuit: FakeStagePursuit, target_hint: Vector2) -> void:
	_advance_scan_if_needed(enemy, fake_pursuit, target_hint)
	var active_key := String(enemy.get("_combat_search_current_node_key"))
	if active_key == "":
		return
	for _i in range(6):
		if String(enemy.get("_combat_search_current_node_key")) != active_key:
			break
		var target := enemy.get("_combat_search_target_pos") as Vector2
		enemy.call("_record_combat_search_execution_feedback", {
			"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH,
			"target": target,
		}, 0.5)
		enemy.call("_update_combat_search_runtime", 0.1, false, target_hint, true)


func _test_session_stays_active_while_coverage_below_threshold_and_budget_open() -> void:
	var world := Node2D.new()
	add_child(world)
	var nav := FakeNav.new()
	world.add_child(nav)
	var enemy := await _spawn_enemy(world, nav)
	var fake_pursuit := _install_fake_stage_pursuit(enemy)
	var target := Vector2(48.0, 0.0)

	enemy.call("_update_combat_search_runtime", 0.1, false, target, true)
	enemy.set("_combat_search_room_budget_sec", 999.0)
	var start_snap := enemy.get_debug_detection_snapshot() as Dictionary
	var start_room := int(start_snap.get("combat_search_current_room_id", -1))
	var start_target := start_snap.get("combat_search_target_pos", Vector2.ZERO) as Vector2

	for _i in range(6):
		enemy.set("_combat_search_room_budget_sec", 999.0)
		_advance_scan_if_needed(enemy, fake_pursuit, target)
		enemy.call("_update_combat_search_runtime", 0.25, false, target, true)

	var snap := enemy.get_debug_detection_snapshot() as Dictionary
	var same_room := int(snap.get("combat_search_current_room_id", -1)) == start_room
	var target_alive := (snap.get("combat_search_target_pos", Vector2.ZERO) as Vector2) != Vector2.ZERO and start_target != Vector2.ZERO
	var coverage_below := float(snap.get("combat_search_room_coverage_raw", 0.0)) < 0.8
	var budget_open := float(snap.get("combat_search_room_elapsed_sec", 0.0)) < float(snap.get("combat_search_room_budget_sec", 0.0))

	_t.run_test("session stays in same room while coverage < threshold and budget open", same_room)
	_t.run_test("session keeps active combat_search_target_pos while active", target_alive)
	_t.run_test("setup guard: coverage still below threshold before completion test", coverage_below and budget_open)

	world.queue_free()
	await get_tree().process_frame


func _test_room_completion_advances_to_next_room_or_marks_room_visited() -> void:
	var world := Node2D.new()
	add_child(world)
	var nav := FakeNav.new()
	nav.force_no_shadow = true
	world.add_child(nav)
	var enemy := await _spawn_enemy(world, nav)
	var fake_pursuit := _install_fake_stage_pursuit(enemy)
	var target := Vector2(60.0, 0.0)

	enemy.call("_update_combat_search_runtime", 0.1, false, target, true)
	enemy.set("_combat_search_room_budget_sec", 999.0)
	var start_room := int(enemy.get_debug_detection_snapshot().get("combat_search_current_room_id", -1))

	var safety := 0
	while safety < 48:
		safety += 1
		enemy.set("_combat_search_room_budget_sec", 999.0)
		_complete_one_node(enemy, fake_pursuit, target)
		var snap := enemy.get_debug_detection_snapshot() as Dictionary
		var room_id := int(snap.get("combat_search_current_room_id", -1))
		var visited := enemy.get("_combat_search_visited_rooms") as Dictionary
		if room_id != start_room or bool(visited.get(start_room, false)):
			break

	var end_snap := enemy.get_debug_detection_snapshot() as Dictionary
	var end_room := int(end_snap.get("combat_search_current_room_id", -1))
	var visited_rooms := enemy.get("_combat_search_visited_rooms") as Dictionary
	var start_room_visited := bool(visited_rooms.get(start_room, false))
	var advanced_or_reinitialized := end_room != -1 and (end_room != start_room or start_room_visited)

	_t.run_test("room completion marks current room visited", start_room_visited)
	_t.run_test("room completion advances to next room or reinitializes active room session", advanced_or_reinitialized)

	world.queue_free()
	await get_tree().process_frame


func _test_total_cap_forces_progress_threshold_and_cap_flag() -> void:
	var world := Node2D.new()
	add_child(world)
	var nav := FakeNav.new()
	world.add_child(nav)
	var enemy := await _spawn_enemy(world, nav)
	_install_fake_stage_pursuit(enemy)
	var target := Vector2(64.0, 0.0)

	for _i in range(26):
		enemy.call("_update_combat_search_runtime", 1.0, false, target, true)

	var snap := enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test("total cap raises combat_search_total_cap_hit", bool(snap.get("combat_search_total_cap_hit", false)))
	_t.run_test(
		"total cap clamps progress to 0.8 threshold",
		absf(float(snap.get("combat_search_progress", 0.0)) - 0.8) <= 0.0001
	)

	world.queue_free()
	await get_tree().process_frame


func _test_confirm_runtime_config_keeps_awareness_field_names() -> void:
	var world := Node2D.new()
	add_child(world)
	var nav := FakeNav.new()
	world.add_child(nav)
	var enemy := await _spawn_enemy(world, nav)
	_install_fake_stage_pursuit(enemy)

	var config := enemy.call("_build_confirm_runtime_config", {}) as Dictionary
	var keys_ok := (
		config.has("combat_search_progress")
		and config.has("combat_search_total_elapsed_sec")
		and config.has("combat_search_room_elapsed_sec")
		and config.has("combat_search_total_cap_sec")
		and config.has("combat_search_force_complete")
	)
	_t.run_test("_build_confirm_runtime_config keeps awareness combat_search_* field names", keys_ok)

	world.queue_free()
	await get_tree().process_frame
