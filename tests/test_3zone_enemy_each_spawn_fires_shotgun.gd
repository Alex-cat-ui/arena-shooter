extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const THREE_ZONE_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")

const FIRE_WAIT_FRAMES := 260

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _active_enemy_id: int = -1
var _shots_by_enemy: Dictionary = {}
var _shotgun_shots_by_enemy: Dictionary = {}
var _saved_ai_fire_profile_mode: String = "auto"


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("3-ZONE: EACH ENEMY SPAWN FIRES SHOTGUN TEST")
	print("============================================================")

	await _test_each_spawn_can_fire_and_declares_shotgun_weapon()

	_t.summary("3-ZONE: EACH ENEMY SPAWN FIRES SHOTGUN RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_each_spawn_can_fire_and_declares_shotgun_weapon() -> void:
	var previous_god_mode := false
	if GameConfig:
		previous_god_mode = bool(GameConfig.god_mode)
		_saved_ai_fire_profile_mode = String(GameConfig.ai_fire_profile_mode)
		GameConfig.god_mode = true
		GameConfig.ai_fire_profile_mode = "production"

	if RuntimeState:
		RuntimeState.is_frozen = false
		RuntimeState.player_visibility_mul = 1.0
		RuntimeState.player_hp = 100

	if EventBus and EventBus.has_signal("enemy_shot") and not EventBus.enemy_shot.is_connected(_on_enemy_shot):
		EventBus.enemy_shot.connect(_on_enemy_shot)

	var level := THREE_ZONE_SCENE.instantiate() as Node2D
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame

	var player := level.get_node_or_null("Entities/Player") as CharacterBody2D
	var nav := level.get_node_or_null("Systems/NavigationService")
	var enemies := _members_in_group_under("enemies", level)

	_t.run_test("3zone each enemy fire: player exists", player != null)
	_t.run_test("3zone each enemy fire: all 5 enemies exist", enemies.size() == 5)
	if player == null or enemies.size() != 5:
		await _cleanup(level, previous_god_mode)
		return

	var all_enemies_fired := true
	var all_enemy_shots_are_shotgun := true
	var all_snapshots_declare_shotgun := true
	var shooter_anchor := Vector2(320.0, 240.0)

	for shooter_variant in enemies:
		var shooter := shooter_variant as Node2D
		if shooter == null:
			all_enemies_fired = false
			all_enemy_shots_are_shotgun = false
			all_snapshots_declare_shotgun = false
			continue

		var shooter_id := int(shooter.get("entity_id")) if shooter.get("entity_id") != null else -1
		if shooter_id <= 0:
			all_enemies_fired = false
			all_enemy_shots_are_shotgun = false
			all_snapshots_declare_shotgun = false
			continue

		_isolate_shooter(enemies, shooter, shooter_anchor)
		var target_pick := _pick_clear_combat_target(level, nav, shooter_anchor)
		var setup_ok := bool(target_pick.get("ok", false))
		if not setup_ok:
			_t.run_test("3zone each enemy fire: setup clear LOS for enemy#%d" % shooter_id, false)
			all_enemies_fired = false
			all_enemy_shots_are_shotgun = false
			all_snapshots_declare_shotgun = false
			continue

		player.global_position = target_pick.get("pos", shooter_anchor + Vector2(180.0, 0.0)) as Vector2
		player.velocity = Vector2.ZERO
		for _settle in range(5):
			await get_tree().physics_frame
			await get_tree().process_frame

		_active_enemy_id = shooter_id
		_shots_by_enemy[shooter_id] = 0
		_shotgun_shots_by_enemy[shooter_id] = 0

		var facing := (player.global_position - shooter.global_position).normalized()
		if facing.length_squared() > 0.0001:
			var pursuit_variant: Variant = shooter.get("_pursuit")
			if pursuit_variant != null:
				var pursuit_obj := pursuit_variant as Object
				if pursuit_obj:
					pursuit_obj.set("facing_dir", facing)
					pursuit_obj.set("_target_facing_dir", facing)

		if shooter.has_method("debug_force_awareness_state"):
			shooter.call("debug_force_awareness_state", "COMBAT")

		var fired := false
		for _frame in range(FIRE_WAIT_FRAMES):
			await get_tree().physics_frame
			await get_tree().process_frame
			if int(_shots_by_enemy.get(shooter_id, 0)) > 0:
				fired = true
				break

		var total_shots := int(_shots_by_enemy.get(shooter_id, 0))
		var shotgun_shots := int(_shotgun_shots_by_enemy.get(shooter_id, 0))
		var shotgun_event_ok := fired and total_shots > 0 and total_shots == shotgun_shots
		var snapshot := shooter.get_debug_detection_snapshot() as Dictionary if shooter.has_method("get_debug_detection_snapshot") else {}
		var snapshot_weapon_ok := snapshot.has("weapon_name") and String(snapshot.get("weapon_name", "")) == "shotgun"

		_t.run_test("3zone each enemy fire: enemy#%d fires at least once" % shooter_id, fired)
		_t.run_test("3zone each enemy fire: enemy#%d emits shotgun-only shot events" % shooter_id, shotgun_event_ok)
		_t.run_test("3zone each enemy fire: enemy#%d snapshot declares weapon_name=shotgun" % shooter_id, snapshot_weapon_ok)

		all_enemies_fired = all_enemies_fired and fired
		all_enemy_shots_are_shotgun = all_enemy_shots_are_shotgun and shotgun_event_ok
		all_snapshots_declare_shotgun = all_snapshots_declare_shotgun and snapshot_weapon_ok

	_active_enemy_id = -1
	_t.run_test("3zone each enemy fire: every spawn fires", all_enemies_fired)
	_t.run_test("3zone each enemy fire: all enemy shot events are shotgun", all_enemy_shots_are_shotgun)
	_t.run_test("3zone each enemy fire: every snapshot declares shotgun", all_snapshots_declare_shotgun)

	await _cleanup(level, previous_god_mode)


func _cleanup(level: Node, previous_god_mode: bool) -> void:
	_active_enemy_id = -1
	if EventBus and EventBus.has_signal("enemy_shot") and EventBus.enemy_shot.is_connected(_on_enemy_shot):
		EventBus.enemy_shot.disconnect(_on_enemy_shot)
	if level and is_instance_valid(level):
		level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if GameConfig:
		GameConfig.god_mode = previous_god_mode
		GameConfig.ai_fire_profile_mode = _saved_ai_fire_profile_mode


func _isolate_shooter(enemies: Array, shooter: Node2D, shooter_anchor: Vector2) -> void:
	for enemy_variant in enemies:
		var enemy := enemy_variant as Node2D
		if enemy == null:
			continue
		if enemy == shooter:
			enemy.global_position = shooter_anchor
			enemy.set_meta("room_id", 0)
			continue
		enemy.global_position = Vector2(-20000.0, -20000.0)
		enemy.set_meta("room_id", -1)


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


func _raycast(level: Node2D, from_pos: Vector2, to_pos: Vector2, exclude_enemies: bool) -> Dictionary:
	if level == null:
		return {}
	var query := PhysicsRayQueryParameters2D.create(from_pos, to_pos)
	query.collision_mask = 1
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = []
	if exclude_enemies and get_tree():
		for enemy_variant in get_tree().get_nodes_in_group("enemies"):
			var enemy := enemy_variant as Node2D
			if enemy == null:
				continue
			query.exclude.append(enemy.get_rid())
	return level.get_world_2d().direct_space_state.intersect_ray(query)


func _on_enemy_shot(enemy_id: int, weapon_type: String, _position: Vector3, _direction: Vector3) -> void:
	if enemy_id != _active_enemy_id:
		return
	_shots_by_enemy[enemy_id] = int(_shots_by_enemy.get(enemy_id, 0)) + 1
	if weapon_type == "shotgun":
		_shotgun_shots_by_enemy[enemy_id] = int(_shotgun_shots_by_enemy.get(enemy_id, 0)) + 1


func _members_in_group_under(group_name: String, ancestor: Node) -> Array:
	var out: Array = []
	if get_tree() == null:
		return out
	for member_variant in get_tree().get_nodes_in_group(group_name):
		var member := member_variant as Node
		if member == null:
			continue
		if member == ancestor or ancestor.is_ancestor_of(member):
			out.append(member)
	return out
