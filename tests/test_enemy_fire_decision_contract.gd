extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")

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
	print("ENEMY FIRE DECISION CONTRACT TEST")
	print("============================================================")

	await _test_reposition_window_splits_can_vs_should_fire()
	await _test_anti_sync_blocks_second_shot_same_tick()

	_t.summary("ENEMY FIRE DECISION CONTRACT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_reposition_window_splits_can_vs_should_fire() -> void:
	Enemy.debug_reset_fire_sync_gate()
	var world := Node2D.new()
	add_child(world)
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(7201, "zombie")
	enemy.debug_force_awareness_state("COMBAT")
	var runtime: Variant = (enemy.get_runtime_helper_refs() as Dictionary).get("fire_control_runtime", null)
	_t.run_test("fire decision: runtime helper exists", runtime != null)
	if runtime == null:
		world.queue_free()
		await get_tree().process_frame
		return
	runtime.call("set_state_patch", {
		"_shot_cooldown": 0.0,
		"_combat_first_shot_fired": true,
		"_combat_fire_phase": Enemy.COMBAT_FIRE_PHASE_REPOSITION,
		"_combat_fire_reposition_left": 0.2,
	})

	var fire_contact := {
		"los": true,
		"inside_fov": true,
		"in_fire_range": true,
		"not_occluded_by_world": true,
		"shadow_rule_passed": true,
		"weapon_ready": true,
		"friendly_block": false,
		"valid_contact_for_fire": true,
	}
	var can_fire := bool(runtime.call("can_fire_contact_allows_shot", fire_contact))
	var should_fire_now := bool(runtime.call("should_fire_now", true, can_fire))
	var schedule_reason := String(runtime.call("resolve_shotgun_fire_schedule_block_reason"))

	_t.run_test("reposition: can_fire remains true", can_fire)
	_t.run_test("reposition: should_fire_now is false", not should_fire_now)
	_t.run_test(
		"reposition: block reason is reposition",
		schedule_reason == Enemy.SHOTGUN_FIRE_BLOCK_REPOSITION
	)

	world.queue_free()
	await get_tree().process_frame
	Enemy.debug_reset_fire_sync_gate()


func _test_anti_sync_blocks_second_shot_same_tick() -> void:
	Enemy.debug_reset_fire_sync_gate()
	var world := Node2D.new()
	add_child(world)
	var enemy_a := ENEMY_SCENE.instantiate() as Enemy
	var enemy_b := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy_a)
	world.add_child(enemy_b)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy_a.initialize(7202, "zombie")
	enemy_b.initialize(7203, "zombie")
	enemy_a.debug_force_awareness_state("COMBAT")
	enemy_b.debug_force_awareness_state("COMBAT")
	var runtime_a: Variant = (enemy_a.get_runtime_helper_refs() as Dictionary).get("fire_control_runtime", null)
	var runtime_b: Variant = (enemy_b.get_runtime_helper_refs() as Dictionary).get("fire_control_runtime", null)
	_t.run_test("anti-sync: runtime_a exists", runtime_a != null)
	_t.run_test("anti-sync: runtime_b exists", runtime_b != null)
	if runtime_a == null or runtime_b == null:
		world.queue_free()
		await get_tree().process_frame
		Enemy.debug_reset_fire_sync_gate()
		return
	runtime_a.call("set_state_patch", {
		"_shot_cooldown": 0.0,
		"_combat_first_shot_fired": true,
		"_combat_fire_phase": Enemy.COMBAT_FIRE_PHASE_FIRE,
		"_combat_fire_reposition_left": 0.0,
	})
	runtime_b.call("set_state_patch", {
		"_shot_cooldown": 0.0,
		"_combat_first_shot_fired": true,
		"_combat_fire_phase": Enemy.COMBAT_FIRE_PHASE_FIRE,
		"_combat_fire_reposition_left": 0.0,
	})

	runtime_a.call("mark_enemy_shot_success")
	var gate_same_tick := bool(runtime_b.call("anti_sync_fire_gate_open"))
	await get_tree().physics_frame
	var gate_next_tick := bool(runtime_b.call("anti_sync_fire_gate_open"))

	_t.run_test("anti-sync: same tick second shot is blocked", not gate_same_tick)
	_t.run_test("anti-sync: next tick gate reopens", gate_next_tick)

	world.queue_free()
	await get_tree().process_frame
	Enemy.debug_reset_fire_sync_gate()
