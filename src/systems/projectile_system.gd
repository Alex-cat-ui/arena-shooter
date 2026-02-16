## projectile_system.gd
## ProjectileSystem - spawns and manages projectiles.
## CANON: TTL, collision, destruction.
## CANON: Reads weapon stats from GameConfig.weapon_stats (Phase 3).
class_name ProjectileSystem
extends Node

const SHOTGUN_SPREAD_SCRIPT := preload("res://src/systems/shotgun_spread.gd")

## Projectile scene
var projectile_scene: PackedScene = null

## Container for projectiles (set by level)
var projectiles_container: Node2D = null

## Next projectile ID
var _next_projectile_id: int = 1
var _next_shotgun_shot_id: int = 1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Load projectile scene
	projectile_scene = load("res://scenes/entities/projectile.tscn")
	_rng.randomize()


## Spawn projectile(s) for weapon
func fire_weapon(weapon_type: String, position: Vector2, direction: Vector2) -> void:
	if not projectile_scene or not projectiles_container:
		push_warning("[ProjectileSystem] Missing scene or container")
		return

	var stats := _weapon_stats_for(weapon_type)
	if stats.is_empty():
		push_warning("[ProjectileSystem] Unknown weapon: %s" % weapon_type)
		return

	var tile_size: int = GameConfig.tile_size if GameConfig else 32
	var speed_pixels: float = stats.speed_tiles * tile_size
	if weapon_type == "shotgun":
		_fire_shotgun(stats, position, direction, speed_pixels)
		return

	var pellets: int = int(stats.get("pellets", 1))
	var spread: float = float(stats.get("spread", 0.0))

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


func _fire_shotgun(stats: Dictionary, position: Vector2, direction: Vector2, speed_pixels: float) -> void:
	var pellets := maxi(int(stats.get("pellets", 16)), 1)
	var cone_deg := maxf(float(stats.get("cone_deg", 8.0)), 0.0)
	var shot_total_damage := maxf(float(stats.get("shot_damage_total", 25.0)), 0.0)
	var shot_id := _next_shotgun_shot_id
	_next_shotgun_shot_id += 1
	var spread_profile := SHOTGUN_SPREAD_SCRIPT.sample_pellets(pellets, cone_deg, _rng)

	for pellet_variant in spread_profile:
		var pellet := pellet_variant as Dictionary
		var angle_offset := float(pellet.get("angle_offset", 0.0))
		var speed_scale := float(pellet.get("speed_scale", 1.0))
		var dir := direction.rotated(angle_offset)
		_spawn_projectile(
			str(stats.get("projectile_type", "pellet")),
			position,
			dir,
			speed_pixels * speed_scale,
			1, # actual pellet damage to enemies is aggregated in CombatSystem by shot metadata
			shot_id,
			pellets,
			shot_total_damage
		)


func _spawn_projectile(type: String, pos: Vector2, dir: Vector2, speed: float, damage: int, shot_id: int = -1, shot_total_pellets: int = 0, shot_total_damage: float = 0.0) -> void:
	var projectile := projectile_scene.instantiate() as Projectile

	projectile.initialize(_next_projectile_id, type, pos, dir, speed, damage, shot_id, shot_total_pellets, shot_total_damage)
	projectiles_container.add_child(projectile)

	_next_projectile_id += 1


## Get weapon cooldown in seconds
func get_weapon_cooldown(weapon_type: String) -> float:
	var stats := _weapon_stats_for(weapon_type)
	if stats.is_empty():
		return 1.0
	var cooldown_sec: float = float(stats.get("cooldown_sec", -1.0))
	if cooldown_sec > 0.0:
		return cooldown_sec
	var rpm: float = maxf(float(stats.get("rpm", 60.0)), 1.0)
	return 60.0 / rpm


## Clear all projectiles
func clear_all() -> void:
	if projectiles_container:
		for child in projectiles_container.get_children():
			child.queue_free()


func _weapon_stats_for(weapon_type: String) -> Dictionary:
	if not GameConfig or not GameConfig.weapon_stats.has(weapon_type):
		return {}
	return GameConfig.weapon_stats[weapon_type] as Dictionary
