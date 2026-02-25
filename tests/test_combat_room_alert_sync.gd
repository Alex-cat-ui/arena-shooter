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

	var controller := room.get_node_or_null("Stealth3ZoneTestController")
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
	if room_id < 0:
		enemy.runtime_budget_tick(0.0)
		room_id = int(enemy.get_meta("room_id", -1))
	var room_alert_effective := ENEMY_ALERT_LEVELS_SCRIPT.CALM
	var room_alert_transient := ENEMY_ALERT_LEVELS_SCRIPT.CALM
	if room_id >= 0:
		if alert_system.has_method("get_room_effective_level"):
			room_alert_effective = int(alert_system.get_room_effective_level(room_id))
		elif alert_system.has_method("get_room_alert_level"):
			room_alert_effective = int(alert_system.get_room_alert_level(room_id))
		if alert_system.has_method("get_room_transient_level"):
			room_alert_transient = int(alert_system.get_room_transient_level(room_id))
		else:
			room_alert_transient = room_alert_effective

	_t.run_test(
		"combat sync: enemy awareness switched to COMBAT",
		String(enemy.get_meta("awareness_state", "CALM")) == "COMBAT"
	)
	_t.run_test(
		"combat sync: room effective is COMBAT same tick",
		room_alert_effective == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
	)
	_t.run_test(
		"combat sync: room transient >= ALERT same tick",
		room_alert_transient >= ENEMY_ALERT_LEVELS_SCRIPT.ALERT
	)

	enemy.runtime_budget_tick(0.1)
	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test(
		"combat sync: snapshot has no COMBAT|CALM effective mismatch",
		not (
			int(snapshot.get("state", ENEMY_ALERT_LEVELS_SCRIPT.CALM)) == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
			and int(snapshot.get("room_alert_effective", ENEMY_ALERT_LEVELS_SCRIPT.CALM)) == ENEMY_ALERT_LEVELS_SCRIPT.CALM
		)
	)
	_t.run_test(
		"combat sync: snapshot reports transient/effective/latch fields",
		snapshot.has("room_alert_effective")
		and snapshot.has("room_alert_transient")
		and snapshot.has("room_latch_count")
		and snapshot.has("latched")
	)
	_t.run_test(
		"combat sync: snapshot includes transition diagnostics",
		snapshot.has("transition_reason")
		and snapshot.has("transition_blocked_by")
		and snapshot.has("transition_from")
		and snapshot.has("transition_to")
	)
	_t.run_test(
		"combat sync: forced combat transition is not blocked",
		String(snapshot.get("transition_blocked_by", "")) == ""
		and String(snapshot.get("transition_to", "")) == "COMBAT"
	)
	_t.run_test(
		"combat sync: snapshot marks enemy as latched in COMBAT",
		bool(snapshot.get("latched", false))
		and int(snapshot.get("room_latch_count", 0)) > 0
		and int(snapshot.get("room_alert_effective", ENEMY_ALERT_LEVELS_SCRIPT.CALM)) == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
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
