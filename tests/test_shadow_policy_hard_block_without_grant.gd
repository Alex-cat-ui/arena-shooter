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

	var blocked_x: float = 48.0

	func can_enemy_traverse_point(enemy: Node, point: Vector2) -> bool:
		var has_grant := false
		if enemy and enemy.has_method("is_flashlight_active_for_navigation"):
			has_grant = bool(enemy.call("is_flashlight_active_for_navigation"))
		if has_grant:
			return true
		return point.x < blocked_x

	func build_reachable_path_points(from_pos: Vector2, to_pos: Vector2, enemy: Node = null) -> Array:
		if can_enemy_traverse_point(enemy, to_pos):
			return [to_pos]
		# Force path through blocked shadow segment.
		return [Vector2(blocked_x + 18.0, from_pos.y), to_pos]

	func nav_path_length(from_pos: Vector2, to_pos: Vector2, enemy: Node = null) -> float:
		var path := build_reachable_path_points(from_pos, to_pos, enemy)
		var total := 0.0
		var prev := from_pos
		for point_variant in path:
			var point := point_variant as Vector2
			if not can_enemy_traverse_point(enemy, point):
				return INF
			total += prev.distance_to(point)
			prev = point
		return total


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("SHADOW POLICY HARD BLOCK WITHOUT GRANT TEST")
	print("============================================================")

	await _test_policy_block_and_fallback()

	_t.summary("SHADOW POLICY HARD BLOCK WITHOUT GRANT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_policy_block_and_fallback() -> void:
	var world := Node2D.new()
	add_child(world)

	var nav := FakeNav.new()
	world.add_child(nav)

	var owner := FakeEnemy.new()
	owner.global_position = Vector2.ZERO
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	world.add_child(owner)
	await get_tree().physics_frame

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	pursuit.configure_navigation(nav, 0)

	var target := Vector2(160.0, 0.0)
	for _i in range(16):
		pursuit.call("_execute_move_to_target", 0.2, target, 1.0)
		await get_tree().physics_frame

	var snap := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
	var fallback_target := snap.get("policy_fallback_target", Vector2.ZERO) as Vector2
	_t.run_test("blocked shadow segment is marked as policy_blocked", String(snap.get("path_failed_reason", "")) == "policy_blocked")
	_t.run_test("replan limit triggers nearest-reachable fallback", bool(snap.get("policy_fallback_used", false)))
	_t.run_test("fallback target avoids shadow without grant", fallback_target.x < nav.blocked_x)
	_t.run_test("enemy starts moving on fallback path", owner.global_position.distance_to(Vector2.ZERO) > 0.1)

	world.queue_free()
	await get_tree().process_frame
