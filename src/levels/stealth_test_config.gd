## stealth_test_config.gd
## Centralized tuning knobs for isolated stealth vertical-slice tests.
class_name StealthTestConfig
extends RefCounted

const VALUES := {
	"suspicion_gain_rate_calm": 0.35,
	"suspicion_gain_rate_alert": 1.2,
	"suspicion_decay_rate": 0.45,
	"suspicious_threshold": 0.25,
	"alert_threshold": 0.55,
	"combat_threshold": 1.0,
	"los_grace_time": 0.3,
	"los_grace_decay_mult": 0.25,
	"look_los_grace_sec": 0.25,
	"intent_policy_lock_sec": 0.45,
	"active_suspicion_min": 0.05,
	"facing_log_delta_rad": 0.35,
	"flashlight_angle_deg": 55.0,
	"flashlight_distance_px": 1000.0,
	"flashlight_bonus": 2.5,
	"flashlight_active_in_alert": true,
	"flashlight_active_in_combat": true,
	"flashlight_bonus_in_alert": true,
	"flashlight_bonus_in_combat": true,
	"shadow_multiplier_default": 0.35,
	"combat_last_seen_grace_sec": 1.5,
	"combat_room_migration_hysteresis_sec": 0.2,
	"combat_search_radius_px": 160,
	"combat_repath_interval_no_los_sec": 0.2,
	"combat_stuck_window_sec": 1.0,
	"combat_stuck_min_progress_px": 8,
	"combat_detour_offsets": [120, 180, 240],
	"recognition_delay_min_sec": 0.15,
	"recognition_delay_max_sec": 0.30,
	"peripheral_suspicion_rate": 0.05,
	"peripheral_range_px": 150.0,
	"peripheral_fov_cutoff_deg": 120.0,
	"back_cone_angle_deg": 60.0,
	"back_cone_range_px": 80.0,
	"stealth_kill_duration_sec": 4.0,
	"suppression_fire_count": 3,
	"suppression_window_sec": 1.5,
	"suppression_range_px": 100.0,
	"cross_room_patrol_chance": 0.20,
	"cross_room_patrol_penetration": 0.25,
	"door_stack_pause_min_sec": 0.5,
	"door_stack_pause_max_sec": 1.0,
	"body_marker_ttl_min_sec": 60.0,
	"body_marker_ttl_max_sec": 120.0,
	"body_marker_radius_px": 80.0,
}


static func values() -> Dictionary:
	return VALUES.duplicate(true)


static func suspicion_profile() -> Dictionary:
	return {
		"suspicion_gain_rate_calm": float(VALUES.get("suspicion_gain_rate_calm", 0.35)),
		"suspicion_gain_rate_alert": float(VALUES.get("suspicion_gain_rate_alert", 1.2)),
		"suspicion_decay_rate": float(VALUES.get("suspicion_decay_rate", 0.45)),
		"suspicious_threshold": float(VALUES.get("suspicious_threshold", 0.25)),
		"alert_threshold": float(VALUES.get("alert_threshold", 0.55)),
		"combat_threshold": float(VALUES.get("combat_threshold", 1.0)),
		"los_grace_time": float(VALUES.get("los_grace_time", 0.3)),
		"los_grace_decay_mult": float(VALUES.get("los_grace_decay_mult", 0.25)),
		"look_los_grace_sec": float(VALUES.get("look_los_grace_sec", 0.25)),
		"intent_policy_lock_sec": float(VALUES.get("intent_policy_lock_sec", 0.45)),
		"active_suspicion_min": float(VALUES.get("active_suspicion_min", 0.05)),
		"facing_log_delta_rad": float(VALUES.get("facing_log_delta_rad", 0.35)),
		"flashlight_bonus": float(VALUES.get("flashlight_bonus", 2.5)),
	}
