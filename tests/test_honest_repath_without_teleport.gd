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
	print("HONEST REPATH WITHOUT TELEPORT TEST")
	print("============================================================")

	await _test_honest_repath_without_teleport()

	_t.summary("HONEST REPATH WITHOUT TELEPORT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_honest_repath_without_teleport() -> void:
	if RuntimeState:
		RuntimeState.player_hp = 100
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := room.get_node_or_null("StealthTestController")
	var player := room.get_node_or_null("Entities/Player") as CharacterBody2D
	var enemy := _first_member_in_group_under("enemies", room) as Enemy

	_t.run_test("honest repath: controller exists", controller != null)
	_t.run_test("honest repath: player exists", player != null)
	_t.run_test("honest repath: enemy exists", enemy != null)
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
	var nav_ready := await _wait_for_navmesh_path(enemy, enemy.global_position, player.global_position)
	_t.run_test("honest repath: navmesh path is ready", nav_ready)
	if not nav_ready:
		room.queue_free()
		await get_tree().process_frame
		return

	_press_key(controller, KEY_3)
	await get_tree().physics_frame

	var initial_distance := enemy.global_position.distance_to(player.global_position)
	var moved_total := 0.0
	var max_step_px := 0.0
	var prev_pos := enemy.global_position
	for _i in range(240):
		await get_tree().physics_frame
		await get_tree().process_frame
		var current_pos := enemy.global_position
		var step_px := current_pos.distance_to(prev_pos)
		moved_total += step_px
		max_step_px = maxf(max_step_px, step_px)
		prev_pos = current_pos
	var final_distance := enemy.global_position.distance_to(player.global_position)

	_t.run_test("honest repath: enemy moves", moved_total > 8.0)
	_t.run_test("honest repath: distance to player decreases", final_distance < initial_distance)
	_t.run_test("honest repath: no teleport/forced unstuck spikes", max_step_px <= 24.0)

	room.queue_free()
	await get_tree().process_frame


func _press_key(controller: Node, keycode: Key) -> void:
	var key := InputEventKey.new()
	key.pressed = true
	key.echo = false
	key.physical_keycode = keycode
	controller.call("_unhandled_input", key)


func _wait_for_navmesh_path(enemy: Enemy, from_pos: Vector2, to_pos: Vector2, max_frames: int = 20) -> bool:
	if enemy == null:
		return false
	var nav_agent := enemy.get_node_or_null("NavAgent") as NavigationAgent2D
	if nav_agent == null:
		return false
	for _i in range(max_frames):
		var nav_map: RID = nav_agent.get_navigation_map()
		if nav_map.is_valid():
			var path := NavigationServer2D.map_get_path(nav_map, from_pos, to_pos, true)
			if not path.is_empty():
				return true
		await get_tree().physics_frame
	return false


func _first_member_in_group_under(group_name: String, ancestor: Node) -> Node:
	for member_variant in get_tree().get_nodes_in_group(group_name):
		var member := member_variant as Node
		if member == null:
			continue
		if member == ancestor or ancestor.is_ancestor_of(member):
			return member
	return null
