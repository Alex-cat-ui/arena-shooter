extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeStagePursuit:
	extends RefCounted

	var stage: int = 0

	func get_shadow_search_stage() -> int:
		return stage


class FakeDarkNav:
	extends Node

	var room_center := Vector2(96.0, 32.0)
	var room_rect := Rect2(Vector2(0.0, -64.0), Vector2(192.0, 192.0))

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func get_neighbors(_room_id: int) -> Array:
		return []

	func get_room_center(_room_id: int) -> Vector2:
		return room_center

	func get_room_rect(_room_id: int) -> Rect2:
		return room_rect

	func is_point_in_shadow(point: Vector2) -> bool:
		# Center and left sample are shadowed, right sample is light.
		return point.x <= room_center.x + 1.0

	func get_nearest_non_shadow_point(target: Vector2, radius_px: float) -> Vector2:
		return Vector2(target.x + minf(radius_px, 24.0), target.y)

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
	print("UNREACHABLE SHADOW NODE FORCES SCAN THEN SEARCH TEST")
	print("============================================================")

	await _test_dark_node_in_shadow_requests_shadow_boundary_scan_before_search()
	await _test_shadow_scan_completion_flips_same_node_to_search_without_repeat_scan()
	await _test_search_dwell_marks_node_covered_and_selects_next_node()

	_t.summary("UNREACHABLE SHADOW NODE FORCES SCAN THEN SEARCH RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _spawn_enemy(world: Node2D, nav: FakeDarkNav, pos: Vector2 = Vector2(72.0, 32.0)) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = pos
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(16301, "zombie")
	enemy.set_room_navigation(nav, 0)
	enemy.debug_force_awareness_state("COMBAT")
	enemy.set_process(false)
	enemy.set_physics_process(false)
	return enemy


func _runtime(enemy: Enemy):
	return (enemy.get_runtime_helper_refs() as Dictionary).get("combat_search_runtime", null)


func _install_fake_stage_pursuit(enemy: Enemy, stage: int = 0) -> FakeStagePursuit:
	var fake := FakeStagePursuit.new()
	fake.stage = stage
	var runtime: Variant = _runtime(enemy)
	if runtime != null:
		runtime.call("set_state_value", "_pursuit", fake)
	return fake


func _phase16_setup() -> Dictionary:
	var world := Node2D.new()
	add_child(world)
	var nav := FakeDarkNav.new()
	world.add_child(nav)
	var enemy := await _spawn_enemy(world, nav)
	var runtime: Variant = _runtime(enemy)
	var fake_pursuit := _install_fake_stage_pursuit(enemy)
	var target := Vector2(160.0, 32.0)
	if runtime != null:
		runtime.call("update_runtime", 0.1, false, target, true)
		runtime.call("set_state_value", "_combat_search_room_budget_sec", 999.0)
	return {
		"world": world,
		"nav": nav,
		"enemy": enemy,
		"runtime": runtime,
		"fake_pursuit": fake_pursuit,
		"target": target,
	}


func _build_no_contact_intent(brain, enemy: Enemy, runtime) -> Dictionary:
	if brain == null or enemy == null or runtime == null:
		return {}
	var target := runtime.call("get_state_value", "_combat_search_target_pos", Vector2.ZERO) as Vector2
	var scan_required := bool(runtime.call("get_state_value", "_combat_search_current_node_requires_shadow_scan", false))
	var scan_done := bool(runtime.call("get_state_value", "_combat_search_current_node_shadow_scan_done", false))
	var suppressed := bool(
		runtime.call(
			"compute_shadow_scan_suppressed_for_context",
			true,
			target,
			true,
			target
		)
	)
	var ctx := {
		"dist": enemy.global_position.distance_to(target),
		"los": false,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.COMBAT,
		"combat_lock": false,
		"last_seen_age": 0.0,
		"last_seen_pos": target,
		"has_last_seen": true,
		"dist_to_last_seen": enemy.global_position.distance_to(target),
		"investigate_anchor": Vector2.ZERO,
		"has_investigate_anchor": false,
		"dist_to_investigate_anchor": INF,
		"role": 0,
		"slot_role": 0,
		"slot_position": Vector2.ZERO,
		"dist_to_slot": INF,
		"hp_ratio": 1.0,
		"path_ok": false,
		"slot_path_status": "unreachable_geometry",
		"slot_path_eta_sec": INF,
		"flank_slot_contract_ok": false,
		"has_slot": false,
		"player_pos": target,
		"known_target_pos": target,
		"target_is_last_seen": false,
		"has_known_target": true,
		"target_context_exists": true,
		"home_position": enemy.global_position,
		"shadow_scan_target": target,
		"has_shadow_scan_target": true,
		"shadow_scan_target_in_shadow": scan_required and not scan_done and not suppressed,
		"shadow_scan_completed": bool(runtime.call("get_state_value", "_shadow_scan_completed", false)),
		"shadow_scan_completed_reason": String(runtime.call("get_state_value", "_shadow_scan_completed_reason", "none")),
	}
	return brain.update(0.1, ctx) as Dictionary


func _complete_shadow_stage_edge(runtime, fake_pursuit: FakeStagePursuit, target_hint: Vector2) -> void:
	if runtime == null:
		return
	fake_pursuit.stage = 2
	runtime.call("update_runtime", 0.1, false, target_hint, true)
	fake_pursuit.stage = 0
	runtime.call("update_runtime", 0.1, false, target_hint, true)
	# Real runtime sets these from _pursuit.execute_intent(...) completion result; this suite calls helpers directly.
	runtime.call("set_state_value", "_shadow_scan_completed", true)
	runtime.call("set_state_value", "_shadow_scan_completed_reason", "timeout")


func _test_dark_node_in_shadow_requests_shadow_boundary_scan_before_search() -> void:
	var setup: Dictionary = await _phase16_setup()
	var world := setup["world"] as Node2D
	var enemy := setup["enemy"] as Enemy
	var runtime: Variant = setup.get("runtime", null)
	_t.run_test("combat-search runtime is available", runtime != null)
	if runtime == null:
		world.queue_free()
		await get_tree().process_frame
		return

	var snap := enemy.get_debug_detection_snapshot() as Dictionary
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	var intent := _build_no_contact_intent(brain, enemy, runtime)
	var intent_target := intent.get("target", Vector2.ZERO) as Vector2
	var search_target := snap.get("combat_search_target_pos", Vector2.ZERO) as Vector2

	_t.run_test(
		"dark node in shadow emits SHADOW_BOUNDARY_SCAN before SEARCH",
		int(intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SHADOW_BOUNDARY_SCAN
	)
	_t.run_test(
		"shadow scan intent target matches active dark node target",
		intent_target.distance_to(search_target) <= 0.001 and search_target != Vector2.ZERO
	)
	_t.run_test(
		"active node requires shadow scan before completion edge",
		bool(snap.get("combat_search_node_requires_shadow_scan", false)) and not bool(snap.get("combat_search_node_shadow_scan_done", false))
	)

	world.queue_free()
	await get_tree().process_frame


func _test_shadow_scan_completion_flips_same_node_to_search_without_repeat_scan() -> void:
	var setup: Dictionary = await _phase16_setup()
	var world := setup["world"] as Node2D
	var enemy := setup["enemy"] as Enemy
	var runtime: Variant = setup.get("runtime", null)
	_t.run_test("runtime available for completion edge test", runtime != null)
	if runtime == null:
		world.queue_free()
		await get_tree().process_frame
		return
	var fake_pursuit := setup["fake_pursuit"] as FakeStagePursuit
	var target := setup["target"] as Vector2
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()

	var first_intent := _build_no_contact_intent(brain, enemy, runtime)
	var first_target := first_intent.get("target", Vector2.ZERO) as Vector2
	_complete_shadow_stage_edge(runtime, fake_pursuit, target)
	var second_intent := _build_no_contact_intent(brain, enemy, runtime)
	var third_intent := _build_no_contact_intent(brain, enemy, runtime)
	var second_target := second_intent.get("target", Vector2.ZERO) as Vector2
	var snap := enemy.get_debug_detection_snapshot() as Dictionary

	_t.run_test(
		"setup: first no-contact tick emits SHADOW_BOUNDARY_SCAN",
		int(first_intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SHADOW_BOUNDARY_SCAN
	)
	_t.run_test(
		"after shadow stage completion edge next intent flips to SEARCH on same target",
		int(second_intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH and second_target.distance_to(first_target) <= 0.001
	)
	_t.run_test(
		"no repeated SHADOW_BOUNDARY_SCAN after completion while same node stays active",
		int(third_intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH
	)
	_t.run_test(
		"debug snapshot reports shadow scan suppression after completion",
		bool(snap.get("combat_search_shadow_scan_suppressed", false))
	)

	world.queue_free()
	await get_tree().process_frame


func _test_search_dwell_marks_node_covered_and_selects_next_node() -> void:
	var setup: Dictionary = await _phase16_setup()
	var world := setup["world"] as Node2D
	var enemy := setup["enemy"] as Enemy
	var runtime: Variant = setup.get("runtime", null)
	_t.run_test("runtime available for dwell progression test", runtime != null)
	if runtime == null:
		world.queue_free()
		await get_tree().process_frame
		return
	var fake_pursuit := setup["fake_pursuit"] as FakeStagePursuit
	var target_hint := setup["target"] as Vector2

	_complete_shadow_stage_edge(runtime, fake_pursuit, target_hint)
	var before_snap := enemy.get_debug_detection_snapshot() as Dictionary
	var previous_key := String(before_snap.get("combat_search_node_key", ""))
	var previous_cov := float(before_snap.get("combat_search_room_coverage_raw", 0.0))
	var search_target := before_snap.get("combat_search_target_pos", Vector2.ZERO) as Vector2

	for _i in range(8):
		if String(runtime.call("get_state_value", "_combat_search_current_node_key", "")) != previous_key:
			break
		runtime.call("record_execution_feedback", {
			"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH,
			"target": search_target,
		}, 0.5)
		runtime.call("update_runtime", 0.1, false, target_hint, true)

	var visited := (runtime.call("get_state_value", "_combat_search_room_node_visited", {}) as Dictionary).get(0, {}) as Dictionary
	var after_snap := enemy.get_debug_detection_snapshot() as Dictionary
	var next_key := String(after_snap.get("combat_search_node_key", ""))
	var after_cov := float(after_snap.get("combat_search_room_coverage_raw", 0.0))

	_t.run_test("SEARCH dwell marks previous dark node visited exactly once (visited flag set)", bool(visited.get(previous_key, false)))
	_t.run_test("SEARCH dwell advances to next node or clears active node", previous_key != "" and next_key != previous_key)
	_t.run_test("SEARCH dwell increases current-room coverage raw", after_cov > previous_cov + 0.0001)

	world.queue_free()
	await get_tree().process_frame
