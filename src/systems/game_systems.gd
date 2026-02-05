## game_systems.gd
## Composition root for all game systems.
## Phase 0: Stub - systems will be added in later phases.
class_name GameSystems
extends Node

## References to all systems (populated in later phases)
var aim_system: Node = null
var physics_world: Node = null
var spawner_system: Node = null
var combat_system: Node = null
var projectile_system: Node = null
var vfx_system: Node = null
var stats_system: Node = null
var ability_system: Node = null
var music_system: Node = null


func _ready() -> void:
	print("[GameSystems] Initialized (Phase 0 stub)")


## Update all systems (called from level)
func update_systems(delta: float) -> void:
	# Phase 0: No systems to update yet
	# Future phases will call system.update(delta) here
	pass


## Pause all systems
func pause_systems() -> void:
	print("[GameSystems] Systems paused")


## Resume all systems
func resume_systems() -> void:
	print("[GameSystems] Systems resumed")
