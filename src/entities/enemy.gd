## enemy.gd
## Base enemy entity.
## CANON: Simple AI - move directly toward player.
## CANON: Hitbox size 0.4 tiles for standard enemies.
## CANON: Contact damage with global i-frames.
class_name Enemy
extends CharacterBody2D

enum AIState {
	IDLE_ROAM,
	INVESTIGATE,
	CHASE,
}

## Enemy stats per type (from ТЗ v1.13)
const ENEMY_STATS := {
	"zombie": {"hp": 100, "damage": 10, "speed": 2.0},
	"fast": {"hp": 100, "damage": 7, "speed": 4.0},
	"tank": {"hp": 100, "damage": 15, "speed": 1.5},
	"swarm": {"hp": 100, "damage": 5, "speed": 3.0},
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

## Stagger timer (melee knockback, blocks movement)
var stagger_timer: float = 0.0

## Knockback velocity (decays over time)
var knockback_vel: Vector2 = Vector2.ZERO

## Reference to sprite
@onready var sprite: Sprite2D = $Sprite2D

## Reference to collision shape
@onready var collision: CollisionShape2D = $CollisionShape2D

## Reference to hitbox area (for player contact detection)
@onready var hitbox: Area2D = $Hitbox

## Room AI/nav
var nav_system: Node = null
var home_room_id: int = -1
var ai_state: int = AIState.IDLE_ROAM
var _roam_target: Vector2 = Vector2.ZERO
var _roam_wait_timer: float = 0.0
var _waypoints: Array[Vector2] = []
var _repath_timer: float = 0.0
var _heard_timer: float = 0.0

## Contact damage throttling
var _touching_player: bool = false
var _contact_cooldown: float = 0.0


func _ready() -> void:
	# Add to enemies group for easy lookup
	add_to_group("enemies")

	# Connect hitbox signals
	if hitbox:
		hitbox.body_entered.connect(_on_hitbox_body_entered)
		hitbox.body_exited.connect(_on_hitbox_body_exited)

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

	if _contact_cooldown > 0.0:
		_contact_cooldown = maxf(0.0, _contact_cooldown - delta)
	if _touching_player and _contact_cooldown <= 0.0 and enemy_type != "zombie":
		if EventBus:
			EventBus.emit_enemy_contact(entity_id, enemy_type, _contact_damage_amount())
		_contact_cooldown = 1.0

	# Check if frozen
	if RuntimeState and RuntimeState.is_frozen:
		return

	# Handle stagger (blocks normal movement)
	if stagger_timer > 0:
		stagger_timer -= delta
		# Apply knockback velocity with decay during stagger
		if knockback_vel.length_squared() > 1.0:
			velocity = knockback_vel
			move_and_slide()
			knockback_vel = knockback_vel.lerp(Vector2.ZERO, minf(10.0 * delta, 1.0))
		return

	# Decay any residual knockback
	if knockback_vel.length_squared() > 1.0:
		knockback_vel = knockback_vel.lerp(Vector2.ZERO, minf(10.0 * delta, 1.0))

	# Room-aware AI movement if nav is available, otherwise fallback to direct chase.
	if nav_system and home_room_id >= 0:
		_update_room_ai(delta)
	else:
		_move_toward_player(delta)


func set_room_navigation(p_nav_system: Node, p_home_room_id: int) -> void:
	nav_system = p_nav_system
	home_room_id = p_home_room_id
	set_meta("room_id", p_home_room_id)
	ai_state = AIState.IDLE_ROAM
	_waypoints.clear()
	_roam_target = Vector2.ZERO
	_roam_wait_timer = 0.0
	_repath_timer = 0.0
	_heard_timer = 0.0


func on_heard_shot(shot_room_id: int, shot_pos: Vector2) -> void:
	if not nav_system:
		return
	var own_room := int(get_meta("room_id", home_room_id))
	if own_room < 0 and nav_system.has_method("room_id_at_point"):
		own_room = int(nav_system.room_id_at_point(global_position))
		set_meta("room_id", own_room)
	if own_room < 0:
		return
	var same_or_adjacent := own_room == shot_room_id
	if not same_or_adjacent and nav_system.has_method("is_adjacent"):
		same_or_adjacent = bool(nav_system.is_adjacent(own_room, shot_room_id))
	if not same_or_adjacent:
		return
	ai_state = AIState.CHASE
	_heard_timer = 10.0
	_plan_path_to(shot_pos)


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


func _update_room_ai(delta: float) -> void:
	if _heard_timer > 0.0:
		_heard_timer = maxf(0.0, _heard_timer - delta)
	elif ai_state != AIState.IDLE_ROAM:
		ai_state = AIState.IDLE_ROAM
		_waypoints.clear()

	if ai_state == AIState.IDLE_ROAM:
		_update_idle_roam(delta)
		return

	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = 0.35
		var player_pos := Vector2.ZERO
		if RuntimeState:
			player_pos = Vector2(RuntimeState.player_pos.x, RuntimeState.player_pos.y)
		_plan_path_to(player_pos)

	_follow_waypoints(delta)


func _update_idle_roam(delta: float) -> void:
	if _roam_wait_timer > 0.0:
		_roam_wait_timer = maxf(0.0, _roam_wait_timer - delta)
		velocity = Vector2.ZERO
		return
	if _roam_target == Vector2.ZERO or global_position.distance_to(_roam_target) < 10.0:
		if nav_system and nav_system.has_method("random_point_in_room"):
			_roam_target = nav_system.random_point_in_room(home_room_id, 28.0)
		else:
			_roam_target = global_position
		_roam_wait_timer = randf_range(0.1, 0.35)
		velocity = Vector2.ZERO
		return

	var dir := (_roam_target - global_position).normalized()
	var tile_size: int = GameConfig.tile_size if GameConfig else 32
	var speed_pixels := speed_tiles * tile_size * 0.85
	velocity = dir * speed_pixels
	move_and_slide()
	if sprite and dir.length_squared() > 0:
		sprite.rotation = dir.angle()


func _plan_path_to(target_pos: Vector2) -> void:
	if nav_system and nav_system.has_method("build_path_points"):
		_waypoints = nav_system.build_path_points(global_position, target_pos)
	else:
		_waypoints = [target_pos]


func _follow_waypoints(delta: float) -> void:
	if _waypoints.is_empty():
		velocity = Vector2.ZERO
		return
	var waypoint := _waypoints[0]
	if global_position.distance_to(waypoint) <= 12.0:
		_waypoints.remove_at(0)
		if _waypoints.is_empty():
			velocity = Vector2.ZERO
			return
		waypoint = _waypoints[0]
	var dir := (waypoint - global_position).normalized()
	var tile_size: int = GameConfig.tile_size if GameConfig else 32
	var speed_pixels := speed_tiles * tile_size
	velocity = dir * speed_pixels
	move_and_slide()
	if sprite and dir.length_squared() > 0:
		sprite.rotation = dir.angle()


func _contact_damage_amount() -> int:
	var max_hp := GameConfig.player_max_hp if GameConfig else 100
	return maxi(1, int(ceil(float(max_hp) * 0.25)))


## Apply damage from any source (melee, projectile, etc.)
## Reduces HP, emits EventBus signals, handles death once.
func apply_damage(amount: int, source: String) -> void:
	if is_dead:
		return
	hp -= amount
	# Visual feedback (white flash per visual polish spec)
	if sprite:
		var flash_dur := GameConfig.hit_flash_duration if GameConfig else 0.06
		sprite.modulate = Color(3.0, 3.0, 3.0, 1.0)
		var tween := create_tween()
		tween.tween_property(sprite, "modulate", Color.WHITE, flash_dur)
	# Track stats
	if RuntimeState:
		RuntimeState.damage_dealt += amount
	# Emit damage event
	if EventBus:
		EventBus.emit_damage_dealt(entity_id, amount, source)
	if hp <= 0:
		die()


## Apply stagger (blocks movement for duration)
func apply_stagger(sec: float) -> void:
	stagger_timer = maxf(stagger_timer, sec)


## Apply knockback impulse
func apply_knockback(impulse: Vector2) -> void:
	knockback_vel = impulse


## Take damage (legacy, used by CombatSystem projectile pipeline)
func take_damage(amount: int) -> void:
	if is_dead:
		return

	hp -= amount

	# Visual feedback (white flash per visual polish spec)
	if sprite:
		var flash_dur := GameConfig.hit_flash_duration if GameConfig else 0.06
		sprite.modulate = Color(3.0, 3.0, 3.0, 1.0)
		var tween := create_tween()
		tween.tween_property(sprite, "modulate", Color.WHITE, flash_dur)

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


## Kill feedback: scale pop 1.0 → kill_pop_scale → 0 + fade
func _play_death_effect() -> void:
	if not sprite:
		call_deferred("_cleanup_after_death")
		return

	var pop_scale := GameConfig.kill_pop_scale if GameConfig else 1.2
	var pop_dur := GameConfig.kill_pop_duration if GameConfig else 0.1

	sprite.modulate = Color(3.0, 3.0, 3.0, 1.0)
	var tween := create_tween()
	# Scale pop: 1.0 → pop_scale
	tween.tween_property(sprite, "scale", Vector2(pop_scale, pop_scale), pop_dur * 0.5).set_ease(Tween.EASE_OUT)
	# Then shrink to 0 + fade
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2(0, 0), pop_dur * 0.5).set_ease(Tween.EASE_IN)
	tween.tween_property(sprite, "modulate:a", 0.0, pop_dur * 0.5)
	tween.set_parallel(false)
	tween.tween_callback(_cleanup_after_death)


func _on_hitbox_body_entered(body: Node2D) -> void:
	if is_dead:
		return

	# Check if it's the player
	if body.is_in_group("player"):
		_touching_player = true


func _on_hitbox_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_touching_player = false
