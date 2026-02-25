## enemy_combat_role_runtime.gd
## Phase 5 owner for combat-role domain.
class_name EnemyCombatRoleRuntime
extends RefCounted

const SQUAD_ROLE_PRESSURE := 0
const SQUAD_ROLE_HOLD := 1
const SQUAD_ROLE_FLANK := 2
const COMBAT_ROLE_LOCK_SEC := 3.0
const COMBAT_ROLE_REASSIGN_LOST_LOS_SEC := 1.0
const COMBAT_ROLE_REASSIGN_STUCK_SEC := 1.2
const COMBAT_ROLE_REASSIGN_PATH_FAILED_COUNT := 3

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


func resolve_runtime_combat_role(base_role: int) -> int:
	if not _owner_is_combat_awareness_active():
		return base_role
	var current_role := int(get_state_value("_combat_role_current", SQUAD_ROLE_PRESSURE))
	var lock_timer := float(get_state_value("_combat_role_lock_timer", 0.0))
	return current_role if lock_timer > 0.0 else base_role


func reset_runtime() -> void:
	set_state_patch({
		"_combat_role_current": SQUAD_ROLE_PRESSURE,
		"_combat_role_lock_timer": 0.0,
		"_combat_role_lost_los_sec": 0.0,
		"_combat_role_stuck_sec": 0.0,
		"_combat_role_path_failed_streak": 0,
		"_combat_role_last_target_room": -1,
		"_combat_role_lost_los_trigger_latched": false,
		"_combat_role_stuck_trigger_latched": false,
		"_combat_role_path_failed_trigger_latched": false,
		"_combat_role_last_reassign_reason": "",
		"_combat_last_runtime_pos": _owner_global_position(),
	})


func update_runtime(
	delta: float,
	has_valid_contact: bool,
	movement_intent: bool,
	moved_distance: float,
	path_failed: bool,
	target_room_id: int,
	target_distance: float,
	assignment: Dictionary
) -> void:
	var base_role := int(assignment.get("role", SQUAD_ROLE_PRESSURE))
	if not _owner_is_combat_awareness_active():
		reset_runtime()
		set_state_value("_combat_role_current", base_role)
		return

	var clamped_delta := maxf(delta, 0.0)
	set_state_value("_combat_role_lock_timer", maxf(0.0, float(get_state_value("_combat_role_lock_timer", 0.0)) - clamped_delta))

	if has_valid_contact:
		set_state_value("_combat_role_lost_los_sec", 0.0)
		set_state_value("_combat_role_lost_los_trigger_latched", false)
	else:
		set_state_value(
			"_combat_role_lost_los_sec",
			float(get_state_value("_combat_role_lost_los_sec", 0.0)) + clamped_delta
		)

	if movement_intent:
		if moved_distance <= 2.0:
			set_state_value("_combat_role_stuck_sec", float(get_state_value("_combat_role_stuck_sec", 0.0)) + clamped_delta)
		else:
			set_state_value("_combat_role_stuck_sec", 0.0)
			set_state_value("_combat_role_stuck_trigger_latched", false)
	else:
		set_state_value("_combat_role_stuck_sec", 0.0)
		set_state_value("_combat_role_stuck_trigger_latched", false)

	if path_failed:
		set_state_value("_combat_role_path_failed_streak", int(get_state_value("_combat_role_path_failed_streak", 0)) + 1)
	else:
		set_state_value("_combat_role_path_failed_streak", 0)
		set_state_value("_combat_role_path_failed_trigger_latched", false)

	var trigger_reason := ""
	if float(get_state_value("_combat_role_lost_los_sec", 0.0)) > COMBAT_ROLE_REASSIGN_LOST_LOS_SEC and not bool(get_state_value("_combat_role_lost_los_trigger_latched", false)):
		trigger_reason = "lost_los"
		set_state_value("_combat_role_lost_los_trigger_latched", true)
	elif float(get_state_value("_combat_role_stuck_sec", 0.0)) > COMBAT_ROLE_REASSIGN_STUCK_SEC and not bool(get_state_value("_combat_role_stuck_trigger_latched", false)):
		trigger_reason = "stuck"
		set_state_value("_combat_role_stuck_trigger_latched", true)
	elif int(get_state_value("_combat_role_path_failed_streak", 0)) >= COMBAT_ROLE_REASSIGN_PATH_FAILED_COUNT and not bool(get_state_value("_combat_role_path_failed_trigger_latched", false)):
		trigger_reason = "path_failed"
		set_state_value("_combat_role_path_failed_trigger_latched", true)
	elif target_room_id >= 0 and int(get_state_value("_combat_role_last_target_room", -1)) >= 0 and target_room_id != int(get_state_value("_combat_role_last_target_room", -1)):
		trigger_reason = "target_room_changed"

	if target_room_id >= 0:
		set_state_value("_combat_role_last_target_room", target_room_id)

	if trigger_reason == "" and float(get_state_value("_combat_role_lock_timer", 0.0)) > 0.0:
		return

	var reason := trigger_reason if trigger_reason != "" else "lock_expired"
	reassign_combat_role(base_role, reason, has_valid_contact, target_distance, assignment)
	set_state_value("_combat_role_lock_timer", COMBAT_ROLE_LOCK_SEC)


func reassign_combat_role(
	base_role: int,
	reason: String,
	has_valid_contact: bool,
	target_distance: float,
	assignment: Dictionary
) -> void:
	var current_role := int(get_state_value("_combat_role_current", SQUAD_ROLE_PRESSURE))
	var new_role := base_role
	match reason:
		"lost_los":
			new_role = SQUAD_ROLE_FLANK if assignment_supports_flank_role(assignment) else SQUAD_ROLE_PRESSURE
		"stuck":
			new_role = SQUAD_ROLE_HOLD
		"path_failed":
			new_role = SQUAD_ROLE_HOLD if current_role != SQUAD_ROLE_HOLD else SQUAD_ROLE_FLANK
		"target_room_changed":
			new_role = SQUAD_ROLE_PRESSURE
		_:
			new_role = base_role

	var contextual_role := resolve_contextual_combat_role(new_role, has_valid_contact, target_distance, assignment)
	set_state_value("_combat_role_current", contextual_role)
	set_state_value("_combat_role_last_reassign_reason", reason)


func assignment_supports_flank_role(assignment: Dictionary) -> bool:
	var effective_role := int(assignment.get("role", SQUAD_ROLE_PRESSURE))
	var effective_slot_role := int(assignment.get("slot_role", effective_role))
	if effective_slot_role != SQUAD_ROLE_FLANK:
		return false
	if not bool(assignment.get("has_slot", false)):
		return false
	if not bool(assignment.get("path_ok", false)):
		return false
	var path_status := String(
		assignment.get("path_status", "ok" if bool(assignment.get("path_ok", false)) else "unreachable_geometry")
	)
	if path_status != "ok":
		return false
	var path_length := float(assignment.get("slot_path_length", INF))
	var eta_sec := float(assignment.get("slot_path_eta_sec", INF))
	var assumed_speed := _owner_squad_cfg_float("flank_walk_speed_assumed_px_per_sec", 150.0)
	if not is_finite(eta_sec):
		eta_sec = path_length / maxf(assumed_speed, 0.001)
	if path_length > _owner_squad_cfg_float("flank_max_path_px", 900.0):
		return false
	if eta_sec > _owner_squad_cfg_float("flank_max_time_sec", 3.5):
		return false
	return true


func resolve_contextual_combat_role(
	candidate_role: int,
	has_valid_contact: bool,
	target_distance: float,
	assignment: Dictionary
) -> int:
	var flank_available := assignment_supports_flank_role(assignment)
	var hold_range_min := _owner_utility_cfg_float("hold_range_min_px", 390.0)
	var hold_range_max := _owner_utility_cfg_float("hold_range_max_px", 610.0)
	if not has_valid_contact:
		return SQUAD_ROLE_FLANK if flank_available else SQUAD_ROLE_PRESSURE
	if is_finite(target_distance):
		if target_distance > hold_range_max:
			return SQUAD_ROLE_PRESSURE
		if target_distance < hold_range_min and not flank_available:
			return SQUAD_ROLE_HOLD
	if candidate_role == SQUAD_ROLE_FLANK and not flank_available:
		return SQUAD_ROLE_PRESSURE
	if flank_available and is_finite(target_distance):
		if target_distance >= hold_range_min and target_distance <= hold_range_max:
			return SQUAD_ROLE_FLANK
	return candidate_role


func _owner_global_position() -> Vector2:
	var owner_2d := _owner as Node2D
	if owner_2d == null:
		return Vector2.ZERO
	return owner_2d.global_position


func _owner_is_combat_awareness_active() -> bool:
	if _owner == null:
		return false
	if _owner.has_method("_is_combat_awareness_active"):
		return bool(_owner.call("_is_combat_awareness_active"))
	var awareness: Variant = get_state_value("_awareness", null)
	if awareness == null or not awareness.has_method("get_state_name"):
		return false
	return String(awareness.get_state_name()) == "COMBAT"


func _owner_utility_cfg_float(key: String, fallback: float) -> float:
	if _owner != null and _owner.has_method("_utility_cfg_float"):
		return float(_owner.call("_utility_cfg_float", key, fallback))
	if GameConfig and GameConfig.ai_balance.has("utility"):
		var section := GameConfig.ai_balance["utility"] as Dictionary
		return float(section.get(key, fallback))
	return fallback


func _owner_squad_cfg_float(key: String, fallback: float) -> float:
	if _owner != null and _owner.has_method("_squad_cfg_float"):
		return float(_owner.call("_squad_cfg_float", key, fallback))
	if GameConfig and GameConfig.ai_balance.has("squad"):
		var section := GameConfig.ai_balance["squad"] as Dictionary
		return float(section.get(key, fallback))
	return fallback
