extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const STEALTH_ROOM_SCENE := preload("res://src/levels/stealth_test_room.tscn")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _state_events: Array[Dictionary] = []


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("AI TRANSITION SINGLE OWNER TEST")
	print("============================================================")

	await _test_spotted_updates_room_owner_without_forcing_enemy_state()

	_t.summary("AI TRANSITION SINGLE OWNER RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_spotted_updates_room_owner_without_forcing_enemy_state() -> void:
	_state_events.clear()
	if EventBus and not EventBus.enemy_state_changed.is_connected(_on_enemy_state_changed):
		EventBus.enemy_state_changed.connect(_on_enemy_state_changed)

	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := room.get_node_or_null("StealthTestController")
	var enemy := _first_member_in_group_under("enemies", room) as Enemy
	var alert_system = controller.get("_enemy_alert_system") if controller else null

	_t.run_test("single-owner: controller exists", controller != null)
	_t.run_test("single-owner: enemy exists", enemy != null)
	_t.run_test("single-owner: alert system exists", alert_system != null)
	if controller == null or enemy == null or alert_system == null:
		room.queue_free()
		await get_tree().process_frame
		if EventBus and EventBus.enemy_state_changed.is_connected(_on_enemy_state_changed):
			EventBus.enemy_state_changed.disconnect(_on_enemy_state_changed)
		return

	if enemy.has_method("set_physics_process"):
		enemy.set_physics_process(false)

	var room_id := int(enemy.get_meta("room_id", -1))
	if room_id < 0 and enemy.has_method("_resolve_room_id_for_events"):
		room_id = int(enemy.call("_resolve_room_id_for_events"))
	var awareness_before := String(enemy.get_meta("awareness_state", "CALM"))
	var events_before := _state_events.size()

	EventBus.emit_enemy_player_spotted(
		int(enemy.entity_id),
		Vector3(enemy.global_position.x, enemy.global_position.y, 0.0)
	)
	await _flush_event_bus_frames(2)

	var room_effective := ENEMY_ALERT_LEVELS_SCRIPT.CALM
	if room_id >= 0:
		if alert_system.has_method("get_room_effective_level"):
			room_effective = int(alert_system.get_room_effective_level(room_id))
		elif alert_system.has_method("get_room_alert_level"):
			room_effective = int(alert_system.get_room_alert_level(room_id))

	_t.run_test(
		"single-owner: enemy_player_spotted updates room owner",
		room_effective == ENEMY_ALERT_LEVELS_SCRIPT.ALERT
	)
	_t.run_test(
		"single-owner: spotted does not force enemy awareness transition",
		String(enemy.get_meta("awareness_state", "CALM")) == awareness_before
		and _state_events.size() == events_before
	)

	room.queue_free()
	await get_tree().process_frame
	if EventBus and EventBus.enemy_state_changed.is_connected(_on_enemy_state_changed):
		EventBus.enemy_state_changed.disconnect(_on_enemy_state_changed)


func _on_enemy_state_changed(enemy_id: int, from_state: String, to_state: String, room_id: int, reason: String) -> void:
	_state_events.append({
		"enemy_id": enemy_id,
		"from_state": from_state,
		"to_state": to_state,
		"room_id": room_id,
		"reason": reason,
		"tick": int(Engine.get_physics_frames()),
	})


func _flush_event_bus_frames(frames: int = 2) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _first_member_in_group_under(group_name: String, ancestor: Node) -> Node:
	for member_variant in get_tree().get_nodes_in_group(group_name):
		var member := member_variant as Node
		if member == null:
			continue
		if member == ancestor or ancestor.is_ancestor_of(member):
			return member
	return null
