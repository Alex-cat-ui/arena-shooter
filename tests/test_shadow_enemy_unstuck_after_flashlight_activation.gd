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
	print("SHADOW: ENEMY UNSTUCK AFTER FLASHLIGHT ACTIVATION TEST")
	print("============================================================")

	await _test_combat_flashlight_grant_applies_to_navigation_immediately()

	_t.summary("SHADOW: ENEMY UNSTUCK AFTER FLASHLIGHT ACTIVATION RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_combat_flashlight_grant_applies_to_navigation_immediately() -> void:
	if RuntimeState:
		RuntimeState.is_frozen = false
		RuntimeState.player_visibility_mul = 1.0

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

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame

	enemy.initialize(8901, "zombie")
	enemy.global_position = Vector2(0.0, 0.0)
	enemy.debug_force_awareness_state("COMBAT")

	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	var candidate := enemy.global_position + Vector2(20.0, 0.0)
	var candidate_in_shadow := bool(nav.is_point_in_shadow(candidate))
	var can_step := bool(nav.can_enemy_traverse_point(enemy, candidate))

	_t.run_test("setup: enemy forced into COMBAT", String(snapshot.get("state_name", "")) == "COMBAT")
	_t.run_test("setup: candidate point remains in shadow", candidate_in_shadow)
	_t.run_test("combat flashlight grant applies to navigation immediately", can_step)

	world.queue_free()
	await get_tree().process_frame
	if RuntimeState:
		RuntimeState.player_visibility_mul = 1.0
