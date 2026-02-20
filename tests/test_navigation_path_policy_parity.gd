extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const NAVIGATION_SERVICE_SCRIPT := preload("res://src/systems/navigation_service.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const SHADOW_ZONE_SCRIPT := preload("res://src/systems/stealth/shadow_zone.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeEnemy:
	extends CharacterBody2D
	var flashlight_active: bool = false

	func is_flashlight_active_for_navigation() -> bool:
		return flashlight_active


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("NAVIGATION PATH POLICY PARITY TEST")
	print("============================================================")

	await _test_path_policy_parity()

	_t.summary("NAVIGATION PATH POLICY PARITY RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_path_policy_parity() -> void:
	var world := Node2D.new()
	add_child(world)

	var nav := NAVIGATION_SERVICE_SCRIPT.new()
	world.add_child(nav)

	var zone := SHADOW_ZONE_SCRIPT.new()
	zone.position = Vector2.ZERO
	var zone_shape_node := CollisionShape2D.new()
	var zone_shape := RectangleShape2D.new()
	zone_shape.size = Vector2(120.0, 140.0)
	zone_shape_node.shape = zone_shape
	zone.add_child(zone_shape_node)
	world.add_child(zone)
	await get_tree().process_frame
	await get_tree().physics_frame

	var enemy := FakeEnemy.new()
	enemy.global_position = Vector2(-100.0, 0.0)
	enemy.flashlight_active = false
	world.add_child(enemy)

	var sprite := Sprite2D.new()
	enemy.add_child(sprite)
	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(enemy, sprite, 2.0)
	pursuit.configure_navigation(nav, 0)

	var blocked_path: Array[Vector2] = [Vector2(100.0, 0.0)]
	var blocked_nav := bool(nav.call("_path_crosses_policy_block", enemy, enemy.global_position, blocked_path))
	var blocked_validation := pursuit.call("_validate_path_policy", enemy.global_position, blocked_path) as Dictionary
	_t.run_test(
		"blocked shadow segment parity",
		blocked_nav and not bool(blocked_validation.get("valid", true)) and int(blocked_validation.get("segment_index", -1)) == 0
	)

	enemy.flashlight_active = true
	var lit_nav := bool(nav.call("_path_crosses_policy_block", enemy, enemy.global_position, blocked_path))
	var lit_validation := pursuit.call("_validate_path_policy", enemy.global_position, blocked_path) as Dictionary
	_t.run_test(
		"flashlight override parity",
		not lit_nav and bool(lit_validation.get("valid", false))
	)

	enemy.flashlight_active = false
	enemy.global_position = Vector2(0.0, 0.0)
	var inside_path: Array[Vector2] = [Vector2(20.0, 0.0)]
	var inside_nav := bool(nav.call("_path_crosses_policy_block", enemy, enemy.global_position, inside_path))
	var inside_validation := pursuit.call("_validate_path_policy", enemy.global_position, inside_path) as Dictionary
	_t.run_test(
		"inside-shadow escape parity",
		not inside_nav and bool(inside_validation.get("valid", false))
	)

	world.queue_free()
	await get_tree().process_frame
