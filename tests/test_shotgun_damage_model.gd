## test_shotgun_damage_model.gd
## Validates shotgun kill-threshold math and pellet blocking by world solids.
extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")

const SHOTGUN_DAMAGE_MODEL_SCRIPT := preload("res://src/systems/shotgun_damage_model.gd")
const PROJECTILE_SCENE := preload("res://scenes/entities/projectile.tscn")
const DOOR_SCRIPT := preload("res://src/systems/door_physics_v3.gd")

var _t := TestHelpers.new()


func _ready() -> void:
	print("=" .repeat(60))
	print("SHOTGUN DAMAGE MODEL TEST")
	print("=" .repeat(60))

	await _run_tests()

	_t.summary("SHOTGUN MODEL RESULTS")
	get_tree().quit(_t.quit_code())


func _run_tests() -> void:
	_t.check("Threshold 80% of 16 = 13", SHOTGUN_DAMAGE_MODEL_SCRIPT.kill_threshold(16) == 13)
	_t.check("12/16 is not lethal", not SHOTGUN_DAMAGE_MODEL_SCRIPT.is_lethal_hits(12, 16))
	_t.check("13/16 is lethal", SHOTGUN_DAMAGE_MODEL_SCRIPT.is_lethal_hits(13, 16))
	_t.check("0 hits => 0 damage", SHOTGUN_DAMAGE_MODEL_SCRIPT.damage_for_hits(0, 16, 25.0) == 0)
	_t.check("8/16 of 25 => 13 damage", SHOTGUN_DAMAGE_MODEL_SCRIPT.damage_for_hits(8, 16, 25.0) == 13)
	_t.check("1/16 of 25 => 2 damage", SHOTGUN_DAMAGE_MODEL_SCRIPT.damage_for_hits(1, 16, 25.0) == 2)
	await _test_pellet_blocked_by_wall()
	await _test_pellet_blocked_by_door()


func _test_pellet_blocked_by_wall() -> void:
	var world := Node2D.new()
	world.name = "ShotgunWorld"
	add_child(world)

	var wall := StaticBody2D.new()
	wall.name = "TestWall"
	wall.collision_layer = 1
	wall.collision_mask = 0
	var wall_shape := CollisionShape2D.new()
	var wall_rect := RectangleShape2D.new()
	wall_rect.size = Vector2(20.0, 200.0)
	wall_shape.shape = wall_rect
	wall.add_child(wall_shape)
	wall.position = Vector2(120.0, 0.0)
	world.add_child(wall)

	var projectile := PROJECTILE_SCENE.instantiate() as Projectile
	world.add_child(projectile)
	projectile.initialize(1, "pellet", Vector2.ZERO, Vector2.RIGHT, 1000.0, 1, 1, 16, 25.0)

	for i in range(20):
		await get_tree().process_frame
		if not is_instance_valid(projectile):
			break

	var blocked := not is_instance_valid(projectile)
	_t.check("Pellet is destroyed by wall collision", blocked)

	if is_instance_valid(projectile):
		projectile.queue_free()
	world.queue_free()


func _test_pellet_blocked_by_door() -> void:
	var world := Node2D.new()
	world.name = "ShotgunDoorWorld"
	add_child(world)

	var door := DOOR_SCRIPT.new()
	world.add_child(door)
	door.configure_from_opening(Rect2(100.0, 0.0, 60.0, 16.0), 16.0)
	await get_tree().process_frame

	var projectile := PROJECTILE_SCENE.instantiate() as Projectile
	world.add_child(projectile)
	projectile.initialize(2, "pellet", Vector2(0.0, 8.0), Vector2.RIGHT, 1000.0, 1, 2, 16, 25.0)

	for i in range(20):
		await get_tree().process_frame
		if not is_instance_valid(projectile):
			break

	var blocked := not is_instance_valid(projectile)
	_t.check("Pellet is destroyed by door collision", blocked)

	if is_instance_valid(projectile):
		projectile.queue_free()
	world.queue_free()

