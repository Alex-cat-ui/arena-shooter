extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ROOM_NAV_SYSTEM_SCRIPT := preload("res://src/systems/navigation_service.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")
const ENEMY_AGGRO_COORDINATOR_SCRIPT := preload("res://src/systems/enemy_aggro_coordinator.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _reinforcement_calls_counter: int = 0
const CANON_CONFIG := {
	"confirm_time_to_engage": 2.50,
	"confirm_decay_rate": 0.275,
	"confirm_grace_window": 0.50,
}


class FakeLayout:
	extends RefCounted

	var valid: bool = true
	var rooms: Array = []
	var _void_ids: Array = []
	var _door_adj: Dictionary = {}
	var doors: Array = []

	func _init() -> void:
		rooms = [
			{"rects": [Rect2(-180.0, -60.0, 120.0, 120.0)], "center": Vector2(-120.0, 0.0)},
			{"rects": [Rect2(-60.0, -60.0, 120.0, 120.0)], "center": Vector2(0.0, 0.0)},
			{"rects": [Rect2(60.0, -60.0, 120.0, 120.0)], "center": Vector2(120.0, 0.0)},
		]
		_door_adj = {
			0: [1],
			1: [0, 2],
			2: [1],
		}

	func _room_id_at_point(p: Vector2) -> int:
		for i in range(rooms.size()):
			var room := rooms[i] as Dictionary
			for rect_variant in (room.get("rects", []) as Array):
				var rect := rect_variant as Rect2
				if rect.has_point(p):
					return i
		return -1

	func _door_adjacent_room_ids(_door: Rect2) -> Array:
		return []


class NoiseEnemy:
	extends Node2D

	var entity_id: int = 0
	var awareness = null

	func _init(p_entity_id: int, pos: Vector2) -> void:
		entity_id = p_entity_id
		position = pos
		add_to_group("enemies")

	func _ready() -> void:
		awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
		awareness.reset()
		set_meta("awareness_state", awareness.get_state_name())

	func set_room_navigation(_nav_system: Node, room_id: int) -> void:
		set_meta("room_id", room_id)

	func on_heard_shot(_shot_room_id: int, _shot_pos: Vector2) -> void:
		_emit_transitions(awareness.register_noise())

	func tick_los(has_los: bool, delta: float = 0.1) -> void:
		_emit_transitions(awareness.process_confirm(delta, has_los, false, false, CANON_CONFIG))

	func _emit_transitions(transitions: Array[Dictionary]) -> void:
		for tr_variant in transitions:
			var tr := tr_variant as Dictionary
			var from_state := String(tr.get("from_state", ""))
			var to_state := String(tr.get("to_state", ""))
			var reason := String(tr.get("reason", "timer"))
			if to_state == "":
				continue
			set_meta("awareness_state", to_state)
			if EventBus:
				EventBus.emit_enemy_state_changed(
					entity_id,
					from_state,
					to_state,
					int(get_meta("room_id", -1)),
					reason
				)


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ENEMY NOISE ALERT FLOW TEST")
	print("============================================================")

	await _test_noise_alert_and_los_escalation()

	_t.summary("ENEMY NOISE ALERT FLOW RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_noise_alert_and_los_escalation() -> void:
	var root := Node2D.new()
	add_child(root)
	var entities := Node2D.new()
	root.add_child(entities)
	var player := Node2D.new()
	player.position = Vector2(-120.0, 0.0)
	root.add_child(player)

	var enemy_room0 := NoiseEnemy.new(200, Vector2(-120.0, 0.0))
	var enemy_room1 := NoiseEnemy.new(201, Vector2(0.0, 0.0))
	var enemy_room2 := NoiseEnemy.new(202, Vector2(120.0, 0.0))
	entities.add_child(enemy_room0)
	entities.add_child(enemy_room1)
	entities.add_child(enemy_room2)
	await get_tree().process_frame

	var layout := FakeLayout.new()
	var room_nav := ROOM_NAV_SYSTEM_SCRIPT.new()
	root.add_child(room_nav)
	room_nav.initialize(layout, entities, player)

	var coordinator := ENEMY_AGGRO_COORDINATOR_SCRIPT.new()
	root.add_child(coordinator)
	coordinator.initialize(entities, room_nav, player)

	_reinforcement_calls_counter = 0
	if not EventBus.enemy_reinforcement_called.is_connected(_on_reinforcement_counter):
		EventBus.enemy_reinforcement_called.connect(_on_reinforcement_counter)

	EventBus.emit_player_shot("shotgun", Vector3(-120.0, 0.0, 0.0), Vector3.RIGHT)
	await _flush_event_bus_frames(6)

	_t.run_test("Shot noise alerts same room enemy", String(enemy_room0.get_meta("awareness_state", "CALM")) == "ALERT")
	_t.run_test("Shot noise alerts adjacent room enemy", String(enemy_room1.get_meta("awareness_state", "CALM")) == "ALERT")
	_t.run_test("Shot noise does not alert non-adjacent room enemy", String(enemy_room2.get_meta("awareness_state", "CALM")) == "CALM")
	_t.run_test("Noise without LOS does not call COMBAT reinforcement", _reinforcement_calls_counter == 0)

	for _i in range(30):
		enemy_room0.tick_los(true, 0.1)
	await _flush_event_bus_frames(6)

	_t.run_test("LOS after noise enters COMBAT", String(enemy_room0.get_meta("awareness_state", "CALM")) == "COMBAT")
	_t.run_test("LOS escalation can trigger standard reinforcement", _reinforcement_calls_counter >= 1)

	if EventBus.enemy_reinforcement_called.is_connected(_on_reinforcement_counter):
		EventBus.enemy_reinforcement_called.disconnect(_on_reinforcement_counter)
	root.queue_free()
	await get_tree().process_frame


func _flush_event_bus_frames(frames: int = 3) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _on_reinforcement_counter(_source_enemy_id: int, _source_room_id: int, _target_room_ids: Array) -> void:
	_reinforcement_calls_counter += 1
