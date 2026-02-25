extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeContractNav:
	extends Node

	var mode: String = "ok"
	var plan_calls: int = 0
	var blocked_point: Vector2 = Vector2(96.0, 0.0)

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func can_enemy_traverse_point(_enemy: Node, _point: Vector2) -> bool:
		return true

	func build_policy_valid_path(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		plan_calls += 1
		if mode == "blocked":
			return {
				"status": "unreachable_policy",
				"path_points": [],
				"reason": "policy_blocked",
				"segment_index": 0,
				"blocked_point": blocked_point,
			}
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
	print("PATROL UNIFIED MOVEMENT PIPELINE CONTRACT TEST")
	print("============================================================")

	await _test_patrol_invokes_policy_planner_and_snapshot_contract()
	await _test_patrol_and_push_share_blocked_path_failure_surface()

	_t.summary("PATROL UNIFIED MOVEMENT PIPELINE CONTRACT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_patrol_invokes_policy_planner_and_snapshot_contract() -> void:
	var fixture := await _spawn_fixture("ok")
	var root := fixture.get("root") as Node2D
	var pursuit = fixture.get("pursuit")
	var nav := fixture.get("nav") as FakeContractNav
	var target := Vector2(140.0, 0.0)
	pursuit.set("_patrol", FakePatrolDecision.new(target, 1.0))

	var result: Dictionary = {}
	for _i in range(8):
		result = pursuit.execute_intent(
			1.0 / 60.0,
			{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL},
			_patrol_context(target)
		) as Dictionary
		await get_tree().physics_frame

	var snapshot := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
	var has_contract_keys := (
		result.has("movement_intent")
		and result.has("path_failed")
		and result.has("path_failed_reason")
		and result.has("policy_blocked_segment")
	)
	var snapshot_surface_ok := (
		snapshot.has("path_plan_status")
		and snapshot.has("path_plan_reason")
		and snapshot.has("collision_kind")
		and snapshot.has("collision_forced_repath")
	)

	_t.run_test("patrol unified pipeline: planner invoked", nav.plan_calls > 0)
	_t.run_test("patrol unified pipeline: execute_intent result keeps movement/path failure keys", has_contract_keys)
	_t.run_test("patrol unified pipeline: debug snapshot keeps path/collision keys", snapshot_surface_ok)
	_t.run_test("patrol unified pipeline: path plan status becomes ok", String(snapshot.get("path_plan_status", "")) == "ok")

	root.queue_free()
	await get_tree().physics_frame


func _test_patrol_and_push_share_blocked_path_failure_surface() -> void:
	var fixture := await _spawn_fixture("blocked")
	var root := fixture.get("root") as Node2D
	var pursuit = fixture.get("pursuit")
	var target := Vector2(148.0, 0.0)
	pursuit.set("_patrol", FakePatrolDecision.new(target, 1.0))

	var patrol_result := pursuit.execute_intent(
		1.0 / 60.0,
		{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL},
		_patrol_context(target)
	) as Dictionary
	await get_tree().physics_frame
	var patrol_snapshot := pursuit.debug_get_navigation_policy_snapshot() as Dictionary

	var push_result := pursuit.execute_intent(
		1.0 / 60.0,
		{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH, "target": target},
		_push_context(target)
	) as Dictionary
	await get_tree().physics_frame
	var push_snapshot := pursuit.debug_get_navigation_policy_snapshot() as Dictionary

	_t.run_test(
		"patrol unified pipeline: PATROL blocked path returns policy_blocked",
		bool(patrol_result.get("path_failed", false))
			and String(patrol_result.get("path_failed_reason", "")) == "policy_blocked"
			and int(patrol_result.get("policy_blocked_segment", -1)) >= 0
	)
	_t.run_test(
		"patrol unified pipeline: PUSH blocked path returns same policy_blocked surface",
		bool(push_result.get("path_failed", false))
			and String(push_result.get("path_failed_reason", "")) == "policy_blocked"
			and int(push_result.get("policy_blocked_segment", -1)) >= 0
	)
	_t.run_test(
		"patrol unified pipeline: blocked plan snapshot exposes unreachable_policy + blocked_point",
		String(push_snapshot.get("path_plan_status", "")) == "unreachable_policy"
			and bool(push_snapshot.get("path_plan_blocked_point_valid", false))
	)
	_t.run_test(
		"patrol unified pipeline: plan id still advances across intent transitions",
		int(push_result.get("plan_id", 0)) > int(patrol_result.get("plan_id", -1))
	)
	_t.run_test(
		"patrol unified pipeline: collision snapshot keys remain present in blocked flow",
		patrol_snapshot.has("collision_kind") and push_snapshot.has("collision_kind")
	)

	root.queue_free()
	await get_tree().physics_frame


func _spawn_fixture(mode: String) -> Dictionary:
	var root := Node2D.new()
	add_child(root)
	var enemy := TestHelpers.spawn_mover(root, Vector2.ZERO, 1, 1, "enemies")
	var nav := FakeContractNav.new()
	nav.mode = mode
	root.add_child(nav)

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(enemy, null, 2.4)
	pursuit.configure_navigation(nav, 0)
	await get_tree().process_frame
	await get_tree().physics_frame

	return {
		"root": root,
		"enemy": enemy,
		"nav": nav,
		"pursuit": pursuit,
	}


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


func _push_context(player_pos: Vector2) -> Dictionary:
	return {
		"player_pos": player_pos,
		"known_target_pos": player_pos,
		"last_seen_pos": player_pos,
		"investigate_anchor": Vector2.ZERO,
		"home_position": Vector2.ZERO,
		"alert_level": 2,
		"los": true,
		"dist": 140.0,
		"combat_lock": true,
	}


func can_enemy_traverse_geometry_point(_enemy: Node, _point: Vector2) -> bool:
	return true
