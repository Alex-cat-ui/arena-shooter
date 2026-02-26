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
	print("PATROL PREAVOID TRIGGERS BEFORE COLLISION TEST")
	print("============================================================")

	await _test_preavoid_triggers_before_non_door_collision()

	_t.summary("PATROL PREAVOID TRIGGERS BEFORE COLLISION RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_preavoid_triggers_before_non_door_collision() -> void:
	var root := Node2D.new()
	add_child(root)
	TestHelpers.add_wall(root, Vector2(92.0, 0.0), Vector2(20.0, 220.0))
	var enemy := TestHelpers.spawn_mover(root, Vector2(0.0, 0.0), 1, 1, "enemies")
	var nav := FakeNav.new()
	root.add_child(nav)

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(enemy, null, 2.4)
	pursuit.configure_navigation(nav, 0)
	var patrol_target := Vector2(220.0, 0.0)
	pursuit.set("_patrol", FakePatrolDecision.new(patrol_target))

	await get_tree().process_frame
	await get_tree().physics_frame

	var preavoid_tick := -1
	var collision_tick := -1
	var preavoid_non_door_forced := false
	var preavoid_side_contract_ok := true
	var initial_distance := enemy.global_position.distance_to(patrol_target)
	var final_snapshot: Dictionary = {}

	for i in range(220):
		pursuit.execute_intent(
			1.0 / 60.0,
			{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL},
			_patrol_context(patrol_target)
		)
		await get_tree().physics_frame
		var snapshot := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
		final_snapshot = snapshot
		if preavoid_tick < 0 and bool(snapshot.get("preavoid_triggered", false)):
			preavoid_tick = i
		if bool(snapshot.get("preavoid_triggered", false)) and String(snapshot.get("preavoid_kind", "")) == "non_door":
			preavoid_non_door_forced = preavoid_non_door_forced or bool(snapshot.get("preavoid_forced_repath", false))
			var side := String(snapshot.get("preavoid_side", "none"))
			preavoid_side_contract_ok = preavoid_side_contract_ok and (
				side == "none" or side == "left" or side == "right"
			)
		if collision_tick < 0 and String(snapshot.get("collision_kind", "")) == "non_door":
			collision_tick = i
		if enemy.global_position.distance_to(patrol_target) <= 20.0:
			break

	var final_distance := enemy.global_position.distance_to(patrol_target)
	_t.run_test(
		"preavoid collision: non-door preavoid trigger observed",
		preavoid_tick >= 0 and preavoid_non_door_forced
	)
	_t.run_test(
		"preavoid collision: trigger occurs before (or without) physical non-door collision",
		preavoid_tick >= 0 and (collision_tick < 0 or preavoid_tick <= collision_tick)
	)
	_t.run_test(
		"preavoid collision: side contract remains stable",
		preavoid_side_contract_ok
	)
	_t.run_test(
		"preavoid collision: patrol still makes path progress",
		final_distance < initial_distance
	)
	_t.run_test(
		"preavoid collision: snapshot keys are present",
		final_snapshot.has("preavoid_triggered")
			and final_snapshot.has("preavoid_kind")
			and final_snapshot.has("preavoid_forced_repath")
			and final_snapshot.has("preavoid_side")
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
