extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SQUAD_SYSTEM_SCRIPT := preload("res://src/systems/enemy_squad_system.gd")


class FakeNav extends Node:
	var room_rect := Rect2(Vector2(-320.0, -220.0), Vector2(640.0, 440.0))
	var player_pos := Vector2.ZERO
	var invalidate_flank_ring: bool = false
	var layout: Node = null

	func _init() -> void:
		layout = self # No _navigation_obstacles() API; wall-cover-only baseline.

	func room_id_at_point(_p: Vector2) -> int:
		return 0

	func get_room_rect(_room_id: int) -> Rect2:
		return room_rect

	func build_policy_valid_path(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null) -> Dictionary:
		if invalidate_flank_ring and to_pos.distance_to(player_pos) >= 580.0:
			return {
				"status": "unreachable_policy",
				"reason": "policy_blocked",
				"path_points": [],
				"blocked_point": to_pos,
			}
		return {
			"status": "ok",
			"reason": "ok",
			"path_points": [to_pos],
		}


class FakeEnemy extends CharacterBody2D:
	var entity_id: int = 0
	var is_dead: bool = false


var embedded_mode: bool = false
var _t := TestHelpers.new()

var _player: Node2D = null
var _entities: Node2D = null
var _nav: FakeNav = null
var _squad = null


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("COMBAT ROLE DISTRIBUTION NOT ALL PRESSURE TEST")
	print("============================================================")

	_setup()
	_test_slot_role_distribution_uses_multiple_tactical_roles()
	_test_flank_invalid_candidates_demote_slot_role()
	_test_hold_assignments_publish_cover_sources_when_room_rect_available()
	_cleanup()

	_t.summary("COMBAT ROLE DISTRIBUTION NOT ALL PRESSURE RESULTS")
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
		enemy.entity_id = 1000 + i
		enemy.global_position = Vector2(-260.0 + 32.0 * float(i), -90.0 + 20.0 * float(i % 3))
		_entities.add_child(enemy)
		enemy.add_to_group("enemies")

	_nav = FakeNav.new()
	_nav.player_pos = _player.global_position
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


func _test_slot_role_distribution_uses_multiple_tactical_roles() -> void:
	_nav.invalidate_flank_ring = false
	_squad.recompute_now()
	var seen := {}
	for child_variant in _entities.get_children():
		var enemy := child_variant as FakeEnemy
		var assignment := _squad.get_assignment(enemy.entity_id) as Dictionary
		if not bool(assignment.get("has_slot", false)):
			continue
		seen[int(assignment.get("slot_role", -1))] = true
	var roles_seen := seen.keys()
	var not_all_pressure := not (roles_seen.size() == 1 and seen.has(_squad.Role.PRESSURE))
	_t.run_test(
		"Slot role distribution uses multiple tactical roles (not all PRESSURE)",
		roles_seen.size() >= 2 and not_all_pressure
	)


func _test_flank_invalid_candidates_demote_slot_role() -> void:
	_nav.invalidate_flank_ring = true
	_squad.recompute_now()
	var flank_demoted := false
	var invalid_flank_slot_survived := false
	for child_variant in _entities.get_children():
		var enemy := child_variant as FakeEnemy
		var assignment := _squad.get_assignment(enemy.entity_id) as Dictionary
		if not bool(assignment.get("has_slot", false)):
			continue
		var stable_role := int(assignment.get("role", -1))
		var slot_role := int(assignment.get("slot_role", -1))
		var path_status := String(assignment.get("path_status", ""))
		if stable_role == _squad.Role.FLANK and (slot_role == _squad.Role.HOLD or slot_role == _squad.Role.PRESSURE):
			flank_demoted = true
		if slot_role == _squad.Role.FLANK and path_status != "ok":
			invalid_flank_slot_survived = true
	_t.run_test("Invalid FLANK candidates demote slot_role", flank_demoted)
	_t.run_test("No invalid FLANK tactical slot survives selection", not invalid_flank_slot_survived)
	_nav.invalidate_flank_ring = false


func _test_hold_assignments_publish_cover_sources_when_room_rect_available() -> void:
	_nav.invalidate_flank_ring = false
	_squad.recompute_now()
	var has_wall_cover_hold := false
	for child_variant in _entities.get_children():
		var enemy := child_variant as FakeEnemy
		var assignment := _squad.get_assignment(enemy.entity_id) as Dictionary
		if not bool(assignment.get("has_slot", false)):
			continue
		if (
			int(assignment.get("slot_role", -1)) == _squad.Role.HOLD
			and String(assignment.get("cover_source", "")) == "wall"
		):
			has_wall_cover_hold = true
	_t.run_test("HOLD assignments publish wall cover sources when room rect available", has_wall_cover_hold)
