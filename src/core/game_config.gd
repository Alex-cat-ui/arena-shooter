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

## Delay before first wave starts (seconds)
@export_range(0.0, 10.0) var start_delay_sec: float = 1.5

## Delay between waves (seconds)
@export_range(0.0, 10.0) var inter_wave_delay_sec: float = 1.0

## Base enemies per wave (WaveIndex=1)
@export_range(1, 100) var enemies_per_wave: int = 12

## Additional enemies per wave after first
@export_range(0, 20) var wave_size_growth: int = 3

## Time between spawn ticks (seconds)
@export_range(0.1, 5.0) var spawn_tick_sec: float = 0.6

## Enemies spawned per tick
@export_range(1, 20) var spawn_batch_size: int = 6

## Threshold for wave advance (0.0-1.0)
@export_range(0.0, 1.0) var wave_advance_threshold: float = 0.2

## Number of waves per level (Phase 0 addition for LEVEL_SETUP)
@export_range(1, 200) var waves_per_level: int = 3

## ============================================================================
## SECTION: Combat
## ============================================================================
@export_group("Combat")

## Player starting HP
@export_range(1, 1000) var player_max_hp: int = 100

## Global i-frame duration for contact damage (seconds)
@export_range(0.1, 5.0) var contact_iframes_sec: float = 0.7

## Boss contact damage i-frame duration (seconds)
@export_range(0.1, 10.0) var boss_contact_iframes_sec: float = 3.0

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
var weapon_stats: Dictionary = {
	"pistol": {
		"damage": 10,
		"rpm": 180,
		"speed_tiles": 12.0,
		"projectile_type": "bullet",
		"pellets": 1,
	},
	"auto": {
		"damage": 7,
		"rpm": 150,
		"speed_tiles": 14.0,
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
	"plasma": {
		"damage": 20,
		"rpm": 120,
		"speed_tiles": 9.0,
		"projectile_type": "plasma",
		"pellets": 1,
	},
	"rocket": {
		"damage": 40,
		"rpm": 30,
		"speed_tiles": 4.0,
		"projectile_type": "rocket",
		"pellets": 1,
		"aoe_damage": 20,
		"aoe_radius_tiles": 7.0,
	},
	"chain_lightning": {
		"damage": 8,
		"rpm": 120,
		"chain_count": 5,
		"chain_range_tiles": 6.0,
		"projectile_type": "hitscan",
	},
}

## Camera shake on rocket explosion
@export_range(0.0, 20.0) var rocket_shake_amplitude: float = 3.0

## Camera shake duration on rocket explosion
@export_range(0.0, 1.0) var rocket_shake_duration: float = 0.15

## ============================================================================
## SECTION: Katana / Melee (Phase 4 - Patch 0.2)
## ============================================================================
@export_group("Katana")

## Master toggle for katana system
@export var katana_enabled: bool = true

## Input buffer window for melee requests (seconds)
@export_range(0.0, 0.5) var melee_input_buffer_sec: float = 0.12

## ---------- Light Slash ----------
@export_range(0.0, 1.0) var katana_light_windup: float = 0.12
@export_range(0.0, 1.0) var katana_light_active: float = 0.08
@export_range(0.0, 1.0) var katana_light_recovery: float = 0.22
@export var katana_light_damage: int = 50
@export_range(1, 20) var katana_light_cleave_max: int = 3
@export_range(10.0, 200.0) var katana_light_range_px: float = 55.0
@export_range(10.0, 360.0) var katana_light_arc_deg: float = 120.0
@export_range(0.0, 2000.0) var katana_light_knockback: float = 420.0
@export_range(0.0, 2.0) var katana_light_stagger_sec: float = 0.15
@export_range(0.0, 0.5) var katana_light_hitstop_sec: float = 0.07

## ---------- Heavy Slash ----------
@export_range(0.0, 1.0) var katana_heavy_windup: float = 0.24
@export_range(0.0, 1.0) var katana_heavy_active: float = 0.10
@export_range(0.0, 1.0) var katana_heavy_recovery: float = 0.38
@export var katana_heavy_damage: int = 90
@export_range(1, 20) var katana_heavy_cleave_max: int = 5
@export_range(10.0, 200.0) var katana_heavy_range_px: float = 65.0
@export_range(10.0, 360.0) var katana_heavy_arc_deg: float = 140.0
@export_range(0.0, 2000.0) var katana_heavy_knockback: float = 680.0
@export_range(0.0, 2.0) var katana_heavy_stagger_sec: float = 0.28
@export_range(0.0, 0.5) var katana_heavy_hitstop_sec: float = 0.10

## ---------- Dash Slash ----------
@export_range(0.0, 1.0) var katana_dash_duration_sec: float = 0.15
@export_range(10.0, 500.0) var katana_dash_distance_px: float = 110.0
@export_range(0.0, 1.0) var katana_dash_iframes_sec: float = 0.12
@export_range(0.0, 1.0) var katana_dash_active_sec: float = 0.08
@export_range(0.0, 1.0) var katana_dash_recovery_sec: float = 0.25
@export_range(0.0, 10.0) var katana_dash_cooldown_sec: float = 1.5
@export var katana_dash_damage: int = 60
@export_range(10.0, 200.0) var katana_dash_range_px: float = 60.0
@export_range(10.0, 360.0) var katana_dash_arc_deg: float = 120.0
@export_range(0.0, 2000.0) var katana_dash_knockback: float = 520.0
@export_range(0.0, 2.0) var katana_dash_stagger_sec: float = 0.18
@export_range(0.0, 0.5) var katana_dash_hitstop_sec: float = 0.07

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

## ---------- Melee Arc Visuals ----------
@export_range(5.0, 60.0) var melee_arc_light_radius: float = 26.0
@export_range(10.0, 180.0) var melee_arc_light_arc_deg: float = 80.0
@export_range(1.0, 8.0) var melee_arc_light_thickness: float = 2.0
@export_range(0.01, 1.0) var melee_arc_light_duration: float = 0.08
@export_range(0.0, 1.0) var melee_arc_light_alpha: float = 0.6

@export_range(5.0, 80.0) var melee_arc_heavy_radius: float = 30.0
@export_range(10.0, 220.0) var melee_arc_heavy_arc_deg: float = 110.0
@export_range(1.0, 8.0) var melee_arc_heavy_thickness: float = 3.0
@export_range(0.01, 1.0) var melee_arc_heavy_duration: float = 0.12
@export_range(0.0, 1.0) var melee_arc_heavy_alpha: float = 0.8

@export_range(5.0, 60.0) var melee_arc_dash_length_min: float = 20.0
@export_range(10.0, 60.0) var melee_arc_dash_length_max: float = 28.0
@export_range(1, 6) var melee_arc_dash_afterimages: int = 3
@export_range(0.0, 1.0) var melee_arc_dash_alpha: float = 0.6

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
@export var waves_enabled: bool = false
@export var spawn_enemies_enabled: bool = false
@export var spawn_boss_enabled: bool = false

@export var layout_seed: int = 1337

@export_range(2, 20) var rooms_count_min: int = 9
@export_range(2, 20) var rooms_count_max: int = 15

@export_range(4.0, 64.0) var wall_thickness: float = 16.0

@export_range(40.0, 320.0) var door_opening_uniform: float = 75.0
@export_range(40.0, 300.0) var door_opening_min: float = 75.0
@export_range(40.0, 400.0) var door_opening_max: float = 75.0
@export_range(0.0, 100.0) var door_from_corner_min: float = 56.0
@export_range(1, 5) var max_doors_per_room: int = 3

## ---------- Door Physics ----------
@export_range(0.5, 10.0) var door_close_stiffness_idle: float = 2.8
@export_range(0.1, 5.0) var door_close_stiffness_pushed: float = 0.3
@export_range(0.5, 8.0) var door_angular_damping: float = 1.6
@export_range(0.0, 5.0) var door_dry_friction: float = 0.8
@export_range(5.0, 40.0) var door_max_angular_speed: float = 24.0
@export_range(0.1, 1.0) var door_limit_bounce: float = 0.35
@export_range(0.5, 40.0) var door_push_torque_min: float = 4.0
@export_range(1.0, 60.0) var door_push_torque_max: float = 32.0
@export_range(50.0, 800.0) var door_push_speed_ref: float = 280.0
@export_range(0.0, 2.0) var door_reverse_impulse_mult: float = 0.0
@export var door_debug_draw: bool = false
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

@export var layout_debug_draw: bool = false
@export var layout_debug_text: bool = true

## ============================================================================
## METHODS
## ============================================================================

## Reset all values to defaults
func reset_to_defaults() -> void:
	# Core
	tile_size = 32
	max_alive_enemies = 64
	direction_render_mode = DirectionRenderMode.ROTATE_SPRITE
	pixel_perfect_rotation = true
	god_mode = false

	# Spawn
	start_delay_sec = 1.5
	inter_wave_delay_sec = 1.0
	enemies_per_wave = 12
	wave_size_growth = 3
	spawn_tick_sec = 0.6
	spawn_batch_size = 6
	wave_advance_threshold = 0.2
	waves_per_level = 3

	# Combat
	player_max_hp = 100
	contact_iframes_sec = 0.7
	boss_contact_iframes_sec = 3.0

	# Audio
	music_volume = 0.7
	sfx_volume = 0.7
	music_fade_in_sec = 0.5
	music_fade_out_sec = 0.7

	# Physics
	player_speed_tiles = 10.0

	# Weapons
	weapon_stats = {
		"pistol": {"damage": 10, "rpm": 180, "speed_tiles": 12.0, "projectile_type": "bullet", "pellets": 1},
		"auto": {"damage": 7, "rpm": 150, "speed_tiles": 14.0, "projectile_type": "bullet", "pellets": 1},
		"shotgun": {"damage": 6, "rpm": 50.0, "cooldown_sec": 1.2, "speed_tiles": 40.0, "projectile_type": "pellet", "pellets": 16, "cone_deg": 8.0, "shot_damage_total": 25.0},
		"plasma": {"damage": 20, "rpm": 120, "speed_tiles": 9.0, "projectile_type": "plasma", "pellets": 1},
		"rocket": {"damage": 40, "rpm": 30, "speed_tiles": 4.0, "projectile_type": "rocket", "pellets": 1, "aoe_damage": 20, "aoe_radius_tiles": 7.0},
		"chain_lightning": {"damage": 8, "rpm": 120, "chain_count": 5, "chain_range_tiles": 6.0, "projectile_type": "hitscan"},
	}
	rocket_shake_amplitude = 3.0
	rocket_shake_duration = 0.15

	# Katana
	katana_enabled = true
	melee_input_buffer_sec = 0.12
	katana_light_windup = 0.12
	katana_light_active = 0.08
	katana_light_recovery = 0.22
	katana_light_damage = 50
	katana_light_cleave_max = 3
	katana_light_range_px = 55.0
	katana_light_arc_deg = 120.0
	katana_light_knockback = 420.0
	katana_light_stagger_sec = 0.15
	katana_light_hitstop_sec = 0.07
	katana_heavy_windup = 0.24
	katana_heavy_active = 0.10
	katana_heavy_recovery = 0.38
	katana_heavy_damage = 90
	katana_heavy_cleave_max = 5
	katana_heavy_range_px = 65.0
	katana_heavy_arc_deg = 140.0
	katana_heavy_knockback = 680.0
	katana_heavy_stagger_sec = 0.28
	katana_heavy_hitstop_sec = 0.10
	katana_dash_duration_sec = 0.15
	katana_dash_distance_px = 110.0
	katana_dash_iframes_sec = 0.12
	katana_dash_active_sec = 0.08
	katana_dash_recovery_sec = 0.25
	katana_dash_cooldown_sec = 1.5
	katana_dash_damage = 60
	katana_dash_range_px = 60.0
	katana_dash_arc_deg = 120.0
	katana_dash_knockback = 520.0
	katana_dash_stagger_sec = 0.18
	katana_dash_hitstop_sec = 0.07

	# Visual Polish
	footprints_enabled = true
	footprint_step_distance_px = 40.0
	footprint_rear_offset_px = 12.0
	footprint_separation_px = 7.0
	footprint_scale = 0.65
	footprint_alpha = 0.35
	footprint_rotation_jitter_deg = 1.0
	footprint_lifetime_sec = 20.0
	footprint_velocity_threshold = 35.0
	footprint_max_count = 4000
	footprint_bloody_steps = 8
	footprint_black_steps = 4
	footprint_blood_detect_radius = 25.0
	footprint_rotation_offset_deg = 90.0
	boots_blood_max_prints = 8
	melee_arc_light_radius = 26.0
	melee_arc_light_arc_deg = 80.0
	melee_arc_light_thickness = 2.0
	melee_arc_light_duration = 0.08
	melee_arc_light_alpha = 0.6
	melee_arc_heavy_radius = 30.0
	melee_arc_heavy_arc_deg = 110.0
	melee_arc_heavy_thickness = 3.0
	melee_arc_heavy_duration = 0.12
	melee_arc_heavy_alpha = 0.8
	melee_arc_dash_length_min = 20.0
	melee_arc_dash_length_max = 28.0
	melee_arc_dash_afterimages = 3
	melee_arc_dash_alpha = 0.6
	shadow_player_radius_mult = 1.2
	shadow_player_alpha = 0.25
	shadow_enemy_radius_mult = 1.1
	shadow_enemy_alpha = 0.18
	highlight_player_radius_offset = 2.0
	highlight_player_thickness = 2.0
	highlight_player_alpha = 0.5
	hit_flash_duration = 0.06
	kill_pop_scale = 1.2
	kill_pop_duration = 0.1
	kill_edge_pulse_alpha = 0.15
	damage_arc_duration = 0.12
	blood_max_decals = 500
	blood_darken_rate = 0.01
	blood_desaturate_rate = 0.005
	vignette_alpha = 0.3
	floor_overlay_alpha = 0.15
	atmosphere_particle_alpha_min = 0.05
	atmosphere_particle_alpha_max = 0.15
	atmosphere_particle_lifetime_min = 3.0
	atmosphere_particle_lifetime_max = 6.0
	debug_overlay_visible = false

	# Procedural Layout
	procedural_layout_enabled = true
	waves_enabled = false
	spawn_enemies_enabled = false
	spawn_boss_enabled = false
	layout_seed = 1337
	rooms_count_min = 9
	rooms_count_max = 15
	wall_thickness = 16.0
	door_opening_uniform = 75.0
	door_opening_min = 75.0
	door_opening_max = 75.0
	door_from_corner_min = 56.0
	max_doors_per_room = 3
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
	layout_debug_draw = false
	layout_debug_text = true

## Create a snapshot of current config (for validation/comparison)
func get_snapshot() -> Dictionary:
	return {
		"tile_size": tile_size,
		"max_alive_enemies": max_alive_enemies,
		"god_mode": god_mode,
		"start_delay_sec": start_delay_sec,
		"enemies_per_wave": enemies_per_wave,
		"waves_per_level": waves_per_level,
		"player_max_hp": player_max_hp,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"player_speed_tiles": player_speed_tiles,
		"rocket_shake_amplitude": rocket_shake_amplitude,
		"rocket_shake_duration": rocket_shake_duration,
		"katana_enabled": katana_enabled,
		"katana_light_damage": katana_light_damage,
		"katana_heavy_damage": katana_heavy_damage,
		"katana_dash_damage": katana_dash_damage,
	}
