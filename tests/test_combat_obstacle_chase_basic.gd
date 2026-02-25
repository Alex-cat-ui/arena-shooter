extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const STEALTH_ROOM_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakePatrolDecision:
	extends RefCounted

	var fixed_target: Vector2 = Vector2.ZERO
	var fixed_speed_scale: float = 0.9

	func _init(target: Vector2, speed_scale: float = 0.9) -> void:
		fixed_target = target
		fixed_speed_scale = speed_scale

	func configure(_nav_system: Node, _home_room_id: int) -> void:
		pass

	func update(_delta: float, _facing_dir: Vector2) -> Dictionary:
		return {
			"waiting": false,
			"target": fixed_target,
			"speed_scale": fixed_speed_scale,
		}


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
	if RuntimeState:
		RuntimeState.player_hp = 100
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := room.get_node_or_null("Stealth3ZoneTestController")
	var player := room.get_node_or_null("Entities/Player") as CharacterBody2D
	var enemy := _first_member_in_group_under("enemies", room) as Enemy
	var nav_service := room.get_node_or_null("Systems/NavigationService")

	_t.run_test("obstacle chase: controller exists", controller != null)
	_t.run_test("obstacle chase: player exists", player != null)
	_t.run_test("obstacle chase: enemy exists", enemy != null)
	_t.run_test("obstacle chase: navigation service exists", nav_service != null)
	if controller == null or player == null or enemy == null or nav_service == null:
		room.queue_free()
		await get_tree().process_frame
		return

	enemy.global_position = Vector2(460.0, 20.0)
	enemy.velocity = Vector2.ZERO
	player.global_position = Vector2(-320.0, 20.0)
	player.velocity = Vector2.ZERO
	if controller.has_method("_set_test_weapons_enabled"):
		controller.call("_set_test_weapons_enabled", false)
	await get_tree().physics_frame
	var nav_ready := await _wait_for_navmesh_path(enemy, enemy.global_position, player.global_position)
	_t.run_test("obstacle chase: navmesh path is ready", nav_ready)
	if not nav_ready:
		room.queue_free()
		await get_tree().process_frame
		return

	var patrol_metrics := await _run_precombat_patrol_segment(enemy, player.global_position)
	_t.run_test("obstacle chase: pre-combat PATROL moves", float(patrol_metrics.get("moved_total", 0.0)) > 8.0)
	_t.run_test(
		"obstacle chase: pre-combat PATROL reduces distance to player",
		float(patrol_metrics.get("final_distance", INF)) < float(patrol_metrics.get("initial_distance", INF))
	)
	_t.run_test(
		"obstacle chase: pre-combat PATROL advances while direct path is blocked",
		bool(patrol_metrics.get("direct_path_blocked_start", false))
			and bool(patrol_metrics.get("progress_while_blocked", false))
	)
	_t.run_test(
		"obstacle chase: pre-combat snapshot exposes geometry traverse source",
		String(patrol_metrics.get("traverse_check_source", "")) == "geometry_api"
	)
	_t.run_test(
		"obstacle chase: pre-combat snapshot exposes route source contract",
		String(patrol_metrics.get("route_source", "")) != ""
			and patrol_metrics.get("obstacle_intersection_detected", null) is bool
	)

	var path_contract := nav_service.call("build_policy_valid_path", enemy.global_position, player.global_position, enemy) as Dictionary
	var obstacle_intersection := bool(path_contract.get("obstacle_intersection_detected", false))
	var segment_intersection := false
	if nav_service.has_method("path_intersects_navigation_obstacles"):
		segment_intersection = bool(
			nav_service.call(
				"path_intersects_navigation_obstacles",
				enemy.global_position,
				path_contract.get("path_points", []) as Array
			)
		)
	_t.run_test("obstacle chase: path contract reports route_source", String(path_contract.get("route_source", "")) != "")
	_t.run_test(
		"obstacle chase: path segment-vs-obstacle validation blocks intersections",
		not obstacle_intersection and not segment_intersection
	)

	_press_key(controller, KEY_3)
	await get_tree().physics_frame

	var initial_distance := enemy.global_position.distance_to(player.global_position)
	var initial_blocked := _ray_blocked(enemy, enemy.global_position, player.global_position)
	var moved_total := 0.0
	var prev_pos := enemy.global_position
	var lateral_min_y := prev_pos.y
	var lateral_max_y := prev_pos.y
	var max_step_px := 0.0
	for _i in range(220):
		await get_tree().physics_frame
		await get_tree().process_frame
		var current_pos := enemy.global_position
		var step_px := current_pos.distance_to(prev_pos)
		moved_total += step_px
		max_step_px = maxf(max_step_px, step_px)
		lateral_min_y = minf(lateral_min_y, current_pos.y)
		lateral_max_y = maxf(lateral_max_y, current_pos.y)
		prev_pos = current_pos
	var final_distance := enemy.global_position.distance_to(player.global_position)
	var lateral_span := lateral_max_y - lateral_min_y

	_t.run_test("obstacle chase: obstacle initially blocks direct ray", initial_blocked)
	_t.run_test("obstacle chase: COMBAT chase reduces distance to player", final_distance < initial_distance)
	_t.run_test("obstacle chase: enemy is not stationary", moved_total > 8.0)
	# L1 detour was removed in navmesh migration (Phase 4/7); NavigationAgent2D handles paths.
	_t.run_test("obstacle chase: l1 detour removed - navmesh handles avoidance", moved_total > 8.0)
	_t.run_test("obstacle chase: honest repath has no teleport spikes", max_step_px <= 24.0)

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


func _run_precombat_patrol_segment(enemy: Enemy, player_pos: Vector2, frames: int = 90) -> Dictionary:
	if enemy == null:
		return {
			"initial_distance": INF,
			"final_distance": INF,
			"moved_total": 0.0,
			"direct_path_blocked_start": false,
			"progress_while_blocked": false,
		}
	var pursuit = enemy.debug_get_pursuit_system_for_test()
	if pursuit == null:
		return {
			"initial_distance": INF,
			"final_distance": INF,
			"moved_total": 0.0,
			"direct_path_blocked_start": false,
			"progress_while_blocked": false,
		}

	var prev_patrol: Variant = pursuit.get("_patrol")
	pursuit.set("_patrol", FakePatrolDecision.new(player_pos, 0.9))

	var prev_physics_processing := enemy.is_physics_processing()
	enemy.set_physics_process(false)

	var initial_distance := enemy.global_position.distance_to(player_pos)
	var moved_total := 0.0
	var prev_pos := enemy.global_position
	var direct_path_blocked_start := _ray_blocked(enemy, enemy.global_position, player_pos)
	var progress_while_blocked := false
	var final_snapshot: Dictionary = {}
	for _i in range(frames):
		pursuit.execute_intent(
			1.0 / 60.0,
			{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL},
			{
				"player_pos": player_pos,
				"known_target_pos": Vector2.ZERO,
				"last_seen_pos": Vector2.ZERO,
				"investigate_anchor": Vector2.ZERO,
				"home_position": Vector2.ZERO,
				"alert_level": 0,
				"los": false,
				"combat_lock": false,
			}
		)
		await get_tree().physics_frame
		var current_pos := enemy.global_position
		var step_px := current_pos.distance_to(prev_pos)
		moved_total += step_px
		if _ray_blocked(enemy, current_pos, player_pos) and step_px > 0.15:
			progress_while_blocked = true
		prev_pos = current_pos
		final_snapshot = pursuit.debug_get_navigation_policy_snapshot() as Dictionary

	enemy.set_physics_process(prev_physics_processing)
	pursuit.set("_patrol", prev_patrol)
	await get_tree().physics_frame

	return {
		"initial_distance": initial_distance,
		"final_distance": enemy.global_position.distance_to(player_pos),
		"moved_total": moved_total,
		"direct_path_blocked_start": direct_path_blocked_start,
		"progress_while_blocked": progress_while_blocked,
		"traverse_check_source": String(final_snapshot.get("traverse_check_source", "")),
		"route_source": String(final_snapshot.get("path_route_source", "")),
		"obstacle_intersection_detected": bool(final_snapshot.get("obstacle_intersection_detected", false)),
	}
