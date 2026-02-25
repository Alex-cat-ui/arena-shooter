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

	func build_policy_valid_path(_from: Vector2, to: Vector2, _enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		return {
			"status": "ok",
			"path_points": [to],
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
	print("PATROL PREAVOID ANTI-JITTER CONTRACT TEST")
	print("============================================================")

	await _test_preavoid_side_does_not_flip_each_tick_and_progress_is_nonzero()

	_t.summary("PATROL PREAVOID ANTI-JITTER CONTRACT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_preavoid_side_does_not_flip_each_tick_and_progress_is_nonzero() -> void:
	var root := Node2D.new()
	add_child(root)

	# Narrow corridor
	TestHelpers.add_wall(root, Vector2(128.0, -64.0), Vector2(300.0, 16.0))
	TestHelpers.add_wall(root, Vector2(128.0, 64.0), Vector2(300.0, 16.0))
	# Obstacle near entry to force preavoid side choice.
	TestHelpers.add_wall(root, Vector2(84.0, 0.0), Vector2(18.0, 68.0))

	var enemy := TestHelpers.spawn_mover(root, Vector2(0.0, 0.0), 1, 1, "enemies")
	var nav := FakeNav.new()
	root.add_child(nav)

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(enemy, null, 2.4)
	pursuit.configure_navigation(nav, 0)
	var patrol_target := Vector2(236.0, 0.0)
	pursuit.set("_patrol", FakePatrolDecision.new(patrol_target))

	await get_tree().process_frame
	await get_tree().physics_frame

	var preavoid_side_triggers := 0
	var preavoid_triggered_total := 0
	var side_flips := 0
	var last_side := ""
	var moved_total := 0.0
	var max_step_px := 0.0
	var moving_frames := 0
	var stall_streak := 0
	var max_stall_streak := 0
	var prev_pos := enemy.global_position
	var initial_distance := enemy.global_position.distance_to(patrol_target)

	for _i in range(260):
		pursuit.execute_intent(
			1.0 / 60.0,
			{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL},
			_patrol_context(patrol_target)
		)
		await get_tree().physics_frame

		var current_pos := enemy.global_position
		var step_px := current_pos.distance_to(prev_pos)
		moved_total += step_px
		max_step_px = maxf(max_step_px, step_px)
		if step_px >= 0.12:
			moving_frames += 1
		if step_px < 0.08 and current_pos.distance_to(patrol_target) > 24.0:
			stall_streak += 1
		else:
			max_stall_streak = maxi(max_stall_streak, stall_streak)
			stall_streak = 0
		prev_pos = current_pos

		var snapshot := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
		if bool(snapshot.get("preavoid_triggered", false)):
			preavoid_triggered_total += 1
			var side := String(snapshot.get("preavoid_side", "none"))
			if side == "left" or side == "right":
				preavoid_side_triggers += 1
				if last_side != "" and side != last_side:
					side_flips += 1
				last_side = side

		if current_pos.distance_to(patrol_target) <= 20.0:
			break

	max_stall_streak = maxi(max_stall_streak, stall_streak)
	var final_distance := enemy.global_position.distance_to(patrol_target)
	var max_allowed_flips := maxi(1, int(floor(float(preavoid_side_triggers) / 3.0)))
	var side_flip_contract_ok := side_flips <= max_allowed_flips if preavoid_side_triggers > 1 else true

	_t.run_test("preavoid anti-jitter: preavoid trigger observed", preavoid_triggered_total > 0)
	_t.run_test("preavoid anti-jitter: side does not flip every tick when side-steering is used", side_flip_contract_ok)
	_t.run_test("preavoid anti-jitter: corridor run has non-zero progress", final_distance < initial_distance and moved_total > 24.0)
	_t.run_test("preavoid anti-jitter: movement dominates over zero-progress oscillation", moving_frames >= 30)
	_t.run_test("preavoid anti-jitter: no teleport spikes", max_step_px <= 24.0)

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


func can_enemy_traverse_geometry_point(_enemy: Node, _point: Vector2) -> bool:
	return true
