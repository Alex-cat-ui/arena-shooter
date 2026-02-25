extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
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
	print("ALERT/COMBAT CONTEXT NEVER PATROL TEST")
	print("============================================================")

	_test_alert_known_target_uses_search_not_return_home()
	_test_alert_without_target_context_can_return_home()
	await _test_combat_context_keeps_last_seen()

	_t.summary("ALERT/COMBAT CONTEXT NEVER PATROL RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_alert_known_target_uses_search_not_return_home() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()
	var ctx := _brain_ctx({
		"los": false,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.ALERT,
		"has_known_target": true,
		"has_last_seen": false,
		"last_seen_age": INF,
		"last_seen_pos": Vector2.ZERO,
		"has_investigate_anchor": false,
		"dist_to_last_seen": INF,
		"home_position": Vector2(12.0, 34.0),
		"known_target_pos": Vector2(200.0, 0.0),
	})
	var intent := brain.update(0.3, ctx) as Dictionary
	var intent_type := int(intent.get("type", -1))
	_t.run_test(
		"ALERT no-LOS + known target uses SEARCH (no RETURN_HOME/PATROL)",
		intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH
			and intent_type != ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETURN_HOME
			and intent_type != ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL
	)


func _test_alert_without_target_context_can_return_home() -> void:
	var brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	brain.reset()
	var home_pos := Vector2(8.0, -5.0)
	var ctx := _brain_ctx({
		"los": false,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.ALERT,
		"has_known_target": false,
		"has_last_seen": false,
		"last_seen_age": INF,
		"last_seen_pos": Vector2.ZERO,
		"has_investigate_anchor": false,
		"dist_to_last_seen": INF,
		"home_position": home_pos,
	})
	var intent := brain.update(0.3, ctx) as Dictionary
	var intent_type := int(intent.get("type", -1))
	var intent_target := intent.get("target", Vector2.ZERO) as Vector2
	_t.run_test(
		"ALERT no-LOS + no target context permits RETURN_HOME",
		intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETURN_HOME
			and intent_target.distance_to(home_pos) <= 0.001
	)


func _test_combat_context_keeps_last_seen() -> void:
	if RuntimeState:
		RuntimeState.player_hp = 100
	var world := Node2D.new()
	add_child(world)

	var enemy = ENEMY_SCENE.instantiate()
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame

	enemy.call("initialize", 5001, "zombie")
	enemy.call("debug_force_awareness_state", "COMBAT")
	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test(
		"setup: enemy is in COMBAT awareness",
		int(snapshot.get("state", ENEMY_ALERT_LEVELS_SCRIPT.CALM)) == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
	)

	var detection_runtime := _detection_runtime(enemy)
	_t.run_test("combat context setup: detection runtime exists", detection_runtime != null)
	if detection_runtime == null:
		world.queue_free()
		await get_tree().process_frame
		return
	detection_runtime.call("set_state_value", "_last_seen_age", 0.5)
	detection_runtime.call("set_state_value", "_last_seen_pos", Vector2(64.0, 0.0))
	var assignment := {
		"role": 0,
		"slot_position": Vector2.ZERO,
		"path_ok": false,
		"has_slot": false,
	}
	var target_context := {
		"known_target_pos": Vector2.ZERO,
			"target_is_last_seen": false,
			"has_known_target": false,
		}
	var utility_ctx := detection_runtime.call("build_utility_context", false, false, assignment, target_context) as Dictionary
	_t.run_test(
		"COMBAT utility context keeps has_last_seen when _last_seen_age is finite",
		bool(utility_ctx.get("has_last_seen", false))
			and is_equal_approx(float(utility_ctx.get("last_seen_age", INF)), 0.5)
	)

	world.queue_free()
	await get_tree().process_frame


func _brain_ctx(override: Dictionary) -> Dictionary:
	var base := {
		"dist": INF,
		"los": false,
		"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.CALM,
		"last_seen_age": INF,
		"last_seen_pos": Vector2.ZERO,
		"dist_to_last_seen": INF,
		"combat_lock": false,
		"hp_ratio": 1.0,
		"path_ok": false,
		"has_slot": false,
		"slot_position": Vector2.ZERO,
		"home_position": Vector2.ZERO,
		"known_target_pos": Vector2.ZERO,
		"player_pos": Vector2.ZERO,
		"has_known_target": false,
		"has_last_seen": false,
		"investigate_anchor": Vector2.ZERO,
		"has_investigate_anchor": false,
		"dist_to_investigate_anchor": INF,
	}
	for key_variant in override.keys():
		base[key_variant] = override[key_variant]
	return base


func _detection_runtime(enemy: Enemy) -> Object:
	var refs := enemy.get_runtime_helper_refs()
	return refs.get("detection_runtime", null) as Object
