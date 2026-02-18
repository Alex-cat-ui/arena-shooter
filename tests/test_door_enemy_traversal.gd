extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LAYOUT_DOOR_SYSTEM_SCRIPT := preload("res://src/systems/layout_door_system.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeLayout:
	extends RefCounted

	var valid: bool = true
	var doors: Array = [Rect2(-60.0, -6.0, 120.0, 12.0)]
	var _entry_gate: Rect2 = Rect2()

	func _door_wall_thickness() -> float:
		return 16.0


class PursuitDriver:
	extends Node

	var pursuit: Variant = null
	var speed_scale: float = 1.0

	func _physics_process(_delta: float) -> void:
		if pursuit == null:
			return
		pursuit.call("_follow_waypoints", speed_scale, 1.0 / 60.0)


func _ready() -> void:
	if embedded_mode:
		return
	var result = await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("DOOR ENEMY TRAVERSAL TEST")
	print("============================================================")

	await _test_door_blocks_enemy_movement()
	await _test_enemy_opens_door_when_blocked()
	await _test_enemy_passes_through_open_door()
	await _test_door_does_not_push_enemy()
	await _test_closed_door_blocks_los()

	_t.summary("DOOR ENEMY TRAVERSAL RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_door_blocks_enemy_movement() -> void:
	var world := await _create_world()
	var door := world.get("door", null) as Node2D
	var enemy := TestHelpers.spawn_mover(world["root"], Vector2(0.0, 56.0), 2, 1, "enemies")
	var collided := false
	for _i in range(120):
		enemy.velocity = Vector2(0.0, -180.0)
		enemy.move_and_slide()
		if enemy.get_slide_collision_count() > 0:
			collided = true
		await get_tree().physics_frame

	var door_body := door.get_node_or_null("DoorBody") as StaticBody2D
	var blocked := enemy.global_position.y > 6.0
	var layer_mask_ok := door_body != null and door_body.collision_layer == 1 and (enemy.collision_mask & 1) != 0
	_t.run_test("door_blocks_enemy_movement", collided and blocked and layer_mask_ok)

	enemy.queue_free()
	await _free_world(world)


func _test_enemy_opens_door_when_blocked() -> void:
	var world := await _create_world()
	var door := world.get("door", null) as Node2D
	var enemy := TestHelpers.spawn_mover(world["root"], Vector2(0.0, 56.0), 2, 1, "enemies")
	enemy.set_meta("door_system", world["door_system"])
	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(enemy, null, 2.4)
	pursuit.call("_plan_path_to", Vector2(0.0, -120.0))
	var driver := PursuitDriver.new()
	driver.pursuit = pursuit
	world["root"].add_child(driver)

	var opened := false
	for _i in range(320):
		await get_tree().physics_frame
		var metrics := door.get_debug_metrics() as Dictionary
		var angle_deg := absf(float(metrics.get("angle_deg", 0.0)))
		if angle_deg > 0.5:
			opened = true
			break

	_t.run_test("enemy_opens_door_when_blocked", opened)

	enemy.queue_free()
	await _free_world(world)


func _test_enemy_passes_through_open_door() -> void:
	var world := await _create_world()
	var enemy := TestHelpers.spawn_mover(world["root"], Vector2(0.0, 56.0), 2, 1, "enemies")
	enemy.set_meta("door_system", world["door_system"])
	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(enemy, null, 2.4)
	var target := Vector2(0.0, -120.0)
	pursuit.call("_plan_path_to", target)
	var driver := PursuitDriver.new()
	driver.pursuit = pursuit
	world["root"].add_child(driver)

	var reached := false
	for _i in range(720):
		await get_tree().physics_frame
		if enemy.global_position.distance_to(target) <= 18.0:
			reached = true
			break

	_t.run_test("enemy_passes_through_open_door", reached)

	enemy.queue_free()
	await _free_world(world)


func _test_door_does_not_push_enemy() -> void:
	var world := await _create_world()
	var door := world.get("door", null) as Node2D
	var enemy := TestHelpers.spawn_mover(world["root"], Vector2(-92.0, 48.0), 2, 1, "enemies")
	var start_pos := enemy.global_position
	var max_displacement := 0.0

	for i in range(180):
		if i % 45 == 0:
			door.command_open_enemy(Vector2(0.0, 80.0))
		elif i % 45 == 22:
			door.command_close()
		enemy.velocity = Vector2.ZERO
		enemy.move_and_slide()
		await get_tree().physics_frame
		max_displacement = maxf(max_displacement, enemy.global_position.distance_to(start_pos))

	_t.run_test("door_does_not_push_enemy", max_displacement <= 3.0)

	enemy.queue_free()
	await _free_world(world)


func _test_closed_door_blocks_los() -> void:
	var world := await _create_world()
	var door := world.get("door", null) as Node2D
	var query := PhysicsRayQueryParameters2D.create(Vector2(0.0, 48.0), Vector2(0.0, -48.0))
	query.collision_mask = 1
	query.collide_with_areas = false
	var hit: Dictionary = world["root"].get_world_2d().direct_space_state.intersect_ray(query)
	var collider := hit.get("collider", null) as Node
	var hit_door_body := collider != null and collider.name == "DoorBody" and collider.get_parent() == door
	_t.run_test("closed_door_blocks_los", not hit.is_empty() and hit_door_body)

	await _free_world(world)


func _create_world() -> Dictionary:
	var root = Node2D.new()
	add_child(root)

	TestHelpers.add_wall(root, Vector2(-180.0, 0.0), Vector2(240.0, 16.0))
	TestHelpers.add_wall(root, Vector2(180.0, 0.0), Vector2(240.0, 16.0))

	var doors_parent = Node2D.new()
	doors_parent.name = "LayoutDoors"
	root.add_child(doors_parent)

	var door_system = LAYOUT_DOOR_SYSTEM_SCRIPT.new()
	door_system.name = "LayoutDoorSystem"
	root.add_child(door_system)
	door_system.initialize(doors_parent)
	door_system.rebuild_for_layout(FakeLayout.new())

	await get_tree().process_frame
	await get_tree().physics_frame

	var door = door_system.find_nearest_door(Vector2.ZERO, 9999.0)
	return {
		"root": root,
		"door_system": door_system,
		"door": door,
	}


func _free_world(world: Dictionary) -> void:
	var root = world.get("root", null) as Node
	if root:
		root.queue_free()
	await get_tree().physics_frame
