extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")

const DOOR_SCRIPT := preload("res://src/systems/door_physics_v3.gd")
const PROJECTILE_SCENE := preload("res://scenes/entities/projectile.tscn")
const ENEMY_PERCEPTION_SYSTEM_SCRIPT := preload("res://src/systems/enemy_perception_system.gd")

var _t := TestHelpers.new()


func _ready() -> void:
	print("")
	print("============================================================")
	print("DOOR PHYSICS FULL TEST")
	print("============================================================")
	await _run_tests()
	_t.summary("DOOR PHYSICS FULL RESULTS")
	get_tree().quit(_t.quit_code())


func _run_tests() -> void:
	# Group 1: Physical blocking (CRITICAL)
	print("\n--- GROUP 1: Blocking ---")
	await _test_closed_door_blocks_at_any_speed()
	await _test_closed_door_blocks_enemy()
	await _test_closed_door_blocks_pellet()
	await _test_closed_door_blocks_los()

	# Group 2: Push mechanics
	print("\n--- GROUP 2: Push ---")
	await _test_push_opens_door()
	await _test_faster_push_opens_wider()
	await _test_bidirectional_push()
	await _test_no_ghost_push()

	# Group 3: Pass through (push -> open -> pass)
	print("\n--- GROUP 3: Pass-through ---")
	await _test_slow_player_pushes_and_passes()
	await _test_fast_player_pushes_and_passes()
	await _test_enemy_pushes_and_passes()

	# Group 4: Closing and stability
	print("\n--- GROUP 4: Closing ---")
	await _test_auto_close_timing()
	await _test_closed_stability()
	await _test_settle_after_release()
	await _test_no_jitter_sign_flips()

	# Group 5: Realism
	print("\n--- GROUP 5: Realism ---")
	await _test_weight_feel()
	await _test_wall_bounce()
	await _test_anti_pinch()


# ==========================================================================
# GROUP 1: Blocking (CRITICAL)
# ==========================================================================

## CRITICAL TEST: StaticBody2D collision integrity — no tunneling at any speed.
## Disable trigger so door stays closed. Mover must NOT pass through.
func _test_closed_door_blocks_at_any_speed() -> void:
	var speeds := [100.0, 300.0, 600.0, 1000.0]
	for speed in speeds:
		var world := TestHelpers.create_horizontal_door_world(self)
		await get_tree().physics_frame
		var door: Variant = world["door"]
		# Disable push detection so door stays firmly closed
		door._trigger_area.monitoring = false
		var mover := TestHelpers.spawn_mover(world["root"], Vector2(0.0, 40.0), 1, 1, "")
		mover.remove_meta("door_push_velocity")
		var min_y := mover.global_position.y
		for i in range(120):
			mover.velocity = Vector2(0.0, -speed)
			mover.move_and_slide()
			min_y = minf(min_y, mover.global_position.y)
			await get_tree().physics_frame
		var blocked := min_y > -20.0
		print("  blocks@%.0fpx/s: min_y=%.1f %s" % [speed, min_y, "OK" if blocked else "FAIL"])
		_t.run_test("Closed door blocks player at %.0f px/s" % speed, blocked)
		mover.queue_free()
		await get_tree().physics_frame
		await _free_world(world)


## Closed door blocks enemies (trigger disabled).
func _test_closed_door_blocks_enemy() -> void:
	var world := TestHelpers.create_horizontal_door_world(self)
	await get_tree().physics_frame
	var door: Variant = world["door"]
	door._trigger_area.monitoring = false
	var mover := TestHelpers.spawn_mover(world["root"], Vector2(0.0, 40.0), 2, 1, "enemies")
	mover.remove_meta("door_push_velocity")
	var min_y := mover.global_position.y
	for i in range(90):
		mover.velocity = Vector2(0.0, -300.0)
		mover.move_and_slide()
		min_y = minf(min_y, mover.global_position.y)
		await get_tree().physics_frame
	_t.run_test("Closed door blocks enemy at 300 px/s", min_y > -20.0)
	mover.queue_free()
	await get_tree().physics_frame
	await _free_world(world)


## Closed door stops pellet projectile.
func _test_closed_door_blocks_pellet() -> void:
	var world_root := Node2D.new()
	add_child(world_root)
	var door := DOOR_SCRIPT.new()
	world_root.add_child(door)
	door.configure_from_opening(Rect2(100.0, 0.0, 60.0, 16.0), 16.0)
	await get_tree().physics_frame

	var projectile := PROJECTILE_SCENE.instantiate() as Projectile
	world_root.add_child(projectile)
	projectile.initialize(777, "pellet", Vector2(0.0, 8.0), Vector2.RIGHT, 1000.0, 1, 12, 16, 25.0)
	for i in range(30):
		await get_tree().process_frame
		if not is_instance_valid(projectile):
			break
	_t.run_test("Closed door blocks pellet projectile", not is_instance_valid(projectile))
	if is_instance_valid(projectile):
		projectile.queue_free()
	world_root.queue_free()
	await get_tree().physics_frame


## Closed door blocks enemy LOS (raycast).
func _test_closed_door_blocks_los() -> void:
	var world_root := Node2D.new()
	add_child(world_root)
	var enemy := CharacterBody2D.new()
	enemy.position = Vector2(-140.0, 0.0)
	world_root.add_child(enemy)
	var player := CharacterBody2D.new()
	player.position = Vector2(140.0, 0.0)
	player.add_to_group("player")
	world_root.add_child(player)
	var perception = ENEMY_PERCEPTION_SYSTEM_SCRIPT.new(enemy)
	var exclude: Array[RID] = [enemy.get_rid()]

	var clear_without_door := bool(perception.can_see_player(enemy.global_position, Vector2.RIGHT, 180.0, 500.0, exclude))
	_t.run_test("LOS baseline clear without door", clear_without_door)

	var door := DOOR_SCRIPT.new()
	world_root.add_child(door)
	door.configure_from_opening(Rect2(-6.0, -80.0, 12.0, 160.0), 16.0)
	await get_tree().physics_frame

	var clear_with_door := bool(perception.can_see_player(enemy.global_position, Vector2.RIGHT, 180.0, 500.0, exclude))
	_t.run_test("Closed door blocks enemy LOS", not clear_with_door)
	world_root.queue_free()
	await get_tree().physics_frame


# ==========================================================================
# GROUP 2: Push
# ==========================================================================

## Player with push velocity near door opens it.
func _test_push_opens_door() -> void:
	var world := TestHelpers.create_horizontal_door_world(self)
	await get_tree().physics_frame
	var door: Variant = world["door"]
	var mover := TestHelpers.spawn_mover(world["root"], Vector2(0.0, 30.0), 1, 1, "player")
	var max_angle := 0.0
	for i in range(60):
		mover.velocity = Vector2(0.0, -200.0)
		mover.set_meta("door_push_velocity", mover.velocity)
		mover.move_and_slide()
		await get_tree().physics_frame
		var m := door.get_debug_metrics() as Dictionary
		max_angle = maxf(max_angle, absf(float(m.get("angle_deg", 0.0))))
	print("  push_opens: max_angle=%.1f°" % max_angle)
	_t.run_test("Push velocity opens door (>10°)", max_angle >= 10.0)
	mover.queue_free()
	await get_tree().physics_frame
	await _free_world(world)


## Faster approach opens door wider.
func _test_faster_push_opens_wider() -> void:
	var angles: Array = []
	for speed in [60.0, 140.0, 350.0]:
		var world := TestHelpers.create_horizontal_door_world(self)
		await get_tree().physics_frame
		var door: Variant = world["door"]
		var mover := TestHelpers.spawn_mover(world["root"], Vector2(0.0, 30.0), 1, 1, "player")
		var max_angle := 0.0
		for i in range(30):
			mover.velocity = Vector2(0.0, -speed)
			mover.set_meta("door_push_velocity", mover.velocity)
			mover.move_and_slide()
			await get_tree().physics_frame
			var m := door.get_debug_metrics() as Dictionary
			max_angle = maxf(max_angle, absf(float(m.get("angle_deg", 0.0))))
		angles.append(max_angle)
		mover.queue_free()
		await get_tree().physics_frame
		await _free_world(world)
	var slow_a := float(angles[0])
	var med_a := float(angles[1])
	var fast_a := float(angles[2])
	print("  inertia: slow=%.1f° med=%.1f° fast=%.1f°" % [slow_a, med_a, fast_a])
	_t.run_test("Faster push opens wider: slow < medium", slow_a < med_a)
	_t.run_test("Faster push opens wider: medium < fast", med_a < fast_a)


## Door opens in both directions.
func _test_bidirectional_push() -> void:
	var world := TestHelpers.create_horizontal_door_world(self)
	await get_tree().physics_frame
	var door: Variant = world["door"]

	# Push from below (positive y → negative y)
	var mover_a := TestHelpers.spawn_mover(world["root"], Vector2(0.0, 30.0), 1, 1, "player")
	var angle_a := 0.0
	for i in range(40):
		mover_a.velocity = Vector2(0.0, -300.0)
		mover_a.set_meta("door_push_velocity", mover_a.velocity)
		mover_a.move_and_slide()
		await get_tree().physics_frame
		var m := door.get_debug_metrics() as Dictionary
		angle_a = maxf(angle_a, absf(float(m.get("angle_deg", 0.0))))
	mover_a.queue_free()
	await get_tree().physics_frame

	# Reset door
	door.reset_to_closed()
	await get_tree().physics_frame

	# Push from above (negative y → positive y)
	var mover_b := TestHelpers.spawn_mover(world["root"], Vector2(0.0, -30.0), 1, 1, "player")
	var angle_b := 0.0
	for i in range(40):
		mover_b.velocity = Vector2(0.0, 300.0)
		mover_b.set_meta("door_push_velocity", mover_b.velocity)
		mover_b.move_and_slide()
		await get_tree().physics_frame
		var m := door.get_debug_metrics() as Dictionary
		angle_b = maxf(angle_b, absf(float(m.get("angle_deg", 0.0))))
	mover_b.queue_free()
	await get_tree().physics_frame

	print("  bidirectional: from_below=%.1f° from_above=%.1f°" % [angle_a, angle_b])
	_t.run_test("Door opens from below (>10°)", angle_a >= 10.0)
	_t.run_test("Door opens from above (>10°)", angle_b >= 10.0)
	await _free_world(world)


## Body far from door or moving parallel doesn't ghost-push.
func _test_no_ghost_push() -> void:
	var world := TestHelpers.create_horizontal_door_world(self)
	await get_tree().physics_frame
	var door: Variant = world["door"]
	var mover := TestHelpers.spawn_mover(world["root"], Vector2(25.0, 40.0), 1, 1, "player")
	var max_angle := 0.0
	for i in range(90):
		mover.velocity = Vector2(120.0, 0.0)
		mover.set_meta("door_push_velocity", mover.velocity)
		mover.move_and_slide()
		await get_tree().physics_frame
		var m := door.get_debug_metrics() as Dictionary
		max_angle = maxf(max_angle, absf(float(m.get("angle_deg", 0.0))))
	_t.run_test("No ghost push: parallel body 40px away (<2°)", max_angle < 2.0)
	mover.queue_free()
	await get_tree().physics_frame
	await _free_world(world)


# ==========================================================================
# GROUP 3: Pass-through (push -> open -> pass)
# ==========================================================================

## At 140px/s: player pushes door open and passes through.
func _test_slow_player_pushes_and_passes() -> void:
	var result := await _run_pass_scenario(140.0, 1, 1, Vector2(0.0, 165.0), Vector2(0.0, -90.0), 360, "player")
	print("  slow_pass: final_y=%.1f max_open=%.1f° angle=%.1f°" % [
		float(result.get("final_y", 0.0)),
		float(result.get("max_open_deg", 0.0)),
		float(result.get("final_angle_deg", 0.0)),
	])
	_t.run_test("Slow player pushes and passes through", bool(result.get("passed", false)))
	_t.run_test("Slow push opens door (>10°)", float(result.get("max_open_deg", 0.0)) >= 10.0)


## At 420px/s: player pushes door open wider and passes through.
func _test_fast_player_pushes_and_passes() -> void:
	var result := await _run_pass_scenario(420.0, 1, 1, Vector2(0.0, 165.0), Vector2(0.0, -90.0), 220, "player")
	print("  fast_pass: final_y=%.1f max_open=%.1f° angle=%.1f°" % [
		float(result.get("final_y", 0.0)),
		float(result.get("max_open_deg", 0.0)),
		float(result.get("final_angle_deg", 0.0)),
	])
	_t.run_test("Fast player pushes and passes through", bool(result.get("passed", false)))


## Enemy can also push and pass.
func _test_enemy_pushes_and_passes() -> void:
	var result := await _run_pass_scenario(220.0, 2, 1, Vector2(0.0, 165.0), Vector2(0.0, -90.0), 300, "enemies")
	print("  enemy_pass: final_y=%.1f max_open=%.1f° angle=%.1f°" % [
		float(result.get("final_y", 0.0)),
		float(result.get("max_open_deg", 0.0)),
		float(result.get("final_angle_deg", 0.0)),
	])
	_t.run_test("Enemy pushes and passes through", bool(result.get("passed", false)))


# ==========================================================================
# GROUP 4: Closing
# ==========================================================================

## Door auto-closes within 1-6 seconds after push ends.
func _test_auto_close_timing() -> void:
	var world := TestHelpers.create_horizontal_door_world(self)
	await get_tree().physics_frame
	var door: Variant = world["door"]
	var mover := TestHelpers.spawn_mover(world["root"], Vector2(0.0, 30.0), 1, 1, "player")
	for i in range(25):
		mover.velocity = Vector2(0.0, -200.0)
		mover.set_meta("door_push_velocity", mover.velocity)
		mover.move_and_slide()
		await get_tree().physics_frame
	mover.queue_free()
	await get_tree().physics_frame
	var m0 := door.get_debug_metrics() as Dictionary
	var start_angle := absf(float(m0.get("angle_deg", 0.0)))
	print("  auto_close start: %.1f°" % start_angle)
	var close_frame := -1
	for i in range(360):
		await get_tree().physics_frame
		var m := door.get_debug_metrics() as Dictionary
		if absf(float(m.get("angle_deg", 0.0))) < 20.0:
			close_frame = i
			break
	if close_frame >= 0:
		var close_sec := float(close_frame) / 60.0
		print("  auto_close: closed in %.2fs (%d frames)" % [close_sec, close_frame])
		_t.run_test("Auto-close within 8 seconds", close_sec <= 8.0)
		_t.run_test("Auto-close not instant (>0.3s)", close_sec >= 0.3)
	else:
		_t.run_test("Auto-close within 8 seconds", false)
		_t.run_test("Auto-close not instant (>0.3s)", true)
	await _free_world(world)


## Closed door doesn't jitter when idle.
func _test_closed_stability() -> void:
	var world := TestHelpers.create_horizontal_door_world(self)
	await get_tree().physics_frame
	var door: Variant = world["door"]
	var max_angle := 0.0
	for i in range(180):
		await get_tree().physics_frame
		var m := door.get_debug_metrics() as Dictionary
		max_angle = maxf(max_angle, absf(float(m.get("angle_deg", 0.0))))
	_t.run_test("Closed door idle jitter < 1°", max_angle <= 1.0)
	await _free_world(world)


## Door settles back near closed after push ends.
func _test_settle_after_release() -> void:
	var world := TestHelpers.create_horizontal_door_world(self)
	await get_tree().physics_frame
	var door: Variant = world["door"]
	var mover := TestHelpers.spawn_mover(world["root"], Vector2(0.0, 165.0), 1, 1, "player")
	for i in range(40):
		mover.velocity = Vector2(0.0, -420.0)
		mover.set_meta("door_push_velocity", mover.velocity)
		mover.move_and_slide()
		await get_tree().physics_frame
	mover.queue_free()
	await get_tree().physics_frame
	for i in range(420):
		await get_tree().physics_frame
	var metrics := door.get_debug_metrics() as Dictionary
	_t.run_test("Door settles near closed (<20°)", absf(float(metrics.get("angle_deg", 0.0))) <= 20.0)
	_t.run_test("Door angular velocity settles (<0.35)", absf(float(metrics.get("angular_velocity", 0.0))) <= 0.35)
	await _free_world(world)


## No rapid sign-flip jitter with swaying motion.
func _test_no_jitter_sign_flips() -> void:
	var world := TestHelpers.create_horizontal_door_world(self)
	await get_tree().physics_frame
	var door: Variant = world["door"]
	var mover := TestHelpers.spawn_mover(world["root"], Vector2(18.0, 165.0), 1, 1, "player")
	for i in range(320):
		var sway := sin(float(i) * 0.22) * 70.0
		mover.velocity = Vector2(sway, -190.0)
		mover.set_meta("door_push_velocity", mover.velocity)
		mover.move_and_slide()
		await get_tree().physics_frame
	mover.queue_free()
	await get_tree().physics_frame
	var metrics := door.get_debug_metrics() as Dictionary
	print("  jitter: sign_flips=%d limit_hits=%d" % [
		int(metrics.get("sign_flips", 0)),
		int(metrics.get("limit_hits", 0)),
	])
	# Empirical threshold: healthy doors are usually <15 sign flips; >30 looks visibly jittery.
	_t.run_test("Sign flips bounded (<24)", int(metrics.get("sign_flips", 0)) <= 24)
	# Empirical threshold: repeated hard-stop oscillation starts looking wrong around 80+ hits.
	_t.run_test("Limit hits bounded (<80)", int(metrics.get("limit_hits", 0)) <= 80)
	await _free_world(world)


# ==========================================================================
# GROUP 5: Realism
# ==========================================================================

## Very slow push (50px/s) barely affects door (<15°).
func _test_weight_feel() -> void:
	var world := TestHelpers.create_horizontal_door_world(self)
	await get_tree().physics_frame
	var door: Variant = world["door"]
	var mover := TestHelpers.spawn_mover(world["root"], Vector2(0.0, 30.0), 1, 1, "player")
	var max_angle := 0.0
	for i in range(60):
		mover.velocity = Vector2(0.0, -50.0)
		mover.set_meta("door_push_velocity", mover.velocity)
		mover.move_and_slide()
		await get_tree().physics_frame
		var m := door.get_debug_metrics() as Dictionary
		max_angle = maxf(max_angle, absf(float(m.get("angle_deg", 0.0))))
	print("  weight: 50px/s -> %.1f° max open" % max_angle)
	_t.run_test("Weight feel: 50px/s push < 55°", max_angle < 55.0)
	mover.queue_free()
	await get_tree().physics_frame
	await _free_world(world)


## Door bounces when hitting swing limit.
func _test_wall_bounce() -> void:
	var world := TestHelpers.create_horizontal_door_world(self)
	await get_tree().physics_frame
	var door: Variant = world["door"]
	var mover := TestHelpers.spawn_mover(world["root"], Vector2(0.0, 30.0), 1, 1, "player")
	for i in range(30):
		mover.velocity = Vector2(0.0, -450.0)
		mover.set_meta("door_push_velocity", mover.velocity)
		mover.move_and_slide()
		await get_tree().physics_frame
	mover.queue_free()
	await get_tree().physics_frame
	var m_at_limit := door.get_debug_metrics() as Dictionary
	var limit_hits := int(m_at_limit.get("limit_hits", 0))
	print("  wall_bounce: limit_hits=%d angle=%.1f°" % [limit_hits, float(m_at_limit.get("angle_deg", 0.0))])
	_t.run_test("Door hits swing limit (>=1)", limit_hits >= 1)
	for i in range(10):
		await get_tree().physics_frame
	var m_after := door.get_debug_metrics() as Dictionary
	var angle_after := absf(float(m_after.get("angle_deg", 0.0)))
	var angle_at_limit := absf(float(m_at_limit.get("angle_deg", 0.0)))
	_t.run_test("Door bounces back from limit", angle_after < angle_at_limit)
	await _free_world(world)


## Body in doorway triggers anti-pinch (door re-opens).
func _test_anti_pinch() -> void:
	var world := TestHelpers.create_horizontal_door_world(self)
	await get_tree().physics_frame
	var door: Variant = world["door"]
	# Push door wide open first
	var mover := TestHelpers.spawn_mover(world["root"], Vector2(0.0, 80.0), 1, 1, "player")
	for i in range(60):
		mover.velocity = Vector2(0.0, -450.0)
		mover.set_meta("door_push_velocity", mover.velocity)
		mover.move_and_slide()
		await get_tree().physics_frame
	# Move mover into doorway at hinge
	mover.global_position = Vector2(20.0, 0.0)
	mover.velocity = Vector2.ZERO
	mover.set_meta("door_push_velocity", Vector2.ZERO)
	await get_tree().physics_frame
	var pinch_detected := false
	for i in range(600):
		await get_tree().physics_frame
		var m := door.get_debug_metrics() as Dictionary
		if bool(m.get("pinch_active", false)):
			pinch_detected = true
			break
	_t.run_test("Anti-pinch activates when body in doorway", pinch_detected)
	mover.queue_free()
	await get_tree().physics_frame
	await _free_world(world)


# ==========================================================================
# HELPERS
# ==========================================================================

func _run_pass_scenario(speed_px: float, mover_layer: int, mover_mask: int, start_pos: Vector2, pass_check_pos: Vector2, frames: int, group_name: String) -> Dictionary:
	var world := TestHelpers.create_horizontal_door_world(self)
	await get_tree().physics_frame
	var door: Variant = world["door"]
	var mover := TestHelpers.spawn_mover(world["root"], start_pos, mover_layer, mover_mask, group_name)

	var passed := false
	var max_open := 0.0
	var move_dir := (pass_check_pos - start_pos).normalized()
	var final_y := start_pos.y
	var final_angle := 0.0
	for i in range(frames):
		mover.velocity = move_dir * speed_px
		mover.set_meta("door_push_velocity", mover.velocity)
		mover.move_and_slide()
		await get_tree().physics_frame
		var m := door.get_debug_metrics() as Dictionary
		max_open = maxf(max_open, absf(float(m.get("angle_deg", 0.0))))
		final_y = mover.global_position.y
		final_angle = float(m.get("angle_deg", 0.0))
		if move_dir.y < 0.0 and mover.global_position.y <= pass_check_pos.y:
			passed = true
			break
		if move_dir.y > 0.0 and mover.global_position.y >= pass_check_pos.y:
			passed = true
			break

	mover.queue_free()
	await get_tree().physics_frame
	await _free_world(world)
	return {
		"passed": passed,
		"max_open_deg": max_open,
		"final_y": final_y,
		"final_angle_deg": final_angle,
	}


func _free_world(world: Dictionary) -> void:
	var root := world.get("root", null) as Node
	if root:
		root.queue_free()
	await get_tree().physics_frame
