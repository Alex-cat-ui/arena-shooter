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
	print("SHADOW/FLASHLIGHT RULE BLOCKS OR ALLOWS FIRE TEST")
	print("============================================================")

	await _test_shadow_flashlight_rule_blocks_or_allows_fire()

	_t.summary("SHADOW/FLASHLIGHT RULE BLOCKS OR ALLOWS FIRE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_shadow_flashlight_rule_blocks_or_allows_fire() -> void:
	var world := Node2D.new()
	add_child(world)
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame

	enemy.initialize(7607, "zombie")
	enemy.debug_force_awareness_state("COMBAT")
	var runtime: Variant = (enemy.get_runtime_helper_refs() as Dictionary).get("fire_control_runtime", null)
	_t.run_test("shadow flashlight rule: runtime helper exists", runtime != null)
	if runtime == null:
		world.queue_free()
		await get_tree().process_frame
		return
	runtime.call("set_state_patch", {
		"_shot_cooldown": 0.0,
		"_combat_first_shot_fired": true,
	})

	var blocked_contact := {
		"los": true,
		"inside_fov": true,
		"in_fire_range": true,
		"not_occluded_by_world": true,
		"shadow_rule_passed": false,
		"weapon_ready": true,
		"friendly_block": false,
	}
	var allowed_contact := {
		"los": true,
		"inside_fov": true,
		"in_fire_range": true,
		"not_occluded_by_world": true,
		"shadow_rule_passed": true,
		"weapon_ready": true,
		"friendly_block": false,
	}
	var blocked_reason := String(runtime.call("resolve_shotgun_fire_block_reason", blocked_contact))
	var allowed_reason := String(runtime.call("resolve_shotgun_fire_block_reason", allowed_contact))

	_t.run_test(
		"in shadow without flashlight_active: fire is blocked by shadow rule",
		blocked_reason == "shadow_blocked"
	)
	_t.run_test(
		"in shadow with flashlight_active: shadow no longer blocks fire gate",
		allowed_reason == ""
	)

	world.queue_free()
	await get_tree().process_frame
