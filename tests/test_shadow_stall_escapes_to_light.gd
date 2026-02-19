extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeEnemy:
	extends CharacterBody2D

	var flashlight_active: bool = false

	func is_flashlight_active_for_navigation() -> bool:
		return flashlight_active


class FakeNav:
	extends Node

	var shadow_edge_x: float = 20.0
	var blocked_deep_shadow_x: float = -60.0

	func is_point_in_shadow(point: Vector2) -> bool:
		return point.x < shadow_edge_x

	func can_enemy_traverse_point(enemy: Node, point: Vector2) -> bool:
		var has_grant := false
		if enemy and enemy.has_method("is_flashlight_active_for_navigation"):
			has_grant = bool(enemy.call("is_flashlight_active_for_navigation"))
		if has_grant:
			return true
		return point.x >= blocked_deep_shadow_x

	func build_reachable_path_points(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null) -> Array:
		return [to_pos]

	func nav_path_length(from_pos: Vector2, to_pos: Vector2, enemy: Node = null) -> float:
		var steps := maxi(int(ceil(from_pos.distance_to(to_pos) / 12.0)), 1)
		for step in range(1, steps + 1):
			var t := float(step) / float(steps)
			var sample := from_pos.lerp(to_pos, t)
			if not can_enemy_traverse_point(enemy, sample):
				return INF
		return from_pos.distance_to(to_pos)


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("SHADOW STALL ESCAPES TO LIGHT TEST")
	print("============================================================")

	await _test_shadow_stall_prefers_escape_to_light()

	_t.summary("SHADOW STALL ESCAPES TO LIGHT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_shadow_stall_prefers_escape_to_light() -> void:
	var world := Node2D.new()
	add_child(world)

	var nav := FakeNav.new()
	world.add_child(nav)

	var owner := FakeEnemy.new()
	owner.global_position = Vector2(-40.0, 0.0)
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	world.add_child(owner)
	await get_tree().physics_frame

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	pursuit.configure_navigation(nav, 0)

	var blocked_shadow_target := Vector2(-140.0, 0.0)
	var escape_target_in_light_seen := false
	var escaped_to_light := false

	for _i in range(240):
		pursuit.call("_execute_move_to_target", 1.0 / 60.0, blocked_shadow_target, 1.0)
		await get_tree().physics_frame
		var snap := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
		var escape_target := snap.get("shadow_escape_target", Vector2.ZERO) as Vector2
		if bool(snap.get("shadow_escape_active", false)) and escape_target.x >= nav.shadow_edge_x:
			escape_target_in_light_seen = true
		if owner.global_position.x >= nav.shadow_edge_x:
			escaped_to_light = true
			break

	_t.run_test("setup: owner starts in shadow", nav.is_point_in_shadow(Vector2(-40.0, 0.0)))
	_t.run_test("shadow stall picks escape target in light", escape_target_in_light_seen)
	_t.run_test("enemy exits shadow to light during recovery", escaped_to_light)
	_t.run_test("after recovery owner remains outside shadow", escaped_to_light and not nav.is_point_in_shadow(owner.global_position))

	owner.queue_free()
	nav.queue_free()
	world.queue_free()
	await get_tree().process_frame
