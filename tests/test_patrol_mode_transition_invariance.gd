extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeDetourNav:
	extends Node

	var plan_calls: int = 0

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func can_enemy_traverse_point(_enemy: Node, _point: Vector2) -> bool:
		return true

	func build_policy_valid_path(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		plan_calls += 1
		return {
			"status": "ok",
			"path_points": [
				Vector2(56.0, 74.0),
				Vector2(168.0, 74.0),
				to_pos,
			],
			"reason": "ok",
		}


class FakePatrolDecision:
	extends RefCounted

	var fixed_target: Vector2 = Vector2.ZERO

	func _init(target: Vector2) -> void:
		fixed_target = target

	func configure(_nav_system: Node, _home_room_id: int) -> void:
		pass

	func update(_delta: float, _facing_dir: Vector2) -> Dictionary:
		return {
			"waiting": false,
			"target": fixed_target,
			"speed_scale": 1.0,
		}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("PATROL MODE TRANSITION INVARIANCE TEST")
	print("============================================================")

	await _test_calm_patrol_to_alert_combat_keeps_intent_contracts()

	_t.summary("PATROL MODE TRANSITION INVARIANCE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_calm_patrol_to_alert_combat_keeps_intent_contracts() -> void:
	var root := Node2D.new()
	add_child(root)
	TestHelpers.add_wall(root, Vector2(100.0, 0.0), Vector2(24.0, 200.0))
	var enemy := TestHelpers.spawn_mover(root, Vector2(0.0, 0.0), 1, 1, "enemies")
	var nav := FakeDetourNav.new()
	root.add_child(nav)

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(enemy, null, 2.4)
	pursuit.configure_navigation(nav, 0)
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()

	var target := Vector2(220.0, 0.0)
	pursuit.set("_patrol", FakePatrolDecision.new(target))

	await get_tree().process_frame
	await get_tree().physics_frame

	var calm_brain_ctx := _brain_ctx({
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.CALM,
		"los": false,
		"player_pos": target,
		"known_target_pos": target,
		"home_position": Vector2.ZERO,
	})
	var calm_intent := brain.update(1.0, calm_brain_ctx)
	var calm_exec := pursuit.execute_intent(
		1.0 / 60.0,
		calm_intent,
		_pursuit_ctx(target, ENEMY_ALERT_LEVELS_SCRIPT.CALM, false, false, target, Vector2.ZERO)
	) as Dictionary
	await get_tree().physics_frame

	var alert_brain_ctx := _brain_ctx({
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.ALERT,
		"los": false,
		"player_pos": target,
		"known_target_pos": target,
		"has_known_target": true,
		"has_last_seen": true,
		"last_seen_age": 1.0,
		"last_seen_pos": target,
		"dist_to_last_seen": 160.0,
	})
	var alert_intent := brain.update(1.0, alert_brain_ctx)
	var alert_exec := pursuit.execute_intent(
		1.0 / 60.0,
		alert_intent,
		_pursuit_ctx(target, ENEMY_ALERT_LEVELS_SCRIPT.ALERT, false, false, target, target)
	) as Dictionary
	await get_tree().physics_frame

	var combat_brain_ctx := _brain_ctx({
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.COMBAT,
		"combat_lock": true,
		"los": false,
		"player_pos": target,
		"known_target_pos": target,
		"has_known_target": true,
		"has_last_seen": true,
		"last_seen_age": 1.2,
		"last_seen_pos": target,
		"dist_to_last_seen": 140.0,
	})
	var combat_intent := brain.update(1.0, combat_brain_ctx)
	var combat_exec := pursuit.execute_intent(
		1.0 / 60.0,
		combat_intent,
		_pursuit_ctx(target, ENEMY_ALERT_LEVELS_SCRIPT.COMBAT, false, true, target, target)
	) as Dictionary
	await get_tree().physics_frame

	var final_snapshot := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
	var alert_type := int(alert_intent.get("type", -1))
	var combat_type := int(combat_intent.get("type", -1))

	_t.run_test(
		"mode transition invariance: CALM context starts in PATROL",
		int(calm_intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL
	)
	_t.run_test(
		"mode transition invariance: ALERT context does not fall back to PATROL",
		alert_type != ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL
	)
	_t.run_test(
		"mode transition invariance: COMBAT context does not fall back to PATROL",
		combat_type != ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL
	)
	_t.run_test(
		"mode transition invariance: COMBAT no-LOS intent resolves to PUSH",
		combat_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH
	)
	_t.run_test(
		"mode transition invariance: execute_intent remains movement-capable across transitions",
		bool(calm_exec.get("movement_intent", false))
			and bool(alert_exec.get("movement_intent", false))
			and bool(combat_exec.get("movement_intent", false))
	)
	_t.run_test(
		"mode transition invariance: plan id remains monotonic after intent transitions",
		int(alert_exec.get("plan_id", 0)) > int(calm_exec.get("plan_id", -1))
			and int(combat_exec.get("plan_id", 0)) > int(alert_exec.get("plan_id", -1))
	)
	_t.run_test(
		"mode transition invariance: shared path planning contract remains ok in final snapshot",
		String(final_snapshot.get("path_plan_status", "")) == "ok"
	)
	_t.run_test("mode transition invariance: planner participates across transitions", nav.plan_calls >= 1)

	root.queue_free()
	await get_tree().physics_frame


func _brain_ctx(override: Dictionary) -> Dictionary:
	var base := {
		"dist": 220.0,
		"los": false,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.CALM,
		"combat_lock": false,
		"last_seen_age": INF,
		"last_seen_pos": Vector2.ZERO,
		"has_last_seen": false,
		"dist_to_last_seen": INF,
		"role": 0,
		"slot_position": Vector2.ZERO,
		"dist_to_slot": INF,
		"hp_ratio": 1.0,
		"path_ok": false,
		"has_slot": false,
		"player_pos": Vector2.ZERO,
		"known_target_pos": Vector2.ZERO,
		"has_known_target": false,
		"home_position": Vector2.ZERO,
		"investigate_anchor": Vector2.ZERO,
		"has_investigate_anchor": false,
		"dist_to_investigate_anchor": INF,
		"target_is_last_seen": false,
		"has_shadow_scan_target": false,
		"shadow_scan_target": Vector2.ZERO,
		"shadow_scan_target_in_shadow": false,
		"shadow_scan_completed": false,
		"shadow_scan_completed_reason": "none",
	}
	for key_variant in override.keys():
		base[key_variant] = override[key_variant]
	return base


func _pursuit_ctx(
	player_pos: Vector2,
	alert_level: int,
	los: bool,
	combat_lock: bool,
	known_target_pos: Vector2,
	last_seen_pos: Vector2
) -> Dictionary:
	return {
		"player_pos": player_pos,
		"known_target_pos": known_target_pos,
		"last_seen_pos": last_seen_pos,
		"investigate_anchor": Vector2.ZERO,
		"home_position": Vector2.ZERO,
		"alert_level": alert_level,
		"los": los,
		"dist": 220.0,
		"combat_lock": combat_lock,
	}
