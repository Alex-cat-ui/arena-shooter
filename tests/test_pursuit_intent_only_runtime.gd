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

	func build_policy_valid_path(from_pos: Vector2, to_pos: Vector2, enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
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

	func random_point_in_room(_room_id: int, _margin: float = 20.0) -> Vector2:
		return Vector2(24.0, 0.0)


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("PURSUIT INTENT-ONLY RUNTIME TEST")
	print("============================================================")

	_test_intent_runtime_without_legacy_update_path()

	_t.summary("PURSUIT INTENT-ONLY RUNTIME RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_intent_runtime_without_legacy_update_path() -> void:
	var owner := CharacterBody2D.new()
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	add_child(owner)

	var nav := FakeNav.new()
	add_child(nav)

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	pursuit.configure_navigation(nav, 0)

	_t.run_test("legacy update(delta,use_room_nav,...) API removed", not pursuit.has_method("update"))

	var push_intent := {
		"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH,
		"target": Vector2(120.0, 0.0),
	}
	var push_ctx := {
		"player_pos": Vector2(120.0, 0.0),
		"los": true,
		"dist": 120.0,
		"alert_level": 2,
		"combat_lock": true,
	}
	var push_result := pursuit.execute_intent(1.0 / 60.0, push_intent, push_ctx) as Dictionary
	var push_ok := bool(push_result.get("movement_intent", false)) and not bool(push_result.get("path_failed", true))
	var facing_ok := pursuit.get_target_facing_dir().dot(Vector2.RIGHT) > 0.9
	_t.run_test("intent runtime executes PUSH without legacy path", push_ok)
	_t.run_test("intent runtime updates facing toward PUSH target", facing_ok)

	var search_intent := {
		"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH,
		"target": Vector2(30.0, 0.0),
	}
	var search_result := pursuit.execute_intent(1.0 / 60.0, search_intent, {}) as Dictionary
	_t.run_test("SEARCH intent keeps movement_intent=false", not bool(search_result.get("movement_intent", true)))

	owner.queue_free()
	nav.queue_free()
