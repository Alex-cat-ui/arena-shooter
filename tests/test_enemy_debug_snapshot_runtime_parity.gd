extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
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
	print("ENEMY DEBUG SNAPSHOT RUNTIME PARITY TEST")
	print("============================================================")

	await _test_export_snapshot_matches_enemy_proxy()
	await _test_transition_guard_runtime_contract()
	await _test_record_and_trace_bridge_updates_owner_state()

	_t.summary("ENEMY DEBUG SNAPSHOT RUNTIME PARITY RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _spawn_enemy(world: Node2D, id: int) -> Dictionary:
	var player := CharacterBody2D.new()
	player.add_to_group("player")
	player.global_position = Vector2(320.0, 0.0)
	world.add_child(player)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = Vector2.ZERO
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(id, "zombie")
	return {
		"enemy": enemy,
		"runtime": (enemy.get_runtime_helper_refs() as Dictionary).get("debug_snapshot_runtime", null),
	}


func _test_export_snapshot_matches_enemy_proxy() -> void:
	var world := Node2D.new()
	add_child(world)
	var refs := await _spawn_enemy(world, 91001)
	var enemy := refs.get("enemy", null) as Enemy
	var runtime: Variant = refs.get("runtime", null)

	_t.run_test("debug snapshot parity: runtime helper exists", runtime != null)
	if runtime == null or enemy == null:
		world.queue_free()
		await get_tree().process_frame
		return

	enemy.on_heard_shot(0, Vector2(320.0, 0.0))
	enemy.runtime_budget_tick(0.2)
	var api_snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	var runtime_snapshot := runtime.call("export_snapshot") as Dictionary

	var keys_match := api_snapshot.size() == runtime_snapshot.size()
	if keys_match:
		for key_variant in api_snapshot.keys():
			var key := String(key_variant)
			if not runtime_snapshot.has(key):
				keys_match = false
				break

	_t.run_test("debug snapshot parity: runtime export keyset matches API proxy", keys_match)
	_t.run_test(
		"debug snapshot parity: core values match",
		int(api_snapshot.get("state", -1)) == int(runtime_snapshot.get("state", -2))
			and float(api_snapshot.get("suspicion", -1.0)) == float(runtime_snapshot.get("suspicion", -2.0))
			and bool(api_snapshot.get("flashlight_active", false)) == bool(runtime_snapshot.get("flashlight_active", true))
			and String(api_snapshot.get("shotgun_fire_block_reason", "")) == String(runtime_snapshot.get("shotgun_fire_block_reason", "mismatch"))
	)

	world.queue_free()
	await get_tree().process_frame


func _test_transition_guard_runtime_contract() -> void:
	var world := Node2D.new()
	add_child(world)
	var refs := await _spawn_enemy(world, 91002)
	var enemy := refs.get("enemy", null) as Enemy
	var runtime: Variant = refs.get("runtime", null)

	_t.run_test("transition guard runtime: helper exists", runtime != null)
	if runtime == null or enemy == null:
		world.queue_free()
		await get_tree().process_frame
		return

	runtime.call("set_state_patch", {
		"_debug_last_transition_tick_id": -1,
		"_debug_transition_count_this_tick": 3,
		"_debug_last_transition_blocked_by": "fixture_value",
	})
	runtime.call("refresh_transition_guard_tick")
	var reset_count := int(runtime.call("get_state_value", "_debug_transition_count_this_tick", -1))
	var reset_blocked := String(runtime.call("get_state_value", "_debug_last_transition_blocked_by", "x"))
	runtime.call("set_state_value", "_debug_transition_count_this_tick", 5)
	runtime.call("refresh_transition_guard_tick")
	var preserved_count := int(runtime.call("get_state_value", "_debug_transition_count_this_tick", -1))

	_t.run_test("transition guard runtime: first refresh resets count", reset_count == 0)
	_t.run_test("transition guard runtime: first refresh clears blocked_by", reset_blocked == "")
	_t.run_test("transition guard runtime: same-frame refresh is a no-op", preserved_count == 5)

	world.queue_free()
	await get_tree().process_frame


func _test_record_and_trace_bridge_updates_owner_state() -> void:
	var world := Node2D.new()
	add_child(world)
	var refs := await _spawn_enemy(world, 91003)
	var enemy := refs.get("enemy", null) as Enemy
	var runtime: Variant = refs.get("runtime", null)

	_t.run_test("record/trace bridge: helper exists", runtime != null)
	if runtime == null or enemy == null:
		world.queue_free()
		await get_tree().process_frame
		return

	runtime.call("record_runtime_tick_debug_state", {
		"behavior_visible": true,
		"visibility_factor": 0.42,
		"distance_factor": 0.31,
		"shadow_mul": 0.8,
		"distance_to_player": 123.0,
		"flashlight_active": true,
		"flashlight_hit": true,
		"flashlight_in_cone": true,
		"raw_player_visible": true,
		"valid_firing_solution": true,
		"fire_contact": {
			"los": true,
			"inside_fov": true,
			"in_fire_range": true,
			"not_occluded_by_world": true,
			"shadow_rule_passed": true,
			"weapon_ready": true,
			"friendly_block": false,
		},
		"flashlight_bonus_raw": 1.75,
		"flashlight_inactive_reason": "",
		"effective_visibility_pre_clamp": 1.2,
		"effective_visibility_post_clamp": 1.0,
		"intent": {"type": 2, "target": Vector2(64.0, -32.0)},
		"last_seen_age": 0.7,
		"room_alert_effective": ENEMY_ALERT_LEVELS_SCRIPT.ALERT,
		"flashlight_facing_used": Vector2.RIGHT,
		"facing_after_move": Vector2.RIGHT,
		"target_facing_after_move": Vector2.RIGHT,
		"debug_tick_id": 99,
	})
	runtime.call("set_debug_logging", true)
	runtime.call("set_state_patch", {
		"_debug_last_logged_intent_type": -1,
		"_debug_last_logged_target_facing": Vector2.ZERO,
		"_debug_last_intent_type": 2,
		"_debug_last_target_facing_dir": Vector2.RIGHT,
		"_debug_last_room_alert_level": 2,
		"_debug_last_state_name": "ALERT",
		"_debug_last_visibility_factor": 0.42,
		"_debug_last_last_seen_age": 0.7,
	})
	runtime.call("emit_stealth_debug_trace_if_needed", {"los": true, "dist": 123.0}, 0.6)

	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	var logged_intent := int(runtime.call("get_state_value", "_debug_last_logged_intent_type", -1))
	var logged_facing := runtime.call("get_state_value", "_debug_last_logged_target_facing", Vector2.ZERO) as Vector2
	_t.run_test(
		"record bridge writes snapshot fields",
		bool(snapshot.get("has_los", false))
			and bool(snapshot.get("flashlight_active", false))
			and int(snapshot.get("intent_type", -1)) == 2
			and int(snapshot.get("flashlight_calc_tick_id", -1)) == 99
	)
	_t.run_test("trace bridge stores last logged intent", logged_intent == 2)
	_t.run_test("trace bridge stores last logged facing", logged_facing == Vector2.RIGHT)

	world.queue_free()
	await get_tree().process_frame
