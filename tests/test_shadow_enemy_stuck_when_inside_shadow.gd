extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const NAVIGATION_SERVICE_SCRIPT := preload("res://src/systems/navigation_service.gd")
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
	print("SHADOW: ENEMY STUCK WHEN INSIDE SHADOW TEST")
	print("============================================================")

	await _test_enemy_inside_shadow_can_continue_moving_without_grant()

	_t.summary("SHADOW: ENEMY STUCK WHEN INSIDE SHADOW RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_enemy_inside_shadow_can_continue_moving_without_grant() -> void:
	var world := Node2D.new()
	add_child(world)

	var nav := NAVIGATION_SERVICE_SCRIPT.new()
	world.add_child(nav)

	var zone := SHADOW_ZONE_SCRIPT.new()
	zone.position = Vector2.ZERO
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(220.0, 160.0)
	shape_node.shape = shape
	zone.add_child(shape_node)
	world.add_child(zone)

	var enemy := FakeEnemy.new()
	enemy.global_position = Vector2(0.0, 0.0)
	enemy.flashlight_active = false
	world.add_child(enemy)

	await get_tree().process_frame
	await get_tree().physics_frame

	var candidate := enemy.global_position + Vector2(18.0, 0.0)
	var start_in_shadow := bool(nav.is_point_in_shadow(enemy.global_position))
	var candidate_in_shadow := bool(nav.is_point_in_shadow(candidate))
	var can_step := bool(nav.can_enemy_traverse_point(enemy, candidate))

	_t.run_test("setup: enemy starts in shadow", start_in_shadow)
	_t.run_test("setup: candidate point remains in shadow", candidate_in_shadow)
	_t.run_test("enemy already in shadow can keep moving in shadow without flashlight grant", can_step)

	world.queue_free()
	await get_tree().process_frame
