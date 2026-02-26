extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeNav:
	extends Node

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func can_enemy_traverse_point(_enemy: Node, _point: Vector2) -> bool:
		return true

	func can_enemy_traverse_geometry_point(_enemy: Node, _point: Vector2) -> bool:
		return true

	func build_policy_valid_path(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		return {
			"status": "ok",
			"path_points": [to_pos],
			"reason": "ok",
		}


class FakePatrolDecision:
	extends RefCounted

	var fixed_target: Vector2 = Vector2.ZERO
	var fixed_speed_scale: float = 1.0

	func _init(target: Vector2, speed_scale: float = 1.0) -> void:
		fixed_target = target
		fixed_speed_scale = speed_scale

	func configure(_nav_system: Node, _home_room_id: int) -> void:
		pass

	func update(_delta: float, _facing_dir: Vector2) -> Dictionary:
		return {
			"waiting": false,
			"target": fixed_target,
			"speed_scale": fixed_speed_scale,
		}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("PREAVOID WALL CONTRACT TEST")
	print("============================================================")

	await _test_direct_move_preavoid_prevents_wall_collision()
	await _test_patrol_intent_preavoid_prevents_wall_collision()

	_t.summary("PREAVOID WALL CONTRACT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_direct_move_preavoid_prevents_wall_collision() -> void:
	var root := Node2D.new()
	add_child(root)
	TestHelpers.add_wall(root, Vector2.ZERO, Vector2(240.0, 16.0))
	var enemy := TestHelpers.spawn_mover(root, Vector2(0.0, 56.0), 1, 1, "enemies")
	var nav := FakeNav.new()
	root.add_child(nav)

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(enemy, null, 2.4)
	pursuit.configure_navigation(nav, 0)
	var collision_repath_before := 0
	var preavoid_before := 0
	if AIWatchdog and AIWatchdog.has_method("debug_reset_metrics_for_tests"):
		AIWatchdog.call("debug_reset_metrics_for_tests")
	if AIWatchdog and AIWatchdog.has_method("get_snapshot"):
		var before_snapshot := AIWatchdog.call("get_snapshot") as Dictionary
		collision_repath_before = int(before_snapshot.get("collision_repath_events_total", 0))
		preavoid_before = int(before_snapshot.get("preavoid_events_total", 0))

	await get_tree().process_frame
	await get_tree().physics_frame

	var target := Vector2(0.0, -120.0)
	var saw_preavoid_triggered := false
	var saw_preavoid_forced := false
	var saw_non_door_collision := false
	var saw_policy_blocked := false
	var last_snapshot: Dictionary = {}
	for _i in range(180):
		pursuit.call("_execute_move_to_target", 1.0 / 60.0, target, 1.0, 2.0)
		last_snapshot = pursuit.debug_get_navigation_policy_snapshot() as Dictionary
		if bool(last_snapshot.get("preavoid_triggered", false)):
			saw_preavoid_triggered = true
		if bool(last_snapshot.get("preavoid_forced_repath", false)):
			saw_preavoid_forced = true
		if String(last_snapshot.get("collision_kind", "")) == "non_door":
			saw_non_door_collision = true
		if bool(last_snapshot.get("policy_blocked", false)):
			saw_policy_blocked = true
		await get_tree().physics_frame

	var collision_repath_after := collision_repath_before
	var preavoid_after := preavoid_before
	if AIWatchdog and AIWatchdog.has_method("get_snapshot"):
		var after_snapshot := AIWatchdog.call("get_snapshot") as Dictionary
		collision_repath_after = int(after_snapshot.get("collision_repath_events_total", collision_repath_before))
		preavoid_after = int(after_snapshot.get("preavoid_events_total", preavoid_before))

	_t.run_test("direct move: preavoid detects wall hazard before contact", saw_preavoid_triggered)
	_t.run_test("direct move: preavoid can trigger forced repath", saw_preavoid_forced)
	_t.run_test("direct move: non-door collision against wall is prevented", not saw_non_door_collision)
	_t.run_test("direct move: policy_blocked feedback appears while halted", saw_policy_blocked)
	_t.run_test("direct move: collision_repath_events_total does not increment", collision_repath_after == collision_repath_before)
	_t.run_test("direct move: preavoid_events_total increments", preavoid_after > preavoid_before)
	_t.run_test(
		"direct move: no collision_blocked reason in snapshot",
		String(last_snapshot.get("path_failed_reason", "")) != "collision_blocked"
	)

	root.queue_free()
	await get_tree().physics_frame


func _test_patrol_intent_preavoid_prevents_wall_collision() -> void:
	var root := Node2D.new()
	add_child(root)
	TestHelpers.add_wall(root, Vector2.ZERO, Vector2(240.0, 16.0))
	var enemy := TestHelpers.spawn_mover(root, Vector2(0.0, 56.0), 1, 1, "enemies")
	var nav := FakeNav.new()
	root.add_child(nav)

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(enemy, null, 2.4)
	pursuit.configure_navigation(nav, 0)
	var patrol_target := Vector2(0.0, -120.0)
	pursuit.set("_patrol", FakePatrolDecision.new(patrol_target, 1.0))
	var patrol_collision_repath_before := 0
	var patrol_preavoid_before := 0
	if AIWatchdog and AIWatchdog.has_method("debug_reset_metrics_for_tests"):
		AIWatchdog.call("debug_reset_metrics_for_tests")
	if AIWatchdog and AIWatchdog.has_method("get_snapshot"):
		var before_snapshot := AIWatchdog.call("get_snapshot") as Dictionary
		patrol_collision_repath_before = int(before_snapshot.get("patrol_collision_repath_events_total", 0))
		patrol_preavoid_before = int(before_snapshot.get("patrol_preavoid_events_total", 0))

	await get_tree().process_frame
	await get_tree().physics_frame

	var saw_preavoid_triggered := false
	var saw_preavoid_forced := false
	var saw_non_door_collision := false
	var saw_policy_blocked := false
	var exec_result: Dictionary = {}
	var last_snapshot: Dictionary = {}
	for _i in range(180):
		exec_result = pursuit.execute_intent(
			1.0 / 60.0,
			{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL},
			_patrol_context(patrol_target)
		) as Dictionary
		last_snapshot = pursuit.debug_get_navigation_policy_snapshot() as Dictionary
		if bool(last_snapshot.get("preavoid_triggered", false)):
			saw_preavoid_triggered = true
		if bool(last_snapshot.get("preavoid_forced_repath", false)):
			saw_preavoid_forced = true
		if String(last_snapshot.get("collision_kind", "")) == "non_door":
			saw_non_door_collision = true
		if bool(last_snapshot.get("policy_blocked", false)):
			saw_policy_blocked = true
		await get_tree().physics_frame

	var patrol_collision_repath_after := patrol_collision_repath_before
	var patrol_preavoid_after := patrol_preavoid_before
	if AIWatchdog and AIWatchdog.has_method("get_snapshot"):
		var after_snapshot := AIWatchdog.call("get_snapshot") as Dictionary
		patrol_collision_repath_after = int(after_snapshot.get("patrol_collision_repath_events_total", patrol_collision_repath_before))
		patrol_preavoid_after = int(after_snapshot.get("patrol_preavoid_events_total", patrol_preavoid_before))

	_t.run_test("patrol intent: preavoid detects wall hazard before contact", saw_preavoid_triggered)
	_t.run_test("patrol intent: preavoid can trigger forced repath", saw_preavoid_forced)
	_t.run_test("patrol intent: non-door collision against wall is prevented", not saw_non_door_collision)
	_t.run_test("patrol intent: policy_blocked feedback appears while halted", saw_policy_blocked)
	_t.run_test(
		"patrol intent: patrol_collision_repath_events_total does not increment",
		patrol_collision_repath_after == patrol_collision_repath_before
	)
	_t.run_test(
		"patrol intent: patrol_preavoid_events_total increments",
		patrol_preavoid_after > patrol_preavoid_before
	)
	_t.run_test(
		"patrol intent: no collision_blocked reason in execute result",
		String(exec_result.get("path_failed_reason", "")) != "collision_blocked"
	)

	root.queue_free()
	await get_tree().physics_frame


func _patrol_context(player_pos: Vector2) -> Dictionary:
	return {
		"player_pos": player_pos,
		"known_target_pos": Vector2.ZERO,
		"last_seen_pos": Vector2.ZERO,
		"investigate_anchor": Vector2.ZERO,
		"home_position": Vector2.ZERO,
		"alert_level": 0,
		"los": false,
		"combat_lock": false,
	}
