## enemy_debug_snapshot_runtime.gd
## Phase 8 owner for debug-snapshot domain.
class_name EnemyDebugSnapshotRuntime
extends RefCounted

const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

const TEST_FACING_LOG_DELTA_RAD := 0.35
const WEAPON_SHOTGUN := "shotgun"

var _owner: Node = null


func _init(owner: Node = null) -> void:
	_owner = owner


func bind(owner: Node) -> void:
	_owner = owner


func get_owner() -> Node:
	return _owner


func has_owner() -> bool:
	return _owner != null


func get_state_value(key: String, default_value: Variant = null) -> Variant:
	if _owner == null:
		return default_value
	var value: Variant = _owner.get(key)
	return default_value if value == null else value


func set_state_value(key: String, value: Variant) -> void:
	if _owner == null:
		return
	_owner.set(key, value)


func set_state_patch(values: Dictionary) -> void:
	if _owner == null:
		return
	for key_variant in values.keys():
		var key := String(key_variant)
		_owner.set(key, values[key_variant])


func set_debug_logging(enabled: bool) -> void:
	set_state_value("_stealth_test_debug_logging_enabled", enabled)
	if not enabled:
		set_state_value("_debug_last_logged_intent_type", -1)
		set_state_value("_debug_last_logged_target_facing", Vector2.ZERO)


func refresh_transition_guard_tick() -> void:
	var tick_id := Engine.get_physics_frames()
	if int(get_state_value("_debug_last_transition_tick_id", -1)) == tick_id:
		return
	set_state_value("_debug_last_transition_tick_id", tick_id)
	set_state_value("_debug_transition_count_this_tick", 0)
	set_state_value("_debug_last_transition_blocked_by", "")


func emit_stealth_debug_trace_if_needed(context: Dictionary, suspicion_now: float) -> void:
	if not bool(get_state_value("_stealth_test_debug_logging_enabled", false)):
		return
	var intent_type := int(get_state_value("_debug_last_intent_type", -1))
	var target_facing := get_state_value("_debug_last_target_facing_dir", Vector2.ZERO) as Vector2
	var last_logged_target_facing := get_state_value("_debug_last_logged_target_facing", Vector2.ZERO) as Vector2
	var facing_delta := 0.0
	if last_logged_target_facing.length_squared() > 0.0001 and target_facing.length_squared() > 0.0001:
		facing_delta = absf(wrapf(target_facing.angle() - last_logged_target_facing.angle(), -PI, PI))
	var intent_changed := intent_type != int(get_state_value("_debug_last_logged_intent_type", -1))
	var facing_changed := facing_delta >= TEST_FACING_LOG_DELTA_RAD
	if not intent_changed and not facing_changed:
		return
	print("[EnemyStealthTrace] id=%d state=%s room_alert=%s intent=%d los=%s susp=%.3f vis=%.3f dist=%.1f last_seen_age=%.2f facing_delta=%.3f" % [
		int(get_state_value("entity_id", 0)),
		String(get_state_value("_debug_last_state_name", "CALM")),
		ENEMY_ALERT_LEVELS_SCRIPT.level_name(int(get_state_value("_debug_last_room_alert_level", ENEMY_ALERT_LEVELS_SCRIPT.CALM))),
		intent_type,
		str(bool(context.get("los", false))),
		suspicion_now,
		float(get_state_value("_debug_last_visibility_factor", 0.0)),
		float(context.get("dist", INF)),
		float(get_state_value("_debug_last_last_seen_age", INF)),
		facing_delta,
	])
	set_state_value("_debug_last_logged_intent_type", intent_type)
	set_state_value("_debug_last_logged_target_facing", target_facing)


func record_runtime_tick_debug_state(payload: Dictionary) -> void:
	if _owner == null:
		return
	var fire_contact := payload.get("fire_contact", {}) as Dictionary
	var intent := payload.get("intent", {}) as Dictionary
	var awareness: Variant = get_state_value("_awareness", null)
	var state_name := String(get_state_value("_debug_last_state_name", "CALM"))
	if awareness != null and awareness.has_method("get_state_name"):
		state_name = String(awareness.get_state_name())
	set_state_patch({
		"_debug_last_has_los": bool(payload.get("behavior_visible", false)),
		"_debug_last_visibility_factor": float(payload.get("visibility_factor", 0.0)),
		"_debug_last_distance_factor": float(payload.get("distance_factor", 0.0)),
		"_debug_last_shadow_mul": float(payload.get("shadow_mul", 1.0)),
		"_debug_last_distance_to_player": float(payload.get("distance_to_player", INF)),
		"_debug_last_flashlight_active": bool(payload.get("flashlight_active", false)),
		"_debug_last_flashlight_hit": bool(payload.get("flashlight_hit", false)),
		"_debug_last_flashlight_in_cone": bool(payload.get("flashlight_in_cone", false)),
		"_debug_last_flashlight_los_to_player": bool(payload.get("raw_player_visible", false)),
		"_debug_last_valid_contact_for_fire": bool(payload.get("valid_firing_solution", false)),
		"_debug_last_fire_los": bool(fire_contact.get("los", false)),
		"_debug_last_fire_inside_fov": bool(fire_contact.get("inside_fov", false)),
		"_debug_last_fire_in_range": bool(fire_contact.get("in_fire_range", false)),
		"_debug_last_fire_not_occluded_by_world": bool(fire_contact.get("not_occluded_by_world", false)),
		"_debug_last_fire_shadow_rule_passed": bool(fire_contact.get("shadow_rule_passed", false)),
		"_debug_last_fire_weapon_ready": bool(fire_contact.get("weapon_ready", false)),
		"_debug_last_fire_friendly_block": bool(fire_contact.get("friendly_block", false)),
		"_debug_last_flashlight_bonus_raw": float(payload.get("flashlight_bonus_raw", 1.0)),
		"_debug_last_flashlight_inactive_reason": String(payload.get("flashlight_inactive_reason", "state_blocked")),
		"_debug_last_effective_visibility_pre_clamp": float(payload.get("effective_visibility_pre_clamp", 0.0)),
		"_debug_last_effective_visibility_post_clamp": float(payload.get("effective_visibility_post_clamp", 0.0)),
		"_debug_last_intent_type": int(intent.get("type", -1)),
		"_debug_last_intent_target": intent.get("target", Vector2.ZERO) as Vector2,
		"_debug_last_last_seen_age": float(payload.get("last_seen_age", INF)),
		"_debug_last_room_alert_level": int(payload.get("room_alert_effective", ENEMY_ALERT_LEVELS_SCRIPT.CALM)),
		"_debug_last_facing_used_for_flashlight": payload.get("flashlight_facing_used", Vector2.RIGHT) as Vector2,
		"_debug_last_facing_after_move": payload.get("facing_after_move", Vector2.RIGHT) as Vector2,
		"_debug_last_flashlight_calc_tick_id": int(payload.get("debug_tick_id", -1)),
		"_debug_last_state_name": state_name,
		"_debug_last_facing_dir": payload.get("facing_after_move", Vector2.RIGHT) as Vector2,
		"_debug_last_target_facing_dir": payload.get("target_facing_after_move", Vector2.RIGHT) as Vector2,
	})
	_owner.set_meta("flashlight_active", bool(payload.get("flashlight_active", false)))


func export_snapshot() -> Dictionary:
	refresh_transition_guard_tick()
	var awareness: Variant = get_state_value("_awareness", null)
	var state_enum := ENEMY_ALERT_LEVELS_SCRIPT.CALM
	var suspicion := 0.0
	var confirmed := false
	var state_name := String(get_state_value("_debug_last_state_name", "CALM"))
	if awareness != null:
		if awareness.has_method("get_awareness_state"):
			state_enum = int(awareness.get_awareness_state())
		elif awareness.has_method("get_state"):
			state_enum = int(awareness.get_state())
		if awareness.has_method("get_state_name"):
			state_name = String(awareness.get_state_name())
		if awareness.has_method("get_suspicion"):
			suspicion = float(awareness.get_suspicion())
		if awareness.has_method("has_confirmed_visual"):
			confirmed = bool(awareness.has_confirmed_visual())

	var combat_search_nodes_total := 0
	var combat_search_nodes_covered := 0
	var combat_search_room_coverage_raw := 0.0
	var current_room_id := int(get_state_value("_combat_search_current_room_id", -1))
	if current_room_id >= 0:
		var room_nodes_map := get_state_value("_combat_search_room_nodes", {}) as Dictionary
		var room_nodes_variant: Variant = room_nodes_map.get(current_room_id, [])
		var room_nodes := room_nodes_variant as Array
		var visited_by_room := get_state_value("_combat_search_room_node_visited", {}) as Dictionary
		var visited := visited_by_room.get(current_room_id, {}) as Dictionary
		for node_variant in room_nodes:
			var node := node_variant as Dictionary
			var node_key := String(node.get("key", ""))
			var weight := float(node.get("coverage_weight", 0.0))
			if node_key == "" or not is_finite(weight) or weight <= 0.0:
				continue
			combat_search_nodes_total += 1
			if bool(visited.get(node_key, false)):
				combat_search_nodes_covered += 1
		var room_coverage_map := get_state_value("_combat_search_room_coverage", {}) as Dictionary
		combat_search_room_coverage_raw = clampf(
			float(room_coverage_map.get(current_room_id, 0.0)),
			0.0,
			1.0
		)

	var weapon_name := WEAPON_SHOTGUN
	var fire_profile_mode := "production"
	if _owner != null and _owner.has_method("get_runtime_helper_refs"):
		var helper_refs := _owner.call("get_runtime_helper_refs") as Dictionary
		var fire_control_runtime: Node = helper_refs.get("fire_control_runtime", null) as Node
		if fire_control_runtime != null and fire_control_runtime.has_method("resolve_ai_fire_profile_mode"):
			fire_profile_mode = String(fire_control_runtime.call("resolve_ai_fire_profile_mode"))
	var fire_phase_name := "unknown"
	if _owner != null and _owner.has_method("_combat_fire_phase_name"):
		fire_phase_name = String(_owner.call("_combat_fire_phase_name", int(get_state_value("_combat_fire_phase", 0))))

	var suspicion_ring_progress := suspicion
	var suspicion_ring: Variant = get_state_value("_suspicion_ring", null)
	if suspicion_ring != null and suspicion_ring.has_method("get_progress"):
		suspicion_ring_progress = float(suspicion_ring.call("get_progress"))
	var first_shot_max_pause_sec := _owner_float_constant("COMBAT_FIRST_SHOT_MAX_PAUSE_SEC", 2.5)

	return {
		"state": state_enum,
		"state_name": state_name,
		"suspicion": suspicion,
		"has_los": bool(get_state_value("_debug_last_has_los", false)),
		"los_to_player": bool(get_state_value("_debug_last_flashlight_los_to_player", false)),
		"distance_to_player": float(get_state_value("_debug_last_distance_to_player", INF)),
		"distance_factor": float(get_state_value("_debug_last_distance_factor", 0.0)),
		"shadow_mul": float(get_state_value("_debug_last_shadow_mul", 1.0)),
		"visibility_factor": float(get_state_value("_debug_last_visibility_factor", 0.0)),
		"flashlight_active": bool(get_state_value("_debug_last_flashlight_active", false)),
		"in_cone": bool(get_state_value("_debug_last_flashlight_in_cone", false)),
		"flashlight_hit": bool(get_state_value("_debug_last_flashlight_hit", false)),
		"flashlight_bonus_raw": float(get_state_value("_debug_last_flashlight_bonus_raw", 1.0)),
		"flashlight_inactive_reason": String(get_state_value("_debug_last_flashlight_inactive_reason", "state_blocked")),
		"effective_visibility_pre_clamp": float(get_state_value("_debug_last_effective_visibility_pre_clamp", 0.0)),
		"effective_visibility_post_clamp": float(get_state_value("_debug_last_effective_visibility_post_clamp", 0.0)),
		"confirmed": confirmed,
		"intent_type": int(get_state_value("_debug_last_intent_type", -1)),
		"intent_target": get_state_value("_debug_last_intent_target", Vector2.ZERO) as Vector2,
		"facing_dir": get_state_value("_debug_last_facing_dir", Vector2.RIGHT) as Vector2,
		"facing_used_for_flashlight": get_state_value("_debug_last_facing_used_for_flashlight", Vector2.RIGHT) as Vector2,
		"facing_after_move": get_state_value("_debug_last_facing_after_move", Vector2.RIGHT) as Vector2,
		"target_facing_dir": get_state_value("_debug_last_target_facing_dir", Vector2.RIGHT) as Vector2,
		"flashlight_calc_tick_id": int(get_state_value("_debug_last_flashlight_calc_tick_id", -1)),
		"last_seen_age": float(get_state_value("_debug_last_last_seen_age", INF)),
		"room_alert_level": int(get_state_value("_debug_last_room_alert_level", ENEMY_ALERT_LEVELS_SCRIPT.CALM)),
		"room_alert_effective": int(get_state_value("_debug_last_room_alert_effective", ENEMY_ALERT_LEVELS_SCRIPT.CALM)),
		"room_alert_transient": int(get_state_value("_debug_last_room_alert_transient", ENEMY_ALERT_LEVELS_SCRIPT.CALM)),
		"room_latch_count": int(get_state_value("_debug_last_room_latch_count", 0)),
		"latched": bool(get_state_value("_debug_last_latched", false)),
		"transition_from": String(get_state_value("_debug_last_transition_from", "")),
		"transition_to": String(get_state_value("_debug_last_transition_to", "")),
		"transition_reason": String(get_state_value("_debug_last_transition_reason", "")),
		"transition_source": String(get_state_value("_debug_last_transition_source", "")),
		"transition_blocked_by": String(get_state_value("_debug_last_transition_blocked_by", "")),
		"transition_tick_id": int(get_state_value("_debug_last_transition_tick_id", -1)),
		"transition_count_this_tick": int(get_state_value("_debug_transition_count_this_tick", 0)),
		"shotgun_fire_block_reason": String(get_state_value("_debug_last_shotgun_fire_block_reason", "no_combat_state")),
		"shotgun_fire_requested": bool(get_state_value("_debug_last_shotgun_fire_requested", false)),
		"shotgun_can_fire_contact": bool(get_state_value("_debug_last_shotgun_can_fire", false)),
		"shotgun_should_fire_now": bool(get_state_value("_debug_last_shotgun_should_fire_now", false)),
		"shotgun_fire_attempted": bool(get_state_value("_debug_last_shotgun_fire_attempted", false)),
		"shotgun_fire_success": bool(get_state_value("_debug_last_shotgun_fire_success", false)),
		"weapon_name": weapon_name,
		"shotgun_cooldown_left": float(get_state_value("_shot_cooldown", 0.0)),
		"fire_valid_contact_for_fire": bool(get_state_value("_debug_last_valid_contact_for_fire", false)),
		"fire_los": bool(get_state_value("_debug_last_fire_los", false)),
		"fire_inside_fov": bool(get_state_value("_debug_last_fire_inside_fov", false)),
		"fire_in_range": bool(get_state_value("_debug_last_fire_in_range", false)),
		"fire_not_occluded_by_world": bool(get_state_value("_debug_last_fire_not_occluded_by_world", false)),
		"fire_shadow_rule_passed": bool(get_state_value("_debug_last_fire_shadow_rule_passed", false)),
		"fire_weapon_ready": bool(get_state_value("_debug_last_fire_weapon_ready", false)),
		"fire_friendly_block": bool(get_state_value("_debug_last_fire_friendly_block", false)),
		"fire_profile_mode": fire_profile_mode,
		"shotgun_first_attack_delay_left": float(get_state_value("_combat_first_attack_delay_timer", 0.0)),
		"shotgun_first_attack_delay_armed": bool(get_state_value("_combat_first_shot_delay_armed", false)),
		"shotgun_first_attack_fired": bool(get_state_value("_combat_first_shot_fired", false)),
		"shotgun_first_attack_target_context_key": String(get_state_value("_combat_first_shot_target_context_key", "")),
		"shotgun_fire_phase": fire_phase_name,
		"shotgun_fire_reposition_left": float(get_state_value("_combat_fire_reposition_left", 0.0)),
		"shotgun_first_attack_pause_left_before_reset": maxf(0.0, first_shot_max_pause_sec - float(get_state_value("_combat_first_shot_pause_elapsed", 0.0))),
		"shotgun_first_attack_pause_elapsed": float(get_state_value("_combat_first_shot_pause_elapsed", 0.0)),
		"shotgun_telegraph_active": bool(get_state_value("_combat_telegraph_active", false)),
		"shotgun_telegraph_left": float(get_state_value("_combat_telegraph_timer", 0.0)),
		"shotgun_telegraph_pause_elapsed": float(get_state_value("_combat_telegraph_pause_elapsed", 0.0)),
		"shotgun_friendly_block_streak": int(get_state_value("_friendly_block_streak", 0)),
		"shotgun_friendly_block_reposition_cooldown_left": float(get_state_value("_friendly_block_reposition_cooldown_left", 0.0)),
		"shotgun_friendly_block_reposition_pending": bool(get_state_value("_friendly_block_force_reposition", false)),
		"combat_role_current": int(get_state_value("_combat_role_current", 0)),
		"combat_role_lock_left": float(get_state_value("_combat_role_lock_timer", 0.0)),
		"combat_role_reassign_reason": String(get_state_value("_combat_role_last_reassign_reason", "")),
		"combat_search_progress": float(get_state_value("_combat_search_progress", 0.0)),
		"combat_search_total_elapsed_sec": float(get_state_value("_combat_search_total_elapsed_sec", 0.0)),
		"combat_search_room_elapsed_sec": float(get_state_value("_combat_search_room_elapsed_sec", 0.0)),
		"combat_search_room_budget_sec": float(get_state_value("_combat_search_room_budget_sec", 0.0)),
		"combat_search_current_room_id": current_room_id,
		"combat_search_target_pos": get_state_value("_combat_search_target_pos", Vector2.ZERO) as Vector2,
		"combat_search_total_cap_hit": bool(get_state_value("_combat_search_total_cap_hit", false)),
		"combat_search_node_key": String(get_state_value("_combat_search_current_node_key", "")),
		"combat_search_node_kind": String(get_state_value("_combat_search_current_node_kind", "")),
		"combat_search_node_requires_shadow_scan": bool(get_state_value("_combat_search_current_node_requires_shadow_scan", false)),
		"combat_search_node_shadow_scan_done": bool(get_state_value("_combat_search_current_node_shadow_scan_done", false)),
		"combat_search_room_nodes_total": combat_search_nodes_total,
		"combat_search_room_nodes_covered": combat_search_nodes_covered,
		"combat_search_room_coverage_raw": combat_search_room_coverage_raw,
		"combat_search_shadow_scan_suppressed": bool(get_state_value("_combat_search_shadow_scan_suppressed_last_tick", false)),
		"combat_search_recovery_applied": bool(get_state_value("_combat_search_recovery_applied_last_tick", false)),
		"combat_search_recovery_reason": String(get_state_value("_combat_search_recovery_reason_last_tick", "none")),
		"combat_search_recovery_blocked_point": get_state_value("_combat_search_recovery_blocked_point_last", Vector2.ZERO) as Vector2,
		"combat_search_recovery_blocked_point_valid": bool(get_state_value("_combat_search_recovery_blocked_point_valid_last", false)),
		"combat_search_recovery_skipped_node_key": String(get_state_value("_combat_search_recovery_skipped_node_key_last", "")),
		"suspicion_ring_progress": suspicion_ring_progress,
		"target_is_last_seen": bool(get_state_value("_debug_last_target_is_last_seen", false)),
		"last_seen_grace_left": float(get_state_value("_last_seen_grace_timer", 0.0)),
	}


func _owner_float_constant(key: String, fallback: float) -> float:
	if _owner == null:
		return fallback
	var value: Variant = _owner.get(key)
	if value == null:
		return fallback
	if value is float or value is int:
		return float(value)
	return fallback
