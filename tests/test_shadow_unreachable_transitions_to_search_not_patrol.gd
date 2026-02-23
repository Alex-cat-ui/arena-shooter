extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeEnemy:
	extends CharacterBody2D

	var flashlight_active: bool = false

	func is_flashlight_active_for_navigation() -> bool:
		return flashlight_active

	func set_shadow_check_flashlight(_active: bool) -> void:
		pass

	func set_shadow_scan_active(_active: bool) -> void:
		pass


class FakeNav:
	extends Node

	var shadow_start_x: float = 48.0

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func is_point_in_shadow(point: Vector2) -> bool:
		return point.x >= shadow_start_x

	func get_nearest_non_shadow_point(target: Vector2, _radius_px: float) -> Vector2:
		return Vector2(shadow_start_x - 12.0, target.y)

	func can_enemy_traverse_point(enemy: Node, point: Vector2) -> bool:
		var has_grant := false
		if enemy and enemy.has_method("is_flashlight_active_for_navigation"):
			has_grant = bool(enemy.call("is_flashlight_active_for_navigation"))
		if has_grant:
			return true
		return point.x < shadow_start_x

	func build_policy_valid_path(from_pos: Vector2, to_pos: Vector2, enemy: Node = null) -> Dictionary:
		var path: Array[Vector2] = [to_pos]
		var prev := from_pos
		for point in path:
			var steps := maxi(int(ceil(prev.distance_to(point) / 12.0)), 1)
			for step in range(1, steps + 1):
				var sample := prev.lerp(point, float(step) / float(steps))
				if not can_enemy_traverse_point(enemy, sample):
					return {
						"status": "unreachable_policy",
						"path_points": [],
						"reason": "policy_blocked",
						"segment_index": 0,
						"blocked_point": sample,
					}
			prev = point
		return {
			"status": "ok",
			"path_points": path,
			"reason": "ok",
		}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("SHADOW UNREACHABLE TRANSITIONS TO SEARCH (NO PATROL)")
	print("============================================================")

	await _test_phase2_shadow_unreachable_canon_and_plan_lock()

	_t.summary("SHADOW UNREACHABLE TRANSITIONS TO SEARCH RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_phase2_shadow_unreachable_canon_and_plan_lock() -> void:
	var world := Node2D.new()
	add_child(world)

	var nav := FakeNav.new()
	world.add_child(nav)

	var owner := FakeEnemy.new()
	owner.global_position = Vector2.ZERO
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	world.add_child(owner)
	await get_tree().physics_frame

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	pursuit.configure_navigation(nav, 0)

	var light_target := Vector2(24.0, 0.0)
	var light_ctx := {
		"player_pos": light_target,
		"known_target_pos": Vector2.ZERO,
		"last_seen_pos": Vector2.ZERO,
		"investigate_anchor": Vector2.ZERO,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.CALM,
		"los": false,
		"dist": light_target.length(),
	}
	var plan_a := pursuit.execute_intent(1.0 / 60.0, {"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT, "target": light_target}, light_ctx) as Dictionary
	var plan_b := pursuit.execute_intent(1.0 / 60.0, {"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT, "target": light_target + Vector2(6.0, 0.0)}, light_ctx) as Dictionary
	var plan_c := pursuit.execute_intent(1.0 / 60.0, {"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT, "target": light_target + Vector2(20.0, 0.0)}, light_ctx) as Dictionary
	_t.run_test("plan_id stable for <=8px target jitter", int(plan_b.get("plan_id", -1)) == int(plan_a.get("plan_id", -2)))
	_t.run_test("plan_id increments by exactly one for >8px target change", int(plan_c.get("plan_id", -1)) == int(plan_b.get("plan_id", -2)) + 1)

	var blocked_target := Vector2(160.0, 0.0)
	var active_ctx := {
		"player_pos": blocked_target,
		"known_target_pos": blocked_target,
		"last_seen_pos": Vector2.ZERO,
		"investigate_anchor": Vector2.ZERO,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.ALERT,
		"los": false,
		"dist": blocked_target.length(),
	}
	var patrol_guard := pursuit.execute_intent(1.0 / 60.0, {"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL}, active_ctx) as Dictionary
	var return_home_guard := pursuit.execute_intent(1.0 / 60.0, {"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETURN_HOME}, active_ctx) as Dictionary
	var guard_target_1 := patrol_guard.get("intent_target", Vector2.ZERO) as Vector2
	var guard_target_2 := return_home_guard.get("intent_target", Vector2.ZERO) as Vector2
	_t.run_test("runtime anti-patrol guard rewrites PATROL to search-target context", guard_target_1.distance_to(blocked_target) <= 0.001)
	_t.run_test("runtime anti-patrol guard rewrites RETURN_HOME to search-target context", guard_target_2.distance_to(blocked_target) <= 0.001)

	var move_intent := {
		"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT,
		"target": blocked_target,
	}
	var transitions: Array[String] = []
	var search_state_ticks := 0
	for _i in range(300):
		active_ctx["dist"] = owner.global_position.distance_to(blocked_target)
		var result := pursuit.execute_intent(1.0 / 60.0, move_intent, active_ctx) as Dictionary
		var state := String(result.get("shadow_unreachable_fsm_state", ""))
		if transitions.is_empty() or transitions[transitions.size() - 1] != state:
			transitions.append(state)
		if state == "search":
			search_state_ticks += 1
		if transitions.has("shadow_boundary_scan") and transitions.has("search"):
			break
		await get_tree().physics_frame

	_t.run_test("shadow unreachable enters boundary scan then search", transitions.has("shadow_boundary_scan") and transitions.has("search"))
	_t.run_test("search phase is exposed for one execute tick", search_state_ticks == 1)

	world.queue_free()
	await get_tree().process_frame
