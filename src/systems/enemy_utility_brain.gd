## enemy_utility_brain.gd
## Pure utility decision layer (no movement/physics calls).
class_name EnemyUtilityBrain
extends RefCounted

const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")
const ENEMY_SQUAD_SYSTEM_SCRIPT := preload("res://src/systems/enemy_squad_system.gd")

enum IntentType {
	PATROL,
	INVESTIGATE,
	SEARCH,
	MOVE_TO_SLOT,
	HOLD_RANGE,
	PUSH,
	RETREAT,
	RETURN_HOME,
	SHADOW_BOUNDARY_SCAN,
}

const DECISION_INTERVAL_SEC := 0.25
const MIN_ACTION_HOLD_SEC := 0.6
const HOLD_RANGE_MIN_PX := 390.0
const HOLD_RANGE_MAX_PX := 610.0
const RETREAT_HP_RATIO := 0.25
const INVESTIGATE_MAX_LAST_SEEN_AGE := 3.5
const INVESTIGATE_ARRIVE_PX := 24.0
const SEARCH_MAX_LAST_SEEN_AGE := 8.0

var _decision_timer: float = 0.0
var _action_hold_timer: float = 0.0
var _current_intent: Dictionary = {"type": IntentType.PATROL}


func reset() -> void:
	_decision_timer = 0.0
	_action_hold_timer = 0.0
	_current_intent = {"type": IntentType.PATROL}


func get_current_intent() -> Dictionary:
	return _current_intent.duplicate(true)


func update(delta: float, context: Dictionary) -> Dictionary:
	_decision_timer = maxf(0.0, _decision_timer - maxf(delta, 0.0))
	_action_hold_timer = maxf(0.0, _action_hold_timer - maxf(delta, 0.0))
	if _decision_timer > 0.0 and _action_hold_timer > 0.0:
		return get_current_intent()

	var next_intent := _choose_intent(context)
	var changed := _intent_changed(next_intent, _current_intent)
	if changed or _action_hold_timer <= 0.0:
		_current_intent = next_intent
		_action_hold_timer = _utility_cfg_float("min_action_hold_sec", MIN_ACTION_HOLD_SEC)

	_decision_timer = _utility_cfg_float("decision_interval_sec", DECISION_INTERVAL_SEC)
	return get_current_intent()


func _choose_intent(ctx: Dictionary) -> Dictionary:
	var dist := float(ctx.get("dist", INF))
	var has_los := bool(ctx.get("los", false))
	var alert_level := int(ctx.get("alert_level", ENEMY_ALERT_LEVELS_SCRIPT.CALM))
	var last_seen_age := float(ctx.get("last_seen_age", INF))
	var role := int(ctx.get("role", ENEMY_SQUAD_SYSTEM_SCRIPT.Role.PRESSURE))
	var hp_ratio := clampf(float(ctx.get("hp_ratio", 1.0)), 0.0, 1.0)
	var path_ok := bool(ctx.get("path_ok", false))
	var slot_pos := ctx.get("slot_position", Vector2.ZERO) as Vector2
	var has_slot := bool(ctx.get("has_slot", false))
	var combat_lock := bool(ctx.get("combat_lock", false))
	var known_target_pos := ctx.get("known_target_pos", ctx.get("player_pos", Vector2.ZERO)) as Vector2
	var last_seen_pos := ctx.get("last_seen_pos", Vector2.ZERO) as Vector2
	var target_is_last_seen := bool(ctx.get("target_is_last_seen", false))
	var has_last_seen := bool(ctx.get("has_last_seen", target_is_last_seen or last_seen_pos != Vector2.ZERO))
	var dist_to_last_seen := float(ctx.get("dist_to_last_seen", dist))
	var home_pos := ctx.get("home_position", Vector2.ZERO) as Vector2
	var investigate_anchor := ctx.get("investigate_anchor", Vector2.ZERO) as Vector2
	var has_investigate_anchor := bool(ctx.get("has_investigate_anchor", false))
	var dist_to_investigate_anchor := float(ctx.get("dist_to_investigate_anchor", INF))
	var shadow_scan_target := ctx.get("shadow_scan_target", Vector2.ZERO) as Vector2
	var has_shadow_scan_target := bool(ctx.get("has_shadow_scan_target", false))
	var shadow_scan_target_in_shadow := bool(ctx.get("shadow_scan_target_in_shadow", false))

	var retreat_hp_ratio := _utility_cfg_float("retreat_hp_ratio", RETREAT_HP_RATIO)
	var hold_range_min := _utility_cfg_float("hold_range_min_px", HOLD_RANGE_MIN_PX)
	var hold_range_max := _utility_cfg_float("hold_range_max_px", HOLD_RANGE_MAX_PX)
	var investigate_max_age := _utility_cfg_float("investigate_max_last_seen_age", INVESTIGATE_MAX_LAST_SEEN_AGE)
	var investigate_arrive_px := _utility_cfg_float("investigate_arrive_px", INVESTIGATE_ARRIVE_PX)
	var search_max_last_seen_age := _utility_cfg_float("search_max_last_seen_age", SEARCH_MAX_LAST_SEEN_AGE)
	var slot_reposition_threshold := _utility_cfg_float("slot_reposition_threshold_px", 40.0)
	var search_target := last_seen_pos if has_last_seen else home_pos
	var has_search_anchor := has_last_seen and last_seen_age <= search_max_last_seen_age

	if combat_lock and not has_los:
		return _combat_no_los_grace_intent(known_target_pos, last_seen_pos, home_pos)

	if hp_ratio <= retreat_hp_ratio and has_los and dist < hold_range_min:
		return {
			"type": IntentType.RETREAT,
			"target": known_target_pos,
		}

	if alert_level <= ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS and not has_los:
		if alert_level == ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS and has_shadow_scan_target and shadow_scan_target_in_shadow:
			return {
				"type": IntentType.SHADOW_BOUNDARY_SCAN,
				"target": shadow_scan_target,
			}
		var inv_target := investigate_anchor if has_investigate_anchor else last_seen_pos
		var inv_dist := dist_to_investigate_anchor if has_investigate_anchor else dist_to_last_seen
		var inv_valid := (has_investigate_anchor or has_last_seen) and last_seen_age <= investigate_max_age
		if inv_valid and inv_dist > investigate_arrive_px:
			return {
				"type": IntentType.INVESTIGATE,
				"target": inv_target,
			}
		if has_search_anchor:
			return {
				"type": IntentType.SEARCH,
				"target": search_target,
			}
		return {"type": IntentType.PATROL}

	if not has_los and alert_level >= ENEMY_ALERT_LEVELS_SCRIPT.ALERT:
		if has_last_seen and dist_to_last_seen > investigate_arrive_px:
			return {
				"type": IntentType.INVESTIGATE,
				"target": last_seen_pos,
			}
		if has_last_seen:
			return {
				"type": IntentType.SEARCH,
				"target": search_target,
			}
		if has_investigate_anchor and dist_to_investigate_anchor > investigate_arrive_px:
			return {
				"type": IntentType.INVESTIGATE,
				"target": investigate_anchor,
			}
		return {
			"type": IntentType.RETURN_HOME,
			"target": home_pos,
		}

	if has_los:
		if has_slot and path_ok and slot_pos != Vector2.ZERO:
			var dist_to_slot := float(ctx.get("dist_to_slot", INF))
			if dist_to_slot > slot_reposition_threshold:
				return {
					"type": IntentType.MOVE_TO_SLOT,
					"target": slot_pos,
				}

		if dist > hold_range_max:
			return {
				"type": IntentType.PUSH,
				"target": known_target_pos,
			}
		if dist < hold_range_min:
			return {
				"type": IntentType.RETREAT,
				"target": known_target_pos,
			}

		if role == ENEMY_SQUAD_SYSTEM_SCRIPT.Role.FLANK and has_slot and slot_pos != Vector2.ZERO:
			return {
				"type": IntentType.MOVE_TO_SLOT,
				"target": slot_pos,
			}
		return {
			"type": IntentType.HOLD_RANGE,
			"target": slot_pos if has_slot and slot_pos != Vector2.ZERO else known_target_pos,
		}

	return {
		"type": IntentType.RETURN_HOME,
		"target": home_pos,
	}


func _combat_no_los_grace_intent(known_target_pos: Vector2, _last_seen_pos: Vector2, home_pos: Vector2) -> Dictionary:
	var target := known_target_pos
	if target == Vector2.ZERO:
		target = home_pos
	return {
		"type": IntentType.PUSH,
		"target": target,
	}


func _intent_changed(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("type", -1)) != int(b.get("type", -1)):
		return true
	var at := a.get("target", Vector2.ZERO) as Vector2
	var bt := b.get("target", Vector2.ZERO) as Vector2
	return at.distance_to(bt) > _utility_cfg_float("intent_target_delta_px", 8.0)


func _utility_cfg_float(key: String, fallback: float) -> float:
	if GameConfig and GameConfig.ai_balance.has("utility"):
		var section := GameConfig.ai_balance["utility"] as Dictionary
		return float(section.get(key, fallback))
	return fallback
