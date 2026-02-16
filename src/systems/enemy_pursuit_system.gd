## enemy_pursuit_system.gd
## Room-aware pursuit/state machine for enemy movement and investigation behavior.
class_name EnemyPursuitSystem
extends RefCounted

const ENEMY_PATROL_SYSTEM_SCRIPT := preload("res://src/systems/enemy_patrol_system.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")

enum AIState {
	IDLE_ROAM,
	APPROACH_ATTACK_RANGE,
	INVESTIGATE_LAST_SEEN,
	SEARCH_LAST_SEEN,
	RETURN_TO_HOME,
}

const ATTACK_RANGE_MAX_PX := 600.0
const ATTACK_RANGE_PREF_MIN_PX := 500.0
const LAST_SEEN_REACHED_PX := 20.0
const RETURN_TARGET_REACHED_PX := 20.0
const SEARCH_MIN_SEC := 4.0
const SEARCH_MAX_SEC := 7.0
const SEARCH_SWEEP_RAD := 0.9
const SEARCH_SWEEP_SPEED := 2.4
const PATH_REPATH_INTERVAL_SEC := 0.35
const TURN_SPEED_RAD := 6.0
const TARGET_FACING_LOCK_WINDOW_SEC := 0.22
const TARGET_FACING_SHARP_DELTA_RAD := 1.8
const ENEMY_ACCEL_TIME_SEC := 1.0 / 3.0
const ENEMY_DECEL_TIME_SEC := 1.0 / 3.0

var owner: CharacterBody2D = null
var sprite: Sprite2D = null
var speed_tiles: float = 2.0
var nav_system: Node = null
var home_room_id: int = -1
var _patrol = null

var ai_state: int = AIState.IDLE_ROAM
var facing_dir: Vector2 = Vector2.RIGHT
var _target_facing_dir: Vector2 = Vector2.RIGHT

var _roam_target: Vector2 = Vector2.ZERO
var _roam_wait_timer: float = 0.0
var _waypoints: Array[Vector2] = []
var _repath_timer: float = 0.0
var _last_seen_pos: Vector2 = Vector2.ZERO
var _has_last_seen: bool = false
var _search_timer: float = 0.0
var _search_phase: float = 0.0
var _search_base_angle: float = 0.0
var _return_target: Vector2 = Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _target_facing_lock_timer: float = 0.0
var _pending_target_facing: Vector2 = Vector2.ZERO


func _init(p_owner: CharacterBody2D, p_sprite: Sprite2D, p_speed_tiles: float) -> void:
	owner = p_owner
	sprite = p_sprite
	speed_tiles = p_speed_tiles
	_rng.randomize()
	_patrol = ENEMY_PATROL_SYSTEM_SCRIPT.new(owner)


func set_speed_tiles(p_speed_tiles: float) -> void:
	speed_tiles = p_speed_tiles


func get_facing_dir() -> Vector2:
	return facing_dir


func get_target_facing_dir() -> Vector2:
	return _target_facing_dir


func face_towards(target_pos: Vector2) -> void:
	var dir := (target_pos - owner.global_position).normalized()
	_set_target_facing(dir)


func set_external_look_dir(dir: Vector2, force_apply: bool = false) -> void:
	_set_target_facing(dir, force_apply)


func configure_navigation(p_nav_system: Node, p_home_room_id: int) -> void:
	nav_system = p_nav_system
	home_room_id = p_home_room_id
	owner.set_meta("room_id", p_home_room_id)
	ai_state = AIState.IDLE_ROAM
	_waypoints.clear()
	_roam_target = Vector2.ZERO
	_roam_wait_timer = 0.0
	_repath_timer = 0.0
	_last_seen_pos = Vector2.ZERO
	_has_last_seen = false
	_search_timer = 0.0
	_return_target = Vector2.ZERO
	_target_facing_dir = facing_dir
	_target_facing_lock_timer = 0.0
	_pending_target_facing = Vector2.ZERO
	if _patrol:
		_patrol.configure(nav_system, home_room_id)


func on_heard_shot(shot_room_id: int, shot_pos: Vector2) -> void:
	if not nav_system:
		return
	var own_room := int(owner.get_meta("room_id", home_room_id))
	if nav_system.has_method("get_enemy_room_id"):
		own_room = int(nav_system.get_enemy_room_id(owner))
	elif own_room < 0 and nav_system.has_method("room_id_at_point"):
		own_room = int(nav_system.room_id_at_point(owner.global_position))
		owner.set_meta("room_id", own_room)
	if own_room < 0:
		return
	var same_or_adjacent := own_room == shot_room_id
	if not same_or_adjacent and nav_system.has_method("get_neighbors"):
		same_or_adjacent = (nav_system.get_neighbors(own_room) as Array).has(shot_room_id)
	elif not same_or_adjacent and nav_system.has_method("is_adjacent"):
		same_or_adjacent = bool(nav_system.is_adjacent(own_room, shot_room_id))
	if not same_or_adjacent:
		return

	_set_last_seen(shot_pos)
	ai_state = AIState.INVESTIGATE_LAST_SEEN
	_plan_path_to(_last_seen_pos)
	if _patrol:
		_patrol.notify_alert()


func update(delta: float, use_room_nav: bool, player_valid: bool, player_pos: Vector2, player_visible: bool) -> void:
	if use_room_nav:
		_update_room_ai(delta, player_valid, player_pos, player_visible)
	else:
		_update_simple_ai(delta, player_valid, player_pos)
	_update_facing(delta)


func execute_intent(delta: float, intent: Dictionary, context: Dictionary) -> Dictionary:
	var request_fire := false
	var intent_type := int(intent.get("type", ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL))
	var target := intent.get("target", owner.global_position) as Vector2
	var player_pos := context.get("player_pos", target) as Vector2
	var has_los := bool(context.get("los", false))
	var dist := float(context.get("dist", INF))

	match intent_type:
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL:
			_update_idle_roam(delta)
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.INVESTIGATE:
			if target != Vector2.ZERO:
				_set_last_seen(target)
			var investigate_arrive_px := _pursuit_cfg_float("last_seen_reached_px", LAST_SEEN_REACHED_PX)
			if target == Vector2.ZERO:
				_execute_search(delta, context.get("last_seen_pos", owner.global_position) as Vector2)
			elif owner.global_position.distance_to(target) <= investigate_arrive_px:
				_execute_search(delta, target)
			else:
				_execute_move_to_target(delta, target, 1.0)
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH:
			_execute_search(delta, target)
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT:
			_execute_move_to_target(delta, target, 0.95)
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.HOLD_RANGE:
			_stop_motion(delta)
			face_towards(player_pos if has_los else target)
			request_fire = has_los and dist <= _pursuit_cfg_float("attack_range_max_px", ATTACK_RANGE_MAX_PX)
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH:
			_execute_move_to_target(delta, player_pos, 1.0)
			face_towards(player_pos)
			request_fire = has_los and dist <= _pursuit_cfg_float("attack_range_max_px", ATTACK_RANGE_MAX_PX)
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETREAT:
			_execute_retreat_from(delta, player_pos)
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETURN_HOME:
			var home_target := target if target != Vector2.ZERO else _pick_home_return_target()
			_execute_move_to_target(delta, home_target, 0.9)
		_:
			_update_idle_roam(delta)

	_update_facing(delta)
	return {"request_fire": request_fire}


func _execute_move_to_target(delta: float, target: Vector2, speed_scale: float) -> void:
	if target == Vector2.ZERO:
		_stop_motion(delta)
		return
	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = _pursuit_cfg_float("path_repath_interval_sec", PATH_REPATH_INTERVAL_SEC)
		_plan_path_to(target)
	_follow_waypoints(speed_scale, delta)
	if owner.global_position.distance_to(target) <= _pursuit_cfg_float("waypoint_reached_px", 12.0):
		_stop_motion(delta)


func _execute_search(delta: float, center: Vector2) -> void:
	_stop_motion(delta)
	_search_phase += delta * _pursuit_cfg_float("search_sweep_speed", SEARCH_SWEEP_SPEED)
	if center != Vector2.ZERO:
		face_towards(center)
	var angle := facing_dir.angle() + sin(_search_phase) * _pursuit_cfg_float("search_sweep_rad", SEARCH_SWEEP_RAD)
	_set_target_facing(Vector2.RIGHT.rotated(angle))


func _execute_retreat_from(delta: float, danger_origin: Vector2) -> void:
	var retreat_dir := (owner.global_position - danger_origin).normalized()
	if retreat_dir.length_squared() <= 0.0001:
		retreat_dir = Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU))
	var retreat_target := owner.global_position + retreat_dir * _pursuit_cfg_float("retreat_distance_px", 140.0)
	_execute_move_to_target(delta, retreat_target, 0.95)


func _update_simple_ai(delta: float, player_valid: bool, player_pos: Vector2) -> void:
	if not player_valid:
		_stop_motion(delta)
		return

	var to_player := player_pos - owner.global_position
	var dist := to_player.length()
	if dist <= 0.001:
		_stop_motion(delta)
		return

	var dir := to_player / dist
	face_towards(player_pos)
	if dist > _pursuit_cfg_float("attack_range_max_px", ATTACK_RANGE_MAX_PX):
		_move_in_direction(dir, 1.0, delta)
		return

	_stop_motion(delta)


func _update_room_ai(delta: float, player_valid: bool, player_pos: Vector2, player_visible: bool) -> void:
	if player_valid and player_visible:
		_set_last_seen(player_pos)
		if _patrol:
			_patrol.notify_alert()
		_update_engage_player(delta, player_pos)
		return

	if _has_last_seen:
		if ai_state == AIState.IDLE_ROAM or ai_state == AIState.APPROACH_ATTACK_RANGE:
			ai_state = AIState.INVESTIGATE_LAST_SEEN
			_plan_path_to(_last_seen_pos)
		match ai_state:
			AIState.INVESTIGATE_LAST_SEEN:
				_update_investigate_last_seen(delta)
			AIState.SEARCH_LAST_SEEN:
				_update_search_last_seen(delta)
			AIState.RETURN_TO_HOME:
				_update_return_to_home(delta)
			_:
				_update_idle_roam(delta)
		return

	_update_idle_roam(delta)


func _update_engage_player(delta: float, player_pos: Vector2) -> void:
	var dist := owner.global_position.distance_to(player_pos)
	face_towards(player_pos)

	if dist > _pursuit_cfg_float("attack_range_max_px", ATTACK_RANGE_MAX_PX):
		ai_state = AIState.APPROACH_ATTACK_RANGE
		_repath_timer -= delta
		if _repath_timer <= 0.0:
			_repath_timer = _pursuit_cfg_float("path_repath_interval_sec", PATH_REPATH_INTERVAL_SEC)
			_plan_path_to(player_pos)
		_follow_waypoints(1.0, delta)
		return

	if dist < _pursuit_cfg_float("attack_range_pref_min_px", ATTACK_RANGE_PREF_MIN_PX):
		ai_state = AIState.APPROACH_ATTACK_RANGE
		_repath_timer -= delta
		if _repath_timer <= 0.0:
			_repath_timer = _pursuit_cfg_float("path_repath_interval_sec", PATH_REPATH_INTERVAL_SEC)
			var retreat_dir := (owner.global_position - player_pos).normalized()
			if retreat_dir == Vector2.ZERO:
				retreat_dir = Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU))
			var retreat_target := owner.global_position + retreat_dir * _pursuit_cfg_float("retreat_distance_px", 140.0)
			if nav_system and nav_system.has_method("room_id_at_point"):
				var rid := int(nav_system.room_id_at_point(retreat_target))
				if rid < 0:
					retreat_target = owner.global_position
			_plan_path_to(retreat_target)
		_follow_waypoints(0.9, delta)
		return
	else:
		_waypoints.clear()
		_stop_motion(delta)


func _update_investigate_last_seen(delta: float) -> void:
	if not _has_last_seen:
		_begin_return_home()
		return

	if owner.global_position.distance_to(_last_seen_pos) <= _pursuit_cfg_float("last_seen_reached_px", LAST_SEEN_REACHED_PX):
		_begin_search_last_seen()
		return

	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = _pursuit_cfg_float("path_repath_interval_sec", PATH_REPATH_INTERVAL_SEC)
		_plan_path_to(_last_seen_pos)
	_follow_waypoints(1.0, delta)


func _update_search_last_seen(delta: float) -> void:
	_stop_motion(delta)
	_search_timer = maxf(0.0, _search_timer - delta)
	_search_phase += delta * _pursuit_cfg_float("search_sweep_speed", SEARCH_SWEEP_SPEED)
	var angle := _search_base_angle + sin(_search_phase) * _pursuit_cfg_float("search_sweep_rad", SEARCH_SWEEP_RAD)
	_set_target_facing(Vector2.RIGHT.rotated(angle))
	if _search_timer <= 0.0:
		_begin_return_home()


func _update_return_to_home(delta: float) -> void:
	if _return_target == Vector2.ZERO:
		_return_target = _pick_home_return_target()

	if owner.global_position.distance_to(_return_target) <= _pursuit_cfg_float("return_target_reached_px", RETURN_TARGET_REACHED_PX):
		_clear_alert_and_idle()
		return

	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = _pursuit_cfg_float("path_repath_interval_sec", PATH_REPATH_INTERVAL_SEC)
		_plan_path_to(_return_target)
	_follow_waypoints(0.95, delta)


func _update_idle_roam(delta: float) -> void:
	if _patrol:
		var patrol_decision := _patrol.update(delta, facing_dir) as Dictionary
		if bool(patrol_decision.get("waiting", true)):
			_stop_motion(delta)
			var look_dir := patrol_decision.get("look_dir", Vector2.ZERO) as Vector2
			if look_dir.length_squared() > 0.0001:
				_set_target_facing(look_dir)
			return
		var target := patrol_decision.get("target", owner.global_position) as Vector2
		var speed_scale := float(patrol_decision.get("speed_scale", 0.85))
		var dir := (target - owner.global_position).normalized()
		if dir.length_squared() > 0.0001:
			_move_in_direction(dir, speed_scale, delta)
		else:
			_stop_motion(delta)
		return

	if _roam_wait_timer > 0.0:
		_roam_wait_timer = maxf(0.0, _roam_wait_timer - delta)
		_stop_motion(delta)
		return

	if _roam_target == Vector2.ZERO or owner.global_position.distance_to(_roam_target) < 10.0:
		if nav_system and nav_system.has_method("random_point_in_room"):
			_roam_target = nav_system.random_point_in_room(home_room_id, 28.0)
		else:
			_roam_target = owner.global_position
		_roam_wait_timer = randf_range(0.1, 0.35)
		_stop_motion(delta)
		return

	var dir := (_roam_target - owner.global_position).normalized()
	_move_in_direction(dir, 0.85, delta)


func _plan_path_to(target_pos: Vector2) -> void:
	if nav_system and nav_system.has_method("build_path_points"):
		_waypoints = nav_system.build_path_points(owner.global_position, target_pos)
	else:
		_waypoints = [target_pos]


func _follow_waypoints(speed_scale: float, delta: float) -> void:
	if _waypoints.is_empty():
		_stop_motion(delta)
		return

	var waypoint := _waypoints[0]
	if owner.global_position.distance_to(waypoint) <= _pursuit_cfg_float("waypoint_reached_px", 12.0):
		_waypoints.remove_at(0)
		if _waypoints.is_empty():
			_stop_motion(delta)
			return
		waypoint = _waypoints[0]

	var dir := (waypoint - owner.global_position).normalized()
	_move_in_direction(dir, speed_scale, delta)
	if nav_system and nav_system.has_method("room_id_at_point"):
		var rid := int(nav_system.room_id_at_point(owner.global_position))
		if rid >= 0:
			owner.set_meta("room_id", rid)


func _move_in_direction(dir: Vector2, speed_scale: float, delta: float) -> void:
	if delta <= 0.0:
		return
	var tile_size: int = GameConfig.tile_size if GameConfig else 32
	var speed_pixels := speed_tiles * tile_size * speed_scale
	var target_velocity := dir * speed_pixels
	var accel_per_sec := speed_pixels / maxf(_pursuit_cfg_float("accel_time_sec", ENEMY_ACCEL_TIME_SEC), 0.001)
	owner.velocity = owner.velocity.move_toward(target_velocity, accel_per_sec * delta)
	owner.move_and_slide()
	_set_target_facing(dir)


func _stop_motion(delta: float) -> void:
	if delta <= 0.0:
		owner.velocity = Vector2.ZERO
		return
	var tile_size: int = GameConfig.tile_size if GameConfig else 32
	var base_speed_pixels := speed_tiles * tile_size
	var decel_per_sec := base_speed_pixels / maxf(_pursuit_cfg_float("decel_time_sec", ENEMY_DECEL_TIME_SEC), 0.001)
	owner.velocity = owner.velocity.move_toward(Vector2.ZERO, decel_per_sec * delta)
	if owner.velocity.length_squared() <= 1.0:
		owner.velocity = Vector2.ZERO
	owner.move_and_slide()


func _set_target_facing(dir: Vector2, force_apply: bool = false) -> void:
	if dir.length_squared() <= 0.0001:
		return
	var normalized := dir.normalized()
	if force_apply:
		_target_facing_dir = normalized
		_pending_target_facing = Vector2.ZERO
		_target_facing_lock_timer = maxf(_pursuit_cfg_float("target_facing_lock_window_sec", TARGET_FACING_LOCK_WINDOW_SEC), 0.0)
		return

	var current_target := _target_facing_dir
	if current_target.length_squared() <= 0.0001:
		current_target = facing_dir if facing_dir.length_squared() > 0.0001 else normalized

	var sharp_delta := absf(wrapf(normalized.angle() - current_target.angle(), -PI, PI))
	var sharp_threshold := maxf(_pursuit_cfg_float("target_facing_sharp_delta_rad", TARGET_FACING_SHARP_DELTA_RAD), 0.0)
	var lock_window := maxf(_pursuit_cfg_float("target_facing_lock_window_sec", TARGET_FACING_LOCK_WINDOW_SEC), 0.0)
	if sharp_delta >= sharp_threshold and _target_facing_lock_timer > 0.0:
		_pending_target_facing = normalized
		return

	_target_facing_dir = normalized
	if sharp_delta >= sharp_threshold:
		_target_facing_lock_timer = lock_window
		_pending_target_facing = Vector2.ZERO


func _update_facing(delta: float) -> void:
	if _target_facing_lock_timer > 0.0:
		_target_facing_lock_timer = maxf(0.0, _target_facing_lock_timer - maxf(delta, 0.0))
		if _target_facing_lock_timer <= 0.0 and _pending_target_facing.length_squared() > 0.0001:
			_target_facing_dir = _pending_target_facing.normalized()
			_pending_target_facing = Vector2.ZERO

	var desired := _target_facing_dir
	if desired.length_squared() <= 0.0001:
		return
	var current_angle := facing_dir.angle()
	var target_angle := desired.angle()
	var turn_weight := clampf(_pursuit_cfg_float("turn_speed_rad", TURN_SPEED_RAD) * maxf(delta, 0.0), 0.0, 1.0)
	var next_angle := lerp_angle(current_angle, target_angle, turn_weight)
	facing_dir = Vector2.RIGHT.rotated(next_angle)
	if sprite:
		sprite.rotation = next_angle


func _set_last_seen(pos: Vector2) -> void:
	_last_seen_pos = pos
	_has_last_seen = true


func _begin_search_last_seen() -> void:
	ai_state = AIState.SEARCH_LAST_SEEN
	_search_timer = _rng.randf_range(
		_pursuit_cfg_float("search_min_sec", SEARCH_MIN_SEC),
		_pursuit_cfg_float("search_max_sec", SEARCH_MAX_SEC)
	)
	_search_phase = 0.0
	_search_base_angle = facing_dir.angle()
	_waypoints.clear()
	_stop_motion(0.0)


func _begin_return_home() -> void:
	ai_state = AIState.RETURN_TO_HOME
	_return_target = _pick_home_return_target()
	_repath_timer = 0.0
	_plan_path_to(_return_target)


func _pick_home_return_target() -> Vector2:
	if nav_system and nav_system.has_method("random_point_in_room") and home_room_id >= 0:
		return nav_system.random_point_in_room(home_room_id, 28.0)
	return owner.global_position


func _clear_alert_and_idle() -> void:
	_has_last_seen = false
	_last_seen_pos = Vector2.ZERO
	_search_timer = 0.0
	_return_target = Vector2.ZERO
	_waypoints.clear()
	ai_state = AIState.IDLE_ROAM
	_roam_wait_timer = randf_range(0.1, 0.35)
	if _patrol:
		_patrol.notify_calm()


func _pursuit_cfg_float(key: String, fallback: float) -> float:
	if GameConfig and GameConfig.ai_balance.has("pursuit"):
		var section := GameConfig.ai_balance["pursuit"] as Dictionary
		return float(section.get(key, fallback))
	return fallback
