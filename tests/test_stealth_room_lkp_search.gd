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
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var player := room.get_node_or_null("Entities/Player") as CharacterBody2D
	var enemy := _first_member_in_group_under("enemies", room) as Enemy
	_t.run_test("lkp search: player exists", player != null)
	_t.run_test("lkp search: enemy exists", enemy != null)
	if player == null or enemy == null:
		room.queue_free()
		await get_tree().process_frame
		return

	enemy.set_physics_process(false)
	player.remove_from_group("player")
	var lkp := enemy.global_position + Vector2(120.0, 0.0)
	enemy.set("_last_seen_pos", lkp)
	enemy.set("_last_seen_age", 0.1)

	enemy.runtime_budget_tick(0.2)
	var investigate_snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test(
		"lkp search: no LOS with recent last_seen chooses INVESTIGATE",
		int(investigate_snapshot.get("intent_type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.INVESTIGATE
	)

	enemy.global_position = lkp
	for _i in range(4):
		enemy.runtime_budget_tick(0.2)
	var search_snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test(
		"lkp search: arriving at last_seen switches to SEARCH",
		int(search_snapshot.get("intent_type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH
	)

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
