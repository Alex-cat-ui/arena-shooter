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


class FakeLayout:
	extends RefCounted
	var valid: bool = true
	var rooms: Array = [
		{
			"center": Vector2(-100.0, 0.0),
			"rects": [Rect2(-220.0, -120.0, 220.0, 240.0)],
		},
		{
			"center": Vector2(100.0, 0.0),
			"rects": [Rect2(0.0, -120.0, 220.0, 240.0)],
		},
	]
	var doors: Array = []
	var _door_adj: Dictionary = {
		0: [1],
		1: [0],
	}

	func _room_id_at_point(p: Vector2) -> int:
		return 0 if p.x < 0.0 else 1


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
	nav.layout = FakeLayout.new()
	var stub_region := NavigationRegion2D.new()
	nav._nav_regions = [stub_region]
	nav._room_graph = {
		0: [1],
		1: [0],
	}
	nav._pair_doors = {
		"0|1": [Vector2(-12.0, 0.0), Vector2(12.0, 0.0)],
	}

	var enemy := FakeEnemy.new()
	enemy.global_position = Vector2(-100.0, 0.0)
	enemy.flashlight_active = false
	world.add_child(enemy)

	var target := Vector2(100.0, 0.0)
	var blocked_plan := nav.build_policy_valid_path(enemy.global_position, target, enemy) as Dictionary
	_t.run_test(
		"build_policy_valid_path returns unreachable_policy when only route is shadow-blocked",
		String(blocked_plan.get("status", "")) == "unreachable_policy"
			and String(blocked_plan.get("reason", "")) == "policy_blocked"
			and (blocked_plan.get("path_points", []) as Array).is_empty()
	)

	enemy.flashlight_active = true
	var lit_plan := nav.build_policy_valid_path(enemy.global_position, target, enemy) as Dictionary
	var lit_path := lit_plan.get("path_points", []) as Array
	_t.run_test(
		"flashlight override allows build_policy_valid_path direct route_type",
		String(lit_plan.get("status", "")) == "ok"
			and String(lit_plan.get("reason", "")) == "ok"
			and String(lit_plan.get("route_type", "")) == "direct"
			and not lit_path.is_empty()
	)

	nav._nav_regions.clear()
	stub_region.free()
	world.queue_free()
	await get_tree().process_frame
