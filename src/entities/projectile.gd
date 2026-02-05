## projectile.gd
## Projectile entity.
## CANON: TTL defaults - bullet/pellet/plasma 2.0s, rocket 3.0s, piercing 2.0s
## CANON: Hitbox 0.1 tile
class_name Projectile
extends Area2D

## Projectile types and their TTL
const PROJECTILE_TTL := {
	"bullet": 2.0,
	"pellet": 2.0,
	"plasma": 2.0,
	"rocket": 3.0,
	"piercing_bullet": 2.0,
}

## Unique projectile ID
var projectile_id: int = 0

## Projectile type
var projectile_type: String = "bullet"

## Damage amount
var damage: int = 10

## Velocity (pixels/sec)
var velocity: Vector2 = Vector2.ZERO

## Time to live remaining
var ttl: float = 2.0

## Is this a piercing projectile?
var is_piercing: bool = false

## Set of enemy IDs already hit (for piercing)
var _hit_enemies: Dictionary = {}

## Reference to sprite
@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	# Connect collision signal
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


## Initialize projectile
func initialize(id: int, type: String, pos: Vector2, dir: Vector2, speed: float, dmg: int) -> void:
	projectile_id = id
	projectile_type = type
	damage = dmg
	position = pos
	velocity = dir.normalized() * speed

	# Set TTL based on type
	ttl = PROJECTILE_TTL.get(type, 2.0)

	# Check if piercing
	is_piercing = (type == "piercing_bullet")

	# Rotate sprite to face direction
	if sprite:
		sprite.rotation = dir.angle()

	# Emit spawn event
	if EventBus:
		EventBus.emit_projectile_spawned(projectile_id, projectile_type, Vector3(pos.x, pos.y, 0))


func _physics_process(delta: float) -> void:
	# Check if frozen
	if RuntimeState and RuntimeState.is_frozen:
		return

	# Update TTL
	ttl -= delta
	if ttl <= 0:
		_destroy("ttl")
		return

	# Move
	position += velocity * delta


func _on_body_entered(body: Node2D) -> void:
	# Check if it's an enemy
	if body.is_in_group("enemies"):
		_hit_enemy(body)
	# Phase 2: Check if it's a boss
	elif body.is_in_group("boss"):
		_hit_boss(body)


func _on_area_entered(area: Area2D) -> void:
	# Check if it's an enemy hitbox
	var parent := area.get_parent()
	if parent and parent.is_in_group("enemies"):
		_hit_enemy(parent)
	# Phase 2: Check if it's a boss hitbox
	elif parent and parent.is_in_group("boss"):
		_hit_boss(parent)


func _hit_enemy(enemy: Node2D) -> void:
	if not "entity_id" in enemy:
		return

	var enemy_id: int = enemy.entity_id

	# Check piercing - each enemy hit only once
	if is_piercing:
		if _hit_enemies.has(enemy_id):
			return
		_hit_enemies[enemy_id] = true

	# Emit hit event
	if EventBus:
		EventBus.emit_projectile_hit(projectile_id, enemy_id, damage)

	# Destroy if not piercing
	if not is_piercing:
		_destroy("hit")


## Phase 2: Hit boss
func _hit_boss(boss: Node2D) -> void:
	if not "entity_id" in boss:
		return

	var boss_id: int = boss.entity_id

	# Check piercing - hit boss only once per projectile
	if is_piercing:
		var key := "boss_%d" % boss_id
		if _hit_enemies.has(key):
			return
		_hit_enemies[key] = true

	# Apply damage directly to boss (not through event for simplicity)
	if boss.has_method("take_damage"):
		boss.take_damage(damage)

	# Track stats
	if RuntimeState:
		RuntimeState.damage_dealt += damage

	# Destroy if not piercing
	if not is_piercing:
		_destroy("hit_boss")


func _destroy(reason: String) -> void:
	# Emit destroy event
	if EventBus:
		EventBus.emit_projectile_destroyed(projectile_id, reason)

	queue_free()
