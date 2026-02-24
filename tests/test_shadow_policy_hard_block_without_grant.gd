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
	var shadow_check_flashlight: bool = false
	var shadow_scan_active_flag: bool = false

	func is_flashlight_active_for_navigation() -> bool:
		return flashlight_active

	func set_shadow_check_flashlight(active: bool) -> void:
		shadow_check_flashlight = active

	func set_shadow_scan_active(active: bool) -> void:
		shadow_scan_active_flag = active


class FakeNav:
	extends Node

	var blocked_x: float = 48.0

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func is_point_in_shadow(point: Vector2) -> bool:
		return point.x >= blocked_x

	func get_nearest_non_shadow_point(target: Vector2, _radius_px: float) -> Vector2:
		return Vector2(blocked_x - 18.0, target.y)

	func can_enemy_traverse_point(enemy: Node, point: Vector2) -> bool:
		var has_grant := false
		if enemy and enemy.has_method("is_flashlight_active_for_navigation"):
			has_grant = bool(enemy.call("is_flashlight_active_for_navigation"))
		if has_grant:
			return true
		return point.x < blocked_x

	func build_policy_valid_path(from_pos: Vector2, to_pos: Vector2, enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		var path: Array[Vector2] = [to_pos]
		var prev := from_pos
		var segment_index := 0
		for point in path:
			var steps := maxi(int(ceil(prev.distance_to(point) / 12.0)), 1)
			for step in range(1, steps + 1):
				var t := float(step) / float(steps)
				var sample := prev.lerp(point, t)
				if not can_enemy_traverse_point(enemy, sample):
					return {
						"status": "unreachable_policy",
						"path_points": [],
						"reason": "policy_blocked",
						"segment_index": segment_index,
						"blocked_point": sample,
					}
			prev = point
			segment_index += 1
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
	print("SHADOW POLICY HARD BLOCK WITHOUT GRANT TEST")
	print("============================================================")

	await _test_shadow_policy_enters_phase2_fsm()

	_t.summary("SHADOW POLICY HARD BLOCK WITHOUT GRANT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_shadow_policy_enters_phase2_fsm() -> void:
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

	var blocked_target := Vector2(160.0, 0.0)
	var intent := {
		"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT,
		"target": blocked_target,
	}
	var ctx := {
		"player_pos": blocked_target,
		"known_target_pos": blocked_target,
		"last_seen_pos": Vector2.ZERO,
		"investigate_anchor": Vector2.ZERO,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.ALERT,
		"los": false,
		"dist": blocked_target.length(),
	}

	var transitions: Array[String] = []
	var first_result: Dictionary = {}
	var first_snapshot: Dictionary = {}
	var saw_search := false
	var repeated_unreachable_policy_count := 0
	var repeated_unreachable_policy_reason_stable := true
	for i in range(240):
		ctx["dist"] = owner.global_position.distance_to(blocked_target)
		var result := pursuit.execute_intent(1.0 / 60.0, intent, ctx) as Dictionary
		var snapshot := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
		if i == 0:
			first_result = result.duplicate(true)
			first_snapshot = snapshot.duplicate(true)
		var state := String(result.get("shadow_unreachable_fsm_state", ""))
		if transitions.is_empty() or transitions[transitions.size() - 1] != state:
			transitions.append(state)
		if String(snapshot.get("path_plan_status", "")) == "unreachable_policy":
			repeated_unreachable_policy_count += 1
			if String(snapshot.get("path_plan_reason", "")) != "policy_blocked":
				repeated_unreachable_policy_reason_stable = false
		if state == "search":
			saw_search = true
			break
		await get_tree().physics_frame

	var k1 := "policy_" + "fallback_used"
	var k2 := "policy_" + "fallback_target"
	var k3 := "shadow_" + "escape_active"
	var k4 := "shadow_" + "escape_target"
	_t.run_test("first blocked plan reports shadow_unreachable_policy", String(first_result.get("path_failed_reason", "")) == "shadow_unreachable_policy")
	_t.run_test("planner contract reason remains policy_blocked in snapshot", String(first_snapshot.get("path_plan_reason", "")) == "policy_blocked")
	_t.run_test("phase2 fsm starts in shadow_boundary_scan", String(first_result.get("shadow_unreachable_fsm_state", "")) == "shadow_boundary_scan")
	_t.run_test("phase2 fsm reaches search state", saw_search and transitions.has("shadow_boundary_scan") and transitions.has("search"))
	_t.run_test("execute_intent returns plan contract keys", first_result.has("plan_id") and first_result.has("intent_target") and first_result.has("plan_target"))
	_t.run_test("debug snapshot has phase2 keys", first_snapshot.has("plan_id") and first_snapshot.has("intent_target") and first_snapshot.has("plan_target") and first_snapshot.has("shadow_unreachable_fsm_state"))
	_t.run_test(
		"repeated blocked attempts keep path_plan_reason == policy_blocked",
		repeated_unreachable_policy_count >= 2 and repeated_unreachable_policy_reason_stable
	)
	_t.run_test("debug snapshot omits legacy keys", not first_snapshot.has(k1) and not first_snapshot.has(k2) and not first_snapshot.has(k3) and not first_snapshot.has(k4))

	world.queue_free()
	await get_tree().process_frame
