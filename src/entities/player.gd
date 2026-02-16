## player.gd
## Player entity with WASD movement and shooting.
## CANON: Movement is free (not grid-based), uses tile units for speed.
## CANON: Position stored as Vector3 in RuntimeState.
## CANON: ROTATE_SPRITE mode - sprite rotates to aim direction.
## Phase 3: Weapon switching via AbilitySystem.
extends CharacterBody2D

## Reference to sprite for rotation
@onready var sprite: Sprite2D = $Sprite2D

## Movement speed in tiles per second (from GameConfig)
var speed_tiles: float = 5.0

## Tile size in pixels (from GameConfig)
var tile_size: int = 32

## Current weapon type (kept for backward compat, reads from ability_system)
var current_weapon: String = "pistol"

## Weapon cooldown remaining (legacy fallback)
var _weapon_cooldown: float = 0.0

## Reference to ProjectileSystem (set by level, legacy fallback)
var projectile_system: Node = null

## Reference to AbilitySystem (set by level, Phase 3)
var ability_system: Node = null

const PLAYER_ACCEL_TIME_SEC := 1.0 / 3.0
const PLAYER_DECEL_TIME_SEC := 1.0 / 3.0

func _ready() -> void:
	print("[Player] Ready")
	add_to_group("player")
	safe_margin = 2.0
	_load_config()


func _load_config() -> void:
	if GameConfig:
		speed_tiles = GameConfig.player_speed_tiles
		tile_size = GameConfig.tile_size


func _physics_process(delta: float) -> void:
	# Check if gameplay is frozen
	if RuntimeState and RuntimeState.is_frozen:
		return

	# Get input direction
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		input_dir.y -= 1
	if Input.is_action_pressed("move_down"):
		input_dir.y += 1
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1

	# Normalize for consistent diagonal speed
	if input_dir.length_squared() > 0:
		input_dir = input_dir.normalized()

	# Calculate velocity in pixels/sec
	var speed_pixels := speed_tiles * tile_size
	var target_velocity := input_dir * speed_pixels
	if target_velocity.length_squared() > 0.0:
		var accel_per_sec := speed_pixels / maxf(PLAYER_ACCEL_TIME_SEC, 0.001)
		velocity = velocity.move_toward(target_velocity, accel_per_sec * delta)
	else:
		var decel_per_sec := speed_pixels / maxf(PLAYER_DECEL_TIME_SEC, 0.001)
		velocity = velocity.move_toward(Vector2.ZERO, decel_per_sec * delta)
		if velocity.length_squared() <= 1.0:
			velocity = Vector2.ZERO

	# Move
	move_and_slide()

	# Update RuntimeState position (CANON: Vector3)
	if RuntimeState:
		RuntimeState.player_pos = Vector3(global_position.x, global_position.y, 0)

	# Update aim direction and rotate sprite
	_update_aim()

	# Handle weapon switching (Phase 3)
	_handle_weapon_switch()

	# Handle shooting
	_handle_shooting(delta)


func _update_aim() -> void:
	# Get mouse position in world space
	var mouse_pos := get_global_mouse_position()

	# Calculate direction from player to mouse
	var aim_dir := (mouse_pos - position).normalized()

	# Store in RuntimeState (CANON: Vector3)
	if RuntimeState:
		RuntimeState.player_aim_dir = Vector3(aim_dir.x, aim_dir.y, 0)

	# CANON: ROTATE_SPRITE mode - rotate sprite to face aim direction
	if sprite and aim_dir.length_squared() > 0:
		sprite.rotation = aim_dir.angle()


## Phase 3: Weapon switching via mouse wheel and keys 1-6
func _handle_weapon_switch() -> void:
	if not ability_system:
		return

	# Mouse wheel
	if Input.is_action_just_pressed("weapon_next"):
		ability_system.cycle_weapon(1)
	elif Input.is_action_just_pressed("weapon_prev"):
		ability_system.cycle_weapon(-1)

	# Keys 1-6
	for i in range(6):
		var action := "weapon_%d" % (i + 1)
		if Input.is_action_just_pressed(action):
			ability_system.set_weapon_by_index(i)
			break


func _handle_shooting(delta: float) -> void:
	# Use AbilitySystem if available (Phase 3), else fallback to legacy
	if ability_system:
		if ability_system.has_method("tick_cooldown"):
			ability_system.tick_cooldown(delta)
		if Input.is_action_pressed("shoot"):
			var aim_dir := Vector2.ZERO
			if RuntimeState:
				aim_dir = Vector2(RuntimeState.player_aim_dir.x, RuntimeState.player_aim_dir.y)
			else:
				aim_dir = (get_global_mouse_position() - position).normalized()
			var spawn_pos := position + aim_dir * 20
			ability_system.try_fire(spawn_pos, aim_dir, 0.0)
		return

	# Legacy fallback (no ability system)
	if _weapon_cooldown > 0:
		_weapon_cooldown -= delta
	if Input.is_action_pressed("shoot") and _weapon_cooldown <= 0:
		_fire_weapon()


func _fire_weapon() -> void:
	if not projectile_system:
		return

	# Get aim direction
	var aim_dir := Vector2.ZERO
	if RuntimeState:
		aim_dir = Vector2(RuntimeState.player_aim_dir.x, RuntimeState.player_aim_dir.y)
	else:
		aim_dir = (get_global_mouse_position() - position).normalized()

	# Spawn position slightly in front of player
	var spawn_offset := aim_dir * 20  # 20 pixels in front
	var spawn_pos := position + spawn_offset

	# Fire through ProjectileSystem
	if projectile_system.has_method("fire_weapon"):
		projectile_system.fire_weapon(current_weapon, spawn_pos, aim_dir)

	# Set cooldown
	if projectile_system.has_method("get_weapon_cooldown"):
		_weapon_cooldown = projectile_system.get_weapon_cooldown(current_weapon)
	else:
		_weapon_cooldown = 0.33  # Default ~180 rpm

	# Emit event
	if EventBus:
		EventBus.emit_player_shot(current_weapon, Vector3(spawn_pos.x, spawn_pos.y, 0), RuntimeState.player_aim_dir if RuntimeState else Vector3.ZERO)


## Get current position as Vector3 (CANON)
func get_position_v3() -> Vector3:
	return Vector3(position.x, position.y, 0)


## Set position from Vector3 (CANON)
func set_position_v3(pos: Vector3) -> void:
	position = Vector2(pos.x, pos.y)


## Take damage (called by CombatSystem)
func take_damage(_amount: int) -> void:
	# Visual feedback
	if sprite:
		sprite.modulate = Color.RED
		var tween := create_tween()
		tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)
