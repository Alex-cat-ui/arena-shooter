extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const STEALTH_ROOM_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")
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
	print("COMBAT DEGRADES ON NO-CONTACT TIMER TEST")
	print("============================================================")

	await _test_combat_degrades_to_alert_with_los_break()

	_t.summary("COMBAT DEGRADES ON NO-CONTACT TIMER RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_combat_degrades_to_alert_with_los_break() -> void:
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := room.get_node_or_null("Stealth3ZoneTestController")
	var player := room.get_node_or_null("Entities/Player") as CharacterBody2D
	var enemy := _first_member_in_group_under("enemies", room) as Enemy

	_t.run_test("combat degrade: controller exists", controller != null)
	_t.run_test("combat degrade: player exists", player != null)
	_t.run_test("combat degrade: enemy exists", enemy != null)
	if controller == null or player == null or enemy == null:
		room.queue_free()
		await get_tree().process_frame
		return

	if controller.has_method("_force_enemy_combat"):
		controller.call("_force_enemy_combat")

	enemy.set_physics_process(false)
	enemy.runtime_budget_tick(0.1)
	var initial_snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test(
		"combat degrade: starts in COMBAT",
		int(initial_snapshot.get("state", ENEMY_ALERT_LEVELS_SCRIPT.CALM)) == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
	)

	var had_player_group := player.is_in_group("player")
	if had_player_group:
		player.remove_from_group("player")

	var combat_ttl := ENEMY_ALERT_LEVELS_SCRIPT.ttl_for_level(ENEMY_ALERT_LEVELS_SCRIPT.COMBAT)
	var frames := maxi(int(ceil((combat_ttl + 1.0) / 0.1)), 1)
	var downgraded := false
	for _i in range(frames):
		enemy.runtime_budget_tick(0.1)
		await get_tree().physics_frame
		var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
		if int(snapshot.get("state", ENEMY_ALERT_LEVELS_SCRIPT.CALM)) == ENEMY_ALERT_LEVELS_SCRIPT.ALERT:
			downgraded = true
			break

	_t.run_test("combat degrade: LOS break eventually downgrades COMBAT->ALERT", downgraded)

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
