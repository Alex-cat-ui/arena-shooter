## enemy_pursuit_system.gd
## Room-aware pursuit/state machine for enemy movement and investigation behavior.
class_name EnemyPursuitSystem
extends RefCounted

const ENEMY_PATROL_SYSTEM_SCRIPT := preload("res://src/systems/enemy_patrol_system.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

const ATTACK_RANGE_MAX_PX := 600.0
const LAST_SEEN_REACHED_PX := 20.0
const SEARCH_SWEEP_RAD := 0.9
const SEARCH_SWEEP_SPEED := 2.4
const HOLD_LISTEN_MIN_SEC := 0.8
const HOLD_LISTEN_MAX_SEC := 1.6
const PATH_REPATH_INTERVAL_SEC := 0.35
const TURN_SPEED_RAD := 6.0
const TARGET_FACING_LOCK_WINDOW_SEC := 0.22
const TARGET_FACING_SHARP_DELTA_RAD := 1.8
const ENEMY_ACCEL_TIME_SEC := 1.0 / 3.0
const ENEMY_DECEL_TIME_SEC := 1.0 / 3.0
const COMBAT_REPATH_INTERVAL_NO_LOS_SEC := 0.2
const PATH_POLICY_REPLAN_LIMIT := 10
const PATH_POLICY_SAMPLE_STEP_PX := 12.0
const FALLBACK_RING_MIN_RADIUS_PX := 48.0
const FALLBACK_RING_STEP_RADIUS_PX := 48.0
const FALLBACK_RING_COUNT := 4
const FALLBACK_RING_SAMPLES_PER_RING := 8
const STALL_WINDOW_SEC := 0.6
const STALL_CHECK_INTERVAL_SEC := 0.1
const STALL_SPEED_THRESHOLD_PX_PER_SEC := 8.0
const STALL_PATH_PROGRESS_THRESHOLD_PX := 12.0
const STALL_HARD_CONSECUTIVE_WINDOWS := 2

var owner: CharacterBody2D = null
var sprite: Sprite2D = null
var speed_tiles: float = 2.0
var nav_system: Node = null
var home_room_id: int = -1
var _patrol = null

var facing_dir: Vector2 = Vector2.RIGHT
var _target_facing_dir: Vector2 = Vector2.RIGHT

var _roam_target: Vector2 = Vector2.ZERO
var _roam_wait_timer: float = 0.0
var _waypoints: Array[Vector2] = []
var _repath_timer: float = 0.0
var _last_seen_pos: Vector2 = Vector2.ZERO
var _search_phase: float = 0.0
var _in_hold_listen: bool = false
var _hold_listen_timer: float = 0.0
var _last_intent_type: int = -1
var _rng := RandomNumberGenerator.new()
var _target_facing_lock_timer: float = 0.0
var _pending_target_facing: Vector2 = Vector2.ZERO
var _door_system_cache: Node = null
var _door_system_checked: bool = false
var _nav_agent: NavigationAgent2D = null
var _use_navmesh: bool = false
var _last_path_failed: bool = false
var _last_path_failed_reason: String = ""
var _last_policy_blocked_segment: int = -1
var _path_policy_blocked: bool = false
var _policy_replan_attempts: int = 0
var _policy_fallback_used: bool = false
var _policy_fallback_target: Vector2 = Vector2.ZERO
var _last_valid_path_node: Vector2 = Vector2.ZERO
var _active_move_target: Vector2 = Vector2.ZERO
var _stall_clock: float = 0.0
var _stall_check_timer: float = 0.0
var _stall_samples: Array[Dictionary] = []
var _stall_consecutive_windows: int = 0
var _hard_stall: bool = false
var _last_stall_speed_avg: float = 0.0
var _last_stall_path_progress: float = 0.0


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
	_waypoints.clear()
	_roam_target = Vector2.ZERO
	_roam_wait_timer = 0.0
	_repath_timer = 0.0
	_last_seen_pos = Vector2.ZERO
	_in_hold_listen = false
	_hold_listen_timer = 0.0
	_last_intent_type = -1
	_target_facing_dir = facing_dir
	_target_facing_lock_timer = 0.0
	_pending_target_facing = Vector2.ZERO
	_door_system_cache = null
	_door_system_checked = false
	_use_navmesh = _nav_agent != null
	_last_path_failed = false
	_last_path_failed_reason = ""
	_last_policy_blocked_segment = -1
	_path_policy_blocked = false
	_policy_replan_attempts = 0
	_policy_fallback_used = false
	_policy_fallback_target = Vector2.ZERO
	_last_valid_path_node = Vector2.ZERO
	_active_move_target = Vector2.ZERO
	_reset_stall_monitor()
	if _patrol:
		_patrol.configure(nav_system, home_room_id)


func configure_nav_agent(agent: NavigationAgent2D) -> void:
	_nav_agent = agent
	_use_navmesh = agent != null


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
	_plan_path_to(_last_seen_pos)
	if _patrol:
		_patrol.notify_alert()


func execute_intent(delta: float, intent: Dictionary, context: Dictionary) -> Dictionary:
	var request_fire := false
	var intent_type := int(intent.get("type", ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL))
	var target := intent.get("target", owner.global_position) as Vector2
	var movement_intent := false
	var player_pos := context.get("player_pos", target) as Vector2
	var has_los := bool(context.get("los", false))
	var dist := float(context.get("dist", INF))
	var alert_level := int(context.get("alert_level", ENEMY_ALERT_LEVELS_SCRIPT.CALM))
	var combat_no_los := (
		not has_los
		and (
			bool(context.get("combat_lock", false))
			or alert_level >= ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
		)
	)
	# Reset search sub-state when intent type changes.
	if intent_type != _last_intent_type:
		_last_intent_type = intent_type
		_search_phase = 0.0
		_in_hold_listen = false
		_hold_listen_timer = 0.0
	_last_path_failed = false
	_last_path_failed_reason = ""
	_last_policy_blocked_segment = -1

	match intent_type:
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL:
			_update_idle_roam(delta)
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.INVESTIGATE:
			movement_intent = true
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
			movement_intent = true
			_execute_move_to_target(delta, target, 0.95)
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.HOLD_RANGE:
			_stop_motion(delta)
			face_towards(player_pos if has_los else target)
			request_fire = has_los and dist <= _pursuit_cfg_float("attack_range_max_px", ATTACK_RANGE_MAX_PX)
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH:
			movement_intent = true
			var push_target := target if target != Vector2.ZERO else player_pos
			var repath_override := _combat_no_los_repath_interval_sec() if combat_no_los else -1.0
			_execute_move_to_target(delta, push_target, 1.0, repath_override)
			face_towards(push_target)
			request_fire = has_los and dist <= _pursuit_cfg_float("attack_range_max_px", ATTACK_RANGE_MAX_PX)
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETREAT:
			movement_intent = true
			_execute_retreat_from(delta, player_pos)
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETURN_HOME:
			movement_intent = true
			var home_target := target if target != Vector2.ZERO else _pick_home_return_target()
			_execute_move_to_target(delta, home_target, 0.9)
		_:
			_update_idle_roam(delta)

	_update_facing(delta)
	return {
		"request_fire": request_fire,
		"path_failed": _last_path_failed,
		"path_failed_reason": _last_path_failed_reason,
		"policy_blocked_segment": _last_policy_blocked_segment,
		"movement_intent": movement_intent,
	}


func _execute_move_to_target(
	delta: float,
	target: Vector2,
	speed_scale: float,
	repath_interval_override_sec: float = -1.0
) -> bool:
	if target == Vector2.ZERO:
		_stop_motion(delta)
		_mark_path_failed("no_target")
		_reset_stall_monitor()
		return false
	if _active_move_target == Vector2.ZERO or _active_move_target.distance_to(target) > 0.5:
		_reset_stall_monitor()
	_active_move_target = target
	var repath_interval := repath_interval_override_sec
	if repath_interval <= 0.0:
		repath_interval = _pursuit_cfg_float("path_repath_interval_sec", PATH_REPATH_INTERVAL_SEC)
	_repath_timer -= delta
	if _repath_timer <= 0.0 or _path_policy_blocked:
		_repath_timer = repath_interval
		if not _attempt_replan_with_policy(target):
			if not _handle_replan_failure(target):
				_stop_motion(delta)
				_mark_path_failed("replan_failed")
				return false
	if not _has_active_path_to(target):
		_mark_path_failed("path_unavailable")
		_stop_motion(delta)
		return false
	var moved := _follow_waypoints(speed_scale, delta)
	if not moved and _path_policy_blocked:
		_mark_path_failed("policy_blocked")
		_repath_timer = 0.0
		if not _attempt_replan_with_policy(target):
			_handle_replan_failure(target)
	if _update_stall_monitor(delta, target):
		_mark_path_failed("hard_stall")
		_repath_timer = 0.0
		if not _attempt_replan_with_policy(target):
			_handle_replan_failure(target)
	if owner.global_position.distance_to(target) <= _pursuit_cfg_float("waypoint_reached_px", 12.0):
		_stop_motion(delta)
		_policy_replan_attempts = 0
		_policy_fallback_used = false
		_policy_fallback_target = Vector2.ZERO
		_reset_stall_monitor()
	return not _last_path_failed


func _combat_no_los_repath_interval_sec() -> float:
	return maxf(_pursuit_cfg_float("combat_repath_interval_no_los_sec", COMBAT_REPATH_INTERVAL_NO_LOS_SEC), 0.01)


func _execute_search(delta: float, center: Vector2) -> void:
	_stop_motion(delta)
	# HOLD_LISTEN phase: stand still after one full sweep cycle.
	if _in_hold_listen:
		_hold_listen_timer = maxf(0.0, _hold_listen_timer - delta)
		if _hold_listen_timer <= 0.0:
			_in_hold_listen = false
			_search_phase = 0.0
		return
	_search_phase += delta * _pursuit_cfg_float("search_sweep_speed", SEARCH_SWEEP_SPEED)
	if center != Vector2.ZERO:
		face_towards(center)
	var angle := facing_dir.angle() + sin(_search_phase) * _pursuit_cfg_float("search_sweep_rad", SEARCH_SWEEP_RAD)
	_set_target_facing(Vector2.RIGHT.rotated(angle))
	# After one full oscillation cycle, enter HOLD_LISTEN.
	if _search_phase >= TAU:
		_in_hold_listen = true
		_hold_listen_timer = _rng.randf_range(
			_pursuit_cfg_float("hold_listen_min_sec", HOLD_LISTEN_MIN_SEC),
			_pursuit_cfg_float("hold_listen_max_sec", HOLD_LISTEN_MAX_SEC)
		)
		_search_phase = 0.0


func _execute_retreat_from(delta: float, danger_origin: Vector2) -> void:
	var retreat_dir := (owner.global_position - danger_origin).normalized()
	if retreat_dir.length_squared() <= 0.0001:
		retreat_dir = Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU))
	var retreat_target := owner.global_position + retreat_dir * _pursuit_cfg_float("retreat_distance_px", 140.0)
	_execute_move_to_target(delta, retreat_target, 0.95)


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


func _plan_path_to(target_pos: Vector2) -> bool:
	if target_pos == Vector2.ZERO:
		_waypoints.clear()
		_path_policy_blocked = false
		return false
	var planned_points := _build_reachable_path_points_for_enemy(target_pos)
	if planned_points.is_empty():
		_path_policy_blocked = true
		_last_policy_blocked_segment = -1
		if nav_system and nav_system.has_method("can_enemy_traverse_point") and not bool(nav_system.call("can_enemy_traverse_point", owner, target_pos)):
			_last_policy_blocked_segment = 0
			_mark_path_failed("policy_blocked")
		else:
			_mark_path_failed("path_unreachable")
		if _use_navmesh and _nav_agent:
			_nav_agent.target_position = owner.global_position
		_waypoints.clear()
		return false
	var policy_validation := _validate_path_policy(owner.global_position, planned_points)
	if not bool(policy_validation.get("valid", false)):
		_path_policy_blocked = true
		_last_policy_blocked_segment = int(policy_validation.get("segment_index", -1))
		_mark_path_failed("policy_blocked")
		if _use_navmesh and _nav_agent:
			_nav_agent.target_position = owner.global_position
		_waypoints.clear()
		return false
	_path_policy_blocked = false
	_last_policy_blocked_segment = -1
	_last_valid_path_node = planned_points.back()
	if _use_navmesh and _nav_agent:
		_nav_agent.target_position = target_pos
		_waypoints.clear()
	else:
		_waypoints = planned_points.duplicate()
	return true


func _has_active_path_to(target_pos: Vector2) -> bool:
	if _path_policy_blocked:
		return false
	var arrive_px := _pursuit_cfg_float("waypoint_reached_px", 12.0)
	if owner.global_position.distance_to(target_pos) <= arrive_px:
		return true
	if _use_navmesh and _nav_agent:
		return not _nav_agent.is_navigation_finished()
	return not _waypoints.is_empty()


func _follow_waypoints(speed_scale: float, delta: float) -> bool:
	if _use_navmesh and _nav_agent:
		if _nav_agent.is_navigation_finished():
			_stop_motion(delta)
			return false
		var next_point := _nav_agent.get_next_path_position()
		var moved := false
		var dir := (next_point - owner.global_position).normalized()
		if dir.length_squared() > 0.0001:
			moved = _move_in_direction(dir, speed_scale, delta)
		else:
			_stop_motion(delta)
		if owner.get_slide_collision_count() > 0:
			var blocked_door_system := _get_door_system()
			if blocked_door_system and blocked_door_system.has_method("try_enemy_open_nearest"):
				blocked_door_system.try_enemy_open_nearest(owner.global_position)
		if nav_system and nav_system.has_method("room_id_at_point"):
			var nav_rid := int(nav_system.room_id_at_point(owner.global_position))
			if nav_rid >= 0:
				owner.set_meta("room_id", nav_rid)
		return moved

	if _waypoints.is_empty():
		_stop_motion(delta)
		return false

	var waypoint := _waypoints[0]
	if owner.global_position.distance_to(waypoint) <= _pursuit_cfg_float("waypoint_reached_px", 12.0):
		_waypoints.remove_at(0)
		if _waypoints.is_empty():
			_stop_motion(delta)
			return false
		waypoint = _waypoints[0]

	var dir := (waypoint - owner.global_position).normalized()
	var moved := _move_in_direction(dir, speed_scale, delta)
	# After move_and_slide, check if blocked by door.
	if owner.get_slide_collision_count() > 0:
		var door_system := _get_door_system()
		if door_system and door_system.has_method("try_enemy_open_nearest"):
			door_system.try_enemy_open_nearest(owner.global_position)
	if nav_system and nav_system.has_method("room_id_at_point"):
		var rid := int(nav_system.room_id_at_point(owner.global_position))
		if rid >= 0:
			owner.set_meta("room_id", rid)
	return moved


func _move_in_direction(dir: Vector2, speed_scale: float, delta: float) -> bool:
	if delta <= 0.0:
		return false
	var tile_size: int = GameConfig.tile_size if GameConfig else 32
	var speed_pixels := speed_tiles * tile_size * speed_scale
	var target_velocity := dir * speed_pixels
	var accel_per_sec := speed_pixels / maxf(_pursuit_cfg_float("accel_time_sec", ENEMY_ACCEL_TIME_SEC), 0.001)
	var next_velocity := owner.velocity.move_toward(target_velocity, accel_per_sec * delta)
	var predicted_pos := owner.global_position + next_velocity * delta
	if not _can_traverse_position(predicted_pos):
		owner.velocity = Vector2.ZERO
		_path_policy_blocked = true
		if _last_policy_blocked_segment < 0:
			_last_policy_blocked_segment = 0
		return false
	owner.velocity = next_velocity
	owner.move_and_slide()
	_set_target_facing(dir)
	return true


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


func _can_traverse_position(candidate_pos: Vector2) -> bool:
	if nav_system and nav_system.has_method("can_enemy_traverse_point"):
		return bool(nav_system.can_enemy_traverse_point(owner, candidate_pos))
	return true


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


func _pick_home_return_target() -> Vector2:
	if nav_system and nav_system.has_method("random_point_in_room") and home_room_id >= 0:
		return nav_system.random_point_in_room(home_room_id, 28.0)
	return owner.global_position


func _get_door_system() -> Node:
	if _door_system_checked:
		return _door_system_cache
	_door_system_checked = true
	if owner and owner.has_meta("door_system"):
		_door_system_cache = owner.get_meta("door_system") as Node
	return _door_system_cache


func _mark_path_failed(reason: String) -> void:
	_last_path_failed = true
	if _last_path_failed_reason == "":
		_last_path_failed_reason = reason


func _attempt_replan_with_policy(target_pos: Vector2) -> bool:
	if AIWatchdog:
		AIWatchdog.record_replan()
	var planned := _plan_path_to(target_pos)
	if planned:
		_policy_replan_attempts = 0
		_policy_fallback_used = false
		_policy_fallback_target = Vector2.ZERO
		return true
	_policy_replan_attempts += 1
	return false


func _handle_replan_failure(target_pos: Vector2) -> bool:
	if _policy_replan_attempts < PATH_POLICY_REPLAN_LIMIT:
		return false
	var fallback_target := _resolve_nearest_reachable_fallback(target_pos)
	if fallback_target == Vector2.ZERO:
		_mark_path_failed("fallback_missing")
		return false
	_policy_fallback_used = true
	_policy_fallback_target = fallback_target
	_policy_replan_attempts = 0
	if _plan_path_to(fallback_target):
		return true
	_mark_path_failed("fallback_failed")
	return false


func _build_reachable_path_points_for_enemy(target_pos: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if nav_system and nav_system.has_method("build_reachable_path_points"):
		var path_variant: Variant = nav_system.call("build_reachable_path_points", owner.global_position, target_pos, owner)
		if path_variant is Array:
			for point_variant in (path_variant as Array):
				out.append(point_variant as Vector2)
		return out
	if nav_system and nav_system.has_method("build_path_points"):
		var fallback_variant: Variant = nav_system.call("build_path_points", owner.global_position, target_pos)
		if fallback_variant is Array:
			for point_variant in (fallback_variant as Array):
				out.append(point_variant as Vector2)
		if out.is_empty() and target_pos != Vector2.ZERO:
			out.append(target_pos)
		return out
	if target_pos != Vector2.ZERO:
		out.append(target_pos)
	return out


func _validate_path_policy(from_pos: Vector2, path_points: Array[Vector2]) -> Dictionary:
	if path_points.is_empty():
		return {"valid": false, "segment_index": -1}
	if nav_system == null or not nav_system.has_method("can_enemy_traverse_point"):
		return {"valid": true, "segment_index": -1}
	var prev := from_pos
	var segment_index := 0
	for point in path_points:
		var segment_len := prev.distance_to(point)
		var steps := maxi(int(ceil(segment_len / PATH_POLICY_SAMPLE_STEP_PX)), 1)
		for step in range(1, steps + 1):
			var t := float(step) / float(steps)
			var sample := prev.lerp(point, t)
			if not bool(nav_system.call("can_enemy_traverse_point", owner, sample)):
				return {
					"valid": false,
					"segment_index": segment_index,
					"blocked_point": sample,
				}
		prev = point
		segment_index += 1
	return {"valid": true, "segment_index": -1}


func _resolve_nearest_reachable_fallback(target_pos: Vector2) -> Vector2:
	var candidates := _sample_fallback_candidates(target_pos)
	var best_result := _select_nearest_reachable_candidate(target_pos, candidates)
	if bool(best_result.get("found", false)):
		return best_result.get("point", Vector2.ZERO) as Vector2
	if _last_valid_path_node != Vector2.ZERO:
		return _last_valid_path_node
	return Vector2.ZERO


func _sample_fallback_candidates(target_pos: Vector2) -> Array[Vector2]:
	var candidates: Array[Vector2] = []
	for ring_idx in range(FALLBACK_RING_COUNT):
		var radius := FALLBACK_RING_MIN_RADIUS_PX + FALLBACK_RING_STEP_RADIUS_PX * float(ring_idx)
		for sample_idx in range(FALLBACK_RING_SAMPLES_PER_RING):
			var angle := TAU * (float(sample_idx) / float(FALLBACK_RING_SAMPLES_PER_RING))
			candidates.append(target_pos + Vector2.RIGHT.rotated(angle) * radius)
	return candidates


func _select_nearest_reachable_candidate(target_pos: Vector2, candidates: Array[Vector2]) -> Dictionary:
	var best_point := Vector2.ZERO
	var best_nav_len := INF
	var best_euclid := INF
	for candidate in candidates:
		var nav_len := _nav_path_length_to(candidate)
		if not is_finite(nav_len):
			continue
		var euclid := candidate.distance_to(target_pos)
		if nav_len < best_nav_len or (is_equal_approx(nav_len, best_nav_len) and euclid < best_euclid):
			best_nav_len = nav_len
			best_euclid = euclid
			best_point = candidate
	return {
		"found": is_finite(best_nav_len),
		"point": best_point,
		"nav_path_length": best_nav_len,
		"euclid_to_target": best_euclid,
	}


func _nav_path_length_to(target_pos: Vector2) -> float:
	if nav_system and nav_system.has_method("nav_path_length"):
		var len_variant: Variant = nav_system.call("nav_path_length", owner.global_position, target_pos, owner)
		var len_value := float(len_variant)
		if is_finite(len_value):
			return len_value
		return INF
	var path_points := _build_reachable_path_points_for_enemy(target_pos)
	if path_points.is_empty():
		return INF
	var policy_validation := _validate_path_policy(owner.global_position, path_points)
	if not bool(policy_validation.get("valid", false)):
		return INF
	return _path_length(owner.global_position, path_points)


func _path_length(from_pos: Vector2, path_points: Array[Vector2]) -> float:
	if path_points.is_empty():
		return INF
	var total := 0.0
	var prev := from_pos
	for point in path_points:
		total += prev.distance_to(point)
		prev = point
	return total


func _reset_stall_monitor() -> void:
	_stall_clock = 0.0
	_stall_check_timer = 0.0
	_stall_samples.clear()
	_stall_consecutive_windows = 0
	_hard_stall = false
	_last_stall_speed_avg = 0.0
	_last_stall_path_progress = 0.0


func _update_stall_monitor(delta: float, target_pos: Vector2) -> bool:
	if delta <= 0.0 or target_pos == Vector2.ZERO:
		return false
	_stall_clock += delta
	_stall_samples.append({
		"t": _stall_clock,
		"pos": owner.global_position,
		"dist_to_target": owner.global_position.distance_to(target_pos),
	})
	while _stall_samples.size() > 1 and (_stall_clock - float(_stall_samples[0].get("t", 0.0))) > STALL_WINDOW_SEC:
		_stall_samples.remove_at(0)
	_stall_check_timer += delta
	if _stall_check_timer < STALL_CHECK_INTERVAL_SEC:
		return false
	_stall_check_timer = 0.0
	if _stall_samples.size() < 2:
		return false
	var oldest := _stall_samples[0] as Dictionary
	var newest := _stall_samples[_stall_samples.size() - 1] as Dictionary
	var window_sec := float(newest.get("t", 0.0)) - float(oldest.get("t", 0.0))
	if window_sec < STALL_WINDOW_SEC * 0.95:
		return false
	var traveled := 0.0
	for i in range(1, _stall_samples.size()):
		var prev := _stall_samples[i - 1] as Dictionary
		var cur := _stall_samples[i] as Dictionary
		var prev_pos := prev.get("pos", owner.global_position) as Vector2
		var cur_pos := cur.get("pos", owner.global_position) as Vector2
		traveled += prev_pos.distance_to(cur_pos)
	var speed_avg := traveled / maxf(window_sec, 0.001)
	var path_progress := maxf(
		0.0,
		float(oldest.get("dist_to_target", 0.0)) - float(newest.get("dist_to_target", 0.0))
	)
	_last_stall_speed_avg = speed_avg
	_last_stall_path_progress = path_progress
	var stalled_window := _is_stall_window_stalled(speed_avg, path_progress)
	return _consume_stall_window_result(stalled_window)


func _is_stall_window_stalled(speed_avg: float, path_progress: float) -> bool:
	return speed_avg < STALL_SPEED_THRESHOLD_PX_PER_SEC and path_progress < STALL_PATH_PROGRESS_THRESHOLD_PX


func _consume_stall_window_result(stalled_window: bool) -> bool:
	if stalled_window:
		_stall_consecutive_windows += 1
	else:
		_stall_consecutive_windows = 0
	_hard_stall = _stall_consecutive_windows >= STALL_HARD_CONSECUTIVE_WINDOWS
	return _hard_stall


func debug_get_navigation_policy_snapshot() -> Dictionary:
	return {
		"path_failed": _last_path_failed,
		"path_failed_reason": _last_path_failed_reason,
		"policy_blocked": _path_policy_blocked,
		"policy_blocked_segment": _last_policy_blocked_segment,
		"policy_replan_attempts": _policy_replan_attempts,
		"policy_fallback_used": _policy_fallback_used,
		"policy_fallback_target": _policy_fallback_target,
		"last_valid_path_node": _last_valid_path_node,
		"hard_stall": _hard_stall,
		"stall_consecutive_windows": _stall_consecutive_windows,
		"stall_speed_avg": _last_stall_speed_avg,
		"stall_path_progress": _last_stall_path_progress,
	}


func debug_feed_stall_window(speed_avg: float, path_progress: float) -> Dictionary:
	var stalled_window := _is_stall_window_stalled(speed_avg, path_progress)
	var hard_stall := _consume_stall_window_result(stalled_window)
	_last_stall_speed_avg = speed_avg
	_last_stall_path_progress = path_progress
	return {
		"stalled_window": stalled_window,
		"hard_stall": hard_stall,
		"consecutive_windows": _stall_consecutive_windows,
	}


func debug_select_nearest_reachable_fallback(target_pos: Vector2, candidates: Array[Vector2]) -> Dictionary:
	return _select_nearest_reachable_candidate(target_pos, candidates)


func _pursuit_cfg_float(key: String, fallback: float) -> float:
	if GameConfig and GameConfig.ai_balance.has("pursuit"):
		var section := GameConfig.ai_balance["pursuit"] as Dictionary
		return float(section.get(key, fallback))
	return fallback
