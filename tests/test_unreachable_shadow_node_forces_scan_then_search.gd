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


func _install_fake_stage_pursuit(enemy: Enemy, stage: int = 0) -> FakeStagePursuit:
	var fake := FakeStagePursuit.new()
	fake.stage = stage
	enemy.set("_pursuit", fake)
	return fake


func _phase16_setup() -> Dictionary:
	var world := Node2D.new()
	add_child(world)
	var nav := FakeDarkNav.new()
	world.add_child(nav)
	var enemy := await _spawn_enemy(world, nav)
	var fake_pursuit := _install_fake_stage_pursuit(enemy)
	var target := Vector2(160.0, 32.0)
	enemy.call("_update_combat_search_runtime", 0.1, false, target, true)
	enemy.set("_combat_search_room_budget_sec", 999.0)
	return {
		"world": world,
		"nav": nav,
		"enemy": enemy,
		"fake_pursuit": fake_pursuit,
		"target": target,
	}


func _build_no_contact_intent(enemy: Enemy) -> Dictionary:
	var target_context := enemy.call("_resolve_known_target_context", false, Vector2.ZERO, false) as Dictionary
	var ctx := enemy.call("_build_utility_context", false, false, {}, target_context) as Dictionary
	var brain = enemy.get("_utility_brain")
	return brain.update(0.1, ctx) as Dictionary


func _complete_shadow_stage_edge(enemy: Enemy, fake_pursuit: FakeStagePursuit, target_hint: Vector2) -> void:
	fake_pursuit.stage = 2
	enemy.call("_update_combat_search_runtime", 0.1, false, target_hint, true)
	fake_pursuit.stage = 0
	enemy.call("_update_combat_search_runtime", 0.1, false, target_hint, true)
	# Real runtime sets these from _pursuit.execute_intent(...) completion result; this suite calls helpers directly.
	enemy.set("_shadow_scan_completed", true)
	enemy.set("_shadow_scan_completed_reason", "timeout")


func _test_dark_node_in_shadow_requests_shadow_boundary_scan_before_search() -> void:
	var setup := await _phase16_setup()
	var world := setup["world"] as Node2D
	var enemy := setup["enemy"] as Enemy

	var snap := enemy.get_debug_detection_snapshot() as Dictionary
	var intent := _build_no_contact_intent(enemy)
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
	var setup := await _phase16_setup()
	var world := setup["world"] as Node2D
	var enemy := setup["enemy"] as Enemy
	var fake_pursuit := setup["fake_pursuit"] as FakeStagePursuit
	var target := setup["target"] as Vector2

	var first_intent := _build_no_contact_intent(enemy)
	var first_target := first_intent.get("target", Vector2.ZERO) as Vector2
	_complete_shadow_stage_edge(enemy, fake_pursuit, target)
	var second_intent := _build_no_contact_intent(enemy)
	var third_intent := _build_no_contact_intent(enemy)
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
	var setup := await _phase16_setup()
	var world := setup["world"] as Node2D
	var enemy := setup["enemy"] as Enemy
	var fake_pursuit := setup["fake_pursuit"] as FakeStagePursuit
	var target_hint := setup["target"] as Vector2

	_complete_shadow_stage_edge(enemy, fake_pursuit, target_hint)
	var before_snap := enemy.get_debug_detection_snapshot() as Dictionary
	var previous_key := String(before_snap.get("combat_search_node_key", ""))
	var previous_cov := float(before_snap.get("combat_search_room_coverage_raw", 0.0))
	var search_target := before_snap.get("combat_search_target_pos", Vector2.ZERO) as Vector2

	for _i in range(8):
		if String(enemy.get("_combat_search_current_node_key")) != previous_key:
			break
		enemy.call("_record_combat_search_execution_feedback", {
			"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH,
			"target": search_target,
		}, 0.5)
		enemy.call("_update_combat_search_runtime", 0.1, false, target_hint, true)

	var visited := (enemy.get("_combat_search_room_node_visited") as Dictionary).get(0, {}) as Dictionary
	var after_snap := enemy.get_debug_detection_snapshot() as Dictionary
	var next_key := String(after_snap.get("combat_search_node_key", ""))
	var after_cov := float(after_snap.get("combat_search_room_coverage_raw", 0.0))

	_t.run_test("SEARCH dwell marks previous dark node visited exactly once (visited flag set)", bool(visited.get(previous_key, false)))
	_t.run_test("SEARCH dwell advances to next node or clears active node", previous_key != "" and next_key != previous_key)
	_t.run_test("SEARCH dwell increases current-room coverage raw", after_cov > previous_cov + 0.0001)

	world.queue_free()
	await get_tree().process_frame
