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
	print("FRIENDLY BLOCK PREVENTS FIRE AND TRIGGERS REPOSITION TEST")
	print("============================================================")

	await _test_friendly_block_prevents_fire_and_triggers_reposition()

	_t.summary("FRIENDLY BLOCK PREVENTS FIRE AND TRIGGERS REPOSITION RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_friendly_block_prevents_fire_and_triggers_reposition() -> void:
	var world := Node2D.new()
	add_child(world)
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame

	enemy.initialize(7606, "zombie")
	enemy.debug_force_awareness_state("COMBAT")
	var runtime: Variant = (enemy.get_runtime_helper_refs() as Dictionary).get("fire_control_runtime", null)
	_t.run_test("friendly-block: runtime helper exists", runtime != null)
	if runtime == null:
		world.queue_free()
		await get_tree().process_frame
		return
	runtime.call("set_state_patch", {
		"_shot_cooldown": 0.0,
		"_combat_first_shot_fired": true,
	})

	var fire_contact := {
		"los": true,
		"inside_fov": true,
		"in_fire_range": true,
		"not_occluded_by_world": true,
		"shadow_rule_passed": true,
		"weapon_ready": true,
		"friendly_block": true,
	}
	var reason := String(runtime.call("resolve_shotgun_fire_block_reason", fire_contact))
	runtime.call("register_friendly_block_and_reposition")
	runtime.call("register_friendly_block_and_reposition")
	var snapshot_after_blocks := enemy.get_debug_detection_snapshot() as Dictionary
	runtime.call("mark_enemy_shot_success")
	var snapshot_after_success := enemy.get_debug_detection_snapshot() as Dictionary

	_t.run_test("friendly in line of fire blocks shot", reason == "friendly_block")
	_t.run_test(
		"two consecutive friendly blocks trigger reposition request with cooldown",
		bool(snapshot_after_blocks.get("shotgun_friendly_block_reposition_pending", false))
			and float(snapshot_after_blocks.get("shotgun_friendly_block_reposition_cooldown_left", 0.0)) > 0.0
	)
	_t.run_test(
		"successful shot resets friendly_block_streak",
		int(snapshot_after_success.get("shotgun_friendly_block_streak", -1)) == 0
	)

	world.queue_free()
	await get_tree().process_frame
