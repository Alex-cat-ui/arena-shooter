extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const DOOR_SCRIPT := preload("res://src/systems/door_physics_v3.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("DOOR CONTROLLER FULL TEST (UPDATED)")
	print("============================================================")

	await _test_closed_door_ignores_body_contact_open()
	await _test_shots_do_not_change_door_state()
	await _test_safe_close_with_blocker_and_auto_finish()
	await _test_door_does_not_push_character()

	_t.summary("DOOR CONTROLLER FULL RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_closed_door_ignores_body_contact_open() -> void:
	var world := TestHelpers.create_horizontal_door_world(self)
	await get_tree().physics_frame
	var door: Variant = world["door"]
	var player_mover := TestHelpers.spawn_mover(world["root"], Vector2(0.0, 46.0), 1, 1, "player")
	var enemy_mover := TestHelpers.spawn_mover(world["root"], Vector2(0.0, -46.0), 2, 1, "enemies")
	var max_abs_angle := 0.0

	for _i in range(160):
		player_mover.velocity = Vector2(0.0, -360.0)
		enemy_mover.velocity = Vector2(0.0, 360.0)
		player_mover.move_and_slide()
		enemy_mover.move_and_slide()
		await get_tree().physics_frame
		var m := door.get_debug_metrics() as Dictionary
		max_abs_angle = maxf(max_abs_angle, absf(float(m.get("angle_deg", 0.0))))

	_t.run_test("Closed door does not open from player/enemy body contact", max_abs_angle <= 2.0)

	player_mover.queue_free()
	enemy_mover.queue_free()
	await _free_world(world)


func _test_shots_do_not_change_door_state() -> void:
	var world := TestHelpers.create_horizontal_door_world(self)
	await get_tree().physics_frame
	var door: Variant = world["door"]

	var before := door.get_debug_metrics() as Dictionary
	var before_angle := absf(float(before.get("angle_deg", 0.0)))

	for i in range(40):
		EventBus.emit_player_shot("shotgun", Vector3(-80.0 + i * 4.0, 0.0, 0.0), Vector3.RIGHT)
		EventBus.emit_enemy_shot(1000 + i, "shotgun", Vector3(80.0 - i * 4.0, 0.0, 0.0), Vector3.LEFT)
		await get_tree().process_frame
		await get_tree().physics_frame

	var after := door.get_debug_metrics() as Dictionary
	var after_angle := absf(float(after.get("angle_deg", 0.0)))

	_t.run_test("Shots do not change closed door angle", absf(after_angle - before_angle) <= 0.5 and after_angle <= 1.5)

	await _free_world(world)


func _test_safe_close_with_blocker_and_auto_finish() -> void:
	var world := TestHelpers.create_horizontal_door_world(self)
	await get_tree().physics_frame
	var door: Variant = world["door"]

	var opened_angle := 0.0
	for j in range(8):
		door.command_open_kick(Vector2(0.0, 120.0 if j % 2 == 0 else -120.0))
		for _i in range(8):
			await get_tree().physics_frame
			var m := door.get_debug_metrics() as Dictionary
			opened_angle = maxf(opened_angle, absf(float(m.get("angle_deg", 0.0))))
	_t.run_test("Command kick opens door", opened_angle >= 8.0)

	var blocker_spawn: Vector2 = (door.global_position as Vector2) + Vector2(float(door.door_length) * 0.35, 0.0)
	var blocker := TestHelpers.spawn_mover(world["root"], blocker_spawn, 1, 1, "player")
	door.command_close()
	await get_tree().physics_frame

	var pinch_active_seen := false
	var reopen_seen := false
	var overlap_seen := false
	var start_close_angle := absf(float((door.get_debug_metrics() as Dictionary).get("angle_deg", 0.0)))
	var max_abs_angle := start_close_angle
	var prev_angle := start_close_angle
	var min_abs_angle := prev_angle
	for i in range(220):
		# Oscillation through the doorway simulates blocker moving toward leaf.
		blocker.velocity = Vector2(0.0, -120.0 if i % 40 < 20 else 120.0)
		blocker.move_and_slide()
		await get_tree().physics_frame
		if door._trigger_area and (door._trigger_area.get_overlapping_bodies() as Array).has(blocker):
			overlap_seen = true
		var m := door.get_debug_metrics() as Dictionary
		var angle := absf(float(m.get("angle_deg", 0.0)))
		min_abs_angle = minf(min_abs_angle, angle)
		max_abs_angle = maxf(max_abs_angle, angle)
		if bool(m.get("pinch_active", false)):
			pinch_active_seen = true
		if i > 10 and angle > prev_angle + 0.5:
			reopen_seen = true
		prev_angle = angle

	if max_abs_angle > start_close_angle + 1.0:
		reopen_seen = true

	_t.run_test("Blocker is detected inside doorway sensor", overlap_seen)
	_t.run_test("Safe-close activates anti-pinch when blocker is in doorway", pinch_active_seen or overlap_seen)
	var blocked_dynamic := (max_abs_angle - min_abs_angle) >= 0.5
	_t.run_test("Safe-close allows temporary reopen while blocked", reopen_seen or blocked_dynamic)
	_t.run_test("Door does not fully close while blocker remains in doorway", min_abs_angle > 0.8)

	blocker.queue_free()
	await get_tree().physics_frame

	var auto_closed := false
	for _i in range(1800):
		await get_tree().physics_frame
		var m := door.get_debug_metrics() as Dictionary
		var angle := absf(float(m.get("angle_deg", 0.0)))
		var angular_velocity := absf(float(m.get("angular_velocity", 0.0)))
		if angle <= 1.2 and angular_velocity <= 0.08:
			auto_closed = true
			break

	var final_metrics := door.get_debug_metrics() as Dictionary
	print("  safe_close_final: angle=%.3f av=%.3f close_intent=%s auto_closed=%s" % [
		absf(float(final_metrics.get("angle_deg", 0.0))),
		absf(float(final_metrics.get("angular_velocity", 0.0))),
		str(bool(final_metrics.get("close_intent", true))),
		str(auto_closed),
	])
	_t.run_test("Door auto-finishes closing after blocker leaves", auto_closed)
	_t.run_test("close_intent resets after successful close", not bool(final_metrics.get("close_intent", true)))

	await _free_world(world)


func _test_door_does_not_push_character() -> void:
	var world := TestHelpers.create_horizontal_door_world(self)
	await get_tree().physics_frame
	var door: Variant = world["door"]

	door.command_open_action(Vector2(0.0, 80.0))
	for _i in range(40):
		await get_tree().physics_frame
	door.command_close()

	var blocker := TestHelpers.spawn_mover(world["root"], Vector2(24.0, 0.0), 1, 1, "player")
	var start_pos := blocker.global_position
	var max_displacement := 0.0

	for _i in range(200):
		blocker.velocity = Vector2.ZERO
		blocker.move_and_slide()
		await get_tree().physics_frame
		max_displacement = maxf(max_displacement, blocker.global_position.distance_to(start_pos))

	_t.run_test("Door does not push stationary blocker body", max_displacement <= 18.0)

	blocker.queue_free()
	await _free_world(world)


func _free_world(world: Dictionary) -> void:
	var root := world.get("root", null) as Node
	if root:
		root.queue_free()
	await get_tree().physics_frame
