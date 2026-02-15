## enemy_pursuit_system.gd
## Room-aware pursuit/state machine for enemy movement and investigation behavior.
class_name EnemyPursuitSystem
extends RefCounted

const ENEMY_PATROL_SYSTEM_SCRIPT := preload("res://src/systems/enemy_patrol_system.gd")

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


func face_towards(target_pos: Vector2) -> void:
	var dir := (target_pos - owner.global_position).normalized()
	_set_target_facing(dir)


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
	if _patrol:
		_patrol.configure(nav_system, home_room_id)


func on_heard_shot(shot_room_id: int, shot_pos: Vector2) -> void:
	if not nav_system:
		return
	var own_room := int(owner.get_meta("room_id", home_room_id))
	if own_room < 0 and nav_system.has_method("room_id_at_point"):
		own_room = int(nav_system.room_id_at_point(owner.global_position))
		owner.set_meta("room_id", own_room)
	if own_room < 0:
		return
	var same_or_adjacent := own_room == shot_room_id
	if not same_or_adjacent and nav_system.has_method("is_adjacent"):
		same_or_adjacent = bool(nav_system.is_adjacent(own_room, shot_room_id))
	if not same_or_adjacent:
		return

	_set_last_seen(shot_pos)
	ai_state = AIState.INVESTIGATE_LAST_SEEN
	_plan_path_to(_last_seen_pos)
	if _patrol:
		_patrol.notify_alert()


func update(delta: float, use_room_nav: bool, player_valid: bool, player_pos: Vector2, player_visible: bool) -> Dictionary:
	var decision: Dictionary = {}
	if use_room_nav:
		decision = _update_room_ai(delta, player_valid, player_pos, player_visible)
	else:
		decision = _update_simple_ai(delta, player_valid, player_pos)
	_update_facing(delta)
	return decision


func _update_simple_ai(delta: float, player_valid: bool, player_pos: Vector2) -> Dictionary:
	if not player_valid:
		_stop_motion(delta)
		return {}

	var to_player := player_pos - owner.global_position
	var dist := to_player.length()
	if dist <= 0.001:
		_stop_motion(delta)
		return {}

	var dir := to_player / dist
	face_towards(player_pos)
	if dist > ATTACK_RANGE_MAX_PX:
		_move_in_direction(dir, 1.0, delta)
		return {}

	_stop_motion(delta)
	return {"request_fire": true, "fire_target": player_pos}


func _update_room_ai(delta: float, player_valid: bool, player_pos: Vector2, player_visible: bool) -> Dictionary:
	if player_valid and player_visible:
		_set_last_seen(player_pos)
		if _patrol:
			_patrol.notify_alert()
		return _update_engage_player(delta, player_pos)

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
		return {}

	_update_idle_roam(delta)
	return {}


func _update_engage_player(delta: float, player_pos: Vector2) -> Dictionary:
	var dist := owner.global_position.distance_to(player_pos)
	face_towards(player_pos)

	if dist > ATTACK_RANGE_MAX_PX:
		ai_state = AIState.APPROACH_ATTACK_RANGE
		_repath_timer -= delta
		if _repath_timer <= 0.0:
			_repath_timer = PATH_REPATH_INTERVAL_SEC
			_plan_path_to(player_pos)
		_follow_waypoints(1.0, delta)
		return {}

	if dist < ATTACK_RANGE_PREF_MIN_PX:
		ai_state = AIState.APPROACH_ATTACK_RANGE
		_repath_timer -= delta
		if _repath_timer <= 0.0:
			_repath_timer = PATH_REPATH_INTERVAL_SEC
			var retreat_dir := (owner.global_position - player_pos).normalized()
			if retreat_dir == Vector2.ZERO:
				retreat_dir = Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU))
			var retreat_target := owner.global_position + retreat_dir * 140.0
			if nav_system and nav_system.has_method("room_id_at_point"):
				var rid := int(nav_system.room_id_at_point(retreat_target))
				if rid < 0:
					retreat_target = owner.global_position
			_plan_path_to(retreat_target)
		_follow_waypoints(0.9, delta)
	else:
		_waypoints.clear()
		_stop_motion(delta)

	return {"request_fire": true, "fire_target": player_pos}


func _update_investigate_last_seen(delta: float) -> void:
	if not _has_last_seen:
		_begin_return_home()
		return

	if owner.global_position.distance_to(_last_seen_pos) <= LAST_SEEN_REACHED_PX:
		_begin_search_last_seen()
		return

	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = PATH_REPATH_INTERVAL_SEC
		_plan_path_to(_last_seen_pos)
	_follow_waypoints(1.0, delta)


func _update_search_last_seen(delta: float) -> void:
	_stop_motion(delta)
	_search_timer = maxf(0.0, _search_timer - delta)
	_search_phase += delta * SEARCH_SWEEP_SPEED
	var angle := _search_base_angle + sin(_search_phase) * SEARCH_SWEEP_RAD
	_set_target_facing(Vector2.RIGHT.rotated(angle))
	if _search_timer <= 0.0:
		_begin_return_home()


func _update_return_to_home(delta: float) -> void:
	if _return_target == Vector2.ZERO:
		_return_target = _pick_home_return_target()

	if owner.global_position.distance_to(_return_target) <= RETURN_TARGET_REACHED_PX:
		_clear_alert_and_idle()
		return

	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = PATH_REPATH_INTERVAL_SEC
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
	if owner.global_position.distance_to(waypoint) <= 12.0:
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
	owner.set_meta("door_push_velocity", target_velocity)
	var accel_per_sec := speed_pixels / maxf(ENEMY_ACCEL_TIME_SEC, 0.001)
	owner.velocity = owner.velocity.move_toward(target_velocity, accel_per_sec * delta)
	owner.move_and_slide()
	_set_target_facing(dir)


func _stop_motion(delta: float) -> void:
	if delta <= 0.0:
		owner.velocity = Vector2.ZERO
		owner.set_meta("door_push_velocity", Vector2.ZERO)
		return
	var tile_size: int = GameConfig.tile_size if GameConfig else 32
	var base_speed_pixels := speed_tiles * tile_size
	var decel_per_sec := base_speed_pixels / maxf(ENEMY_DECEL_TIME_SEC, 0.001)
	owner.velocity = owner.velocity.move_toward(Vector2.ZERO, decel_per_sec * delta)
	if owner.velocity.length_squared() <= 1.0:
		owner.velocity = Vector2.ZERO
	owner.set_meta("door_push_velocity", owner.velocity)
	owner.move_and_slide()


func _set_target_facing(dir: Vector2) -> void:
	if dir.length_squared() <= 0.0001:
		return
	_target_facing_dir = dir.normalized()


func _update_facing(delta: float) -> void:
	var desired := _target_facing_dir
	if desired.length_squared() <= 0.0001:
		return
	var current_angle := facing_dir.angle()
	var target_angle := desired.angle()
	var next_angle := rotate_toward(current_angle, target_angle, TURN_SPEED_RAD * maxf(delta, 0.0))
	facing_dir = Vector2.RIGHT.rotated(next_angle)
	if sprite:
		sprite.rotation = next_angle


func _set_last_seen(pos: Vector2) -> void:
	_last_seen_pos = pos
	_has_last_seen = true


func _begin_search_last_seen() -> void:
	ai_state = AIState.SEARCH_LAST_SEEN
	_search_timer = _rng.randf_range(SEARCH_MIN_SEC, SEARCH_MAX_SEC)
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
