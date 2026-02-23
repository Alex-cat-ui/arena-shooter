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
const PATH_POLICY_SAMPLE_STEP_PX := 12.0
const STALL_WINDOW_SEC := 0.6
const STALL_CHECK_INTERVAL_SEC := 0.1
const STALL_SPEED_THRESHOLD_PX_PER_SEC := 8.0
const STALL_PATH_PROGRESS_THRESHOLD_PX := 12.0
const STALL_HARD_CONSECUTIVE_WINDOWS := 2
const PLAN_TARGET_SWITCH_EPS_PX := 8.0
const SHADOW_UNREACHABLE_SEARCH_TICKS := 1
const SHADOW_UNREACHABLE_FSM_STATE_NONE := "none"
const SHADOW_UNREACHABLE_FSM_STATE_BOUNDARY_SCAN := "shadow_boundary_scan"
const SHADOW_UNREACHABLE_FSM_STATE_SEARCH := "search"
const SHADOW_BOUNDARY_SEARCH_RADIUS_PX := 96.0
const SHADOW_SCAN_DURATION_MIN_SEC := 2.0
const SHADOW_SCAN_DURATION_MAX_SEC := 3.0
const SHADOW_SCAN_SWEEP_RAD := 0.87
const SHADOW_SCAN_SWEEP_SPEED := 2.4
const PATH_PLAN_STATUS_OK := "ok"
const PATH_PLAN_STATUS_UNREACHABLE_POLICY := "unreachable_policy"
const PATH_PLAN_STATUS_UNREACHABLE_GEOMETRY := "unreachable_geometry"

var owner: CharacterBody2D = null
var sprite: Sprite2D = null
var speed_tiles: float = 2.0
var nav_system: Node = null
var home_room_id: int = -1
var _patrol = null

var facing_dir: Vector2 = Vector2.RIGHT
var _target_facing_dir: Vector2 = Vector2.RIGHT

var _roam_target: Vector2 = Vector2.ZERO
var _roam_target_valid: bool = false
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
var _last_path_plan_status: String = ""
var _last_path_plan_reason: String = ""
var _last_path_plan_blocked_point: Vector2 = Vector2.ZERO
var _last_path_plan_blocked_point_valid: bool = false
var _last_valid_path_node: Vector2 = Vector2.ZERO
var _last_valid_path_node_valid: bool = false
var _active_move_target: Vector2 = Vector2.ZERO
var _active_move_target_valid: bool = false
var _stall_clock: float = 0.0
var _stall_check_timer: float = 0.0
var _stall_samples: Array[Dictionary] = []
var _stall_consecutive_windows: int = 0
var _hard_stall: bool = false
var _last_stall_speed_avg: float = 0.0
var _last_stall_path_progress: float = 0.0
var _plan_id: int = 0
var _plan_intent_type: int = -1
var _intent_target: Vector2 = Vector2.ZERO
var _intent_target_valid: bool = false
var _plan_target: Vector2 = Vector2.ZERO
var _plan_target_valid: bool = false
var _shadow_unreachable_fsm_state: String = SHADOW_UNREACHABLE_FSM_STATE_NONE
var _shadow_unreachable_forced_search_ticks_left: int = 0
var _shadow_scan_active: bool = false
var _shadow_scan_phase: float = 0.0
var _shadow_scan_timer: float = 0.0
var _shadow_scan_target: Vector2 = Vector2.ZERO
var _shadow_scan_boundary_point: Vector2 = Vector2.ZERO
var _shadow_scan_boundary_valid: bool = false
var _shadow_scan_exec_status: String = "inactive"
var _shadow_scan_exec_complete_reason: String = "none"
var _last_slide_collision_kind: String = "none"
var _last_slide_collision_forced_repath: bool = false
var _last_slide_collision_reason: String = "none"
var _last_slide_collision_index: int = -1


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
	_roam_target_valid = false
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
	_last_path_plan_status = ""
	_last_path_plan_reason = ""
	_last_path_plan_blocked_point = Vector2.ZERO
	_last_path_plan_blocked_point_valid = false
	_last_valid_path_node = Vector2.ZERO
	_last_valid_path_node_valid = false
	_active_move_target = Vector2.ZERO
	_active_move_target_valid = false
	_plan_id = 0
	_plan_intent_type = -1
	_intent_target = Vector2.ZERO
	_intent_target_valid = false
	_plan_target = Vector2.ZERO
	_plan_target_valid = false
	_shadow_unreachable_fsm_state = SHADOW_UNREACHABLE_FSM_STATE_NONE
	_shadow_unreachable_forced_search_ticks_left = 0
	_shadow_scan_active = false
	_shadow_scan_phase = 0.0
	_shadow_scan_timer = 0.0
	_shadow_scan_target = Vector2.ZERO
	_shadow_scan_boundary_point = Vector2.ZERO
	_shadow_scan_boundary_valid = false
	_shadow_scan_exec_status = "inactive"
	_shadow_scan_exec_complete_reason = "none"
	_last_slide_collision_kind = "none"
	_last_slide_collision_forced_repath = false
	_last_slide_collision_reason = "none"
	_last_slide_collision_index = -1
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
	if not _is_same_or_adjacent_room(own_room, shot_room_id):
		return

	clear_shadow_scan_state()
	_set_last_seen(shot_pos)
	_plan_path_to(_last_seen_pos)
	if _patrol:
		_patrol.notify_alert()


func _is_same_or_adjacent_room(room_a: int, room_b: int) -> bool:
	if room_a < 0 or room_b < 0:
		return false
	if nav_system and nav_system.has_method("is_same_or_adjacent_room"):
		return bool(nav_system.call("is_same_or_adjacent_room", room_a, room_b))
	if room_a == room_b:
		return true
	if nav_system and nav_system.has_method("is_adjacent"):
		return bool(nav_system.call("is_adjacent", room_a, room_b))
	if nav_system and nav_system.has_method("get_neighbors"):
		return (nav_system.get_neighbors(room_a) as Array).has(room_b)
	return false


func execute_intent(delta: float, intent: Dictionary, context: Dictionary) -> Dictionary:
	var normalized_delta := _normalize_nonnegative_delta(delta)
	var request_fire := false
	var intent_type := _normalize_execute_intent_type(intent.get("type", ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL))
	var target_parse := _extract_optional_finite_target(intent)
	var has_target := bool(target_parse.get("valid", false))
	var target := target_parse.get("target", Vector2.ZERO) as Vector2
	var shadow_scan_result_target := target if has_target else Vector2.ZERO
	var movement_intent := false
	var player_pos := _context_vec2_or_default(context, "player_pos", target if has_target else owner.global_position)
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
	var known_target_pos := _context_vec2_or_zero(context, "known_target_pos")
	var last_seen_anchor := _context_vec2_or_zero(context, "last_seen_pos")
	var investigate_anchor := _context_vec2_or_zero(context, "investigate_anchor")
	var home_pos := _context_vec2_or_zero(context, "home_position")
	var active_target_context := (
		known_target_pos != Vector2.ZERO
		or last_seen_anchor != Vector2.ZERO
		or investigate_anchor != Vector2.ZERO
	)
	if owner and owner.has_method("set_shadow_check_flashlight"):
		owner.call("set_shadow_check_flashlight", false)
	if owner and owner.has_method("set_shadow_scan_active"):
		owner.call("set_shadow_scan_active", false)
	_shadow_scan_exec_status = "inactive"
	_shadow_scan_exec_complete_reason = "none"

	if alert_level >= ENEMY_ALERT_LEVELS_SCRIPT.ALERT and active_target_context and (
		intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL
		or intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETURN_HOME
	):
		intent_type = ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH
		var guard_target := _pick_guard_target_from_context(known_target_pos, last_seen_anchor, investigate_anchor, home_pos)
		has_target = _is_finite_vector2(guard_target)
		target = guard_target if has_target else Vector2.ZERO

	# Reset search sub-state when effective intent type changes.
	if intent_type != _last_intent_type:
		_last_intent_type = intent_type
		_search_phase = 0.0
		_in_hold_listen = false
		_hold_listen_timer = 0.0

	_last_path_failed = false
	_last_path_failed_reason = ""
	_last_policy_blocked_segment = -1
	_last_slide_collision_kind = "none"
	_last_slide_collision_forced_repath = false
	_last_slide_collision_reason = "none"
	_last_slide_collision_index = -1
	_intent_target = target if has_target else Vector2.ZERO
	_intent_target_valid = has_target

	var force_missing_move_target := _intent_uses_move_target(intent_type) and not has_target
	var skip_plan_lock_update := force_missing_move_target
	_update_plan_lock(intent_type, _intent_target, _intent_target_valid, not skip_plan_lock_update)

	var keep_shadow_scan_runtime := (
		_shadow_unreachable_fsm_state == SHADOW_UNREACHABLE_FSM_STATE_BOUNDARY_SCAN
		or intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SHADOW_BOUNDARY_SCAN
	)
	if not keep_shadow_scan_runtime and (_shadow_scan_active or _shadow_scan_boundary_valid):
		clear_shadow_scan_state()

	var execute_target := _plan_target if _plan_target_valid else _intent_target
	var execute_has_target := _plan_target_valid if _plan_target_valid else _intent_target_valid
	if force_missing_move_target:
		execute_target = Vector2.ZERO
		execute_has_target = false

	if _shadow_unreachable_fsm_state == SHADOW_UNREACHABLE_FSM_STATE_BOUNDARY_SCAN:
		movement_intent = _execute_shadow_boundary_scan(normalized_delta, execute_target, execute_has_target)
		if not _shadow_scan_active and not movement_intent:
			_shadow_unreachable_fsm_state = SHADOW_UNREACHABLE_FSM_STATE_SEARCH
			_shadow_unreachable_forced_search_ticks_left = max(
				_shadow_unreachable_forced_search_ticks_left,
				SHADOW_UNREACHABLE_SEARCH_TICKS
			)
	elif _shadow_unreachable_fsm_state == SHADOW_UNREACHABLE_FSM_STATE_SEARCH:
		_execute_search(normalized_delta, execute_target)
		if _shadow_unreachable_forced_search_ticks_left > 0:
			_shadow_unreachable_forced_search_ticks_left -= 1
		if _shadow_unreachable_forced_search_ticks_left <= 0:
			_shadow_unreachable_fsm_state = SHADOW_UNREACHABLE_FSM_STATE_NONE
	else:
		match intent_type:
			ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL:
				_update_idle_roam(normalized_delta)
			ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.INVESTIGATE:
				if not execute_has_target:
					_mark_missing_move_target(normalized_delta)
				else:
					movement_intent = true
					_set_last_seen(execute_target)
					var investigate_arrive_px := _pursuit_cfg_float("last_seen_reached_px", LAST_SEEN_REACHED_PX)
					if owner.global_position.distance_to(execute_target) <= investigate_arrive_px:
						_execute_search(normalized_delta, execute_target)
					else:
						_execute_move_to_target(normalized_delta, execute_target, 1.0, -1.0, true, context)
			ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH:
				_execute_search(normalized_delta, execute_target)
			ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SHADOW_BOUNDARY_SCAN:
				movement_intent = _execute_shadow_boundary_scan(normalized_delta, execute_target, execute_has_target)
			ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT:
				if not execute_has_target:
					_mark_missing_move_target(normalized_delta)
				else:
					movement_intent = true
					_execute_move_to_target(normalized_delta, execute_target, 0.95, -1.0, true, context)
			ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.HOLD_RANGE:
				_stop_motion(normalized_delta)
				face_towards(player_pos if has_los else execute_target)
				request_fire = has_los and dist <= _pursuit_cfg_float("attack_range_max_px", ATTACK_RANGE_MAX_PX)
			ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH:
				var push_target := execute_target
				var push_has_target := execute_has_target
				if not push_has_target and _is_finite_vector2(player_pos):
					push_target = player_pos
					push_has_target = true
				if not push_has_target:
					_mark_missing_move_target(normalized_delta)
				else:
					movement_intent = true
					var repath_override := _combat_no_los_repath_interval_sec() if combat_no_los else -1.0
					_execute_move_to_target(normalized_delta, push_target, 1.0, repath_override, true, context)
					face_towards(push_target)
				request_fire = has_los and dist <= _pursuit_cfg_float("attack_range_max_px", ATTACK_RANGE_MAX_PX)
			ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETREAT:
				movement_intent = true
				_execute_retreat_from(normalized_delta, player_pos)
			ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETURN_HOME:
				var home_target := execute_target
				var home_has_target := execute_has_target
				if not home_has_target:
					home_target = _pick_home_return_target()
					home_has_target = _is_finite_vector2(home_target)
				if not home_has_target:
					_mark_missing_move_target(normalized_delta)
				else:
					movement_intent = true
					_execute_move_to_target(normalized_delta, home_target, 0.9, -1.0, true, context)
			_:
				_update_idle_roam(normalized_delta)

	_update_facing(normalized_delta)
	return {
		"request_fire": request_fire,
		"path_failed": _last_path_failed,
		"path_failed_reason": _last_path_failed_reason,
		"policy_blocked_segment": _last_policy_blocked_segment,
		"movement_intent": movement_intent,
		"shadow_scan_status": _shadow_scan_exec_status,
		"shadow_scan_complete_reason": _shadow_scan_exec_complete_reason,
		"shadow_scan_target": shadow_scan_result_target,
		"plan_id": _plan_id,
		"intent_target": _intent_target if _intent_target_valid else Vector2.ZERO,
		"plan_target": _plan_target if _plan_target_valid else Vector2.ZERO,
		"shadow_unreachable_fsm_state": _shadow_unreachable_fsm_state,
	}


func _normalize_nonnegative_delta(delta: float) -> float:
	if not is_finite(delta):
		return 0.0
	return maxf(delta, 0.0)


func _normalize_execute_intent_type(raw_type: Variant) -> int:
	var intent_type := int(raw_type)
	var supported := [
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL,
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.INVESTIGATE,
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH,
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT,
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.HOLD_RANGE,
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH,
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETREAT,
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETURN_HOME,
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SHADOW_BOUNDARY_SCAN,
	]
	if supported.has(intent_type):
		return intent_type
	return ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL


func _extract_optional_finite_target(intent: Dictionary) -> Dictionary:
	if not intent.has("target"):
		return {
			"valid": false,
			"target": Vector2.ZERO,
		}
	var target_variant: Variant = intent.get("target", null)
	if target_variant is Vector2 and _is_finite_vector2(target_variant as Vector2):
		return {
			"valid": true,
			"target": target_variant as Vector2,
		}
	return {
		"valid": false,
		"target": Vector2.ZERO,
	}


func _is_finite_vector2(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)


func _context_vec2_or_default(context: Dictionary, key: String, fallback: Vector2) -> Vector2:
	var value: Variant = context.get(key, fallback)
	if value is Vector2 and _is_finite_vector2(value as Vector2):
		return value as Vector2
	return fallback if _is_finite_vector2(fallback) else Vector2.ZERO


func _context_vec2_or_zero(context: Dictionary, key: String) -> Vector2:
	return _context_vec2_or_default(context, key, Vector2.ZERO)


func _pick_guard_target_from_context(
	known_target_pos: Vector2,
	last_seen_anchor: Vector2,
	investigate_anchor: Vector2,
	home_pos: Vector2
) -> Vector2:
	if _is_finite_vector2(known_target_pos) and known_target_pos != Vector2.ZERO:
		return known_target_pos
	if _is_finite_vector2(last_seen_anchor) and last_seen_anchor != Vector2.ZERO:
		return last_seen_anchor
	if _is_finite_vector2(investigate_anchor) and investigate_anchor != Vector2.ZERO:
		return investigate_anchor
	if _is_finite_vector2(home_pos):
		return home_pos
	return Vector2.ZERO


func _intent_uses_move_target(intent_type: int) -> bool:
	return (
		intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.INVESTIGATE
		or intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT
		or intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH
		or intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETURN_HOME
	)


func _update_plan_lock(intent_type: int, target: Vector2, target_valid: bool, allow_update: bool) -> void:
	if not allow_update:
		return
	var replace_plan := false
	if _plan_id == 0:
		replace_plan = true
	elif intent_type != _plan_intent_type:
		replace_plan = true
	elif target_valid != _plan_target_valid:
		replace_plan = true
	elif target_valid and _plan_target_valid and _plan_target.distance_to(target) > PLAN_TARGET_SWITCH_EPS_PX:
		replace_plan = true
	if not replace_plan:
		return
	_plan_id += 1
	_plan_intent_type = intent_type
	_plan_target_valid = target_valid
	_plan_target = target if target_valid else Vector2.ZERO


func _mark_missing_move_target(delta: float) -> void:
	_stop_motion(delta)
	_mark_path_failed("no_target")
	_active_move_target_valid = false
	_reset_stall_monitor()


func _should_start_shadow_unreachable_fsm(context: Dictionary, target_pos: Vector2, target_valid: bool) -> bool:
	if _shadow_unreachable_fsm_state != SHADOW_UNREACHABLE_FSM_STATE_NONE:
		return false
	if not target_valid:
		return false
	if _last_path_plan_status != PATH_PLAN_STATUS_UNREACHABLE_POLICY:
		return false
	var alert_level := int(context.get("alert_level", ENEMY_ALERT_LEVELS_SCRIPT.CALM))
	if alert_level < ENEMY_ALERT_LEVELS_SCRIPT.ALERT:
		return false
	var known_target_pos := _context_vec2_or_zero(context, "known_target_pos")
	var last_seen_anchor := _context_vec2_or_zero(context, "last_seen_pos")
	var investigate_anchor := _context_vec2_or_zero(context, "investigate_anchor")
	var active_target_context := (
		known_target_pos != Vector2.ZERO
		or last_seen_anchor != Vector2.ZERO
		or investigate_anchor != Vector2.ZERO
	)
	if not active_target_context:
		return false
	if nav_system == null or not nav_system.has_method("is_point_in_shadow"):
		return false
	return bool(nav_system.call("is_point_in_shadow", target_pos))


func _start_shadow_unreachable_fsm() -> void:
	clear_shadow_scan_state()
	_shadow_unreachable_fsm_state = SHADOW_UNREACHABLE_FSM_STATE_BOUNDARY_SCAN
	_shadow_unreachable_forced_search_ticks_left = SHADOW_UNREACHABLE_SEARCH_TICKS
	_last_path_failed = true
	_last_path_failed_reason = "shadow_unreachable_policy"
	_repath_timer = 0.0


func _handle_replan_failure_or_shadow_fsm(delta: float, runtime_context: Dictionary, target_pos: Vector2, target_valid: bool) -> bool:
	if _should_start_shadow_unreachable_fsm(runtime_context, target_pos, target_valid):
		_stop_motion(delta)
		_reset_stall_monitor()
		_start_shadow_unreachable_fsm()
		return true
	_stop_motion(delta)
	_mark_path_failed("replan_failed")
	return false


func _execute_move_to_target(
	delta: float,
	target: Vector2,
	speed_scale: float,
	repath_interval_override_sec: float = -1.0,
	has_target: bool = true,
	runtime_context: Dictionary = {}
) -> bool:
	if not has_target:
		_mark_missing_move_target(delta)
		return false
	var movement_target := target
	if not _active_move_target_valid or _active_move_target.distance_to(movement_target) > 0.5:
		_reset_stall_monitor()
	_active_move_target = movement_target
	_active_move_target_valid = true
	var repath_interval := repath_interval_override_sec
	if repath_interval <= 0.0:
		repath_interval = _pursuit_cfg_float("path_repath_interval_sec", PATH_REPATH_INTERVAL_SEC)
	_repath_timer -= delta
	if _repath_timer <= 0.0 or _path_policy_blocked:
		_repath_timer = repath_interval
		if not _attempt_replan_with_policy(movement_target):
			return _handle_replan_failure_or_shadow_fsm(delta, runtime_context, movement_target, has_target)
	if not _has_active_path_to(movement_target):
		_mark_path_failed("path_unavailable")
		_stop_motion(delta)
		return false
	var moved := _follow_waypoints(speed_scale, delta)
	if not moved and _path_policy_blocked:
		_mark_path_failed("policy_blocked")
		_repath_timer = 0.0
		if not _attempt_replan_with_policy(movement_target):
			return _handle_replan_failure_or_shadow_fsm(delta, runtime_context, movement_target, has_target)
	if _update_stall_monitor(delta, movement_target, has_target):
		_mark_path_failed("hard_stall")
		_repath_timer = 0.0
		if not _attempt_replan_with_policy(movement_target):
			return _handle_replan_failure_or_shadow_fsm(delta, runtime_context, movement_target, has_target)
	if owner.global_position.distance_to(movement_target) <= _pursuit_cfg_float("waypoint_reached_px", 12.0):
		_stop_motion(delta)
		_active_move_target_valid = false
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


func clear_shadow_scan_state() -> void:
	_shadow_scan_active = false
	_shadow_scan_phase = 0.0
	_shadow_scan_timer = 0.0
	_shadow_scan_target = Vector2.ZERO
	_shadow_scan_boundary_point = Vector2.ZERO
	_shadow_scan_boundary_valid = false
	if owner and owner.has_method("set_shadow_check_flashlight"):
		owner.call("set_shadow_check_flashlight", false)
	if owner and owner.has_method("set_shadow_scan_active"):
		owner.call("set_shadow_scan_active", false)


func _set_shadow_scan_exec_result(status: String, complete_reason: String = "none") -> void:
	_shadow_scan_exec_status = status
	_shadow_scan_exec_complete_reason = complete_reason


func _execute_shadow_boundary_scan(delta: float, target: Vector2, has_target: bool) -> bool:
	if not has_target:
		_set_shadow_scan_exec_result("completed", "target_invalid")
		clear_shadow_scan_state()
		_stop_motion(delta)
		return false
	if _shadow_scan_target.distance_to(target) > 0.5:
		_shadow_scan_target = target
		_shadow_scan_boundary_valid = false
	if _shadow_scan_active:
		var timed_out_while_sweeping := _run_shadow_scan_sweep(delta, target)
		if timed_out_while_sweeping:
			_set_shadow_scan_exec_result("completed", "timeout")
		else:
			_set_shadow_scan_exec_result("running")
		return false
	if not _shadow_scan_boundary_valid:
		_shadow_scan_boundary_point = _resolve_shadow_scan_boundary_point(target)
		_shadow_scan_boundary_valid = _shadow_scan_boundary_point != Vector2.ZERO
	if not _shadow_scan_boundary_valid:
		_set_shadow_scan_exec_result("completed", "boundary_unreachable")
		_stop_motion(delta)
		_set_target_facing((target - owner.global_position).normalized())
		return false
	var arrive_px := _pursuit_cfg_float("last_seen_reached_px", LAST_SEEN_REACHED_PX)
	if owner.global_position.distance_to(_shadow_scan_boundary_point) > arrive_px:
		_set_shadow_scan_exec_result("running")
		return _execute_move_to_target(delta, _shadow_scan_boundary_point, 1.0, -1.0, true)
	_shadow_scan_active = true
	_shadow_scan_phase = 0.0
	_shadow_scan_timer = _rng.randf_range(SHADOW_SCAN_DURATION_MIN_SEC, SHADOW_SCAN_DURATION_MAX_SEC)
	var timed_out_on_start := _run_shadow_scan_sweep(delta, target)
	if timed_out_on_start:
		_set_shadow_scan_exec_result("completed", "timeout")
	else:
		_set_shadow_scan_exec_result("running")
	return false


func _resolve_shadow_scan_boundary_point(target: Vector2) -> Vector2:
	if nav_system and nav_system.has_method("get_nearest_non_shadow_point"):
		var boundary := nav_system.call("get_nearest_non_shadow_point", target, SHADOW_BOUNDARY_SEARCH_RADIUS_PX) as Vector2
		if boundary != Vector2.ZERO:
			return boundary
	return Vector2.ZERO


func _run_shadow_scan_sweep(delta: float, target: Vector2) -> bool:
	_stop_motion(delta)
	if owner and owner.has_method("set_shadow_check_flashlight"):
		owner.call("set_shadow_check_flashlight", true)
	if owner and owner.has_method("set_shadow_scan_active"):
		owner.call("set_shadow_scan_active", true)
	_shadow_scan_timer = maxf(0.0, _shadow_scan_timer - maxf(delta, 0.0))
	_shadow_scan_phase += maxf(delta, 0.0) * SHADOW_SCAN_SWEEP_SPEED
	var base_dir := (target - owner.global_position).normalized()
	if base_dir.length_squared() <= 0.0001:
		base_dir = facing_dir if facing_dir.length_squared() > 0.0001 else Vector2.RIGHT
	var angle := sin(_shadow_scan_phase) * SHADOW_SCAN_SWEEP_RAD
	_set_target_facing(base_dir.rotated(angle))
	if _shadow_scan_timer <= 0.0:
		clear_shadow_scan_state()
		return true
	return false


func _execute_retreat_from(delta: float, danger_origin: Vector2) -> void:
	var retreat_dir := (owner.global_position - danger_origin).normalized()
	if retreat_dir.length_squared() <= 0.0001:
		retreat_dir = Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU))
	var retreat_target := owner.global_position + retreat_dir * _pursuit_cfg_float("retreat_distance_px", 140.0)
	_execute_move_to_target(delta, retreat_target, 0.95)


func _update_idle_roam(delta: float) -> void:
	if _patrol:
		var patrol_decision := _patrol.update(delta, facing_dir) as Dictionary
		var shadow_check := bool(patrol_decision.get("shadow_check", false))
		if owner and owner.has_method("set_shadow_check_flashlight"):
			owner.call("set_shadow_check_flashlight", shadow_check)
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

	if not _roam_target_valid or owner.global_position.distance_to(_roam_target) < 10.0:
		if nav_system and nav_system.has_method("random_point_in_room"):
			_roam_target = nav_system.random_point_in_room(home_room_id, 28.0)
		else:
			_roam_target = owner.global_position
		_roam_target_valid = true
		_roam_wait_timer = randf_range(0.1, 0.35)
		_stop_motion(delta)
		return

	var dir := (_roam_target - owner.global_position).normalized()
	_move_in_direction(dir, 0.85, delta)


func _plan_path_to(target_pos: Vector2, has_target: bool = true) -> bool:
	var plan_contract := _request_path_plan_contract(target_pos, has_target)
	var normalized_plan := _normalize_path_plan_contract(plan_contract, target_pos)
	_record_path_plan_contract(normalized_plan)
	var status := String(normalized_plan.get("status", PATH_PLAN_STATUS_UNREACHABLE_GEOMETRY))
	var planned_points := _extract_vector2_path_points(normalized_plan.get("path_points", []))
	var failed_reason := String(normalized_plan.get("reason", "path_unreachable"))
	if status != PATH_PLAN_STATUS_OK:
		_path_policy_blocked = status == PATH_PLAN_STATUS_UNREACHABLE_POLICY
		_last_policy_blocked_segment = int(normalized_plan.get("segment_index", -1))
		if _path_policy_blocked and _last_policy_blocked_segment < 0:
			_last_policy_blocked_segment = 0
		_mark_path_failed(failed_reason)
		if _use_navmesh and _nav_agent:
			_nav_agent.target_position = owner.global_position
		_waypoints.clear()
		return false
	if planned_points.is_empty():
		_path_policy_blocked = false
		_last_policy_blocked_segment = -1
		_mark_path_failed("empty_path")
		if _use_navmesh and _nav_agent:
			_nav_agent.target_position = owner.global_position
		_waypoints.clear()
		return false
	_path_policy_blocked = false
	_last_policy_blocked_segment = -1
	_last_valid_path_node = planned_points.back()
	_last_valid_path_node_valid = true
	if _use_navmesh and _nav_agent:
		_nav_agent.target_position = target_pos
		_waypoints.clear()
	else:
		_waypoints = planned_points.duplicate()
	return true


func _request_path_plan_contract(target_pos: Vector2, has_target: bool = true) -> Dictionary:
	if not has_target:
		return {
			"status": PATH_PLAN_STATUS_UNREACHABLE_GEOMETRY,
			"path_points": [],
			"reason": "no_target",
		}
	if nav_system == null:
		return {
			"status": PATH_PLAN_STATUS_UNREACHABLE_GEOMETRY,
			"path_points": [],
			"reason": "nav_system_missing",
		}
	if not nav_system.has_method("build_policy_valid_path"):
		return {
			"status": PATH_PLAN_STATUS_UNREACHABLE_GEOMETRY,
			"path_points": [],
			"reason": "nav_system_missing",
		}
	var contract_variant: Variant = nav_system.call("build_policy_valid_path", owner.global_position, target_pos, owner)
	if not (contract_variant is Dictionary):
		return {
			"status": PATH_PLAN_STATUS_UNREACHABLE_GEOMETRY,
			"path_points": [],
			"reason": "nav_system_missing",
		}
	return contract_variant as Dictionary


func _normalize_path_plan_contract(contract: Dictionary, target_pos: Vector2) -> Dictionary:
	var status := String(contract.get("status", PATH_PLAN_STATUS_UNREACHABLE_GEOMETRY))
	if status != PATH_PLAN_STATUS_OK and status != PATH_PLAN_STATUS_UNREACHABLE_POLICY and status != PATH_PLAN_STATUS_UNREACHABLE_GEOMETRY:
		status = PATH_PLAN_STATUS_UNREACHABLE_GEOMETRY
	var path_points := _extract_vector2_path_points(contract.get("path_points", []))
	if status == PATH_PLAN_STATUS_OK and not path_points.is_empty() and path_points[path_points.size() - 1].distance_to(target_pos) > 0.5:
		path_points.append(target_pos)
	var reason := String(contract.get("reason", ""))
	if reason == "":
		match status:
			PATH_PLAN_STATUS_OK:
				reason = "ok"
			PATH_PLAN_STATUS_UNREACHABLE_POLICY:
				reason = "policy_blocked"
			_:
				reason = "path_unreachable"
	var out := {
		"status": status,
		"path_points": path_points,
		"reason": reason,
		"segment_index": int(contract.get("segment_index", -1)),
	}
	var blocked_point_variant: Variant = contract.get("blocked_point", null)
	if blocked_point_variant is Vector2:
		out["blocked_point"] = blocked_point_variant as Vector2
	if status == PATH_PLAN_STATUS_OK and path_points.is_empty():
		out["status"] = PATH_PLAN_STATUS_UNREACHABLE_GEOMETRY
		out["reason"] = "empty_path"
	return out


func _record_path_plan_contract(contract: Dictionary) -> void:
	_last_path_plan_status = String(contract.get("status", ""))
	_last_path_plan_reason = String(contract.get("reason", ""))
	_last_path_plan_blocked_point = Vector2.ZERO
	_last_path_plan_blocked_point_valid = false
	if contract.has("blocked_point"):
		var blocked_variant: Variant = contract.get("blocked_point", null)
		if blocked_variant is Vector2:
			_last_path_plan_blocked_point = blocked_variant as Vector2
			_last_path_plan_blocked_point_valid = true


func _extract_vector2_path_points(points_variant: Variant) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if not (points_variant is Array):
		return out
	for point_variant in (points_variant as Array):
		out.append(point_variant as Vector2)
	return out


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
		_handle_slide_collisions_and_repath(owner.get_slide_collision_count())
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
	_handle_slide_collisions_and_repath(owner.get_slide_collision_count())
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


func _handle_slide_collisions_and_repath(slide_count: int) -> Dictionary:
	var none_result := {
		"collision_kind": "none",
		"forced_repath": false,
		"reason": "none",
		"collision_index": -1,
	}
	if slide_count <= 0:
		return none_result

	var first_door_index := -1
	for i in range(slide_count):
		var is_door_collision := false
		var collision: Variant = owner.get_slide_collision(i)
		if collision != null and collision.has_method("get_collider"):
			var collider := collision.call("get_collider") as Node
			if collider != null and collider.name == "DoorBody":
				var collider_parent := collider.get_parent()
				is_door_collision = collider_parent != null and collider_parent.has_method("command_open_enemy")
		if not is_door_collision:
			_repath_timer = 0.0
			_waypoints.clear()
			if _use_navmesh and _nav_agent != null:
				_nav_agent.target_position = owner.global_position
			_last_path_failed = true
			_last_path_failed_reason = "collision_blocked"
			_path_policy_blocked = false
			_last_policy_blocked_segment = -1
			_last_slide_collision_kind = "non_door"
			_last_slide_collision_forced_repath = true
			_last_slide_collision_reason = "collision_blocked"
			_last_slide_collision_index = i
			return {
				"collision_kind": "non_door",
				"forced_repath": true,
				"reason": "collision_blocked",
				"collision_index": i,
			}
		if first_door_index < 0:
			first_door_index = i

	if first_door_index < 0:
		return none_result

	var door_opened := false
	var door_system := _get_door_system()
	if door_system != null and door_system.has_method("try_enemy_open_nearest"):
		door_opened = bool(door_system.call("try_enemy_open_nearest", owner.global_position))
	if door_opened:
		_repath_timer = 0.0
		_path_policy_blocked = false
		_last_policy_blocked_segment = -1
	_last_slide_collision_kind = "door"
	_last_slide_collision_forced_repath = door_opened
	_last_slide_collision_reason = "door_opened" if door_opened else "none"
	_last_slide_collision_index = first_door_index
	return {
		"collision_kind": "door",
		"forced_repath": door_opened,
		"reason": "door_opened" if door_opened else "none",
		"collision_index": first_door_index,
	}


func _mark_path_failed(reason: String) -> void:
	_last_path_failed = true
	if _last_path_failed_reason == "":
		_last_path_failed_reason = reason


func _attempt_replan_with_policy(target_pos: Vector2) -> bool:
	if AIWatchdog:
		AIWatchdog.record_replan()
	return _plan_path_to(target_pos)


func _is_owner_in_shadow_without_flashlight() -> bool:
	# Shadow escape is only valid in ALERT/COMBAT.
	if owner:
		var state_name := String(owner.get_meta("awareness_state", "CALM"))
		if state_name != "ALERT" and state_name != "COMBAT":
			return false
	if nav_system == null or not nav_system.has_method("is_point_in_shadow"):
		return false
	if not bool(nav_system.call("is_point_in_shadow", owner.global_position)):
		return false
	if owner and owner.has_method("is_flashlight_active_for_navigation"):
		return not bool(owner.call("is_flashlight_active_for_navigation"))
	return true


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
	var plan_contract := _request_path_plan_contract(target_pos, true)
	var normalized_plan := _normalize_path_plan_contract(plan_contract, target_pos)
	if String(normalized_plan.get("status", PATH_PLAN_STATUS_UNREACHABLE_GEOMETRY)) != PATH_PLAN_STATUS_OK:
		return INF
	var path_points := _extract_vector2_path_points(normalized_plan.get("path_points", []))
	if path_points.is_empty():
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


func _update_stall_monitor(delta: float, target_pos: Vector2, has_target: bool) -> bool:
	if delta <= 0.0 or not has_target:
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
		"path_plan_status": _last_path_plan_status,
		"path_plan_reason": _last_path_plan_reason,
		"path_plan_blocked_point": _last_path_plan_blocked_point,
		"path_plan_blocked_point_valid": _last_path_plan_blocked_point_valid,
		"policy_blocked": _path_policy_blocked,
		"policy_blocked_segment": _last_policy_blocked_segment,
		"last_valid_path_node": _last_valid_path_node,
		"last_valid_path_node_valid": _last_valid_path_node_valid,
		"active_move_target": _active_move_target,
		"active_move_target_valid": _active_move_target_valid,
		"plan_id": _plan_id,
		"intent_target": _intent_target if _intent_target_valid else Vector2.ZERO,
		"plan_target": _plan_target if _plan_target_valid else Vector2.ZERO,
		"shadow_unreachable_fsm_state": _shadow_unreachable_fsm_state,
		"hard_stall": _hard_stall,
		"stall_consecutive_windows": _stall_consecutive_windows,
		"stall_speed_avg": _last_stall_speed_avg,
		"stall_path_progress": _last_stall_path_progress,
		"shadow_scan_active": _shadow_scan_active,
		"shadow_scan_target": _shadow_scan_target,
		"shadow_scan_boundary_point": _shadow_scan_boundary_point,
		"shadow_scan_boundary_valid": _shadow_scan_boundary_valid,
		"collision_kind": _last_slide_collision_kind,
		"collision_forced_repath": _last_slide_collision_forced_repath,
		"collision_reason": _last_slide_collision_reason,
		"collision_index": _last_slide_collision_index,
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


func _pursuit_cfg_float(key: String, fallback: float) -> float:
	if GameConfig and GameConfig.ai_balance.has("pursuit"):
		var section := GameConfig.ai_balance["pursuit"] as Dictionary
		return float(section.get(key, fallback))
	return fallback
