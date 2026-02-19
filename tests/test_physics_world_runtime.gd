extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const PHYSICS_WORLD_SCRIPT := preload("res://src/systems/physics_world.gd")

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
	print("PHYSICS WORLD RUNTIME TEST")
	print("============================================================")

	await _test_physics_world_runtime_contract()

	_t.summary("PHYSICS WORLD RUNTIME RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_physics_world_runtime_contract() -> void:
	var physics_world := PHYSICS_WORLD_SCRIPT.new()
	add_child(physics_world)

	var world_2d := get_viewport().get_world_2d()
	physics_world.initialize(world_2d.space if world_2d != null else RID())

	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 1
	wall.global_position = Vector2(80.0, 0.0)
	var wall_shape := CollisionShape2D.new()
	var wall_rect := RectangleShape2D.new()
	wall_rect.size = Vector2(20.0, 160.0)
	wall_shape.shape = wall_rect
	wall.add_child(wall_shape)
	add_child(wall)

	var mover := CharacterBody2D.new()
	mover.collision_layer = 1
	mover.collision_mask = 1
	mover.global_position = Vector2.ZERO
	var mover_shape := CollisionShape2D.new()
	var mover_circle := CircleShape2D.new()
	mover_circle.radius = 8.0
	mover_shape.shape = mover_circle
	mover.add_child(mover_shape)
	add_child(mover)

	await _await_physics_frames()

	var ray_hit := physics_world.raycast(Vector3.ZERO, Vector3.RIGHT, 200.0, 1)
	var ray_pos: Variant = ray_hit.get("position", Vector3.ZERO)
	_t.run_test(
		"raycast hits static body and returns Vector3 position",
		not ray_hit.is_empty()
		and ray_pos is Vector3
		and float((ray_pos as Vector3).x) >= 65.0
		and float((ray_pos as Vector3).x) <= 95.0
	)

	var overlaps := physics_world.overlap_circle(Vector3(80.0, 0.0, 0.0), 24.0, 1)
	var overlap_has_wall := false
	for hit_variant in overlaps:
		var hit := hit_variant as Dictionary
		if hit.get("collider", null) == wall:
			overlap_has_wall = true
			break
	_t.run_test("overlap_circle returns collider dictionaries for intersecting bodies", overlap_has_wall)

	var move_result := physics_world.move_and_collide(mover.get_rid(), Vector3(200.0, 0.0, 0.0))
	var move_pos: Variant = move_result.get("position", Vector3.ZERO)
	var move_normal: Variant = move_result.get("collision_normal", Vector3.ZERO)
	_t.run_test(
		"move_and_collide reports collision with Vector3 outputs",
		bool(move_result.get("collided", false))
		and move_pos is Vector3
		and move_normal is Vector3
		and float((move_pos as Vector3).x) < 200.0
	)

	mover.queue_free()
	wall.queue_free()
	physics_world.queue_free()
	await get_tree().process_frame


func _await_physics_frames(frames: int = 3) -> void:
	for _i in range(frames):
		await get_tree().physics_frame
