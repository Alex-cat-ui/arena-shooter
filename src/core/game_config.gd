## game_config.gd
## Singleton holding all game configuration.
## CANON: UI changes ONLY GameConfig. Gameplay reads ONLY GameConfig.
## CANON: Runtime changes during PLAYING/PAUSED are forbidden (v1).
extends Node

## Direction rendering mode per CANON
enum DirectionRenderMode {
	ROTATE_SPRITE  # Sprite rotates to aim direction
}

## ============================================================================
## SECTION: Core
## ============================================================================
@export_group("Core")

## Size of one tile in pixels. All sizes/speeds use tile units.
@export var tile_size: int = 32

## Maximum alive enemies at any time
@export_range(1, 256) var max_alive_enemies: int = 64

## How player direction is rendered
@export var direction_render_mode: DirectionRenderMode = DirectionRenderMode.ROTATE_SPRITE

## Pixel-perfect rotation (nearest filtering)
@export var pixel_perfect_rotation: bool = true

## God mode - player takes no damage
@export var god_mode: bool = false

## ============================================================================
## SECTION: Spawn
## ============================================================================
@export_group("Spawn")

## Delay before gameplay starts (seconds)
@export_range(0.0, 10.0) var start_delay_sec: float = 1.5

## ============================================================================
## SECTION: Combat
## ============================================================================
@export_group("Combat")

## Player starting HP
@export_range(1, 1000) var player_max_hp: int = 100

## Global i-frame duration for contact damage (seconds)
@export_range(0.1, 5.0) var contact_iframes_sec: float = 0.7

## Contact damage emitted when a shotgun shot-level hit reaches the player.
## Set to 0 only when explicitly disabling contact damage for diagnostics.
@export_range(0, 50) var shotgun_hit_contact_damage: int = 1

## ============================================================================
## SECTION: Audio
## ============================================================================
@export_group("Audio")

## Music volume (0.0-1.0)
@export_range(0.0, 1.0) var music_volume: float = 0.7

## SFX volume (0.0-1.0)
@export_range(0.0, 1.0) var sfx_volume: float = 0.7

## Music fade-in duration (seconds)
@export_range(0.0, 5.0) var music_fade_in_sec: float = 0.5

## Music fade-out duration (seconds)
@export_range(0.0, 5.0) var music_fade_out_sec: float = 0.7

## ============================================================================
## SECTION: Physics
## ============================================================================
@export_group("Physics")

## Player movement speed in tiles per second
@export_range(1.0, 50.0) var player_speed_tiles: float = 10.0

## ============================================================================
## SECTION: Weapons (Phase 3)
## ============================================================================
@export_group("Weapons")

## Canonical weapon stats - source of truth for AbilitySystem
const DEFAULT_WEAPON_STATS := {
	"pistol": {
		"damage": 10,
		"rpm": 180,
		"speed_tiles": 12.0,
		"projectile_type": "bullet",
		"pellets": 1,
	},
	"shotgun": {
		"damage": 6,
		"rpm": 50.0,
		"cooldown_sec": 1.2,
		"speed_tiles": 40.0,
		"projectile_type": "pellet",
		"pellets": 16,
		"cone_deg": 8.0,
		"shot_damage_total": 25.0,
	},
}
var weapon_stats: Dictionary = DEFAULT_WEAPON_STATS.duplicate(true)

## ============================================================================
## SECTION: AI / Combat Balance (Data-Driven)
## ============================================================================
@export_group("AI Combat Balance")

const DEFAULT_ENEMY_STATS := {
	"zombie": {"hp": 100, "damage": 10, "speed": 2.0},
	"fast": {"hp": 100, "damage": 7, "speed": 4.0},
	"tank": {"hp": 100, "damage": 15, "speed": 1.5},
	"swarm": {"hp": 100, "damage": 5, "speed": 3.0},
}

const DEFAULT_PROJECTILE_TTL := {
	"bullet": 2.0,
	"pellet": 2.0,
	"plasma": 2.0,
	"rocket": 3.0,
	"piercing_bullet": 2.0,
}

const DEFAULT_AI_BALANCE := {
		"enemy_vision": {
			"fov_deg": 120.0,
			"max_distance_px": 600.0,
			"fire_attack_range_max_px": 600.0,
			"fire_spawn_offset_px": 20.0,
			"fire_ray_range_px": 2000.0,
		},
	"pursuit": {
		"attack_range_max_px": 600.0,
		"attack_range_pref_min_px": 500.0,
		"last_seen_reached_px": 20.0,
		"return_target_reached_px": 20.0,
		"search_min_sec": 5.0,
		"search_max_sec": 9.0,
		"search_sweep_rad": 0.9,
		"search_sweep_speed": 2.4,
		"path_repath_interval_sec": 0.35,
		"turn_speed_rad": 6.0,
		"accel_time_sec": 1.0 / 3.0,
		"decel_time_sec": 1.0 / 3.0,
			"retreat_distance_px": 140.0,
			"waypoint_reached_px": 12.0,
			"shadow_search_probe_count": 3,
			"shadow_search_probe_ring_radius_px": 64.0,
			"shadow_search_coverage_threshold": 0.8,
			"shadow_search_total_budget_sec": 12.0,
			"combat_dark_search_node_sample_radius_px": 64.0,
			"combat_dark_search_boundary_radius_px": 96.0,
			"combat_dark_search_node_dwell_sec": 1.25,
			"combat_dark_search_node_uncovered_bonus": 1000.0,
			"combat_dark_search_node_tactical_priority_weight": 80.0,
			"repath_recovery_blocked_point_bucket_px": 24.0,
			"repath_recovery_blocked_point_repeat_threshold": 2.0,
			"repath_recovery_intent_target_match_radius_px": 28.0,
			"avoidance_radius_px": 12.8,
			"avoidance_max_speed_px_per_sec": 80.0,
		},
	"utility": {
		"decision_interval_sec": 0.25,
		"min_action_hold_sec": 0.6,
		"hold_range_min_px": 390.0,
		"hold_range_max_px": 610.0,
		"retreat_hp_ratio": 0.25,
		"investigate_max_last_seen_age": 3.5,
		"slot_reposition_threshold_px": 40.0,
		"intent_target_delta_px": 8.0,
		"mode_min_hold_sec": 0.8,
	},
	"nav_cost": {
		"shadow_weight_cautious": 80.0,
		"shadow_weight_aggressive": 0.0,
		"shadow_sample_step_px": 16.0,
		"safe_route_max_len_factor": 1.35,
	},
		"alert": {
			"suspicious_ttl_sec": 18.0,
			"alert_ttl_sec": 24.0,
			"combat_ttl_sec": 30.0,
			"visibility_decay_sec": 6.0,
		},
	"fairness": {
		"reaction_warmup_min_sec": 0.15,
		"reaction_warmup_max_sec": 0.30,
		"comm_delay_min_sec": 0.30,
		"comm_delay_max_sec": 0.80,
	},
	"squad": {
		"rebuild_interval_sec": 0.35,
		"slot_reservation_ttl_sec": 1.1,
		"pressure_radius_px": 380.0,
		"hold_radius_px": 520.0,
		"flank_radius_px": 640.0,
		"pressure_slot_count": 6,
		"hold_slot_count": 8,
		"flank_slot_count": 8,
		"invalid_path_score_penalty": 100000.0,
		"flank_max_path_px": 900.0,
		"flank_max_time_sec": 3.5,
		"flank_walk_speed_assumed_px_per_sec": 150.0,
		"flashlight_scanner_cap": 2,
	},
	"runtime_budget": {
		"frame_budget_ms": 1.2,
		"enemy_ai_quota": 6,
		"squad_rebuild_quota": 1,
		"nav_tasks_quota": 2,
	},
		"patrol": {
			"point_reached_px": 14.0,
			"speed_scale": 0.82,
			"route_points_min": 3,
			"route_points_max": 6,
			"route_rebuild_min_sec": 7.0,
			"route_rebuild_max_sec": 12.0,
			"pause_min_sec": 0.25,
			"pause_max_sec": 0.90,
			"look_chance": 0.45,
			"look_min_sec": 0.35,
			"look_max_sec": 0.85,
			"look_sweep_rad": 0.62,
			"look_sweep_speed": 2.6,
			"route_dedup_min_dist_px": 42.0,
			"cross_room_patrol_chance": 0.20,
			"cross_room_patrol_penetration": 0.25,
		},
	"spawner": {
		"enemy_type": "zombie",
		"edge_padding_px": 24.0,
		"safe_soft_padding_px": 8.0,
		"min_safe_rect_size_px": 6.0,
		"min_enemy_spacing_px": 100.0,
		"sample_attempts_per_enemy": 140,
		"grid_search_step_px": 22.0,
		"room_quota_by_size": {"LARGE": 3, "MEDIUM": 2, "SMALL": 1},
	},
}

## Enemy base stats by type (used by Enemy.initialize).
var enemy_stats: Dictionary = DEFAULT_ENEMY_STATS.duplicate(true)

## Projectile TTL (seconds) by projectile type (used by Projectile).
var projectile_ttl: Dictionary = DEFAULT_PROJECTILE_TTL.duplicate(true)

## Central AI/combat tuning values consumed by enemy + tactical systems.
var ai_balance: Dictionary = DEFAULT_AI_BALANCE.duplicate(true)
## Fire profile mode: production|debug_test|auto.
const DEFAULT_AI_FIRE_PROFILE_MODE := "auto"
var ai_fire_profile_mode: String = DEFAULT_AI_FIRE_PROFILE_MODE
## Fire profile timings used by enemy first-shot telegraph.
const DEFAULT_AI_FIRE_PROFILES := {
	"production": {
		"telegraph_min_sec": 0.10,
		"telegraph_max_sec": 0.18,
	},
	"debug_test": {
		"telegraph_min_sec": 0.35,
		"telegraph_max_sec": 0.60,
	},
}
var ai_fire_profiles: Dictionary = DEFAULT_AI_FIRE_PROFILES.duplicate(true)

## Blood evidence gameplay tuning (Phase 14)
@export var blood_evidence_ttl_sec: float = 90.0
@export var blood_evidence_detection_radius_px: float = 150.0

## ============================================================================
## SECTION: Stealth Canon (Phase 0)
## ============================================================================

@export_group("Stealth")

@export var stealth_enabled: bool = true

## Canon stealth timing and behavior toggles.
const DEFAULT_STEALTH_CANON := {
	"confirm_time_to_engage": 5.0,
	"confirm_decay_rate": 1.25,
	"confirm_grace_window": 0.50,
	"suspicious_enter": 0.25,
	"alert_enter": 0.55,
	"suspicion_decay_rate": 0.55,
	"suspicion_gain_partial": 0.24,
	"suspicion_gain_silhouette": 0.18,
	"suspicion_gain_flashlight_glimpse": 0.30,
	"minimum_hold_alert_sec": 5.0,
	"shadow_is_binary": true,
	"flashlight_works_in_alert": true,
	"flashlight_works_in_combat": true,
	"flashlight_works_in_lockdown": true,
}
var stealth_canon := DEFAULT_STEALTH_CANON.duplicate(true)

## Zone system tuning for escalation and reinforcement.
const DEFAULT_ZONE_SYSTEM := {
	"elevated_min_hold_sec": 16.0,
	"lockdown_min_hold_sec": 24.0,
	"elevated_to_calm_no_events_sec": 12.0,
	"lockdown_to_elevated_no_events_sec": 18.0,
	"confirmed_contacts_lockdown_threshold": 3,
	"confirmed_contacts_window_sec": 8.0,
	"calls_per_enemy_per_window": 2,
	"call_window_sec": 20.0,
	"global_call_cooldown_sec": 3.0,
	"call_dedup_ttl_sec": 1.5,
	"zone_profiles": {
		"CALM": {
			"alert_sweep_budget_scale": 0.85,
			"role_weights_profiled": {"PRESSURE": 0.30, "HOLD": 0.60, "FLANK": 0.10},
			"reinforcement_cooldown_scale": 1.25,
			"flashlight_active_cap": 1,
			"zone_refill_scale": 0.0,
		},
		"ELEVATED": {
			"alert_sweep_budget_scale": 1.10,
			"role_weights_profiled": {"PRESSURE": 0.45, "HOLD": 0.40, "FLANK": 0.15},
			"reinforcement_cooldown_scale": 0.90,
			"flashlight_active_cap": 2,
			"zone_refill_scale": 0.35,
		},
		"LOCKDOWN": {
			"alert_sweep_budget_scale": 1.45,
			"role_weights_profiled": {"PRESSURE": 0.60, "HOLD": 0.25, "FLANK": 0.15},
			"reinforcement_cooldown_scale": 0.65,
			"flashlight_active_cap": 4,
			"zone_refill_scale": 1.00,
		},
	},
	"lockdown_spread_delay_elevated_sec": 2.0,
	"lockdown_spread_delay_far_sec": 5.0,
	"max_reinforcement_waves_per_zone": 1,
	"max_reinforcement_enemies_per_zone": 2,
	"lockdown_max_reinforcement_waves_per_zone": 3,
	"lockdown_max_reinforcement_enemies_per_zone": 6,
	"lockdown_combat_no_contact_window_sec": 45.0,
	"lockdown_hold_to_pressure_ratio": 0.75,
	"friendly_fire": false,
}
var zone_system := DEFAULT_ZONE_SYSTEM.duplicate(true)

const DEFAULT_NON_LAYOUT_SCALARS := {
	"tile_size": 32,
	"max_alive_enemies": 64,
	"direction_render_mode": DirectionRenderMode.ROTATE_SPRITE,
	"pixel_perfect_rotation": true,
	"god_mode": false,
	"start_delay_sec": 1.5,
	"player_max_hp": 100,
	"contact_iframes_sec": 0.7,
	"shotgun_hit_contact_damage": 1,
	"music_volume": 0.7,
	"sfx_volume": 0.7,
	"music_fade_in_sec": 0.5,
	"music_fade_out_sec": 0.7,
	"player_speed_tiles": 10.0,
	"ai_fire_profile_mode": DEFAULT_AI_FIRE_PROFILE_MODE,
	"stealth_enabled": true,
	"footprints_enabled": true,
	"footprint_step_distance_px": 40.0,
	"footprint_rear_offset_px": 12.0,
	"footprint_separation_px": 7.0,
	"footprint_scale": 0.65,
	"footprint_alpha": 0.35,
	"footprint_rotation_jitter_deg": 1.0,
	"footprint_lifetime_sec": 20.0,
	"footprint_velocity_threshold": 35.0,
	"footprint_max_count": 4000,
	"footprint_bloody_steps": 8,
	"footprint_black_steps": 4,
	"footprint_blood_detect_radius": 25.0,
	"footprint_rotation_offset_deg": 90.0,
	"boots_blood_max_prints": 8,
	"shadow_player_radius_mult": 1.2,
	"shadow_player_alpha": 0.25,
	"shadow_enemy_radius_mult": 1.1,
	"shadow_enemy_alpha": 0.18,
	"highlight_player_radius_offset": 2.0,
	"highlight_player_thickness": 2.0,
	"highlight_player_alpha": 0.5,
	"hit_flash_duration": 0.06,
	"kill_pop_scale": 1.2,
	"kill_pop_duration": 0.1,
	"kill_edge_pulse_alpha": 0.15,
	"damage_arc_duration": 0.12,
	"blood_max_decals": 500,
	"blood_darken_rate": 0.01,
	"blood_desaturate_rate": 0.005,
	"blood_evidence_ttl_sec": 90.0,
	"blood_evidence_detection_radius_px": 150.0,
	"vignette_alpha": 0.3,
	"floor_overlay_alpha": 0.15,
	"atmosphere_particle_alpha_min": 0.05,
	"atmosphere_particle_alpha_max": 0.15,
	"atmosphere_particle_lifetime_min": 3.0,
	"atmosphere_particle_lifetime_max": 6.0,
	"debug_overlay_visible": false,
	"kpi_ai_ms_avg_max": 1.20,
	"kpi_ai_ms_p95_max": 2.50,
	"kpi_replans_per_enemy_per_sec_max": 1.80,
	"kpi_detour_candidates_per_replan_max": 24.0,
	"kpi_hard_stalls_per_min_max": 1.0,
	"kpi_alert_combat_bad_patrol_count": 0,
	"kpi_shadow_pocket_min_area_px2": 3072.0,
	"kpi_shadow_escape_max_len_px": 960.0,
	"kpi_alt_route_max_factor": 1.50,
	"kpi_shadow_scan_points_min": 3,
	"kpi_replay_position_tolerance_px": 6.0,
	"kpi_replay_drift_budget_percent": 2.0,
	"kpi_replay_discrete_warmup_sec": 0.50,
}

## ============================================================================
## SECTION: Visual Polish (Patch 0.2 Phase 2)
## ============================================================================
@export_group("Visual Polish")

## ---------- Footprints ----------
@export var footprints_enabled: bool = true
@export_range(5.0, 100.0) var footprint_step_distance_px: float = 40.0
@export_range(0.0, 40.0) var footprint_rear_offset_px: float = 12.0
@export_range(0.0, 20.0) var footprint_separation_px: float = 7.0
@export_range(0.1, 3.0) var footprint_scale: float = 0.65
@export_range(0.0, 1.0) var footprint_alpha: float = 0.35
@export_range(0.0, 15.0) var footprint_rotation_jitter_deg: float = 1.0
@export_range(1.0, 120.0) var footprint_lifetime_sec: float = 20.0
@export_range(0.0, 200.0) var footprint_velocity_threshold: float = 35.0
@export_range(10, 4000) var footprint_max_count: int = 4000
@export_range(1, 30) var footprint_bloody_steps: int = 8
@export_range(1, 30) var footprint_black_steps: int = 4
@export_range(5.0, 100.0) var footprint_blood_detect_radius: float = 25.0
@export_range(-180.0, 180.0) var footprint_rotation_offset_deg: float = 90.0
@export_range(1, 30) var boots_blood_max_prints: int = 8

## ---------- Shadows ----------
@export_range(0.5, 3.0) var shadow_player_radius_mult: float = 1.2
@export_range(0.0, 1.0) var shadow_player_alpha: float = 0.25
@export_range(0.5, 3.0) var shadow_enemy_radius_mult: float = 1.1
@export_range(0.0, 1.0) var shadow_enemy_alpha: float = 0.18
@export_range(0.0, 10.0) var highlight_player_radius_offset: float = 2.0
@export_range(0.5, 6.0) var highlight_player_thickness: float = 2.0
@export_range(0.0, 1.0) var highlight_player_alpha: float = 0.5

## ---------- Combat Feedback ----------
@export_range(0.01, 0.5) var hit_flash_duration: float = 0.06
@export_range(1.0, 2.0) var kill_pop_scale: float = 1.2
@export_range(0.01, 1.0) var kill_pop_duration: float = 0.1
@export_range(0.0, 1.0) var kill_edge_pulse_alpha: float = 0.15
@export_range(0.01, 1.0) var damage_arc_duration: float = 0.12

## ---------- Blood & Corpse Lifecycle ----------
@export_range(50, 2000) var blood_max_decals: int = 500
@export_range(0.0, 0.1) var blood_darken_rate: float = 0.01
@export_range(0.0, 0.1) var blood_desaturate_rate: float = 0.005

## ---------- Atmosphere ----------
@export_range(0.0, 1.0) var vignette_alpha: float = 0.3
@export_range(0.0, 0.5) var floor_overlay_alpha: float = 0.15
@export_range(0.0, 0.3) var atmosphere_particle_alpha_min: float = 0.05
@export_range(0.0, 0.5) var atmosphere_particle_alpha_max: float = 0.15
@export_range(1.0, 15.0) var atmosphere_particle_lifetime_min: float = 3.0
@export_range(1.0, 15.0) var atmosphere_particle_lifetime_max: float = 6.0

## ---------- Debug ----------
@export var debug_overlay_visible: bool = false

## ============================================================================
## SECTION: Procedural Layout
## ============================================================================
@export_group("Procedural Layout")

@export var procedural_layout_enabled: bool = true
## Runtime level generation always uses ProceduralLayoutV2.

@export var layout_seed: int = 1337

@export_range(2, 20) var rooms_count_min: int = 9
@export_range(2, 20) var rooms_count_max: int = 15

@export_range(4.0, 64.0) var wall_thickness: float = 16.0

@export_range(40.0, 320.0) var door_opening_uniform: float = 75.0
@export_range(40.0, 300.0) var door_opening_min: float = 75.0
@export_range(40.0, 400.0) var door_opening_max: float = 75.0
@export_range(0.0, 100.0) var door_from_corner_min: float = 56.0
@export_range(1, 5) var max_doors_per_room: int = 3

## ---------- Door Animation (non-physics, 2-state) ----------
@export_range(1.0, 179.0) var door_open_angle_deg: float = 90.0
@export_range(0.01, 2.0) var door_open_duration_sec: float = 0.16
@export_range(0.01, 2.0) var door_close_duration_sec: float = 0.16
@export_range(0.0, 2.0) var door_close_clear_confirm_sec: float = 0.45
@export var door_hinge_notch_enabled: bool = true
@export_range(2.0, 64.0) var door_hinge_notch_depth_px: float = 16.0
@export_range(0.2, 1.5) var door_hinge_notch_span_ratio: float = 0.7
@export_range(0, 3) var extra_loops_max: int = 1

@export_range(0, 5) var corridor_count_min: int = 1
@export_range(0, 5) var corridor_count_max: int = 3
@export_range(40.0, 200.0) var corridor_w_min: float = 128.0
@export_range(40.0, 300.0) var corridor_w_max: float = 128.0
@export_range(100.0, 600.0) var corridor_len_min: float = 220.0
@export_range(0.0, 1.0) var corridor_area_cap: float = 0.25
@export_range(0, 3) var corridor_bends_max: int = 1

@export_range(60.0, 800.0) var room_min_w: float = 150.0
@export_range(60.0, 800.0) var room_min_h: float = 140.0
@export_range(100.0, 1200.0) var room_max_w: float = 350.0
@export_range(100.0, 1200.0) var room_max_h: float = 280.0
@export_range(0.2, 5.0) var room_aspect_min: float = 0.65
@export_range(0.2, 5.0) var room_aspect_max: float = 1.75

@export_range(0, 5) var big_rooms_target: int = 2
@export_range(100.0, 800.0) var big_room_min_w: float = 240.0
@export_range(100.0, 800.0) var big_room_min_h: float = 190.0

@export_range(0.0, 1.0) var l_room_chance: float = 0.35
@export_range(40.0, 400.0) var l_leg_min: float = 160.0
@export_range(0.0, 1.0) var l_cut_max_frac: float = 0.40
@export_range(0.0, 100.0) var inner_padding: float = 32.0

## ---------- Composition (Hotline) ----------
@export_range(0.3, 1.0) var cross_split_max_frac: float = 0.72
@export_range(0.0, 0.3) var void_area_min_frac: float = 0.08
@export_range(0, 5) var narrow_room_max: int = 1
@export_range(2.0, 50.0) var corridor_max_aspect: float = 12.0
@export var composition_enabled: bool = true

@export var layout_debug_text: bool = true

## ============================================================================
## SECTION: QA KPI Gates (Phase 19)
## ============================================================================
@export_group("QA KPI Gates")
@export var kpi_ai_ms_avg_max: float = 1.20
@export var kpi_ai_ms_p95_max: float = 2.50
@export var kpi_replans_per_enemy_per_sec_max: float = 1.80
@export var kpi_detour_candidates_per_replan_max: float = 24.0
@export var kpi_hard_stalls_per_min_max: float = 1.0
@export var kpi_alert_combat_bad_patrol_count: int = 0
@export var kpi_shadow_pocket_min_area_px2: float = 3072.0
@export var kpi_shadow_escape_max_len_px: float = 960.0
@export var kpi_alt_route_max_factor: float = 1.50
@export var kpi_shadow_scan_points_min: int = 3
@export var kpi_replay_position_tolerance_px: float = 6.0
@export var kpi_replay_drift_budget_percent: float = 2.0
@export var kpi_replay_discrete_warmup_sec: float = 0.50

## ============================================================================
## METHODS
## ============================================================================

func _apply_non_layout_scalar_defaults() -> void:
	for key_variant in DEFAULT_NON_LAYOUT_SCALARS.keys():
		var key := String(key_variant)
		set(key, DEFAULT_NON_LAYOUT_SCALARS[key])

## Reset all values to defaults
func reset_to_defaults() -> void:
	# Non-layout scalar defaults.
	_apply_non_layout_scalar_defaults()

	# Weapons
	weapon_stats = DEFAULT_WEAPON_STATS.duplicate(true)

	# AI/combat balance
	enemy_stats = DEFAULT_ENEMY_STATS.duplicate(true)
	projectile_ttl = DEFAULT_PROJECTILE_TTL.duplicate(true)
	ai_balance = DEFAULT_AI_BALANCE.duplicate(true)
	ai_fire_profile_mode = DEFAULT_AI_FIRE_PROFILE_MODE
	ai_fire_profiles = DEFAULT_AI_FIRE_PROFILES.duplicate(true)
	stealth_canon = DEFAULT_STEALTH_CANON.duplicate(true)
	zone_system = DEFAULT_ZONE_SYSTEM.duplicate(true)

	# Procedural Layout
	procedural_layout_enabled = true
	layout_seed = 1337
	rooms_count_min = 9
	rooms_count_max = 15
	wall_thickness = 16.0
	door_opening_uniform = 75.0
	door_opening_min = 75.0
	door_opening_max = 75.0
	door_from_corner_min = 56.0
	max_doors_per_room = 3
	door_open_angle_deg = 90.0
	door_open_duration_sec = 0.16
	door_close_duration_sec = 0.16
	door_close_clear_confirm_sec = 0.45
	door_hinge_notch_enabled = true
	door_hinge_notch_depth_px = 16.0
	door_hinge_notch_span_ratio = 0.7
	extra_loops_max = 1
	corridor_count_min = 1
	corridor_count_max = 3
	corridor_w_min = 128.0
	corridor_w_max = 128.0
	corridor_len_min = 220.0
	corridor_bends_max = 1
	corridor_area_cap = 0.25
	room_min_w = 150.0
	room_min_h = 140.0
	room_max_w = 350.0
	room_max_h = 280.0
	room_aspect_min = 0.65
	room_aspect_max = 1.75
	big_rooms_target = 2
	big_room_min_w = 240.0
	big_room_min_h = 190.0
	l_room_chance = 0.35
	l_leg_min = 160.0
	l_cut_max_frac = 0.40
	inner_padding = 32.0
	cross_split_max_frac = 0.72
	void_area_min_frac = 0.08
	narrow_room_max = 1
	corridor_max_aspect = 12.0
	composition_enabled = true
	layout_debug_text = true

## Create a snapshot of current config (for validation/comparison)
func get_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for key_variant in DEFAULT_NON_LAYOUT_SCALARS.keys():
		var key := String(key_variant)
		snapshot[key] = get(key)
	snapshot["weapon_stats"] = weapon_stats.duplicate(true)
	snapshot["enemy_stats"] = enemy_stats.duplicate(true)
	snapshot["projectile_ttl"] = projectile_ttl.duplicate(true)
	snapshot["ai_balance"] = ai_balance.duplicate(true)
	snapshot["ai_fire_profiles"] = ai_fire_profiles.duplicate(true)
	snapshot["stealth_canon"] = stealth_canon.duplicate(true)
	snapshot["zone_system"] = zone_system.duplicate(true)
	return snapshot
