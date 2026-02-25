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

	var controller := room.get_node_or_null("Stealth3ZoneTestController")
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
	await get_tree().physics_frame
	var nav_ready := await _wait_for_navmesh_path(enemy, enemy.global_position, player.global_position)
	_t.run_test("honest repath: navmesh path is ready", nav_ready)
	if not nav_ready:
		room.queue_free()
		await get_tree().process_frame
		return

	var patrol_metrics := await _run_precombat_patrol_segment(enemy, player.global_position)
	_t.run_test(
		"honest repath: pre-combat patrol moves",
		float(patrol_metrics.get("moved_total", 0.0)) > 8.0
	)
	_t.run_test(
		"honest repath: pre-combat patrol distance to player decreases",
		float(patrol_metrics.get("final_distance", INF)) < float(patrol_metrics.get("initial_distance", INF))
	)
	_t.run_test(
		"honest repath: pre-combat patrol has no teleport spikes",
		float(patrol_metrics.get("max_step_px", INF)) <= 24.0
	)

	_press_key(controller, KEY_3)
	await get_tree().physics_frame

	var collision_snapshot_keys_ok := false
	var initial_snapshot := enemy.debug_get_pursuit_navigation_policy_snapshot_for_test()
	if not initial_snapshot.is_empty():
		collision_snapshot_keys_ok = (
			initial_snapshot.has("collision_kind")
			and initial_snapshot.has("collision_forced_repath")
			and initial_snapshot.has("collision_reason")
			and initial_snapshot.has("collision_index")
		)

	var initial_distance := enemy.global_position.distance_to(player.global_position)
	var moved_total := 0.0
	var max_step_px := 0.0
	var prev_pos := enemy.global_position
	var non_door_collision_snapshot_ok := true
	for _i in range(240):
		await get_tree().physics_frame
		await get_tree().process_frame
		var current_pos := enemy.global_position
		var step_px := current_pos.distance_to(prev_pos)
		moved_total += step_px
		max_step_px = maxf(max_step_px, step_px)
		prev_pos = current_pos
		var snapshot := enemy.debug_get_pursuit_navigation_policy_snapshot_for_test()
		if not snapshot.is_empty():
			if String(snapshot.get("collision_kind", "")) == "non_door":
				non_door_collision_snapshot_ok = (
					non_door_collision_snapshot_ok
					and bool(snapshot.get("collision_forced_repath", false))
					and String(snapshot.get("collision_reason", "")) == "collision_blocked"
					and int(snapshot.get("collision_index", -1)) >= 0
				)
	var final_distance := enemy.global_position.distance_to(player.global_position)

	_t.run_test("honest repath: enemy moves", moved_total > 8.0)
	_t.run_test("honest repath: distance to player decreases", final_distance < initial_distance)
	# avoidance_enabled = true since Phase 7; single-enemy scenario, no RVO partner, max_step_px threshold 24.0 unchanged.
	_t.run_test("honest repath: no teleport/forced unstuck spikes", max_step_px <= 24.0)
	_t.run_test("honest repath: phase3 collision snapshot keys exposed", collision_snapshot_keys_ok)
	_t.run_test("honest repath: non-door collision snapshots stay consistent when observed", non_door_collision_snapshot_ok)

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


func _run_precombat_patrol_segment(enemy: Enemy, player_pos: Vector2, frames: int = 90) -> Dictionary:
	if enemy == null:
		return {
			"initial_distance": INF,
			"final_distance": INF,
			"moved_total": 0.0,
			"max_step_px": INF,
		}
	var pursuit = enemy.debug_get_pursuit_system_for_test()
	if pursuit == null:
		return {
			"initial_distance": INF,
			"final_distance": INF,
			"moved_total": 0.0,
			"max_step_px": INF,
		}

	var prev_patrol: Variant = pursuit.get("_patrol")
	pursuit.set("_patrol", FakePatrolDecision.new(player_pos, 0.9))

	var prev_physics_processing := enemy.is_physics_processing()
	enemy.set_physics_process(false)

	var initial_distance := enemy.global_position.distance_to(player_pos)
	var moved_total := 0.0
	var max_step_px := 0.0
	var prev_pos := enemy.global_position
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
		max_step_px = maxf(max_step_px, step_px)
		prev_pos = current_pos

	enemy.set_physics_process(prev_physics_processing)
	pursuit.set("_patrol", prev_patrol)
	await get_tree().physics_frame

	return {
		"initial_distance": initial_distance,
		"final_distance": enemy.global_position.distance_to(player_pos),
		"moved_total": moved_total,
		"max_step_px": max_step_px,
	}
