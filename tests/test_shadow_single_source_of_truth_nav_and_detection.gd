extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const NAVIGATION_SERVICE_SCRIPT := preload("res://src/systems/navigation_service.gd")
const SHADOW_ZONE_SCRIPT := preload("res://src/systems/stealth/shadow_zone.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("SHADOW SINGLE SOURCE OF TRUTH (NAV + DETECTION) TEST")
	print("============================================================")

	await _test_single_source_of_truth()

	_t.summary("SHADOW SINGLE SOURCE OF TRUTH (NAV + DETECTION) RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_single_source_of_truth() -> void:
	if RuntimeState:
		RuntimeState.is_frozen = false
		RuntimeState.player_hp = 100
		RuntimeState.player_visibility_mul = 1.0

	var world := Node2D.new()
	add_child(world)

	var nav := NAVIGATION_SERVICE_SCRIPT.new()
	world.add_child(nav)

	var zone := SHADOW_ZONE_SCRIPT.new()
	zone.position = Vector2(220.0, 0.0)
	var zone_shape_node := CollisionShape2D.new()
	var zone_shape := RectangleShape2D.new()
	zone_shape.size = Vector2(180.0, 140.0)
	zone_shape_node.shape = zone_shape
	zone.add_child(zone_shape_node)
	world.add_child(zone)

	var player := CharacterBody2D.new()
	player.add_to_group("player")
	player.global_position = zone.global_position
	world.add_child(player)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = Vector2.ZERO
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(7501, "zombie")
	enemy.set_room_navigation(nav, -1)

	if RuntimeState:
		RuntimeState.player_visibility_mul = 1.0
	enemy.runtime_budget_tick(0.25)
	await get_tree().process_frame

	var nav_in_shadow := bool(nav.is_point_in_shadow(player.global_position))
	var snap_in := enemy.get_debug_detection_snapshot() as Dictionary
	var shadow_mul_in := float(snap_in.get("shadow_mul", 1.0))
	_t.run_test("nav check enters shadow via ShadowZone.contains_point", nav_in_shadow)
	_t.run_test(
		"detection shadow uses NavigationService source (runtime override=1.0 ignored)",
		nav_in_shadow and is_equal_approx(shadow_mul_in, 0.0)
	)

	player.global_position += Vector2(280.0, 0.0)
	if RuntimeState:
		RuntimeState.player_visibility_mul = 0.0
	enemy.runtime_budget_tick(0.25)
	await get_tree().process_frame

	var nav_outside_shadow := bool(nav.is_point_in_shadow(player.global_position))
	var snap_out := enemy.get_debug_detection_snapshot() as Dictionary
	var shadow_mul_out := float(snap_out.get("shadow_mul", 0.0))
	_t.run_test("nav check exits shadow via ShadowZone.contains_point", not nav_outside_shadow)
	_t.run_test(
		"detection shadow uses NavigationService source (runtime override=0.0 ignored)",
		not nav_outside_shadow and is_equal_approx(shadow_mul_out, 1.0)
	)

	world.queue_free()
	await get_tree().process_frame
	if RuntimeState:
		RuntimeState.player_visibility_mul = 1.0
