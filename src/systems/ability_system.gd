## ability_system.gd
## AbilitySystem - weapon registry, activation, and firing.
## CANON: Reads all weapon stats from GameConfig.weapon_stats.
## CANON: Delegates projectile spawning to ProjectileSystem.
## CANON: Chain lightning is hitscan (no projectile).
class_name AbilitySystem
extends Node

## Canonical weapon list (order = slot index)
const WEAPON_LIST: Array[String] = [
	"pistol",
	"auto",
	"shotgun",
	"plasma",
	"rocket",
	"chain_lightning",
]

## Current weapon slot index
var current_weapon_index: int = 0

## Weapon cooldown timer
var _weapon_cooldown: float = 0.0

## Reference to ProjectileSystem (set by level)
var projectile_system: Node = null

## Reference to CombatSystem (set by level, for chain lightning damage)
var combat_system: Node = null


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


## Select weapon by slot index (0-5)
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
	# Update cooldown
	_weapon_cooldown -= delta
	if _weapon_cooldown > 0:
		return false

	var weapon := get_current_weapon()
	var stats := _get_stats(weapon)
	if stats.is_empty():
		return false

	# Fire based on weapon type
	if weapon == "chain_lightning":
		_fire_chain_lightning(pos, direction)
	else:
		if projectile_system and projectile_system.has_method("fire_weapon"):
			projectile_system.fire_weapon(weapon, pos, direction)

	# Set cooldown from RPM
	var rpm: float = stats.get("rpm", 60)
	_weapon_cooldown = 60.0 / rpm

	# Emit player_shot event
	if EventBus:
		EventBus.emit_player_shot(weapon, Vector3(pos.x, pos.y, 0), Vector3(direction.x, direction.y, 0))

	return true


## Get weapon cooldown in seconds
func get_weapon_cooldown(weapon: String) -> float:
	var stats := _get_stats(weapon)
	var rpm: float = stats.get("rpm", 60)
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


## ============================================================================
## CHAIN LIGHTNING (Hitscan)
## ============================================================================

func _fire_chain_lightning(origin: Vector2, direction: Vector2) -> void:
	var stats := _get_stats("chain_lightning")
	var damage: int = stats.get("damage", 8)
	var chain_count: int = stats.get("chain_count", 5)
	var chain_range_tiles: float = stats.get("chain_range_tiles", 6.0)
	var tile_size: int = GameConfig.tile_size if GameConfig else 32
	var chain_range_px: float = chain_range_tiles * tile_size

	var targets := _find_chain_targets(origin, direction, chain_count, chain_range_px)

	var prev_pos := origin
	for target in targets:
		if not is_instance_valid(target):
			continue

		# Apply damage through CombatSystem pipeline
		if combat_system and combat_system.has_method("damage_enemy"):
			combat_system.damage_enemy(target, damage, "chain_lightning")
		elif target.has_method("take_damage"):
			target.take_damage(damage)

		# Emit chain arc VFX event
		if EventBus:
			EventBus.emit_chain_lightning_hit(
				Vector3(prev_pos.x, prev_pos.y, 0),
				Vector3(target.position.x, target.position.y, 0)
			)
		prev_pos = target.position


func _find_chain_targets(origin: Vector2, direction: Vector2, max_chains: int, max_range: float) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var used_ids: Dictionary = {}
	var current_pos := origin

	for _i in range(max_chains):
		var best_target: Node2D = null
		var best_dist: float = max_range

		# Gather all potential targets
		var candidates: Array[Node] = []
		candidates.append_array(get_tree().get_nodes_in_group("enemies"))
		candidates.append_array(get_tree().get_nodes_in_group("boss"))

		for candidate in candidates:
			if not candidate is Node2D or not is_instance_valid(candidate):
				continue
			var candidate_node: Node2D = candidate as Node2D
			# Skip already-hit targets
			if "entity_id" in candidate_node and used_ids.has(candidate_node.entity_id):
				continue
			# Skip dead enemies
			if "is_dead" in candidate_node and candidate_node.is_dead:
				continue

			var dist := current_pos.distance_to(candidate_node.position)
			if dist > max_range or dist <= 0:
				continue

			# First target: require direction cone (60 degrees, dot > 0.5)
			if result.is_empty():
				var to_candidate: Vector2 = (candidate_node.position - current_pos).normalized()
				if direction.dot(to_candidate) < 0.5:
					continue

			if dist < best_dist:
				best_dist = dist
				best_target = candidate_node

		if best_target == null:
			break

		result.append(best_target)
		if "entity_id" in best_target:
			used_ids[best_target.entity_id] = true
		current_pos = best_target.position

	return result
