extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const NAVIGATION_SERVICE_SCRIPT := preload("res://src/systems/navigation_service.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeLayout:
	extends RefCounted
	var valid: bool = true
	var rooms: Array = [{}, {}, {}]
	var doors: Array = []
	var _door_adj: Dictionary = {
		0: [1],
		1: [0, 2],
		2: [1],
	}

	func _room_id_at_point(p: Vector2) -> int:
		if p.x < 100.0:
			return 0
		if p.x < 200.0:
			return 1
		if p.x < 300.0:
			return 2
		return -1


class FakeNavServiceEnemy:
	extends Node2D
	var heard_count: int = 0

	func on_heard_shot(_shot_room_id: int, _shot_pos: Vector2) -> void:
		heard_count += 1


class FakePursuitNav:
	extends Node
	var graph: Dictionary = {
		0: [1],
		1: [0, 2],
		2: [1],
	}

	func get_enemy_room_id(enemy: Node) -> int:
		return int(enemy.get_meta("room_id", -1))

	func get_neighbors(room_id: int) -> Array:
		if room_id < 0:
			return []
		return (graph.get(room_id, []) as Array).duplicate()

	func is_adjacent(a: int, b: int) -> bool:
		if a < 0 or b < 0:
			return false
		return (graph.get(a, []) as Array).has(b)

	func build_reachable_path_points(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null) -> Array[Vector2]:
		return [to_pos]


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("NAVIGATION SHOT GATE PARITY TEST")
	print("============================================================")

	await _test_shot_gate_parity_matrix()

	_t.summary("NAVIGATION SHOT GATE PARITY RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_shot_gate_parity_matrix() -> void:
	var nav := NAVIGATION_SERVICE_SCRIPT.new()
	add_child(nav)
	var entities := Node2D.new()
	add_child(entities)
	nav.layout = FakeLayout.new()
	nav.entities_container = entities
	nav._room_graph = {
		0: [1],
		1: [0, 2],
		2: [1],
	}

	var pursuit_nav := FakePursuitNav.new()
	add_child(pursuit_nav)

	var cases := [
		{"name": "same room 0->0", "own_room": 0, "shot_room": 0},
		{"name": "adjacent room 0->1", "own_room": 0, "shot_room": 1},
		{"name": "adjacent room 1->2", "own_room": 1, "shot_room": 2},
		{"name": "non-adjacent room 0->2", "own_room": 0, "shot_room": 2},
		{"name": "same room 2->2", "own_room": 2, "shot_room": 2},
	]
	for case_variant in cases:
		var case := case_variant as Dictionary
		var own_room := int(case.get("own_room", -1))
		var shot_room := int(case.get("shot_room", -1))
		var shot_pos := _room_center_for_test(shot_room) + Vector2(13.0, -7.0)
		var nav_accepts := await _nav_service_accepts_shot(nav, entities, own_room, shot_pos)
		var pursuit_accepts := _pursuit_accepts_shot(pursuit_nav, own_room, shot_room, shot_pos)
		_t.run_test(
			"gate parity: %s" % String(case.get("name", "case")),
			nav_accepts == pursuit_accepts
		)

	nav.queue_free()
	entities.queue_free()
	pursuit_nav.queue_free()
	await get_tree().process_frame


func _nav_service_accepts_shot(nav: Node, entities: Node2D, own_room: int, shot_pos: Vector2) -> bool:
	var enemy := FakeNavServiceEnemy.new()
	enemy.add_to_group("enemies")
	enemy.global_position = _room_center_for_test(own_room)
	entities.add_child(enemy)
	await get_tree().process_frame
	nav.call("_on_player_shot", "shotgun", Vector3(shot_pos.x, shot_pos.y, 0.0), Vector3.RIGHT)
	var accepted := enemy.heard_count > 0
	enemy.queue_free()
	await get_tree().process_frame
	return accepted


func _pursuit_accepts_shot(nav: Node, own_room: int, shot_room: int, shot_pos: Vector2) -> bool:
	var owner := CharacterBody2D.new()
	owner.global_position = _room_center_for_test(own_room)
	owner.set_meta("room_id", own_room)
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	add_child(owner)
	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	pursuit.configure_navigation(nav, own_room)
	pursuit.on_heard_shot(shot_room, shot_pos)
	var remembered := pursuit.get("_last_seen_pos") as Vector2
	var accepted := remembered.distance_to(shot_pos) <= 0.001
	owner.queue_free()
	return accepted


func _room_center_for_test(room_id: int) -> Vector2:
	match room_id:
		0:
			return Vector2(40.0, 20.0)
		1:
			return Vector2(140.0, 20.0)
		2:
			return Vector2(240.0, 20.0)
		_:
			return Vector2(-1000.0, -1000.0)
