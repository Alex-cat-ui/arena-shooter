extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const STEALTH_ROOM_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")
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
	print("STEALTH ROOM LKP SEARCH TEST")
	print("============================================================")

	await _test_lkp_investigate_then_search()

	_t.summary("STEALTH ROOM LKP SEARCH RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_lkp_investigate_then_search() -> void:
	if EventBus and EventBus.has_method("debug_reset_queue_for_tests"):
		EventBus.call("debug_reset_queue_for_tests")
	if RuntimeState:
		RuntimeState.is_frozen = false
		RuntimeState.player_visibility_mul = 1.0
		RuntimeState.player_hp = 100
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var player := room.get_node_or_null("Entities/Player") as CharacterBody2D
	var enemies := _members_in_group_under("enemies", room)
	var enemy := enemies[0] as Enemy if not enemies.is_empty() else null
	_t.run_test("lkp search: player exists", player != null)
	_t.run_test("lkp search: enemy exists", enemy != null)
	if player == null or enemy == null:
		room.queue_free()
		await get_tree().process_frame
		return

	for enemy_variant in enemies:
		var other := enemy_variant as Enemy
		if other == null or other == enemy:
			continue
		other.global_position = Vector2(-20000.0, -20000.0)
		other.set_meta("room_id", -1)
		other.set_physics_process(false)

	enemy.set_physics_process(false)
	enemy.set_meta("room_id", 0)
	# Keep player far away so this suite deterministically validates
	# last-seen intent flow (no live LOS branch) in both standalone/full runner.
	player.global_position = enemy.global_position + Vector2(5000.0, 0.0)
	player.velocity = Vector2.ZERO

	var los_blocker := StaticBody2D.new()
	los_blocker.collision_layer = 1
	los_blocker.collision_mask = 1
	var blocker_shape_node := CollisionShape2D.new()
	var blocker_shape := RectangleShape2D.new()
	blocker_shape.size = Vector2(64.0, 280.0)
	blocker_shape_node.shape = blocker_shape
	los_blocker.add_child(blocker_shape_node)
	room.add_child(los_blocker)
	los_blocker.global_position = enemy.global_position + Vector2(130.0, 0.0)
	await get_tree().physics_frame
	var lkp := enemy.global_position + Vector2(260.0, 0.0)
	enemy.set("_last_seen_pos", lkp)
	enemy.set("_last_seen_age", 0.1)
	enemy.set("_investigate_anchor", lkp)
	enemy.set("_investigate_anchor_valid", true)
	if enemy.has_method("debug_force_awareness_state"):
		enemy.call("debug_force_awareness_state", "ALERT")

	enemy.runtime_budget_tick(0.2)
	var investigate_snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test(
		"lkp search: precondition has_los is false",
		not bool(investigate_snapshot.get("has_los", true))
	)
	var initial_intent := int(investigate_snapshot.get("intent_type", -1))
	_t.run_test(
		"lkp search: no LOS with recent last_seen chooses INVESTIGATE/SEARCH",
		initial_intent == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.INVESTIGATE
		or initial_intent == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH
	)

	if los_blocker and is_instance_valid(los_blocker):
		los_blocker.queue_free()
		await get_tree().physics_frame

	enemy.global_position = lkp
	for _i in range(4):
		enemy.runtime_budget_tick(0.2)
	var search_snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	var arrive_intent := int(search_snapshot.get("intent_type", -1))
	_t.run_test(
		"lkp search: arriving at last_seen stays on LKP flow (SEARCH/INVESTIGATE)",
		arrive_intent == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH
		or arrive_intent == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.INVESTIGATE
	)

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


func _members_in_group_under(group_name: String, ancestor: Node) -> Array[Node]:
	var out: Array[Node] = []
	for member_variant in get_tree().get_nodes_in_group(group_name):
		var member := member_variant as Node
		if member == null:
			continue
		if member == ancestor or ancestor.is_ancestor_of(member):
			out.append(member)
	return out
