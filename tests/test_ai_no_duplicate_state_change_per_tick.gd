extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const STEALTH_ROOM_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")

const ITERATIONS := 1000

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
	print("AI NO DUPLICATE STATE CHANGE PER TICK TEST")
	print("============================================================")

	await _test_no_duplicate_state_change_per_tick()

	_t.summary("AI NO DUPLICATE STATE CHANGE PER TICK RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_no_duplicate_state_change_per_tick() -> void:
	_state_events.clear()
	if EventBus and not EventBus.enemy_state_changed.is_connected(_on_enemy_state_changed):
		EventBus.enemy_state_changed.connect(_on_enemy_state_changed)

	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var enemy := _first_member_in_group_under("enemies", room) as Enemy
	_t.run_test("no-duplicate: enemy exists", enemy != null)
	if enemy == null:
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

	var duplicate_ticks := 0
	var alert_combat_same_tick_cycles := 0

	for _i in range(ITERATIONS):
		await get_tree().physics_frame
		enemy.debug_force_awareness_state("CALM")
		await _flush_event_bus_frames(1)

		var events_before := _state_events.size()
		enemy.on_heard_shot(room_id, enemy.global_position)
		enemy.call("_on_enemy_reinforcement_called", 999001, room_id, [room_id])
		await _flush_event_bus_frames(1)
		var events_after := _state_events.size()
		var produced := events_after - events_before
		if produced > 1:
			duplicate_ticks += 1
			if _has_alert_combat_cycle_same_tick(events_before, events_after):
				alert_combat_same_tick_cycles += 1

	_t.run_test(
		"no-duplicate: 0 duplicate transitions per tick across %d ticks" % ITERATIONS,
		duplicate_ticks == 0
	)
	_t.run_test(
		"no-duplicate: 0 ALERT<->COMBAT cycles in one tick",
		alert_combat_same_tick_cycles == 0
	)

	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test(
		"no-duplicate: snapshot exposes transition diagnostics fields",
		snapshot.has("transition_reason")
		and snapshot.has("transition_blocked_by")
		and snapshot.has("transition_from")
		and snapshot.has("transition_to")
	)

	room.queue_free()
	await get_tree().process_frame
	if EventBus and EventBus.enemy_state_changed.is_connected(_on_enemy_state_changed):
		EventBus.enemy_state_changed.disconnect(_on_enemy_state_changed)


func _has_alert_combat_cycle_same_tick(from_idx: int, to_idx: int) -> bool:
	var events_by_tick: Dictionary = {}
	for i in range(from_idx, to_idx):
		var evt := _state_events[i] as Dictionary
		var tick := int(evt.get("tick", -1))
		if not events_by_tick.has(tick):
			events_by_tick[tick] = []
		var list := events_by_tick[tick] as Array
		list.append(evt)
		events_by_tick[tick] = list

	for tick_variant in events_by_tick.keys():
		var entries := events_by_tick[tick_variant] as Array
		if entries.size() < 2:
			continue
		var has_alert_to_combat := false
		var has_combat_to_alert := false
		for evt_variant in entries:
			var evt := evt_variant as Dictionary
			var from_state := String(evt.get("from_state", ""))
			var to_state := String(evt.get("to_state", ""))
			if from_state == "ALERT" and to_state == "COMBAT":
				has_alert_to_combat = true
			elif from_state == "COMBAT" and to_state == "ALERT":
				has_combat_to_alert = true
		if has_alert_to_combat and has_combat_to_alert:
			return true
	return false


func _on_enemy_state_changed(enemy_id: int, from_state: String, to_state: String, room_id: int, reason: String) -> void:
	_state_events.append({
		"enemy_id": enemy_id,
		"from_state": from_state,
		"to_state": to_state,
		"room_id": room_id,
		"reason": reason,
		"tick": int(Engine.get_physics_frames()),
	})


func _flush_event_bus_frames(frames: int = 1) -> void:
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
