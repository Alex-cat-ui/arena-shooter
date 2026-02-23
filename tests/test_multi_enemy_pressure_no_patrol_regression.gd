extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SQUAD_SYSTEM_SCRIPT := preload("res://src/systems/enemy_squad_system.gd")


class FakeNavService extends Node:
	var door_centers := {
		"0:1": Vector2(100, 0),
		"0:2": Vector2(0, 100),
	}

	func room_id_at_point(_p: Vector2) -> int:
		return 0

	func build_path_points(_from_pos: Vector2, to_pos: Vector2) -> Array[Vector2]:
		return [to_pos]

	func nav_path_length(from_pos: Vector2, to_pos: Vector2, _enemy: Node = null) -> float:
		return from_pos.distance_to(to_pos)

	func get_adjacent_room_ids(room_id: int) -> Array:
		if room_id != 0:
			return []
		return [1, 2]

	func get_door_center_between(room_a: int, room_b: int, _anchor: Vector2) -> Vector2:
		return door_centers.get("%d:%d" % [room_a, room_b], Vector2.ZERO) as Vector2


class FakeEnemy extends CharacterBody2D:
	var entity_id: int = 0
	var is_dead: bool = false


var embedded_mode: bool = false
var _t := TestHelpers.new()

var _player: Node2D = null
var _entities: Node2D = null
var _nav: FakeNavService = null
var _squad = null


func _ready() -> void:
	if embedded_mode:
		return
	var result := run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("MULTI ENEMY PRESSURE NO PATROL REGRESSION TEST")
	print("============================================================")

	_setup()
	_test_pressure_role_assignment_stable_across_recompute()
	_test_hold_role_uses_exit_slots_not_ring_when_nav_provides_doors()
	_test_squad_role_enum_has_no_patrol_value()
	_cleanup()

	_t.summary("MULTI ENEMY PRESSURE NO PATROL REGRESSION RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _setup() -> void:
	_player = Node2D.new()
	_player.global_position = Vector2.ZERO
	add_child(_player)

	_entities = Node2D.new()
	add_child(_entities)

	for i in range(9):
		var enemy := FakeEnemy.new()
		enemy.entity_id = 3000 + i
		enemy.global_position = Vector2(-220.0 + 36.0 * float(i), -100.0 + 24.0 * float(i % 3))
		_entities.add_child(enemy)
		enemy.add_to_group("enemies")

	_nav = FakeNavService.new()
	add_child(_nav)

	_squad = ENEMY_SQUAD_SYSTEM_SCRIPT.new()
	add_child(_squad)
	_squad.initialize(_player, _nav, _entities)
	_squad.recompute_now()


func _cleanup() -> void:
	if _squad:
		_squad.queue_free()
	if _nav:
		_nav.queue_free()
	if _entities:
		_entities.queue_free()
	if _player:
		_player.queue_free()


func _test_pressure_role_assignment_stable_across_recompute() -> void:
	_player.global_position = Vector2(180.0, 60.0)
	_squad.recompute_now()

	var ok := true
	for child_variant in _entities.get_children():
		var enemy := child_variant as FakeEnemy
		var assignment := _squad.get_assignment(enemy.entity_id) as Dictionary
		if int(assignment.get("role", -1)) != _squad.Role.PRESSURE:
			continue
		if not bool(assignment.get("has_slot", false)):
			ok = false

	_t.run_test("PRESSURE-role enemies retain slots after recompute", ok)


func _test_hold_role_uses_exit_slots_not_ring_when_nav_provides_doors() -> void:
	_squad.recompute_now()
	var door_positions := [Vector2(100, 0), Vector2(0, 100)]
	var found_exit_slot := false
	for child_variant in _entities.get_children():
		var enemy := child_variant as FakeEnemy
		var assignment := _squad.get_assignment(enemy.entity_id) as Dictionary
		if int(assignment.get("role", -1)) != _squad.Role.HOLD:
			continue
		if not bool(assignment.get("has_slot", false)):
			continue
		var pos := assignment.get("slot_position", Vector2.ZERO) as Vector2
		for door_pos in door_positions:
			if pos.distance_to(door_pos) <= 1.0:
				found_exit_slot = true

	_t.run_test("At least one HOLD-role enemy uses an exit slot", found_exit_slot)


func _test_squad_role_enum_has_no_patrol_value() -> void:
	var ok := true
	for i in range(18):
		var role := int(_squad._stable_role_for_enemy_id(1000 + i))
		if not (role == 0 or role == 1 or role == 2):
			ok = false
	_t.run_test("Squad roles are limited to PRESSURE/HOLD/FLANK", ok)
