## ability_system.gd
## AbilitySystem - weapon registry, activation, and firing.
## CANON: Reads all weapon stats from GameConfig.weapon_stats.
## CANON: Delegates projectile spawning to ProjectileSystem.
class_name AbilitySystem
extends Node

## Canonical weapon list (order = slot index)
const WEAPON_LIST: Array[String] = [
	"pistol",
	"shotgun",
]

## Current weapon slot index
var current_weapon_index: int = 0

## Weapon cooldown timer
var _weapon_cooldown: float = 0.0

## Reference to ProjectileSystem (set by level)
var projectile_system: Node = null

## Reference to CombatSystem (set by level, for chain lightning damage)
var combat_system: Node = null


## Tick weapon cooldown independently from input state.
func tick_cooldown(delta: float) -> void:
	if delta <= 0.0:
		return
	_weapon_cooldown = maxf(_weapon_cooldown - delta, 0.0)


## Get current weapon name
func get_current_weapon() -> String:
	return WEAPON_LIST[current_weapon_index]


## Get weapon list
func get_weapon_list() -> Array[String]:
	return WEAPON_LIST


## Cycle weapon forward (+1) or backward (-1)
func cycle_weapon(direction: int) -> void:
	var new_index := (current_weapon_index + direction) % WEAPON_LIST.size()
	if new_index < 0:
		new_index += WEAPON_LIST.size()
	_set_weapon(new_index)


## Select weapon by slot index (0..WEAPON_LIST.size()-1)
func set_weapon_by_index(index: int) -> void:
	if index < 0 or index >= WEAPON_LIST.size():
		return
	if index == current_weapon_index:
		return
	_set_weapon(index)


## Select weapon by name
func set_weapon_by_name(weapon_name: String) -> void:
	var idx := WEAPON_LIST.find(weapon_name)
	if idx >= 0:
		set_weapon_by_index(idx)


## Try to fire current weapon. Returns true if fired.
func try_fire(pos: Vector2, direction: Vector2, delta: float) -> bool:
	# Keep backward-compatible cooldown ticking for callers that still pass delta here.
	tick_cooldown(delta)
	if _weapon_cooldown > 0:
		return false

	var weapon := get_current_weapon()
	var stats := _get_stats(weapon)
	if stats.is_empty():
		return false

	if projectile_system and projectile_system.has_method("fire_weapon"):
		projectile_system.fire_weapon(weapon, pos, direction)

	# Set cooldown from RPM
	var cooldown_sec: float = float(stats.get("cooldown_sec", -1.0))
	if cooldown_sec > 0.0:
		_weapon_cooldown = cooldown_sec
	else:
		var rpm: float = maxf(float(stats.get("rpm", 60.0)), 1.0)
		_weapon_cooldown = 60.0 / rpm

	# Emit player_shot event
	if EventBus:
		EventBus.emit_player_shot(weapon, Vector3(pos.x, pos.y, 0), Vector3(direction.x, direction.y, 0))

	return true


## Get weapon cooldown in seconds
func get_weapon_cooldown(weapon: String) -> float:
	var stats := _get_stats(weapon)
	var cooldown_sec: float = float(stats.get("cooldown_sec", -1.0))
	if cooldown_sec > 0.0:
		return cooldown_sec
	var rpm: float = maxf(float(stats.get("rpm", 60.0)), 1.0)
	return 60.0 / rpm


## ============================================================================
## INTERNAL
## ============================================================================

func _set_weapon(index: int) -> void:
	current_weapon_index = index
	_weapon_cooldown = 0.0  # Instant switch
	if EventBus:
		EventBus.emit_weapon_changed(get_current_weapon(), current_weapon_index)


func _get_stats(weapon: String) -> Dictionary:
	if GameConfig and GameConfig.weapon_stats.has(weapon):
		return GameConfig.weapon_stats[weapon]
	return {}
