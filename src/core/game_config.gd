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
		"player_speed_tiles": player_speed_tiles
	}
