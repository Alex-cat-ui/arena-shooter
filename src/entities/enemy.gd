## enemy.gd
## Base enemy entity.
## CANON: Simple AI - move directly toward player.
## CANON: Hitbox size 0.4 tiles for standard enemies.
## CANON: Contact damage with global i-frames.
class_name Enemy
extends CharacterBody2D

## Enemy stats per type (from ТЗ v1.13)
const ENEMY_STATS := {
	"zombie": {"hp": 30, "damage": 10, "speed": 2.0},
	"fast": {"hp": 15, "damage": 7, "speed": 4.0},
	"tank": {"hp": 80, "damage": 15, "speed": 1.5},
	"swarm": {"hp": 5, "damage": 5, "speed": 3.0},
}

## Unique entity ID
var entity_id: int = 0

## Enemy type name
var enemy_type: String = "zombie"

## Wave this enemy belongs to
var wave_id: int = 0

## Current HP
var hp: int = 30

## Max HP (for potential HP bars)
var max_hp: int = 30

## Contact damage
var contact_damage: int = 10

## Movement speed in tiles/sec
var speed_tiles: float = 2.0

## Is enemy dead?
var is_dead: bool = false

## Reference to sprite
@onready var sprite: Sprite2D = $Sprite2D

## Reference to collision shape
@onready var collision: CollisionShape2D = $CollisionShape2D

## Reference to hitbox area (for player contact detection)
@onready var hitbox: Area2D = $Hitbox


func _ready() -> void:
	# Add to enemies group for easy lookup
	add_to_group("enemies")

	# Connect hitbox signals
	if hitbox:
		hitbox.body_entered.connect(_on_hitbox_body_entered)

	# Spawn animation (Phase 3: visual spawn cue)
	_play_spawn_animation()


## Initialize enemy with ID, type, and wave
func initialize(id: int, type: String, wave: int) -> void:
	entity_id = id
	enemy_type = type
	wave_id = wave

	# Load stats from type
	if ENEMY_STATS.has(type):
		var stats: Dictionary = ENEMY_STATS[type]
		hp = stats.hp
		max_hp = stats.hp
		contact_damage = stats.damage
		speed_tiles = stats.speed
	else:
		push_warning("[Enemy] Unknown enemy type: %s" % type)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Check if frozen
	if RuntimeState and RuntimeState.is_frozen:
		return

	# Move toward player
	_move_toward_player(delta)


func _move_toward_player(delta: float) -> void:
	# Get player position
	var player_pos := Vector2.ZERO
	if RuntimeState:
		player_pos = Vector2(RuntimeState.player_pos.x, RuntimeState.player_pos.y)

	# Calculate direction
	var direction := (player_pos - position).normalized()

	# Calculate velocity
	var tile_size: int = GameConfig.tile_size if GameConfig else 32
	var speed_pixels := speed_tiles * tile_size
	velocity = direction * speed_pixels

	# Move
	move_and_slide()

	# Rotate sprite to face movement direction
	if sprite and direction.length_squared() > 0:
		sprite.rotation = direction.angle()


## Take damage
func take_damage(amount: int) -> void:
	if is_dead:
		return

	hp -= amount

	# Visual feedback (flash red)
	if sprite:
		sprite.modulate = Color.RED
		var tween := create_tween()
		tween.tween_property(sprite, "modulate", Color.WHITE, 0.1)

	# Check death
	if hp <= 0:
		die()


## Enemy death
func die() -> void:
	if is_dead:
		return

	is_dead = true

	# Update stats BEFORE emitting event (so VFXSystem can read position)
	if RuntimeState:
		RuntimeState.kills += 1

	# Disable collision immediately
	if collision:
		collision.set_deferred("disabled", true)
	if hitbox:
		hitbox.set_deferred("monitoring", false)

	# Phase 2: VFXSystem handles corpse creation through enemy_killed event
	# Store position for VFXSystem before removing from group
	var death_pos := position
	var death_rot := sprite.rotation if sprite else 0.0

	# Emit kill event (VFXSystem will create corpse at this position)
	# Note: we stay in "enemies" group briefly so VFXSystem can find us
	if EventBus:
		EventBus.emit_enemy_killed(entity_id, enemy_type, wave_id)

	# Death visual feedback then cleanup
	_play_death_effect()


func _cleanup_after_death() -> void:
	# Remove from enemies group
	remove_from_group("enemies")

	# Disable physics
	set_physics_process(false)

	# Queue free - VFXSystem creates the visual corpse
	queue_free()


## Phase 3: Spawn scale-in animation + flash
func _play_spawn_animation() -> void:
	if not sprite:
		return
	sprite.scale = Vector2(0.1, 0.1)
	sprite.modulate = Color(2.0, 2.0, 2.0, 1.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.2)


## Phase 3: Death flash + scale burst before cleanup
func _play_death_effect() -> void:
	if not sprite:
		call_deferred("_cleanup_after_death")
		return

	# White flash + scale burst + fade out
	sprite.modulate = Color(3.0, 3.0, 3.0, 1.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2(1.5, 1.5), 0.12).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.15)
	tween.set_parallel(false)
	tween.tween_callback(_cleanup_after_death)


func _on_hitbox_body_entered(body: Node2D) -> void:
	if is_dead:
		return

	# Check if it's the player
	if body.is_in_group("player"):
		# Emit contact event for CombatSystem to handle
		if EventBus:
			EventBus.emit_enemy_contact(entity_id, enemy_type, contact_damage)
