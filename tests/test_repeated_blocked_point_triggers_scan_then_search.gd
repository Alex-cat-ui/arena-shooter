extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeStagePursuit:
	extends RefCounted

	var stage: int = 0

	func get_shadow_search_stage() -> int:
		return stage


class FakeBlockedPointNav:
	extends Node

	var blocked_point := Vector2(40.0, 0.0)

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func is_point_in_shadow(_point: Vector2) -> bool:
		return false

	func get_nearest_non_shadow_point(target: Vector2, _radius_px: float) -> Vector2:
		return target + Vector2(24.0, 0.0)

	func can_enemy_traverse_point(_enemy: Node, _point: Vector2) -> bool:
		return true

	func build_policy_valid_path(_from_pos: Vector2, _to_pos: Vector2, _enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		return {
			"status": "unreachable_policy",
			"path_points": [],
			"reason": "policy_blocked",
			"segment_index": 0,
			"blocked_point": blocked_point,
		}


class FakeDarkNav:
	extends Node

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func get_neighbors(_room_id: int) -> Array:
		return []

	func get_room_center(_room_id: int) -> Vector2:
		return Vector2(96.0, 32.0)

	func get_room_rect(_room_id: int) -> Rect2:
		return Rect2(Vector2(0.0, -64.0), Vector2(192.0, 192.0))

	func is_point_in_shadow(point: Vector2) -> bool:
		# Only the dark-node target is shadowed.
		return point.x >= 96.0

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
	print("REPEATED BLOCKED POINT TRIGGERS SCAN THEN SEARCH TEST")
	print("============================================================")

	await _test_repeated_same_blocked_point_requests_next_search_node()
	await _test_enemy_applies_recovery_feedback_and_skips_current_dark_node()
	await _test_next_dark_node_in_shadow_runs_shadow_boundary_scan_then_search()

	_t.summary("REPEATED BLOCKED POINT TRIGGERS SCAN THEN SEARCH RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _spawn_enemy(world: Node2D, nav: Node, pos: Vector2 = Vector2(72.0, 32.0)) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = pos
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(17101, "zombie")
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
	enemy.set("_shadow_scan_completed", true)
	enemy.set("_shadow_scan_completed_reason", "timeout")


func _seed_dark_search_session(enemy: Enemy) -> Dictionary:
	var current_target := Vector2(64.0, 32.0)
	var next_dark_target := Vector2(96.0, 32.0)
	var next_dark_approach := Vector2(120.0, 32.0)
	enemy.set("_combat_search_current_room_id", 0)
	enemy.set("_combat_search_room_nodes", {
		0: [
			{
				"key": "r0:boundary:0",
				"kind": "boundary_point",
				"target_pos": current_target,
				"approach_pos": current_target,
				"target_in_shadow": false,
				"requires_shadow_boundary_scan": false,
				"coverage_weight": 0.5,
			},
			{
				"key": "r0:dark:0",
				"kind": "dark_pocket",
				"target_pos": next_dark_target,
				"approach_pos": next_dark_approach,
				"target_in_shadow": true,
				"requires_shadow_boundary_scan": true,
				"coverage_weight": 1.0,
			},
		],
	})
	enemy.set("_combat_search_room_node_visited", {0: {}})
	enemy.set("_combat_search_current_node_key", "r0:boundary:0")
	enemy.set("_combat_search_current_node_kind", "boundary_point")
	enemy.set("_combat_search_current_node_requires_shadow_scan", false)
	enemy.set("_combat_search_current_node_shadow_scan_done", false)
	enemy.set("_combat_search_node_search_dwell_sec", 0.0)
	enemy.set("_combat_search_shadow_scan_suppressed_last_tick", false)
	enemy.set("_combat_search_target_pos", current_target)
	enemy.set("_combat_search_room_budget_sec", 999.0)
	enemy.set("_combat_search_room_elapsed_sec", 0.0)
	enemy.set("_combat_search_total_elapsed_sec", 0.0)
	enemy.set("_combat_search_total_cap_hit", false)
	enemy.set("_combat_search_room_coverage", {0: 0.0})
	enemy.set("_combat_search_visited_rooms", {})
	enemy.call("_update_combat_search_progress")
	return {
		"current_target": current_target,
		"next_dark_target": next_dark_target,
	}


func _build_matching_recovery_exec_result(target: Vector2, reason: String = "blocked_point_repeat") -> Dictionary:
	return {
		"repath_recovery_request_next_search_node": true,
		"repath_recovery_reason": reason,
		"repath_recovery_blocked_point": target + Vector2(8.0, 0.0),
		"repath_recovery_blocked_point_valid": true,
		"repath_recovery_repeat_count": 2,
		"repath_recovery_preserve_intent": true,
		"repath_recovery_intent_target": target,
	}


func _test_repeated_same_blocked_point_requests_next_search_node() -> void:
	var world := Node2D.new()
	add_child(world)
	var nav := FakeBlockedPointNav.new()
	world.add_child(nav)
	var owner := CharacterBody2D.new()
	owner.global_position = Vector2.ZERO
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	world.add_child(owner)
	await get_tree().physics_frame

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	pursuit.configure_navigation(nav, 0)
	var target := Vector2(96.0, 0.0)
	var intent := {
		"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SHADOW_BOUNDARY_SCAN,
		"target": target,
	}
	var ctx := {
		"player_pos": target,
		"known_target_pos": Vector2.ZERO,
		"last_seen_pos": Vector2.ZERO,
		"investigate_anchor": Vector2.ZERO,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.CALM,
		"los": false,
		"dist": target.length(),
	}

	var threshold_result: Dictionary = {}
	var threshold_hit := false
	for _i in range(20):
		var result := pursuit.execute_intent(0.1, intent, ctx) as Dictionary
		if String(result.get("repath_recovery_reason", "")) == "blocked_point_repeat":
			threshold_result = result.duplicate(true)
			threshold_hit = true
			break

	_t.run_test(
		"repeated same blocked_point bucket triggers next-node recovery request",
		threshold_hit
			and bool(threshold_result.get("repath_recovery_request_next_search_node", false))
			and bool(threshold_result.get("repath_recovery_preserve_intent", false))
			and int(threshold_result.get("repath_recovery_repeat_count", 0)) >= 2
	)
	_t.run_test(
		"threshold tick returns gameplay intent target while tracker can reset internally",
		threshold_hit
			and ((threshold_result.get("repath_recovery_intent_target", Vector2.ZERO) as Vector2).distance_to(target) <= 0.001)
	)

	world.queue_free()
	await get_tree().process_frame


func _test_enemy_applies_recovery_feedback_and_skips_current_dark_node() -> void:
	var world := Node2D.new()
	add_child(world)
	var nav := FakeDarkNav.new()
	world.add_child(nav)
	var enemy := await _spawn_enemy(world, nav)
	_install_fake_stage_pursuit(enemy)
	var seeded := _seed_dark_search_session(enemy)
	var before_target := enemy.get("_combat_search_target_pos") as Vector2
	var before_key := String(enemy.get("_combat_search_current_node_key"))

	var intent := {
		"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH,
		"target": before_target,
	}
	var exec_result := _build_matching_recovery_exec_result(before_target, "hard_stall")
	enemy.call("_apply_combat_search_repath_recovery_feedback", intent, exec_result)

	var snap := enemy.get_debug_detection_snapshot() as Dictionary
	var after_key := String(enemy.get("_combat_search_current_node_key"))
	var after_target := enemy.get("_combat_search_target_pos") as Vector2
	var visited := ((enemy.get("_combat_search_room_node_visited") as Dictionary).get(0, {}) as Dictionary)

	_t.run_test(
		"enemy applies recovery and reports skipped node key",
		bool(snap.get("combat_search_recovery_applied", false))
			and String(snap.get("combat_search_recovery_reason", "")) == "hard_stall"
			and String(snap.get("combat_search_recovery_skipped_node_key", "")) == before_key
	)
	_t.run_test(
		"skipped node is marked visited and next node selected",
		bool(visited.get(before_key, false))
			and after_key != ""
			and after_key != before_key
			and after_target.distance_to(before_target) > 0.5
	)
	_t.run_test(
		"next selected node is the dark pocket",
		after_key == "r0:dark:0"
			and after_target.distance_to(seeded.get("next_dark_target", Vector2.ZERO) as Vector2) <= 0.001
	)

	world.queue_free()
	await get_tree().process_frame


func _test_next_dark_node_in_shadow_runs_shadow_boundary_scan_then_search() -> void:
	var world := Node2D.new()
	add_child(world)
	var nav := FakeDarkNav.new()
	world.add_child(nav)
	var enemy := await _spawn_enemy(world, nav)
	var fake_pursuit := _install_fake_stage_pursuit(enemy)
	var seeded := _seed_dark_search_session(enemy)
	var current_target := seeded.get("current_target", Vector2.ZERO) as Vector2
	var next_dark_target := seeded.get("next_dark_target", Vector2.ZERO) as Vector2

	var apply_intent := {
		"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH,
		"target": current_target,
	}
	enemy.call(
		"_apply_combat_search_repath_recovery_feedback",
		apply_intent,
		_build_matching_recovery_exec_result(current_target, "blocked_point_repeat")
	)
	var first_intent := _build_no_contact_intent(enemy)
	var first_target := first_intent.get("target", Vector2.ZERO) as Vector2
	_complete_shadow_stage_edge(enemy, fake_pursuit, next_dark_target)
	var second_intent := _build_no_contact_intent(enemy)
	var third_intent := _build_no_contact_intent(enemy)
	var snap := enemy.get_debug_detection_snapshot() as Dictionary

	_t.run_test(
		"after recovery skip next dark node emits SHADOW_BOUNDARY_SCAN",
		int(first_intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SHADOW_BOUNDARY_SCAN
			and first_target.distance_to(next_dark_target) <= 0.001
	)
	_t.run_test(
		"same next dark node flips to SEARCH after shadow stage completion",
		int(second_intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH
			and ((second_intent.get("target", Vector2.ZERO) as Vector2).distance_to(next_dark_target) <= 0.001)
	)
	_t.run_test(
		"no repeated SHADOW_BOUNDARY_SCAN loop after completion on recovered next node",
		int(third_intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH
			and bool(snap.get("combat_search_shadow_scan_suppressed", false))
	)

	world.queue_free()
	await get_tree().process_frame
