extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SQUAD_SYSTEM_SCRIPT := preload("res://src/systems/enemy_squad_system.gd")


class FakeNav extends Node:
	var room_rect := Rect2(Vector2(-320.0, -220.0), Vector2(640.0, 440.0))
	var player_pos := Vector2.ZERO
	var block_wall_cover_paths: bool = false
	var layout: Node = null

	func _init() -> void:
		layout = self # No _navigation_obstacles() method on purpose.

	func room_id_at_point(_p: Vector2) -> int:
		return 0

	func get_room_rect(_room_id: int) -> Rect2:
		return room_rect

	func build_policy_valid_path(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null) -> Dictionary:
		if block_wall_cover_paths and _is_wall_cover_target(to_pos):
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

	func _is_wall_cover_target(pos: Vector2) -> bool:
		for wall_pos in _wall_cover_positions():
			if pos.distance_to(wall_pos) <= 0.5:
				return true
		return false

	func _wall_cover_positions() -> Array:
		var inset := 12.0
		return [
			Vector2(room_rect.position.x, room_rect.position.y + room_rect.size.y * 0.5) + Vector2(inset, 0.0),
			Vector2(room_rect.position.x + room_rect.size.x, room_rect.position.y + room_rect.size.y * 0.5) + Vector2(-inset, 0.0),
			Vector2(room_rect.position.x + room_rect.size.x * 0.5, room_rect.position.y) + Vector2(0.0, inset),
			Vector2(room_rect.position.x + room_rect.size.x * 0.5, room_rect.position.y + room_rect.size.y) + Vector2(0.0, -inset),
		]


class FakeEnemy extends CharacterBody2D:
	var entity_id: int = 1003 # Stable HOLD role bucket (1003 % 6 == 1).
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
	print("COMBAT COVER SELECTION PREFERS VALID COVER TEST")
	print("============================================================")

	_setup()
	_test_hold_slot_prefers_wall_cover_when_policy_valid()
	_test_policy_blocked_cover_falls_back_to_valid_exposed_slot()
	_test_assignment_publishes_cover_and_path_contract_fields()
	_cleanup()

	_t.summary("COMBAT COVER SELECTION PREFERS VALID COVER RESULTS")
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

	var enemy := FakeEnemy.new()
	enemy.global_position = Vector2(-250.0, 0.0)
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


func _assignment() -> Dictionary:
	var enemy := _entities.get_child(0) as FakeEnemy
	return _squad.get_assignment(enemy.entity_id) as Dictionary


func _test_hold_slot_prefers_wall_cover_when_policy_valid() -> void:
	_nav.block_wall_cover_paths = false
	_squad.recompute_now()
	var assignment := _assignment()
	_t.run_test(
		"HOLD cover selection prefers wall cover when policy-valid",
		int(assignment.get("slot_role", -1)) == _squad.Role.HOLD
		and String(assignment.get("cover_source", "")) == "wall"
		and String(assignment.get("path_status", "")) == "ok"
	)


func _test_policy_blocked_cover_falls_back_to_valid_exposed_slot() -> void:
	_nav.block_wall_cover_paths = true
	_squad.recompute_now()
	var assignment := _assignment()
	_t.run_test(
		"Policy-blocked wall cover falls back to valid exposed slot",
		String(assignment.get("path_status", "")) == "ok"
		and String(assignment.get("cover_source", "")) != "wall"
		and not bool(assignment.get("blocked_point_valid", false))
	)
	_nav.block_wall_cover_paths = false


func _test_assignment_publishes_cover_and_path_contract_fields() -> void:
	_squad.recompute_now()
	var assignment := _assignment()
	var ok := bool(assignment.get("has_slot", false))
	ok = ok \
		and assignment.has("slot_role") \
		and assignment.has("path_status") \
		and assignment.has("path_reason") \
		and assignment.has("slot_path_length") \
		and assignment.has("slot_path_eta_sec") \
		and assignment.has("cover_source") \
		and assignment.has("cover_los_break_quality") \
		and assignment.has("cover_score") \
		and typeof(assignment.get("slot_role", null)) == TYPE_INT \
		and typeof(assignment.get("path_status", null)) == TYPE_STRING \
		and typeof(assignment.get("slot_path_length", null)) == TYPE_FLOAT \
		and typeof(assignment.get("slot_path_eta_sec", null)) == TYPE_FLOAT \
		and typeof(assignment.get("cover_source", null)) == TYPE_STRING \
		and typeof(assignment.get("cover_los_break_quality", null)) == TYPE_FLOAT \
		and typeof(assignment.get("cover_score", null)) == TYPE_FLOAT
	_t.run_test("Assignment publishes cover/path contract fields", ok)
