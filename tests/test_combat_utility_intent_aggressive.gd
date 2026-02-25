extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const STEALTH_ROOM_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")

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
	print("COMBAT NO-LOS INTENT CONTRACT TEST")
	print("============================================================")

	await _test_combat_no_los_intent_contract()

	_t.summary("COMBAT NO-LOS INTENT CONTRACT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_combat_no_los_intent_contract() -> void:
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := room.get_node_or_null("Stealth3ZoneTestController")
	var player := room.get_node_or_null("Entities/Player") as CharacterBody2D
	var enemy := _first_member_in_group_under("enemies", room) as Enemy

	_t.run_test("combat intent: controller exists", controller != null)
	_t.run_test("combat intent: player exists", player != null)
	_t.run_test("combat intent: enemy exists", enemy != null)
	if controller == null or player == null or enemy == null:
		room.queue_free()
		await get_tree().process_frame
		return

	if controller.has_method("_force_enemy_combat"):
		controller.call("_force_enemy_combat")

	enemy.set_physics_process(false)
	enemy.runtime_budget_tick(0.1)

	var had_player_group := player.is_in_group("player")
	if had_player_group:
		player.remove_from_group("player")

	var detection_runtime := _detection_runtime(enemy)
	_t.run_test("combat intent setup: detection runtime exists", detection_runtime != null)
	if detection_runtime == null:
		if had_player_group:
			player.add_to_group("player")
		room.queue_free()
		await get_tree().process_frame
		return
	detection_runtime.call("set_state_value", "_last_seen_pos", enemy.global_position + Vector2(180.0, 0.0))
	detection_runtime.call("set_state_value", "_last_seen_age", 0.1)
	enemy.runtime_budget_tick(0.3)
	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	var intent_type := int(snapshot.get("intent_type", -1))
	var target_is_last_seen := bool(snapshot.get("target_is_last_seen", true))

	_t.run_test(
		"combat intent: state starts in COMBAT",
		int(snapshot.get("state", ENEMY_ALERT_LEVELS_SCRIPT.CALM)) == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
	)
	_t.run_test("combat intent: no-LOS COMBAT does not use last_seen target", not target_is_last_seen)
	_t.run_test(
		"combat intent: no-LOS COMBAT avoids INVESTIGATE/SEARCH-by-last_seen",
		intent_type != ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.INVESTIGATE
		and intent_type != ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH
	)

	if had_player_group:
		player.add_to_group("player")
	room.queue_free()
	await get_tree().process_frame


func _first_member_in_group_under(group_name: String, ancestor: Node) -> Node:
	for member_variant in get_tree().get_nodes_in_group(group_name):
		var member := member_variant as Node
		if member == null:
			continue
		if member == ancestor or ancestor.is_ancestor_of(member):
			return member
	return null


func _detection_runtime(enemy: Enemy) -> Object:
	var refs := enemy.get_runtime_helper_refs()
	return refs.get("detection_runtime", null) as Object
