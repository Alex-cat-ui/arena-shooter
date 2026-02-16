extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const STEALTH_ROOM_SCENE := preload("res://src/levels/stealth_test_room.tscn")

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
	print("COMBAT OBSTACLE CHASE BASIC TEST")
	print("============================================================")

	await _test_combat_obstacle_chase_basic()

	_t.summary("COMBAT OBSTACLE CHASE BASIC RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_combat_obstacle_chase_basic() -> void:
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := room.get_node_or_null("StealthTestController")
	var player := room.get_node_or_null("Entities/Player") as CharacterBody2D
	var enemy := _first_member_in_group_under("enemies", room) as Enemy

	_t.run_test("obstacle chase: controller exists", controller != null)
	_t.run_test("obstacle chase: player exists", player != null)
	_t.run_test("obstacle chase: enemy exists", enemy != null)
	if controller == null or player == null or enemy == null:
		room.queue_free()
		await get_tree().process_frame
		return

	enemy.global_position = Vector2(460.0, 20.0)
	enemy.velocity = Vector2.ZERO
	player.global_position = Vector2(-320.0, 20.0)
	player.velocity = Vector2.ZERO
	if controller.has_method("_set_test_weapons_enabled"):
		controller.call("_set_test_weapons_enabled", false)
	if enemy.has_method("disable_suspicion_test_profile"):
		enemy.disable_suspicion_test_profile()
	await get_tree().physics_frame

	_press_key(controller, KEY_3)
	await get_tree().physics_frame

	var initial_distance := enemy.global_position.distance_to(player.global_position)
	var initial_blocked := _ray_blocked(enemy, enemy.global_position, player.global_position)
	var moved_total := 0.0
	var prev_pos := enemy.global_position
	for _i in range(220):
		await get_tree().physics_frame
		await get_tree().process_frame
		var current_pos := enemy.global_position
		moved_total += current_pos.distance_to(prev_pos)
		prev_pos = current_pos
	var final_distance := enemy.global_position.distance_to(player.global_position)

	_t.run_test("obstacle chase: obstacle initially blocks direct ray", initial_blocked)
	_t.run_test("obstacle chase: COMBAT chase reduces distance to player", final_distance < initial_distance)
	_t.run_test("obstacle chase: enemy is not stationary", moved_total > 8.0)

	room.queue_free()
	await get_tree().process_frame


func _ray_blocked(enemy: Enemy, from_pos: Vector2, to_pos: Vector2) -> bool:
	if enemy == null or enemy.get_world_2d() == null:
		return false
	var query := PhysicsRayQueryParameters2D.create(from_pos, to_pos)
	query.exclude = [enemy.get_rid()]
	query.collide_with_areas = false
	query.collision_mask = 1
	var hit := enemy.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var hit_pos := hit.get("position", to_pos) as Vector2
	return hit_pos.distance_to(to_pos) > 8.0


func _press_key(controller: Node, keycode: Key) -> void:
	var key := InputEventKey.new()
	key.pressed = true
	key.echo = false
	key.physical_keycode = keycode
	controller.call("_unhandled_input", key)


func _first_member_in_group_under(group_name: String, ancestor: Node) -> Node:
	for member_variant in get_tree().get_nodes_in_group(group_name):
		var member := member_variant as Node
		if member == null:
			continue
		if member == ancestor or ancestor.is_ancestor_of(member):
			return member
	return null
