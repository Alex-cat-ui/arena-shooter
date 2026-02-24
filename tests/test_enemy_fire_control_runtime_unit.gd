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
	print("ENEMY FIRE CONTROL RUNTIME UNIT TEST")
	print("============================================================")

	await _test_fire_runtime_block_reason_and_schedule_contract()
	await _test_fire_runtime_anti_sync_gate_contract()

	_t.summary("ENEMY FIRE CONTROL RUNTIME UNIT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _spawn_enemy(world: Node2D, id: int) -> Dictionary:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(id, "zombie")
	enemy.debug_force_awareness_state("COMBAT")
	enemy.set_process(false)
	enemy.set_physics_process(false)
	var runtime: Variant = (enemy.get_runtime_helper_refs() as Dictionary).get("fire_control_runtime", null)
	return {
		"enemy": enemy,
		"runtime": runtime,
	}


func _test_fire_runtime_block_reason_and_schedule_contract() -> void:
	Enemy.debug_reset_fire_sync_gate()
	var world := Node2D.new()
	add_child(world)
	var refs: Dictionary = await _spawn_enemy(world, 84501)
	var runtime: Variant = refs.get("runtime", null)

	_t.run_test("fire runtime: helper is available", runtime != null)
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
	var valid_contact := {
		"los": true,
		"inside_fov": true,
		"in_fire_range": true,
		"not_occluded_by_world": true,
		"shadow_rule_passed": true,
		"weapon_ready": true,
		"friendly_block": false,
		"valid_contact_for_fire": true,
	}
	var can_fire := bool(runtime.call("can_fire_contact_allows_shot", valid_contact))
	var should_fire_now := bool(runtime.call("should_fire_now", true, can_fire))
	var schedule_reason := String(runtime.call("resolve_shotgun_fire_schedule_block_reason"))
	_t.run_test("fire runtime: reposition keeps can_fire=true", can_fire)
	_t.run_test("fire runtime: reposition blocks should_fire_now", not should_fire_now)
	_t.run_test("fire runtime: reposition block reason is emitted", schedule_reason == Enemy.SHOTGUN_FIRE_BLOCK_REPOSITION)

	runtime.call("set_state_patch", {
		"_combat_first_shot_fired": false,
		"_combat_first_shot_delay_armed": true,
		"_combat_first_attack_delay_timer": 0.3,
		"_combat_telegraph_active": false,
	})
	var delay_reason := String(runtime.call("resolve_shotgun_fire_block_reason", valid_contact))
	_t.run_test("fire runtime: first-shot delay reason is preserved", delay_reason == Enemy.SHOTGUN_FIRE_BLOCK_FIRST_ATTACK_DELAY)

	runtime.call("set_state_patch", {
		"_combat_first_shot_delay_armed": true,
		"_combat_first_attack_delay_timer": 0.0,
		"_combat_telegraph_active": true,
		"_combat_telegraph_timer": 0.25,
	})
	var telegraph_reason := String(runtime.call("resolve_shotgun_fire_block_reason", valid_contact))
	_t.run_test("fire runtime: telegraph reason is preserved", telegraph_reason == Enemy.SHOTGUN_FIRE_BLOCK_TELEGRAPH)

	var blocked_by_friendly := valid_contact.duplicate(true)
	blocked_by_friendly["friendly_block"] = true
	runtime.call("set_state_patch", {
		"_combat_first_shot_fired": true,
		"_combat_telegraph_active": false,
		"_combat_first_shot_delay_armed": false,
		"_combat_first_attack_delay_timer": 0.0,
	})
	var friendly_reason := String(runtime.call("resolve_shotgun_fire_block_reason", blocked_by_friendly))
	_t.run_test("fire runtime: friendly block reason is preserved", friendly_reason == Enemy.SHOTGUN_FIRE_BLOCK_FRIENDLY_BLOCK)

	world.queue_free()
	await get_tree().process_frame
	Enemy.debug_reset_fire_sync_gate()


func _test_fire_runtime_anti_sync_gate_contract() -> void:
	Enemy.debug_reset_fire_sync_gate()
	var world := Node2D.new()
	add_child(world)
	var refs_a: Dictionary = await _spawn_enemy(world, 84502)
	var refs_b: Dictionary = await _spawn_enemy(world, 84503)
	var runtime_a: Variant = refs_a.get("runtime", null)
	var runtime_b: Variant = refs_b.get("runtime", null)

	_t.run_test("anti-sync runtime A exists", runtime_a != null)
	_t.run_test("anti-sync runtime B exists", runtime_b != null)
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

	_t.run_test("anti-sync runtime: second shot in same tick is blocked", not gate_same_tick)
	_t.run_test("anti-sync runtime: gate reopens next tick", gate_next_tick)

	world.queue_free()
	await get_tree().process_frame
	Enemy.debug_reset_fire_sync_gate()
