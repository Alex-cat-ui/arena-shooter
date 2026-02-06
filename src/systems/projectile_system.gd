## projectile_system.gd
## ProjectileSystem - spawns and manages projectiles.
## CANON: TTL, collision, destruction.
## CANON: Reads weapon stats from GameConfig.weapon_stats (Phase 3).
class_name ProjectileSystem
extends Node

## Projectile scene
var projectile_scene: PackedScene = null

## Container for projectiles (set by level)
var projectiles_container: Node2D = null

## Next projectile ID
var _next_projectile_id: int = 1

## Weapon stats - populated from GameConfig on _ready
## Fallback values match ТЗ v1.13
var WEAPON_STATS: Dictionary = {
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
		"spread": 0.3,  # radians
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
	"piercing": {
		"damage": 10,
		"rpm": 180,
		"speed_tiles": 12.0,
		"projectile_type": "piercing_bullet",
		"pellets": 1,
	},
}


func _ready() -> void:
	# Load projectile scene
	projectile_scene = load("res://scenes/entities/projectile.tscn")

	# Override stats from GameConfig (canonical source of truth)
	if GameConfig and GameConfig.weapon_stats:
		for key in GameConfig.weapon_stats:
			var stats: Dictionary = GameConfig.weapon_stats[key]
			# Skip hitscan weapons (chain_lightning) - no projectile
			if stats.get("projectile_type", "") == "hitscan":
				continue
			WEAPON_STATS[key] = stats


## Spawn projectile(s) for weapon
func fire_weapon(weapon_type: String, position: Vector2, direction: Vector2) -> void:
	if not projectile_scene or not projectiles_container:
		push_warning("[ProjectileSystem] Missing scene or container")
		return

	if not WEAPON_STATS.has(weapon_type):
		push_warning("[ProjectileSystem] Unknown weapon: %s" % weapon_type)
		return

	var stats: Dictionary = WEAPON_STATS[weapon_type]
	var tile_size: int = GameConfig.tile_size if GameConfig else 32
	var speed_pixels: float = stats.speed_tiles * tile_size
	var pellets: int = stats.get("pellets", 1)
	var spread: float = stats.get("spread", 0.0)

	for i in range(pellets):
		var dir := direction
		# Apply spread for multi-pellet weapons
		if pellets > 1 and spread > 0:
			var angle_offset := (i - (pellets - 1) / 2.0) * spread / (pellets - 1)
			dir = direction.rotated(angle_offset)

		_spawn_projectile(
			stats.projectile_type,
			position,
			dir,
			speed_pixels,
			stats.damage
		)


func _spawn_projectile(type: String, pos: Vector2, dir: Vector2, speed: float, damage: int) -> void:
	var projectile := projectile_scene.instantiate() as Projectile

	projectile.initialize(_next_projectile_id, type, pos, dir, speed, damage)
	projectiles_container.add_child(projectile)

	_next_projectile_id += 1


## Get weapon cooldown in seconds
func get_weapon_cooldown(weapon_type: String) -> float:
	if not WEAPON_STATS.has(weapon_type):
		return 1.0
	var rpm: float = WEAPON_STATS[weapon_type].rpm
	return 60.0 / rpm


## Clear all projectiles
func clear_all() -> void:
	if projectiles_container:
		for child in projectiles_container.get_children():
			child.queue_free()
