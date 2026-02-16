extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const STEALTH_ROOM_SCENE := preload("res://src/levels/stealth_test_room.tscn")
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
	print("COMBAT ROOM ALERT SYNC TEST")
	print("============================================================")

	await _test_force_combat_escalates_room_alert_same_tick()

	_t.summary("COMBAT ROOM ALERT SYNC RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_force_combat_escalates_room_alert_same_tick() -> void:
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := room.get_node_or_null("StealthTestController")
	var enemy := _first_member_in_group_under("enemies", room) as Enemy
	var alert_system = controller.get("_enemy_alert_system") if controller else null

	_t.run_test("combat sync: controller exists", controller != null)
	_t.run_test("combat sync: enemy exists", enemy != null)
	_t.run_test("combat sync: alert system exists", alert_system != null)
	if controller == null or enemy == null or alert_system == null:
		room.queue_free()
		await get_tree().process_frame
		return

	if controller.has_method("_force_enemy_combat"):
		controller.call("_force_enemy_combat")

	var room_id := int(enemy.get_meta("room_id", -1))
	if room_id < 0 and enemy.has_method("_resolve_room_id_for_events"):
		room_id = int(enemy.call("_resolve_room_id_for_events"))
	var room_alert_level := ENEMY_ALERT_LEVELS_SCRIPT.CALM
	if alert_system.has_method("get_room_alert_level") and room_id >= 0:
		room_alert_level = int(alert_system.get_room_alert_level(room_id))

	_t.run_test(
		"combat sync: enemy awareness switched to COMBAT",
		String(enemy.get_meta("awareness_state", "CALM")) == "COMBAT"
	)
	_t.run_test(
		"combat sync: room_alert >= ALERT same tick",
		room_alert_level >= ENEMY_ALERT_LEVELS_SCRIPT.ALERT
	)

	enemy.runtime_budget_tick(0.1)
	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test(
		"combat sync: snapshot has no COMBAT|CALM mismatch",
		not (
			int(snapshot.get("state", ENEMY_ALERT_LEVELS_SCRIPT.CALM)) == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
			and int(snapshot.get("room_alert_level", ENEMY_ALERT_LEVELS_SCRIPT.CALM)) == ENEMY_ALERT_LEVELS_SCRIPT.CALM
		)
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
