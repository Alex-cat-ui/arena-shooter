extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const THREE_ZONE_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")

const ZONE_CALM := 0

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _observed_enemy_id: int = -1
var _observed_enemy_shots: int = 0


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("3-ZONE STEALTH SMOKE")
	print("============================================================")

	var fixture := await _create_fixture()
	var level := fixture.get("level", null) as Node2D
	var loaded_ok := bool(fixture.get("ok", false)) and level != null
	_t.run_test("level_loads_without_error", loaded_ok)
	if not loaded_ok:
		await _cleanup_fixture(fixture)
		_t.summary("3-ZONE STEALTH SMOKE RESULTS")
		return {
			"ok": _t.quit_code() == 0,
			"run": _t.tests_run,
			"passed": _t.tests_passed,
		}

	var nav := level.get_node_or_null("Systems/NavigationService")
	var zone_director := level.get_node_or_null("Systems/ZoneDirector")
	var player := level.get_node_or_null("Entities/Player") as Node2D
	var door := level.get_node_or_null("Doors/DoorA1A2")
	var shadow_root := level.get_node_or_null("ShadowAreas")
	var controller := level.get_node_or_null("Stealth3ZoneTestController")

	_test_six_enemies_spawned(level)
	_test_four_zones_calm(zone_director)
	_test_player_in_room_a1(nav, player)
	await _test_3zone_player_weapon_pipeline(level, controller, player)
	await _test_3zone_spawn_shadow_blocks_calm_detection(level)
	_test_door_a1a2_starts_closed(door)
	_test_shadow_areas_present(shadow_root)
	_test_all_spawns_inside_rooms(level, nav)
	await _test_chokes_are_navigable(level, controller)
	_test_walls_have_no_gaps(level, controller)
	await _test_door_a1a2_in_wall_gap(level)
	await _test_3zone_enemy_combat_fire(level)
	await _test_3zone_door_input_routes(level)
	await _test_3zone_pause_menu_on_esc(level)
	await _test_3zone_game_over_runtime_debug(level)

	await _cleanup_fixture(fixture)

	_t.summary("3-ZONE STEALTH SMOKE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _create_fixture() -> Dictionary:
	var level := THREE_ZONE_SCENE.instantiate() as Node2D
	if level == null:
		return {"ok": false, "level": null}
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	return {"ok": true, "level": level}


func _cleanup_fixture(fixture: Dictionary) -> void:
	var level := fixture.get("level", null) as Node
	if level and is_instance_valid(level):
		level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_six_enemies_spawned(level: Node) -> void:
	var enemies := _members_in_group_under("enemies", level)
	_t.run_test("six_enemies_spawned", enemies.size() == 6)


func _test_four_zones_calm(zone_director: Node) -> void:
	if zone_director == null or not zone_director.has_method("get_zone_state"):
		_t.run_test("four_zones_calm", false)
		return
	var ok := int(zone_director.get_zone_state(0)) == ZONE_CALM
	ok = ok and int(zone_director.get_zone_state(1)) == ZONE_CALM
	ok = ok and int(zone_director.get_zone_state(2)) == ZONE_CALM
	ok = ok and int(zone_director.get_zone_state(3)) == ZONE_CALM
	_t.run_test("four_zones_calm", ok)


func _test_player_in_room_a1(nav: Node, player: Node2D) -> void:
	if nav == null or player == null or not nav.has_method("room_id_at_point"):
		_t.run_test("player_in_room_a1", false)
		return
	var room_id := int(nav.room_id_at_point(player.global_position))
	_t.run_test("player_in_room_a1", room_id == 0)


func _test_3zone_player_weapon_pipeline(level: Node2D, controller: Node, player: CharacterBody2D) -> void:
	if controller == null or player == null or not controller.has_method("debug_get_combat_pipeline_summary"):
		_t.run_test("3zone player weapon pipeline wired", false)
		_t.run_test("3zone weapon_2 switches player to shotgun", false)
		return
	var summary := controller.call("debug_get_combat_pipeline_summary") as Dictionary
	var pipeline_ok := (
		bool(summary.get("combat_system_exists", false))
		and bool(summary.get("projectile_system_exists", false))
		and bool(summary.get("ability_system_exists", false))
		and bool(summary.get("player_ability_wired", false))
		and bool(summary.get("ability_projectile_wired", false))
		and bool(summary.get("ability_combat_wired", false))
	)
	_t.run_test("3zone player weapon pipeline wired", pipeline_ok)

	var ability: Variant = player.ability_system if "ability_system" in player else null
	var switched := false
	if ability != null and ability.has_method("set_weapon_by_index") and ability.has_method("get_current_weapon"):
		ability.set_weapon_by_index(0)
		await get_tree().physics_frame
		Input.action_press("weapon_2")
		await get_tree().physics_frame
		await get_tree().process_frame
		Input.action_release("weapon_2")
		await get_tree().process_frame
		switched = String(ability.get_current_weapon()) == "shotgun"
	else:
		Input.action_release("weapon_2")
	_t.run_test("3zone weapon_2 switches player to shotgun", switched)


func _test_3zone_spawn_shadow_blocks_calm_detection(level: Node2D) -> void:
	var player := level.get_node_or_null("Entities/Player") as CharacterBody2D
	var shadow_a1 := level.get_node_or_null("ShadowAreas/ShadowA1") as Area2D
	var enemies := _members_in_group_under("enemies", level)
	if player == null or shadow_a1 == null or enemies.is_empty():
		_t.run_test("3zone spawn shadow setup is valid", false)
		_t.run_test("3zone CALM in shadow keeps enemies calm", false)
		_t.run_test("3zone CALM in shadow keeps confirm near zero", false)
		return

	var player_start := player.global_position
	player.global_position = shadow_a1.global_position
	player.velocity = Vector2.ZERO
	for _i in range(8):
		await get_tree().physics_frame
		await get_tree().process_frame

	var visibility_mul := float(RuntimeState.player_visibility_mul) if RuntimeState else 1.0
	_t.run_test("3zone spawn shadow setup is valid", visibility_mul < 0.999)

	var stayed_calm := true
	var max_confirm := 0.0
	for _frame in range(180):
		await get_tree().physics_frame
		await get_tree().process_frame
		for enemy_variant in enemies:
			var enemy := enemy_variant as Enemy
			if enemy == null or not is_instance_valid(enemy):
				continue
			if not enemy.has_method("get_ui_awareness_snapshot"):
				continue
			var snap := enemy.get_ui_awareness_snapshot() as Dictionary
			var state := int(snap.get("state", 0))
			var confirm01 := float(snap.get("confirm01", 0.0))
			if state != 0:
				stayed_calm = false
			max_confirm = maxf(max_confirm, confirm01)

	_t.run_test("3zone CALM in shadow keeps enemies calm", stayed_calm)
	_t.run_test("3zone CALM in shadow keeps confirm near zero", max_confirm <= 0.05)

	player.global_position = player_start
	player.velocity = Vector2.ZERO
	for _i in range(4):
		await get_tree().physics_frame
		await get_tree().process_frame


func _test_door_a1a2_starts_closed(door: Node) -> void:
	if door == null or not door.has_method("get_debug_metrics"):
		_t.run_test("door_a1a2_starts_closed", false)
		return
	var metrics := door.get_debug_metrics() as Dictionary
	var angle_deg := absf(float(metrics.get("angle_deg", 999.0)))
	_t.run_test("door_a1a2_starts_closed", angle_deg <= 0.1)


func _test_shadow_areas_present(shadow_root: Node) -> void:
	if shadow_root == null:
		_t.run_test("shadow_areas_present", false)
		return
	var count := 0
	for child_variant in shadow_root.get_children():
		var child := child_variant as Node
		if child == null:
			continue
		if child.get("shadow_multiplier") != null:
			count += 1
	_t.run_test("shadow_areas_present", count == 6)


func _test_all_spawns_inside_rooms(level: Node, nav: Node) -> void:
	if nav == null or not nav.has_method("room_id_at_point"):
		_t.run_test("all_spawns_inside_rooms", false)
		return
	var spawns := level.get_node_or_null("Spawns")
	if spawns == null:
		_t.run_test("all_spawns_inside_rooms", false)
		return
	var spawn_names := ["SpawnA1", "SpawnA2", "SpawnB", "SpawnC1", "SpawnC2", "SpawnD"]
	var ok := true
	for spawn_name_variant in spawn_names:
		var spawn_name := String(spawn_name_variant)
		var spawn := spawns.get_node_or_null(spawn_name) as Node2D
		if spawn == null:
			ok = false
			continue
		ok = ok and int(nav.room_id_at_point(spawn.global_position)) >= 0
	_t.run_test("all_spawns_inside_rooms", ok)


func _test_chokes_are_navigable(level: Node2D, controller: Node) -> void:
	if controller == null or not controller.has_method("debug_get_choke_rect"):
		_t.run_test("chokes_are_navigable", false)
		return
	var choke_ab := controller.call("debug_get_choke_rect", "AB") as Rect2
	var choke_bc := controller.call("debug_get_choke_rect", "BC") as Rect2
	if choke_ab == Rect2() or choke_bc == Rect2():
		_t.run_test("chokes_are_navigable", false)
		return

	var ab_center := choke_ab.get_center()
	var bc_center := choke_bc.get_center()
	var ok_ab_up := await _can_advance(level, ab_center, Vector2(0.0, -180.0))
	var ok_ab_down := await _can_advance(level, ab_center, Vector2(0.0, 180.0))
	var ok_bc_left := await _can_advance(level, bc_center, Vector2(-180.0, 0.0))
	var ok_bc_right := await _can_advance(level, bc_center, Vector2(180.0, 0.0))
	_t.run_test("chokes_are_navigable", ok_ab_up and ok_ab_down and ok_bc_left and ok_bc_right)


func _can_advance(level: Node2D, start_pos: Vector2, velocity: Vector2, frames: int = 16) -> bool:
	var mover := CharacterBody2D.new()
	mover.collision_layer = 4
	mover.collision_mask = 1
	mover.safe_margin = 2.0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.8
	shape.shape = circle
	mover.add_child(shape)
	level.add_child(mover)
	mover.global_position = start_pos
	mover.velocity = velocity

	var origin := mover.global_position
	for _i in range(frames):
		mover.move_and_slide()
		await get_tree().physics_frame

	var moved_dist := mover.global_position.distance_to(origin)
	mover.queue_free()
	await get_tree().physics_frame
	return moved_dist >= 24.0


func _test_walls_have_no_gaps(level: Node2D, controller: Node) -> void:
	if controller == null or not controller.has_method("debug_get_room_rects") or not controller.has_method("debug_get_wall_thickness"):
		_t.run_test("walls_have_no_gaps", false)
		return
	var room_rects := controller.call("debug_get_room_rects") as Array
	var wall_t := float(controller.call("debug_get_wall_thickness"))
	if room_rects.is_empty():
		_t.run_test("walls_have_no_gaps", false)
		return

	var dirs := [
		{"dir": Vector2.LEFT, "axis": "x"},
		{"dir": Vector2.RIGHT, "axis": "x"},
		{"dir": Vector2.UP, "axis": "y"},
		{"dir": Vector2.DOWN, "axis": "y"},
	]
	var ok := true
	for room_index in range(room_rects.size()):
		var rect_variant = room_rects[room_index]
		var room := rect_variant as Rect2
		var center := room.get_center()
		for dir_info_variant in dirs:
			var dir_info := dir_info_variant as Dictionary
			var dir := dir_info.get("dir", Vector2.ZERO) as Vector2
			var axis := String(dir_info.get("axis", "x"))
			var expected_max := room.size.x if axis == "x" else room.size.y
			var perp := Vector2.DOWN if axis == "x" else Vector2.RIGHT
			var origins := [
				center,
				center + perp * 64.0,
				center - perp * 64.0,
			]
			var direction_ok := false
			for origin_variant in origins:
				var origin := origin_variant as Vector2
				var hit := _raycast(level, origin, origin + dir * (expected_max + 128.0), true)
				if hit.is_empty():
					continue
				var hit_pos := hit.get("position", Vector2.ZERO) as Vector2
				var distance := origin.distance_to(hit_pos)
				if distance <= expected_max + wall_t + 8.0:
					direction_ok = true
					break
			ok = ok and direction_ok
	_t.run_test("walls_have_no_gaps", ok)


func _test_door_a1a2_in_wall_gap(level: Node2D) -> void:
	var door := level.get_node_or_null("Doors/DoorA1A2")
	if door == null:
		_t.run_test("door_a1a2_in_wall_gap", false)
		return
	if door.has_method("reset_to_closed"):
		door.reset_to_closed()
	await get_tree().physics_frame

	var through_door_hit := _raycast(level, Vector2(600.0, 240.0), Vector2(700.0, 240.0), true)
	var through_wall_hit := _raycast(level, Vector2(600.0, 120.0), Vector2(700.0, 120.0), true)

	var door_ok := false
	if not through_door_hit.is_empty():
		var collider := through_door_hit.get("collider", null) as Node
		door_ok = collider != null and collider.name == "DoorBody"

	var wall_ok := false
	if not through_wall_hit.is_empty():
		var wall_collider := through_wall_hit.get("collider", null) as Node
		wall_ok = wall_collider != null and wall_collider.name != "DoorBody"

	_t.run_test("door_a1a2_in_wall_gap", door_ok and wall_ok)


func _test_3zone_door_input_routes(level: Node2D) -> void:
	var controller := level.get_node_or_null("Stealth3ZoneTestController")
	var player := level.get_node_or_null("Entities/Player") as CharacterBody2D
	var door := level.get_node_or_null("Doors/DoorA1A2")
	if controller == null or player == null or door == null:
		_t.run_test("3zone door input routes", false)
		return

	var prev_god_mode := false
	if GameConfig:
		prev_god_mode = bool(GameConfig.god_mode)
		GameConfig.god_mode = true

	var opening_center: Vector2 = door.global_position
	if door.has_method("get_opening_center_world"):
		var center_variant: Variant = door.call("get_opening_center_world")
		if center_variant is Vector2:
			opening_center = center_variant
	player.global_position = opening_center
	player.velocity = Vector2.ZERO
	if door.has_method("reset_to_closed"):
		door.reset_to_closed()
	await get_tree().physics_frame

	var interact_event := InputEventAction.new()
	interact_event.action = &"door_interact"
	interact_event.pressed = true
	controller.call("_unhandled_input", interact_event)
	var opened_by_interact := await _wait_door_angle_at_least(door, 10.0, 180)
	_t.run_test("3zone door_interact opens nearby door", opened_by_interact)

	if door.has_method("command_close"):
		door.command_close()
	await _wait_door_closed(door, 180)

	var kick_event := InputEventAction.new()
	kick_event.action = &"door_kick"
	kick_event.pressed = true
	controller.call("_unhandled_input", kick_event)
	var opened_by_kick := await _wait_door_angle_at_least(door, 10.0, 180)
	_t.run_test("3zone door_kick opens nearby door", opened_by_kick)

	if GameConfig:
		GameConfig.god_mode = prev_god_mode


func _wait_door_angle_at_least(door: Node, min_angle_deg: float, frames: int) -> bool:
	if door == null or not door.has_method("get_debug_metrics"):
		return false
	for _i in range(frames):
		await get_tree().physics_frame
		var metrics := door.get_debug_metrics() as Dictionary
		var angle_deg := absf(float(metrics.get("angle_deg", 0.0)))
		if angle_deg >= min_angle_deg:
			return true
	return false


func _wait_door_closed(door: Node, frames: int) -> bool:
	if door == null or not door.has_method("get_debug_metrics"):
		return false
	for _i in range(frames):
		await get_tree().physics_frame
		var metrics := door.get_debug_metrics() as Dictionary
		var angle_deg := absf(float(metrics.get("angle_deg", 999.0)))
		if angle_deg <= 1.2:
			return true
	return false


func _pick_clear_combat_target(level: Node2D, nav: Node, shooter_pos: Vector2) -> Dictionary:
	var offsets := [
		Vector2(140.0, 0.0),
		Vector2(-140.0, 0.0),
		Vector2(0.0, 140.0),
		Vector2(0.0, -140.0),
		Vector2(180.0, 120.0),
		Vector2(-180.0, 120.0),
		Vector2(180.0, -120.0),
		Vector2(-180.0, -120.0),
		Vector2(220.0, 0.0),
		Vector2(0.0, 220.0),
	]
	for offset_variant in offsets:
		var offset := offset_variant as Vector2
		var candidate := shooter_pos + offset
		if nav != null and nav.has_method("room_id_at_point"):
			if int(nav.call("room_id_at_point", candidate)) < 0:
				continue
		if nav != null and nav.has_method("is_point_in_shadow"):
			if bool(nav.call("is_point_in_shadow", candidate)):
				continue
		if _raycast(level, shooter_pos, candidate, true).is_empty():
			return {"ok": true, "pos": candidate}
	return {"ok": false, "pos": shooter_pos}


func _test_3zone_enemy_combat_fire(level: Node2D) -> void:
	var player := level.get_node_or_null("Entities/Player") as CharacterBody2D
	var nav := level.get_node_or_null("Systems/NavigationService")
	var enemies := _members_in_group_under("enemies", level)
	if player == null or enemies.is_empty():
		_t.run_test("3zone enemy fires in COMBAT", false)
		return

	var prev_god_mode := false
	if GameConfig:
		prev_god_mode = bool(GameConfig.god_mode)
		GameConfig.god_mode = true

	var shooter: Node2D = null
	for enemy_variant in enemies:
		var enemy := enemy_variant as Node2D
		if enemy == null:
			continue
		if nav and nav.has_method("room_id_at_point"):
			if int(nav.room_id_at_point(enemy.global_position)) == 0:
				shooter = enemy
				break
		if shooter == null:
			shooter = enemy
	if shooter == null:
		_t.run_test("3zone enemy fires in COMBAT", false)
		return

	var shooter_id := int(shooter.get("entity_id")) if shooter.get("entity_id") != null else -1
	if shooter_id <= 0:
		_t.run_test("3zone enemy fires in COMBAT", false)
		return

	for enemy_variant in enemies:
		var enemy := enemy_variant as Node2D
		if enemy == null or enemy == shooter:
			continue
		enemy.global_position = Vector2(-20000.0, -20000.0)
		enemy.set_meta("room_id", -1)

	shooter.global_position = Vector2(320.0, 240.0)
	shooter.set_meta("room_id", 0)
	var player_start := player.global_position
	var target_pick := _pick_clear_combat_target(level, nav, shooter.global_position)
	var setup_ok := bool(target_pick.get("ok", false))
	if not setup_ok:
		if GameConfig:
			GameConfig.god_mode = prev_god_mode
		_t.run_test("3zone enemy fires in COMBAT", false)
		return
	player.global_position = target_pick.get("pos", shooter.global_position + Vector2(140.0, 0.0)) as Vector2
	player.velocity = Vector2.ZERO
	for _settle in range(4):
		await get_tree().physics_frame
		await get_tree().process_frame

	_observed_enemy_id = shooter_id
	_observed_enemy_shots = 0
	if EventBus and not EventBus.enemy_shot.is_connected(_on_enemy_shot):
		EventBus.enemy_shot.connect(_on_enemy_shot)

	var facing_dir := (player.global_position - shooter.global_position).normalized()
	if facing_dir.length_squared() > 0.0001:
		var pursuit_variant: Variant = shooter.get("_pursuit")
		if pursuit_variant != null:
			var pursuit_obj := pursuit_variant as Object
			if pursuit_obj:
				pursuit_obj.set("facing_dir", facing_dir)
				pursuit_obj.set("_target_facing_dir", facing_dir)

	if shooter.has_method("debug_force_awareness_state"):
		shooter.call("debug_force_awareness_state", "COMBAT")
	if "_combat_first_shot_delay_armed" in shooter:
		shooter.set("_combat_first_shot_delay_armed", true)
	if "_combat_first_attack_delay_timer" in shooter:
		shooter.set("_combat_first_attack_delay_timer", 0.0)
	if "_shot_cooldown" in shooter:
		shooter.set("_shot_cooldown", 0.0)
	if shooter.has_method("set_physics_process"):
		shooter.set_physics_process(false)

	var fired := false
	for _i in range(360):
		if shooter.has_method("runtime_budget_tick"):
			shooter.call("runtime_budget_tick", 0.1)
		await get_tree().physics_frame
		await get_tree().process_frame
		if _observed_enemy_shots > 0:
			fired = true
			break

	if EventBus and EventBus.enemy_shot.is_connected(_on_enemy_shot):
		EventBus.enemy_shot.disconnect(_on_enemy_shot)
	_observed_enemy_id = -1
	_observed_enemy_shots = 0
	if shooter.has_method("set_physics_process"):
		shooter.set_physics_process(true)

	player.global_position = player_start
	player.velocity = Vector2.ZERO
	if GameConfig:
		GameConfig.god_mode = prev_god_mode
	_t.run_test("3zone enemy fires in COMBAT", fired)


func _on_enemy_shot(enemy_id: int, _weapon_type: String, _position: Vector3, _direction: Vector3) -> void:
	if enemy_id == _observed_enemy_id:
		_observed_enemy_shots += 1


func _test_3zone_pause_menu_on_esc(level: Node2D) -> void:
	var controller := level.get_node_or_null("Stealth3ZoneTestController")
	if controller == null:
		_t.run_test("3zone ESC opens pause menu", false)
		_t.run_test("3zone ESC closes pause menu", false)
		return

	var pause_event := InputEventAction.new()
	pause_event.action = &"pause"
	pause_event.pressed = true

	controller.call("_unhandled_input", pause_event)
	await get_tree().process_frame
	var pause_menu_open := level.find_child("PauseMenu", true, false)
	var opened := pause_menu_open != null
	var paused_ok := StateManager == null or StateManager.is_paused()
	_t.run_test("3zone ESC opens pause menu", opened and paused_ok)

	controller.call("_unhandled_input", pause_event)
	await get_tree().process_frame
	var pause_menu_closed := level.find_child("PauseMenu", true, false)
	var closed := pause_menu_closed == null
	var resumed_ok := StateManager == null or StateManager.is_playing()
	_t.run_test("3zone ESC closes pause menu", closed and resumed_ok)


func _test_3zone_game_over_runtime_debug(level: Node2D) -> void:
	var controller := level.get_node_or_null("Stealth3ZoneTestController")
	var label := level.get_node_or_null("DebugUI/DebugLabel") as Label
	var player := level.get_node_or_null("Entities/Player") as CharacterBody2D
	var nav := level.get_node_or_null("Systems/NavigationService")
	var enemies := _members_in_group_under("enemies", level)
	if controller == null or label == null or player == null or enemies.is_empty():
		_t.run_test("3zone reaches GAME_OVER in forced combat", false)
		_t.run_test("3zone debug label shows GAME_OVER freeze + hp", false)
		_t.run_test("3zone shows GameOver menu on GAME_OVER", false)
		return

	var prev_god_mode := false
	if GameConfig:
		prev_god_mode = bool(GameConfig.god_mode)
		GameConfig.god_mode = false

	if RuntimeState:
		RuntimeState.is_frozen = false
		RuntimeState.player_hp = 1
		RuntimeState.player_visibility_mul = 1.0

	var shooter: Node2D = null
	for enemy_variant in enemies:
		var enemy := enemy_variant as Node2D
		if enemy == null:
			continue
		if nav and nav.has_method("room_id_at_point"):
			if int(nav.room_id_at_point(enemy.global_position)) == 0:
				shooter = enemy
				break
		if shooter == null:
			shooter = enemy
	if shooter == null:
		_t.run_test("3zone reaches GAME_OVER in forced combat", false)
		_t.run_test("3zone debug label shows GAME_OVER freeze + hp", false)
		_t.run_test("3zone shows GameOver menu on GAME_OVER", false)
		if GameConfig:
			GameConfig.god_mode = prev_god_mode
		return

	for enemy_variant in enemies:
		var enemy := enemy_variant as Node2D
		if enemy == null or enemy == shooter:
			continue
		enemy.global_position = Vector2(-20000.0, -20000.0)
		enemy.set_meta("room_id", -1)

	shooter.global_position = Vector2(320.0, 240.0)
	shooter.set_meta("room_id", 0)
	var target_pick := _pick_clear_combat_target(level, nav, shooter.global_position)
	if not bool(target_pick.get("ok", false)):
		_t.run_test("3zone reaches GAME_OVER in forced combat", false)
		_t.run_test("3zone debug label shows GAME_OVER freeze + hp", false)
		_t.run_test("3zone shows GameOver menu on GAME_OVER", false)
		if GameConfig:
			GameConfig.god_mode = prev_god_mode
		return
	player.global_position = target_pick.get("pos", shooter.global_position + Vector2(140.0, 0.0)) as Vector2
	player.velocity = Vector2.ZERO
	for _settle in range(4):
		await get_tree().physics_frame
		await get_tree().process_frame

	var facing_dir := (player.global_position - shooter.global_position).normalized()
	if facing_dir.length_squared() > 0.0001:
		var pursuit_variant: Variant = shooter.get("_pursuit")
		if pursuit_variant != null:
			var pursuit_obj := pursuit_variant as Object
			if pursuit_obj:
				pursuit_obj.set("facing_dir", facing_dir)
				pursuit_obj.set("_target_facing_dir", facing_dir)

	if shooter.has_method("debug_force_awareness_state"):
		shooter.call("debug_force_awareness_state", "COMBAT")

	var reached_game_over := false
	var label_has_runtime_game_over := false
	var game_over_menu_visible := false
	for _i in range(540):
		await get_tree().physics_frame
		await get_tree().process_frame
		controller.call("_refresh_debug_label", true)
		var label_text := label.text
		if label_text.find("runtime state=GAME_OVER") >= 0 and label_text.find("frozen=true") >= 0 and label_text.find("player_hp=0") >= 0:
			label_has_runtime_game_over = true
		var game_over_menu := level.find_child("GameOver", true, false)
		if game_over_menu != null and bool(game_over_menu.get("visible")):
			game_over_menu_visible = true
		if StateManager and StateManager.current_state == GameState.State.GAME_OVER:
			reached_game_over = true
		if reached_game_over and label_has_runtime_game_over and game_over_menu_visible:
			break

	_t.run_test("3zone reaches GAME_OVER in forced combat", reached_game_over)
	_t.run_test("3zone debug label shows GAME_OVER freeze + hp", label_has_runtime_game_over)
	_t.run_test("3zone shows GameOver menu on GAME_OVER", game_over_menu_visible)

	if GameConfig:
		GameConfig.god_mode = prev_god_mode


func _raycast(level: Node2D, from: Vector2, to: Vector2, exclude_dynamic: bool) -> Dictionary:
	if level == null or level.get_world_2d() == null:
		return {}
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if exclude_dynamic:
		query.exclude = _dynamic_excludes(level)
	return level.get_world_2d().direct_space_state.intersect_ray(query)


func _dynamic_excludes(level: Node) -> Array[RID]:
	var excludes: Array[RID] = []
	for node_variant in _members_in_group_under("player", level):
		var body := node_variant as CollisionObject2D
		if body:
			excludes.append(body.get_rid())
	for node_variant in _members_in_group_under("enemies", level):
		var body := node_variant as CollisionObject2D
		if body:
			excludes.append(body.get_rid())
	return excludes


func _members_in_group_under(group_name: String, ancestor: Node) -> Array[Node]:
	var out: Array[Node] = []
	for member_variant in get_tree().get_nodes_in_group(group_name):
		var member := member_variant as Node
		if member == null:
			continue
		if member == ancestor or ancestor.is_ancestor_of(member):
			out.append(member)
	return out
