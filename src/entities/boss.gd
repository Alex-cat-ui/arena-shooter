## boss.gd
## Boss entity for Phase 2.
## CANON: HP 500, size 9 tiles hitbox.
## CANON: Contact damage 50% player HP, no more often than 3 seconds.
## CANON: AoE attack radius 8 tiles, cooldown 1-2 seconds random.
## CANON: Boss does NOT chase player (attacks from distance).
class_name Boss
extends CharacterBody2D

## Boss stats per ТЗ v1.13
const BOSS_HP := 500
const BOSS_HITBOX_TILES := 9.0
const BOSS_CONTACT_DAMAGE_PERCENT := 0.5  # 50% of player max HP
const BOSS_CONTACT_IFRAMES := 3.0  # seconds
const BOSS_AOE_RADIUS_TILES := 8.0
const BOSS_AOE_COOLDOWN_MIN := 1.0
const BOSS_AOE_COOLDOWN_MAX := 2.0
const BOSS_AOE_DAMAGE := 25  # Damage per AoE hit

## Unique entity ID
var entity_id: int = 0

## Current HP
var hp: int = BOSS_HP

## Max HP
var max_hp: int = BOSS_HP

## Is boss dead?
var is_dead: bool = false

## AoE attack cooldown timer
var _aoe_cooldown: float = 0.0

## Contact damage cooldown (separate from normal enemy i-frames)
var _contact_cooldown: float = 0.0

## Is player currently in contact
var _player_in_contact: bool = false

## Reference to sprite
@onready var sprite: Sprite2D = $Sprite2D

## Reference to collision shape
@onready var collision: CollisionShape2D = $CollisionShape2D

## Reference to hitbox area (for player contact detection)
@onready var hitbox: Area2D = $Hitbox


func _ready() -> void:
	add_to_group("boss")

	# Connect hitbox signals
	if hitbox:
		hitbox.body_entered.connect(_on_hitbox_body_entered)
		hitbox.body_exited.connect(_on_hitbox_body_exited)

	# Set initial AoE cooldown
	_aoe_cooldown = randf_range(BOSS_AOE_COOLDOWN_MIN, BOSS_AOE_COOLDOWN_MAX)

	print("[Boss] Ready - HP: %d" % hp)


## Initialize boss with ID
func initialize(id: int) -> void:
	entity_id = id
	hp = BOSS_HP
	max_hp = BOSS_HP


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Check if frozen
	if RuntimeState and RuntimeState.is_frozen:
		return

	# Update contact cooldown
	if _contact_cooldown > 0:
		_contact_cooldown -= delta

	# Handle contact damage
	if _player_in_contact and _contact_cooldown <= 0:
		_apply_contact_damage()

	# Update AoE cooldown and attack
	_aoe_cooldown -= delta
	if _aoe_cooldown <= 0:
		_perform_aoe_attack()
		_aoe_cooldown = randf_range(BOSS_AOE_COOLDOWN_MIN, BOSS_AOE_COOLDOWN_MAX)


func _apply_contact_damage() -> void:
	## CANON: Contact damage is 50% of player max HP
	## CANON: No more often than once per 3 seconds (separate i-frames)
	if not GameConfig or not RuntimeState:
		return

	var damage := int(ceil(GameConfig.player_max_hp * BOSS_CONTACT_DAMAGE_PERCENT))

	# Get boss contact i-frames from config (or use default)
	var iframes_sec: float = GameConfig.boss_contact_iframes_sec if GameConfig else BOSS_CONTACT_IFRAMES
	_contact_cooldown = iframes_sec

	# Apply damage through CombatSystem via event
	# We emit a special boss contact event that bypasses normal enemy i-frames
	if EventBus:
		EventBus.emit_player_damaged(damage, maxi(0, RuntimeState.player_hp - damage), "boss_contact")

	# Update RuntimeState directly (CombatSystem will also update, but we do it here for immediate effect)
	if not GameConfig.god_mode:
		RuntimeState.player_hp = maxi(0, RuntimeState.player_hp - damage)
		RuntimeState.damage_received += damage

		if RuntimeState.player_hp <= 0:
			if EventBus:
				EventBus.emit_player_died()
			if StateManager:
				StateManager.change_state(GameState.State.GAME_OVER)

	print("[Boss] Contact damage: %d (player HP: %d)" % [damage, RuntimeState.player_hp])


func _perform_aoe_attack() -> void:
	## CANON: AoE attack centered on player position
	## CANON: Radius 8 tiles
	if not RuntimeState:
		return

	var player_pos := RuntimeState.player_pos
	var tile_size: int = GameConfig.tile_size if GameConfig else 32
	var aoe_radius_pixels := BOSS_AOE_RADIUS_TILES * tile_size

	# Check if player is within AoE radius
	var boss_pos := Vector3(position.x, position.y, 0)
	var player_pos_2d := Vector2(player_pos.x, player_pos.y)
	var distance := position.distance_to(player_pos_2d)

	# Emit AoE attack event (for VFX)
	if EventBus:
		EventBus.emit_boss_aoe_attack(player_pos, BOSS_AOE_RADIUS_TILES)

	# Player takes damage if within AoE (AoE is always at player position per spec)
	# Since AoE centers on player, player always gets hit
	if not GameConfig.god_mode:
		if EventBus:
			EventBus.emit_player_damaged(BOSS_AOE_DAMAGE, maxi(0, RuntimeState.player_hp - BOSS_AOE_DAMAGE), "boss_aoe")

		RuntimeState.player_hp = maxi(0, RuntimeState.player_hp - BOSS_AOE_DAMAGE)
		RuntimeState.damage_received += BOSS_AOE_DAMAGE

		if RuntimeState.player_hp <= 0:
			if EventBus:
				EventBus.emit_player_died()
			if StateManager:
				StateManager.change_state(GameState.State.GAME_OVER)

	print("[Boss] AoE attack at player position - damage: %d" % BOSS_AOE_DAMAGE)


## Take damage
func take_damage(amount: int) -> void:
	if is_dead:
		return

	var old_hp := hp
	hp -= amount

	# Visual feedback (flash red)
	if sprite:
		sprite.modulate = Color.RED
		var tween := create_tween()
		tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)

	# Emit damage event
	if EventBus:
		EventBus.emit_boss_damaged(entity_id, amount, hp)

	print("[Boss] Took %d damage (HP: %d -> %d)" % [amount, old_hp, hp])

	# Check death
	if hp <= 0:
		die()


## Boss death - triggers LEVEL_COMPLETE
func die() -> void:
	if is_dead:
		return

	is_dead = true

	print("[Boss] Defeated!")

	# Emit kill event
	if EventBus:
		EventBus.emit_boss_killed(entity_id)

	# Disable collision
	if collision:
		collision.set_deferred("disabled", true)
	if hitbox:
		hitbox.set_deferred("monitoring", false)

	# Visual death effect
	if sprite:
		sprite.modulate = Color(0.2, 0.1, 0.1, 0.8)
		var tween := create_tween()
		tween.tween_property(sprite, "modulate:a", 0.0, 1.0)
		tween.tween_callback(queue_free)

	# Note: LEVEL_COMPLETE transition is handled by level_mvp.gd listening to boss_killed event


func _on_hitbox_body_entered(body: Node2D) -> void:
	if is_dead:
		return

	if body.is_in_group("player"):
		_player_in_contact = true


func _on_hitbox_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_contact = false


## Get current position as Vector3 (CANON)
func get_position_v3() -> Vector3:
	return Vector3(position.x, position.y, 0)
