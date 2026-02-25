extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const STEALTH_TEST_CONFIG_SCRIPT := preload("res://src/levels/stealth_test_config.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

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
	print("FLASHLIGHT BONUS APPLIES IN COMBAT TEST")
	print("============================================================")

	await _test_flashlight_bonus_applies_in_combat()

	_t.summary("FLASHLIGHT BONUS APPLIES IN COMBAT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_flashlight_bonus_applies_in_combat() -> void:
	if RuntimeState:
		RuntimeState.player_hp = 100
	var cfg := STEALTH_TEST_CONFIG_SCRIPT.values()

	var world := Node2D.new()
	add_child(world)

	var player := CharacterBody2D.new()
	player.add_to_group("player")
	player.global_position = Vector2(300.0, 0.0)
	world.add_child(player)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = Vector2.ZERO
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(5201, "zombie")
	enemy.configure_stealth_test_flashlight(
		float(cfg.get("flashlight_angle_deg", 55.0)),
		float(cfg.get("flashlight_distance_px", 1000.0)),
		float(cfg.get("flashlight_bonus", 2.5))
	)
	enemy.debug_force_awareness_state("COMBAT")

	enemy.debug_set_pursuit_speed_tiles_for_test(0.0)
	enemy.debug_set_pursuit_facing_for_test(Vector2.RIGHT)

	enemy.runtime_budget_tick(0.3)
	var in_cone_snapshot := enemy.get_debug_detection_snapshot() as Dictionary

	player.global_position = Vector2(120.0, 260.0)
	enemy.debug_set_pursuit_facing_for_test(Vector2.RIGHT)
	enemy.runtime_budget_tick(0.3)
	var out_cone_snapshot := enemy.get_debug_detection_snapshot() as Dictionary

	_t.run_test(
		"combat bonus: state remains COMBAT",
		int(in_cone_snapshot.get("state", ENEMY_ALERT_LEVELS_SCRIPT.CALM)) == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
		and int(out_cone_snapshot.get("state", ENEMY_ALERT_LEVELS_SCRIPT.CALM)) == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
	)
	_t.run_test("combat bonus: flashlight active in combat", bool(in_cone_snapshot.get("flashlight_active", false)))
	_t.run_test("combat bonus: in-cone produces flashlight hit", bool(in_cone_snapshot.get("flashlight_hit", false)))
	_t.run_test("combat bonus: out-of-cone disables flashlight hit", not bool(out_cone_snapshot.get("flashlight_hit", true)))
	_t.run_test(
		"combat bonus: in-cone effective visibility pre-clamp is higher",
		float(in_cone_snapshot.get("effective_visibility_pre_clamp", 0.0))
		> float(out_cone_snapshot.get("effective_visibility_pre_clamp", 0.0))
	)
	_t.run_test(
		"combat bonus: debug bonus raw exceeds 1.0 when hit",
		float(in_cone_snapshot.get("flashlight_bonus_raw", 1.0)) > 1.0
	)

	world.queue_free()
	await get_tree().process_frame
