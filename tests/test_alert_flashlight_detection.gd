extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const STEALTH_TEST_CONFIG_SCRIPT := preload("res://src/levels/stealth_test_config.gd")

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
	print("ALERT FLASHLIGHT DETECTION TEST")
	print("============================================================")

	await _test_flashlight_effect_visible()
	await _test_flashlight_clamp_prevents_jump()
	await _test_flashlight_boosts_shadow_detection_in_alert()
	await _test_flashlight_does_not_work_without_los()
	await _test_flashlight_inactive_reason_state_blocked()

	_t.summary("ALERT FLASHLIGHT DETECTION RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _config_values() -> Dictionary:
	return STEALTH_TEST_CONFIG_SCRIPT.values()


func _test_flashlight_boosts_shadow_detection_in_alert() -> void:
	var in_cone := await _run_detection_case(Vector2(300.0, 0.0), false)
	var out_cone := await _run_detection_case(Vector2(150.0, 260.0), false)

	var in_snapshot := in_cone.get("snapshot", {}) as Dictionary
	var out_snapshot := out_cone.get("snapshot", {}) as Dictionary
	var in_suspicion: float = float(in_cone.get("suspicion", 0.0))
	var out_suspicion: float = float(out_cone.get("suspicion", 0.0))
	var in_cone_eval: bool = bool(in_cone.get("direct_in_cone", false))
	var out_cone_eval: bool = bool(out_cone.get("direct_in_cone", true))

	_t.run_test("ALERT enables flashlight", bool(in_snapshot.get("flashlight_active", false)))
	_t.run_test("player in front remains in LOS", bool(in_snapshot.get("has_los", false)))
	_t.run_test("player off-angle is blocked by confirm channel", not bool(out_snapshot.get("has_los", true)))
	_t.run_test("cone geometry includes front player", in_cone_eval)
	_t.run_test("cone geometry excludes off-angle player", not out_cone_eval)
	_t.run_test("player in cone produces flashlight hit", bool(in_snapshot.get("flashlight_hit", false)))
	_t.run_test("player outside cone does not produce flashlight hit", not bool(out_snapshot.get("flashlight_hit", false)))
	_t.run_test("out-of-cone reason is cone_miss", String(out_snapshot.get("flashlight_inactive_reason", "")) == "cone_miss")
	_t.run_test("flashlight hit grows suspicion faster than shadow-only", in_suspicion > out_suspicion)


func _test_flashlight_effect_visible() -> void:
	var in_cone := await _run_detection_case(Vector2(300.0, 0.0), false)
	var out_cone := await _run_detection_case(Vector2(150.0, 260.0), false)
	var in_snapshot := in_cone.get("snapshot", {}) as Dictionary
	var out_snapshot := out_cone.get("snapshot", {}) as Dictionary
	var in_suspicion: float = float(in_cone.get("suspicion", 0.0))
	var out_suspicion: float = float(out_cone.get("suspicion", 0.0))
	var in_vis_post: float = float(in_snapshot.get("effective_visibility_post_clamp", 0.0))
	var out_vis_post: float = float(out_snapshot.get("effective_visibility_post_clamp", 0.0))

	_t.run_test("test_flashlight_effect_visible: in_cone hit is true", bool(in_snapshot.get("flashlight_hit", false)))
	_t.run_test("test_flashlight_effect_visible: out_cone hit is false", not bool(out_snapshot.get("flashlight_hit", true)))
	_t.run_test("test_flashlight_effect_visible: in_cone post-clamp visibility is higher", in_vis_post > out_vis_post)
	_t.run_test("test_flashlight_effect_visible: in_cone suspicion gain is higher", in_suspicion > out_suspicion)


func _test_flashlight_clamp_prevents_jump() -> void:
	var high_bonus_case := await _run_detection_case(Vector2(300.0, 0.0), false, 25.0)
	var snapshot := high_bonus_case.get("snapshot", {}) as Dictionary
	var pre_clamp: float = float(snapshot.get("effective_visibility_pre_clamp", 0.0))
	var post_clamp: float = float(snapshot.get("effective_visibility_post_clamp", 0.0))

	_t.run_test("test_flashlight_clamp_prevents_jump: pre-clamp can exceed 1.0", pre_clamp > 1.0)
	_t.run_test("test_flashlight_clamp_prevents_jump: post-clamp is capped to 1.0", post_clamp <= 1.0 + 0.0001)
	_t.run_test("test_flashlight_clamp_prevents_jump: post-clamp stays non-negative", post_clamp >= -0.0001)


func _test_flashlight_does_not_work_without_los() -> void:
	var blocked := await _run_detection_case(Vector2(300.0, 0.0), true)
	var blocked_snapshot := blocked.get("snapshot", {}) as Dictionary
	var blocked_suspicion: float = float(blocked.get("suspicion", 0.0))

	_t.run_test("occluded LOS reports false", not bool(blocked_snapshot.get("has_los", true)))
	_t.run_test("flashlight hit stays false when LOS is blocked", not bool(blocked_snapshot.get("flashlight_hit", true)))
	_t.run_test("LOS-blocked reason is exposed", String(blocked_snapshot.get("flashlight_inactive_reason", "")) == "los_blocked")
	_t.run_test("suspicion does not grow when LOS is blocked", is_zero_approx(blocked_suspicion))


func _test_flashlight_inactive_reason_state_blocked() -> void:
	var calm_state := await _run_detection_case(Vector2(300.0, 0.0), false, -1.0, false)
	var snapshot := calm_state.get("snapshot", {}) as Dictionary
	_t.run_test("CALM blocks flashlight activity", not bool(snapshot.get("flashlight_active", true)))
	_t.run_test("state-blocked reason is exposed", String(snapshot.get("flashlight_inactive_reason", "")) == "state_blocked")


func _run_detection_case(
	player_position: Vector2,
	add_blocker: bool,
	flashlight_bonus_override: float = -1.0,
	force_alert_state: bool = true
) -> Dictionary:
	if RuntimeState:
		RuntimeState.is_frozen = false
		RuntimeState.player_hp = 100
		RuntimeState.player_visibility_mul = float(_config_values().get("shadow_multiplier_default", 0.35))

	var world := Node2D.new()
	add_child(world)

	var player := CharacterBody2D.new()
	player.add_to_group("player")
	player.collision_layer = 1
	player.collision_mask = 1
	player.global_position = player_position
	var player_shape := CollisionShape2D.new()
	var player_circle := CircleShape2D.new()
	player_circle.radius = 16.0
	player_shape.shape = player_circle
	player.add_child(player_shape)
	world.add_child(player)

	if add_blocker:
		var blocker := StaticBody2D.new()
		blocker.collision_layer = 1
		blocker.collision_mask = 1
		blocker.global_position = Vector2(150.0, 0.0)
		var blocker_shape := CollisionShape2D.new()
		var blocker_rect := RectangleShape2D.new()
		blocker_rect.size = Vector2(32.0, 220.0)
		blocker_shape.shape = blocker_rect
		blocker.add_child(blocker_shape)
		world.add_child(blocker)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = Vector2.ZERO
	world.add_child(enemy)
	await get_tree().process_frame

	enemy.initialize(8801, "zombie")
	if enemy.has_method("configure_stealth_test_flashlight"):
		var cfg := _config_values()
		var flashlight_bonus := float(cfg.get("flashlight_bonus", 2.5))
		if flashlight_bonus_override > 0.0:
			flashlight_bonus = flashlight_bonus_override
		enemy.configure_stealth_test_flashlight(
			float(cfg.get("flashlight_angle_deg", 55.0)),
			float(cfg.get("flashlight_distance_px", 1000.0)),
			flashlight_bonus
		)
	var pursuit_controller = enemy.get("_pursuit")
	if pursuit_controller:
		pursuit_controller.set("facing_dir", Vector2.RIGHT)
		pursuit_controller.set("_target_facing_dir", Vector2.RIGHT)
	if force_alert_state:
		enemy.on_heard_shot(0, player_position)
		# This suite validates flashlight cone/detection behavior, not stagger delay timing.
		enemy.set("_flashlight_activation_delay_timer", 0.0)

	var pre_direct_in_cone := false
	var pre_pursuit = enemy.get("_pursuit")
	var pre_facing := Vector2.RIGHT
	if pre_pursuit and pre_pursuit.has_method("get_facing_dir"):
		pre_facing = pre_pursuit.get_facing_dir() as Vector2
	var pre_cone_node = enemy.get("_flashlight_cone")
	if pre_cone_node and pre_cone_node.has_method("is_point_in_cone"):
		pre_direct_in_cone = bool(pre_cone_node.is_point_in_cone(enemy.global_position, pre_facing, player_position))

	enemy.runtime_budget_tick(0.5)

	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	var suspicion: float = float(snapshot.get("suspicion", 0.0))

	world.queue_free()
	await get_tree().process_frame
	return {
		"snapshot": snapshot,
		"suspicion": suspicion,
		"direct_in_cone": pre_direct_in_cone,
		"pre_facing": pre_facing,
	}
