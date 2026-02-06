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
@export_range(1.0, 50.0) var player_speed_tiles: float = 5.0

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
		"rpm": 60,
		"speed_tiles": 10.0,
		"projectile_type": "pellet",
		"pellets": 5,
		"spread": 0.3,
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
	player_speed_tiles = 5.0

	# Weapons
	weapon_stats = {
		"pistol": {"damage": 10, "rpm": 180, "speed_tiles": 12.0, "projectile_type": "bullet", "pellets": 1},
		"auto": {"damage": 7, "rpm": 150, "speed_tiles": 14.0, "projectile_type": "bullet", "pellets": 1},
		"shotgun": {"damage": 6, "rpm": 60, "speed_tiles": 10.0, "projectile_type": "pellet", "pellets": 5, "spread": 0.3},
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
