extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeNav:
	extends Node

	func room_id_at_point(_p: Vector2) -> int:
		return 0

	func can_enemy_traverse_point(_enemy: Node, _point: Vector2) -> bool:
		return true

	func build_reachable_path_points(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null) -> Array[Vector2]:
		return [to_pos]

	func build_policy_valid_path(from_pos: Vector2, to_pos: Vector2, enemy: Node = null) -> Dictionary:
		var path := build_reachable_path_points(from_pos, to_pos, enemy)
		if path.is_empty():
			return {
				"status": "unreachable_geometry",
				"path_points": [],
				"reason": "path_unreachable",
			}
		return {
			"status": "ok",
			"path_points": path,
			"reason": "ok",
		}

	func nav_path_length(from_pos: Vector2, to_pos: Vector2, _enemy: Node = null) -> float:
		return from_pos.distance_to(to_pos)


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("PURSUIT ORIGIN TARGET NOT SENTINEL TEST")
	print("============================================================")

	_test_origin_target_is_valid()

	_t.summary("PURSUIT ORIGIN TARGET NOT SENTINEL RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_origin_target_is_valid() -> void:
	var owner := CharacterBody2D.new()
	owner.global_position = Vector2(64.0, 0.0)
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	add_child(owner)

	var nav := FakeNav.new()
	add_child(nav)

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	pursuit.configure_navigation(nav, 0)

	var plan_origin_ok := bool(pursuit.call("_plan_path_to", Vector2.ZERO, true))
	var plan_missing_target := bool(pursuit.call("_plan_path_to", Vector2.ZERO, false))

	var intent := {
		"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT,
		"target": Vector2.ZERO,
	}
	var context := {
		"player_pos": Vector2(160.0, 0.0),
		"los": true,
		"dist": 160.0,
		"alert_level": 3,
	}
	var result := pursuit.execute_intent(1.0 / 60.0, intent, context) as Dictionary
	var snapshot := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
	var active_target := snapshot.get("active_move_target", Vector2.ONE) as Vector2

	_t.run_test("planner accepts explicit origin target", plan_origin_ok)
	_t.run_test("planner rejects missing target", not plan_missing_target)
	_t.run_test(
		"origin target intent does not fail as no_target",
		not bool(result.get("path_failed", true)) and String(result.get("path_failed_reason", "")) != "no_target"
	)
	_t.run_test("active target validity flag is true", bool(snapshot.get("active_move_target_valid", false)))
	_t.run_test("active target can equal origin", active_target.distance_to(Vector2.ZERO) <= 0.001)

	owner.queue_free()
	nav.queue_free()
