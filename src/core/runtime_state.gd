## runtime_state.gd
## Singleton holding runtime session data.
## CANON: Positions stored as Vector3 (x, y, z=0).
## CANON: Reset on: exit to MAIN_MENU, restart level, start new level.
extends Node

## ============================================================================
## RUNTIME DATA
## ============================================================================

## Player current HP
var player_hp: int = 100

## Current wave index (1-based, 0 = not started)
var current_wave: int = 0

## Total kills this session
var kills: int = 0

## Damage dealt this session
var damage_dealt: int = 0

## Damage received this session
var damage_received: int = 0

## Time elapsed in level (seconds)
var time_elapsed: float = 0.0

## Player position in world (CANON: Vector3, z=0)
var player_pos: Vector3 = Vector3.ZERO

## Player aim direction (normalized, CANON: Vector3)
var player_aim_dir: Vector3 = Vector3(1, 0, 0)

## Is level currently active (gameplay running)
var is_level_active: bool = false

## Is gameplay frozen (pause, game over, etc.)
var is_frozen: bool = false

## Katana mode active (Q toggle)
var katana_mode: bool = false

## Player invulnerability (dash slash i-frames)
var is_player_invulnerable: bool = false

## Invulnerability timer (auto-decrements)
var invuln_timer: float = 0.0

## Active mission index in cycle (3 -> 1 -> 2)
var mission_index: int = 3

## Generated room metadata (for future prop placement by room type)
var layout_room_memory: Array = []

## ============================================================================
## METHODS
## ============================================================================

## Reset all runtime state to defaults
## Called on: exit to MAIN_MENU, restart level, start new level
func reset() -> void:
	player_hp = GameConfig.player_max_hp if GameConfig else 100
	current_wave = 0
	kills = 0
	damage_dealt = 0
	damage_received = 0
	time_elapsed = 0.0
	player_pos = Vector3.ZERO
	player_aim_dir = Vector3(1, 0, 0)
	is_level_active = false
	is_frozen = false
	katana_mode = false
	is_player_invulnerable = false
	invuln_timer = 0.0
	mission_index = 3
	layout_room_memory = []


## Convert Vector2 to Vector3 (z=0) - utility for physics
static func vec2_to_vec3(v: Vector2) -> Vector3:
	return Vector3(v.x, v.y, 0.0)


## Convert Vector3 to Vector2 (drop z) - utility for physics
static func vec3_to_vec2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.y)


func _ready() -> void:
	reset()
