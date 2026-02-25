## enemy_detection_runtime.gd
## Phase 7 owner for detection/awareness domain.
class_name EnemyDetectionRuntime
extends RefCounted

const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")

const FLASHLIGHT_NEAR_THRESHOLD_PX := 400.0
const SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_CHANCE := 0.30
const SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_BUCKET_COUNT := 10
const SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_ACTIVE_BUCKETS := 3
const INTENT_STABILITY_LOCK_SEC := 0.45
const INTENT_STABILITY_SUSPICION_MIN := 0.05

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


func tick_reaction_warmup(delta: float, raw_los: bool) -> bool:
	var awareness_state := _current_awareness_state()
	var clamped_delta := maxf(delta, 0.0)
	var had_visual_los_last_frame := bool(get_state_value("_had_visual_los_last_frame", false))
	if (not had_visual_los_last_frame) and raw_los and awareness_state == ENEMY_ALERT_LEVELS_SCRIPT.CALM:
		var fairness_cfg := {}
		if GameConfig and GameConfig.ai_balance.has("fairness"):
			fairness_cfg = GameConfig.ai_balance["fairness"] as Dictionary
		var cfg_min := float(fairness_cfg.get("reaction_warmup_min_sec", 0.15))
		var cfg_max := float(fairness_cfg.get("reaction_warmup_max_sec", 0.30))
		var warmup_min := minf(cfg_min, cfg_max)
		var warmup_max := maxf(cfg_min, cfg_max)
		var rng := _ensure_perception_rng_initialized()
		set_state_value("_reaction_warmup_timer", rng.randf_range(warmup_min, warmup_max))
	var warmup_left := float(get_state_value("_reaction_warmup_timer", 0.0))
	if warmup_left > 0.0:
		warmup_left = maxf(0.0, warmup_left - clamped_delta)
		set_state_value("_reaction_warmup_timer", warmup_left)
		set_state_value("_had_visual_los_last_frame", raw_los)
		if warmup_left > 0.0:
			return false
	set_state_value("_had_visual_los_last_frame", raw_los)
	return raw_los


func compute_flashlight_active(awareness_state: int) -> bool:
	var state_is_calm := awareness_state == ENEMY_ALERT_LEVELS_SCRIPT.CALM
	var state_is_suspicious := awareness_state == ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS
	var state_is_alert := awareness_state == ENEMY_ALERT_LEVELS_SCRIPT.ALERT
	var state_is_combat := awareness_state == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT or _owner_is_combat_latched()
	var raw_active: bool = (state_is_alert and _owner_flashlight_policy_active_in_alert()) \
		or (state_is_alert and bool(get_state_value("_investigate_target_in_shadow", false))) \
		or (state_is_suspicious and bool(get_state_value("_shadow_scan_active", false)) and _owner_flashlight_policy_active_in_alert() and _suspicious_shadow_scan_flashlight_gate_passes()) \
		or bool(get_state_value("_shadow_linger_flashlight", false)) \
		or (state_is_combat and _owner_flashlight_policy_active_in_combat()) \
		or (_owner_is_zone_lockdown() and _owner_flashlight_policy_active_in_lockdown()) \
		or (state_is_calm and _owner_flashlight_policy_active_in_calm())
	return raw_active and bool(get_state_value("_flashlight_scanner_allowed", true))


func resolve_known_target_context(player_valid: bool, player_pos: Vector2, player_visible: bool) -> Dictionary:
	var has_last_seen := float(get_state_value("_last_seen_age", INF)) < INF
	if player_valid and player_visible:
		return {
			"known_target_pos": player_pos,
			"target_is_last_seen": false,
			"has_known_target": true,
		}
	if _owner_is_combat_awareness_active():
		var combat_search_target_pos := get_state_value("_combat_search_target_pos", Vector2.ZERO) as Vector2
		if combat_search_target_pos != Vector2.ZERO:
			return {
				"known_target_pos": combat_search_target_pos,
				"target_is_last_seen": false,
				"has_known_target": true,
			}
		if player_valid:
			return {
				"known_target_pos": player_pos,
				"target_is_last_seen": false,
				"has_known_target": true,
			}
		return {
			"known_target_pos": Vector2.ZERO,
			"target_is_last_seen": false,
			"has_known_target": false,
		}
	if has_last_seen:
		return {
			"known_target_pos": get_state_value("_last_seen_pos", Vector2.ZERO) as Vector2,
			"target_is_last_seen": true,
			"has_known_target": true,
		}
	return {
		"known_target_pos": Vector2.ZERO,
		"target_is_last_seen": false,
		"has_known_target": false,
	}


func build_utility_context(player_valid: bool, player_visible: bool, assignment: Dictionary, target_context: Dictionary) -> Dictionary:
	var owner_pos := _owner_global_position()
	var slot_pos := assignment.get("slot_position", Vector2.ZERO) as Vector2
	var hp_ratio := float(get_state_value("hp", 0)) / float(maxi(int(get_state_value("max_hp", 1)), 1))
	var last_seen_age := float(get_state_value("_last_seen_age", INF))
	var last_seen_pos := get_state_value("_last_seen_pos", Vector2.ZERO) as Vector2
	var investigate_anchor := get_state_value("_investigate_anchor", Vector2.ZERO) as Vector2
	var has_last_seen := last_seen_age < INF
	var known_target_pos := target_context.get("known_target_pos", Vector2.ZERO) as Vector2
	var target_is_last_seen := bool(target_context.get("target_is_last_seen", false))
	var has_known_target := bool(target_context.get("has_known_target", false))
	var has_investigate_anchor := bool(get_state_value("_investigate_anchor_valid", false))
	var target_context_exists := has_known_target or has_last_seen or has_investigate_anchor
	var combat_lock_for_context := _owner_is_combat_lock_active()
	var dist_to_known_target := INF
	if has_known_target:
		dist_to_known_target = owner_pos.distance_to(known_target_pos)
	var base_role := int(assignment.get("role", _owner_squad_role_pressure()))
	var raw_role := _owner_resolve_runtime_combat_role(base_role)
	var effective_role := _owner_effective_squad_role_for_context(raw_role)
	var assignment_path_ok := bool(assignment.get("path_ok", false))
	var assignment_slot_role := int(assignment.get("slot_role", base_role))
	var slot_path_status := String(assignment.get("path_status", "ok" if assignment_path_ok else "unreachable_geometry"))
	var slot_path_eta_sec := float(assignment.get("slot_path_eta_sec", INF))
	var flank_slot_contract_ok := _owner_assignment_supports_flank_role(assignment)
	var effective_alert_level := _owner_resolve_effective_alert_level_for_utility()
	var shadow_scan_target := Vector2.ZERO
	var shadow_scan_source := "none"
	var has_shadow_scan_target := false
	var shadow_scan_target_in_shadow := false
	if effective_alert_level >= ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS:
		if has_known_target and _is_finite_nonzero_vector2(known_target_pos):
			shadow_scan_target = known_target_pos
			shadow_scan_source = "known_target_pos"
		elif has_last_seen and _is_finite_nonzero_vector2(last_seen_pos):
			shadow_scan_target = last_seen_pos
			shadow_scan_source = "last_seen"
		elif has_investigate_anchor and _is_finite_nonzero_vector2(investigate_anchor):
			shadow_scan_target = investigate_anchor
			shadow_scan_source = "investigate_anchor"
		has_shadow_scan_target = shadow_scan_source != "none"
		if has_shadow_scan_target:
			var nav_system := _current_nav_system()
			if nav_system and nav_system.has_method("is_point_in_shadow"):
				shadow_scan_target_in_shadow = bool(nav_system.call("is_point_in_shadow", shadow_scan_target))
	var shadow_scan_suppressed := false
	var combat_search_runtime: Variant = get_state_value("_combat_search_runtime", null)
	if combat_search_runtime != null and combat_search_runtime.has_method("compute_shadow_scan_suppressed_for_context"):
		shadow_scan_suppressed = bool(
			combat_search_runtime.call(
				"compute_shadow_scan_suppressed_for_context",
				has_known_target,
				known_target_pos,
				has_shadow_scan_target,
				shadow_scan_target
			)
		)
	else:
		set_state_value("_combat_search_shadow_scan_suppressed_last_tick", false)
	if shadow_scan_suppressed:
		shadow_scan_target_in_shadow = false
	var home_pos := owner_pos
	var nav := _current_nav_system()
	var home_room_id := int(get_state_value("home_room_id", -1))
	if nav and nav.has_method("get_room_center") and home_room_id >= 0:
		var nav_home := nav.get_room_center(home_room_id) as Vector2
		if nav_home != Vector2.ZERO:
			home_pos = nav_home
	return {
		"dist": dist_to_known_target,
		"los": player_visible,
		"alert_level": effective_alert_level,
		"combat_lock": combat_lock_for_context,
		"last_seen_age": last_seen_age if has_last_seen else INF,
		"last_seen_pos": last_seen_pos if has_last_seen else Vector2.ZERO,
		"has_last_seen": has_last_seen,
		"dist_to_last_seen": owner_pos.distance_to(last_seen_pos) if has_last_seen else INF,
		"investigate_anchor": investigate_anchor if has_investigate_anchor else Vector2.ZERO,
		"has_investigate_anchor": has_investigate_anchor,
		"dist_to_investigate_anchor": owner_pos.distance_to(investigate_anchor) if has_investigate_anchor else INF,
		"role": effective_role,
		"slot_role": assignment_slot_role,
		"slot_position": slot_pos,
		"dist_to_slot": owner_pos.distance_to(slot_pos) if slot_pos != Vector2.ZERO else INF,
		"hp_ratio": hp_ratio,
		"path_ok": assignment_path_ok,
		"slot_path_status": slot_path_status,
		"slot_path_eta_sec": slot_path_eta_sec,
		"flank_slot_contract_ok": flank_slot_contract_ok,
		"has_slot": bool(assignment.get("has_slot", false)),
		"player_pos": known_target_pos,
		"known_target_pos": known_target_pos,
		"target_is_last_seen": target_is_last_seen,
		"has_known_target": has_known_target,
		"target_context_exists": target_context_exists,
		"home_position": home_pos,
		"shadow_scan_target": shadow_scan_target,
		"has_shadow_scan_target": has_shadow_scan_target,
		"shadow_scan_target_in_shadow": shadow_scan_target_in_shadow,
		"shadow_scan_source": shadow_scan_source,
		"shadow_scan_completed": bool(get_state_value("_shadow_scan_completed", false)),
		"shadow_scan_completed_reason": String(get_state_value("_shadow_scan_completed_reason", "none")),
	}


func apply_runtime_intent_stability_policy(intent: Dictionary, context: Dictionary, suspicion_now: float, delta: float) -> Dictionary:
	var out := intent.duplicate(true)
	var intent_type := int(out.get("type", ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL))
	var has_los := bool(context.get("los", false))
	var active_suspicion := suspicion_now >= INTENT_STABILITY_SUSPICION_MIN
	var should_stabilize := has_los or active_suspicion
	var lock_timer := maxf(0.0, float(get_state_value("_intent_stability_lock_timer", 0.0)) - maxf(delta, 0.0))
	set_state_value("_intent_stability_lock_timer", lock_timer)
	var blocked_intent := (
		intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT
		or intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETREAT
	)
	if should_stabilize and blocked_intent and lock_timer > 0.0:
		var stable_type := int(get_state_value("_intent_stability_last_type", ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL))
		if (
			stable_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT
			or stable_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETREAT
		):
			stable_type = ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.HOLD_RANGE
			set_state_value("_intent_stability_last_type", stable_type)
		out["type"] = stable_type
		if not out.has("target") or (out.get("target", Vector2.ZERO) as Vector2) == Vector2.ZERO:
			out["target"] = context.get("known_target_pos", context.get("player_pos", _owner_global_position())) as Vector2
		return out

	if should_stabilize and blocked_intent:
		var dist := float(context.get("dist", INF))
		var hold_range_max := _owner_utility_cfg_float("hold_range_max_px", 610.0)
		intent_type = ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.HOLD_RANGE if dist <= hold_range_max else ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH
		out["type"] = intent_type
		out["target"] = context.get("known_target_pos", context.get("player_pos", _owner_global_position())) as Vector2

	if should_stabilize and (
		intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.HOLD_RANGE
		or intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH
		or intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.INVESTIGATE
	):
		set_state_value("_intent_stability_last_type", intent_type)
		set_state_value("_intent_stability_lock_timer", INTENT_STABILITY_LOCK_SEC)
	elif not should_stabilize and lock_timer <= 0.0:
		set_state_value("_intent_stability_last_type", intent_type)

	return out


func on_heard_shot(shot_room_id: int, shot_pos: Vector2) -> void:
	var awareness: Variant = _current_awareness()
	if awareness:
		_owner_apply_awareness_transitions(awareness.register_noise(), "heard_shot")
		_owner_override_alert_hold_from_travel_time(shot_pos, 3.0, 10.0)
	_set_investigate_anchor_from_event(shot_pos)
	_set_flashlight_activation_delay_for_event(shot_pos, 0.5, 1.2, 1.0, 1.8)
	var pursuit: Variant = get_state_value("_pursuit", null)
	if pursuit != null and pursuit.has_method("on_heard_shot"):
		pursuit.on_heard_shot(shot_room_id, shot_pos)


func apply_teammate_call(
	_source_enemy_id: int,
	_source_room_id: int,
	_call_id: int = -1,
	shot_pos: Vector2 = Vector2.ZERO
) -> bool:
	var awareness: Variant = _current_awareness()
	if awareness == null:
		return false
	var transitions: Array = awareness.register_teammate_call()
	if transitions.is_empty():
		return false
	_owner_apply_awareness_transitions(transitions, "teammate_call")
	if shot_pos != Vector2.ZERO:
		_set_investigate_anchor_from_event(shot_pos)
		_owner_override_alert_hold_from_travel_time(shot_pos, 3.0, 10.0)
		_set_flashlight_activation_delay_for_event(shot_pos, 0.3, 0.8, 1.0, 1.8)
	else:
		_owner_override_alert_hold_random(8.0, 15.0)
	return true


func apply_blood_evidence(evidence_pos: Vector2) -> bool:
	var awareness: Variant = _current_awareness()
	if awareness == null:
		return false
	if int(awareness.get_state()) != int(ENEMY_AWARENESS_SYSTEM_SCRIPT.State.CALM):
		return false
	set_state_value("_investigate_anchor", evidence_pos)
	set_state_value("_investigate_anchor_valid", true)
	set_state_value("_investigate_target_in_shadow", false)
	var transitions: Array[Dictionary] = awareness.register_blood_evidence()
	_owner_apply_awareness_transitions(transitions, "blood_evidence")
	return transitions.size() > 0


func _set_investigate_anchor_from_event(target_pos: Vector2) -> void:
	set_state_value("_investigate_anchor", target_pos)
	set_state_value("_investigate_anchor_valid", true)
	set_state_value("_investigate_target_in_shadow", false)
	var nav := _current_nav_system()
	if nav and nav.has_method("is_point_in_shadow"):
		set_state_value("_investigate_target_in_shadow", bool(nav.call("is_point_in_shadow", target_pos)))


func _set_flashlight_activation_delay_for_event(
	target_pos: Vector2,
	near_min_sec: float,
	near_max_sec: float,
	far_min_sec: float,
	far_max_sec: float
) -> void:
	var dist_to_target := _owner_global_position().distance_to(target_pos)
	if dist_to_target < FLASHLIGHT_NEAR_THRESHOLD_PX:
		set_state_value("_flashlight_activation_delay_timer", randf_range(near_min_sec, near_max_sec))
	else:
		set_state_value("_flashlight_activation_delay_timer", randf_range(far_min_sec, far_max_sec))


func _ensure_perception_rng_initialized() -> RandomNumberGenerator:
	var rng := get_state_value("_perception_rng", null) as RandomNumberGenerator
	if rng != null:
		return rng
	rng = RandomNumberGenerator.new()
	var perception_layout_seed: int = int(GameConfig.layout_seed) if GameConfig else 0
	var entity_id := int(get_state_value("entity_id", 0))
	rng.seed = (entity_id * 6364136223846793005) ^ perception_layout_seed
	set_state_value("_perception_rng", rng)
	return rng


func _current_awareness() -> Variant:
	return get_state_value("_awareness", null)


func _current_awareness_state() -> int:
	var awareness: Variant = _current_awareness()
	if awareness == null:
		return ENEMY_ALERT_LEVELS_SCRIPT.CALM
	if awareness.has_method("get_awareness_state"):
		return int(awareness.get_awareness_state())
	if awareness.has_method("get_state"):
		return int(awareness.get_state())
	return ENEMY_ALERT_LEVELS_SCRIPT.CALM


func _current_nav_system() -> Node:
	return get_state_value("nav_system", null) as Node


func _owner_global_position() -> Vector2:
	var owner_2d := _owner as Node2D
	if owner_2d == null:
		return Vector2.ZERO
	return owner_2d.global_position


func _owner_runtime_ref(runtime_key: String) -> Variant:
	if _owner == null or not _owner.has_method("get_runtime_helper_refs"):
		return null
	var refs := _owner.call("get_runtime_helper_refs") as Dictionary
	return refs.get(runtime_key, null)


func _owner_is_combat_awareness_active() -> bool:
	if _owner == null:
		return false
	if _owner.has_method("_is_combat_awareness_active"):
		return bool(_owner.call("_is_combat_awareness_active"))
	var awareness: Variant = _current_awareness()
	if awareness == null or not awareness.has_method("get_state_name"):
		return false
	return String(awareness.get_state_name()) == "COMBAT"


func _owner_is_combat_latched() -> bool:
	if _owner != null and _owner.has_method("_is_combat_latched"):
		return bool(_owner.call("_is_combat_latched"))
	return bool(get_state_value("_combat_latched", false))


func _owner_is_zone_lockdown() -> bool:
	var alert_latch_runtime: Node = _owner_runtime_ref("alert_latch_runtime") as Node
	if alert_latch_runtime != null and alert_latch_runtime.has_method("is_zone_lockdown"):
		return bool(alert_latch_runtime.call("is_zone_lockdown"))
	return false


func _owner_flashlight_policy_active_in_alert() -> bool:
	if _owner != null and _owner.has_method("_flashlight_policy_active_in_alert"):
		return bool(_owner.call("_flashlight_policy_active_in_alert"))
	return float(get_state_value("_flashlight_activation_delay_timer", 0.0)) <= 0.0


func _owner_flashlight_policy_active_in_calm() -> bool:
	if _owner != null and _owner.has_method("_flashlight_policy_active_in_calm"):
		return bool(_owner.call("_flashlight_policy_active_in_calm"))
	return bool(get_state_value("_shadow_check_flashlight_override", false))


func _owner_flashlight_policy_active_in_combat() -> bool:
	if _owner != null and _owner.has_method("_flashlight_policy_active_in_combat"):
		return bool(_owner.call("_flashlight_policy_active_in_combat"))
	return true


func _owner_flashlight_policy_active_in_lockdown() -> bool:
	if _owner != null and _owner.has_method("_flashlight_policy_active_in_lockdown"):
		return bool(_owner.call("_flashlight_policy_active_in_lockdown"))
	return true


func _owner_resolve_runtime_combat_role(base_role: int) -> int:
	if _owner != null and _owner.has_method("_resolve_runtime_combat_role"):
		return int(_owner.call("_resolve_runtime_combat_role", base_role))
	return base_role


func _owner_effective_squad_role_for_context(role: int) -> int:
	if _owner != null and _owner.has_method("_effective_squad_role_for_context"):
		return int(_owner.call("_effective_squad_role_for_context", role))
	return role


func _owner_assignment_supports_flank_role(assignment: Dictionary) -> bool:
	var combat_role_runtime: Node = _owner_runtime_ref("combat_role_runtime") as Node
	if combat_role_runtime != null and combat_role_runtime.has_method("assignment_supports_flank_role"):
		return bool(combat_role_runtime.call("assignment_supports_flank_role", assignment))
	return false


func _owner_resolve_effective_alert_level_for_utility() -> int:
	if _owner != null and _owner.has_method("_resolve_effective_alert_level_for_utility"):
		return int(_owner.call("_resolve_effective_alert_level_for_utility"))
	return ENEMY_ALERT_LEVELS_SCRIPT.CALM


func _owner_is_combat_lock_active() -> bool:
	if _owner != null and _owner.has_method("_is_combat_lock_active"):
		return bool(_owner.call("_is_combat_lock_active"))
	return false


func _owner_utility_cfg_float(key: String, fallback: float) -> float:
	if _owner != null and _owner.has_method("_utility_cfg_float"):
		return float(_owner.call("_utility_cfg_float", key, fallback))
	if GameConfig and GameConfig.ai_balance.has("utility"):
		var section := GameConfig.ai_balance["utility"] as Dictionary
		return float(section.get(key, fallback))
	return fallback


func _owner_apply_awareness_transitions(transitions: Array, source: String) -> void:
	if _owner != null and _owner.has_method("_apply_awareness_transitions"):
		_owner.call("_apply_awareness_transitions", transitions, source)


func _owner_override_alert_hold_from_travel_time(target_pos: Vector2, extra_min_sec: float, extra_max_sec: float) -> void:
	if _owner != null and _owner.has_method("_override_alert_hold_from_travel_time"):
		_owner.call("_override_alert_hold_from_travel_time", target_pos, extra_min_sec, extra_max_sec)


func _owner_override_alert_hold_random(min_sec: float, max_sec: float) -> void:
	if _owner != null and _owner.has_method("_override_alert_hold_random"):
		_owner.call("_override_alert_hold_random", min_sec, max_sec)


func _owner_squad_role_pressure() -> int:
	return int(get_state_value("SQUAD_ROLE_PRESSURE", 0))


func _is_finite_nonzero_vector2(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y) and value != Vector2.ZERO


func _suspicious_shadow_scan_flashlight_bucket() -> int:
	var bucket: int = int(
		posmod(
			int(get_state_value("entity_id", 0)) + int(get_state_value("_debug_tick_id", 0)),
			SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_BUCKET_COUNT
		)
	)
	return bucket


func _suspicious_shadow_scan_flashlight_gate_passes() -> bool:
	var expected_active_buckets := int(
		round(
			SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_CHANCE * float(SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_BUCKET_COUNT)
		)
	)
	if expected_active_buckets != SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_ACTIVE_BUCKETS:
		push_warning("Suspicious shadow-scan flashlight bucket constants are inconsistent")
	return _suspicious_shadow_scan_flashlight_bucket() < SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_ACTIVE_BUCKETS
