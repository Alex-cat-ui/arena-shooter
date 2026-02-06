## boss.gd
## Boss entity for Phase 2.
## CANON: HP 500, size 9 tiles hitbox.
## CANON: Contact damage 50% player HP, cooldown 3 seconds (separate from global i-frames).
## CANON: AoE attack radius 8 tiles from BOSS position, cooldown 1-2 seconds random.
## CANON: Boss does NOT constantly damage player - only via contact and discrete AoE.
class_name Boss
extends CharacterBody2D

## Boss stats per ТЗ v1.13
const BOSS_HP := 500
const BOSS_HITBOX_TILES := 9.0
const BOSS_CONTACT_DAMAGE_PERCENT := 0.5  # 50% of player max HP
const BOSS_CONTACT_IFRAMES := 3.0  # seconds (boss-specific, NOT global)
const BOSS_AOE_RADIUS_TILES := 8.0
const BOSS_AOE_COOLDOWN_MIN := 1.0
const BOSS_AOE_COOLDOWN_MAX := 2.0
const BOSS_AOE_DAMAGE := 25  # Damage per AoE hit

## Minimum spawn distance from player (in tiles)
const BOSS_MIN_SPAWN_DISTANCE_TILES := 10.0

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

## Contact damage cooldown (SEPARATE from global enemy i-frames per CANON)
var _contact_cooldown: float = 0.0

## Is player currently in contact with boss hitbox
var _player_in_contact: bool = false

## Reference to sprite
@onready var sprite: Sprite2D = $Sprite2D

## Reference to collision shape
@onready var collision: CollisionShape2D = $CollisionShape2D

## Reference to hitbox area (for player contact detection)
@onready var hitbox: Area2D = $Hitbox


func _ready() -> void:
	add_to_group("boss")

	# Connect hitbox signals for contact detection
	if hitbox:
		hitbox.body_entered.connect(_on_hitbox_body_entered)
		hitbox.body_exited.connect(_on_hitbox_body_exited)

	# Set initial AoE cooldown (randomized)
	_aoe_cooldown = randf_range(BOSS_AOE_COOLDOWN_MIN, BOSS_AOE_COOLDOWN_MAX)

	print("[Boss] Ready - HP: %d, AoE cooldown: %.2f" % [hp, _aoe_cooldown])


## Initialize boss with ID
func initialize(id: int) -> void:
	entity_id = id
	hp = BOSS_HP
	max_hp = BOSS_HP
	_contact_cooldown = 0.0
	_aoe_cooldown = randf_range(BOSS_AOE_COOLDOWN_MIN, BOSS_AOE_COOLDOWN_MAX)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Check if frozen (paused)
	if RuntimeState and RuntimeState.is_frozen:
		return

	# ========================================================================
	# CONTACT DAMAGE SYSTEM (CANON)
	# - Only when player collider overlaps boss collider
	# - Damage = 50% player max HP
	# - Cooldown = 3 seconds (boss-specific timer, NOT global i-frames)
	# ========================================================================
	if _contact_cooldown > 0:
		_contact_cooldown -= delta

	if _player_in_contact and _contact_cooldown <= 0:
		_apply_contact_damage()

	# ========================================================================
	# AoE ATTACK SYSTEM (CANON)
	# - Cooldown randomly 1-2 seconds
	# - AoE centered on BOSS position
	# - Damage only if player distance <= radius
	# - Fires ONCE per attack (not every frame)
	# ========================================================================
	_aoe_cooldown -= delta
	if _aoe_cooldown <= 0:
		_perform_aoe_attack()
		# Reset cooldown for next attack
		_aoe_cooldown = randf_range(BOSS_AOE_COOLDOWN_MIN, BOSS_AOE_COOLDOWN_MAX)


func _apply_contact_damage() -> void:
	## CANON: Contact damage is 50% of player max HP
	## CANON: Cooldown 3 seconds (boss_contact_timer, NOT global i-frames)
	## CANON: Only triggers when player overlaps boss hitbox
	if not GameConfig or not RuntimeState:
		return

	# Check GodMode
	if GameConfig.god_mode:
		print("[Boss] Contact blocked - GodMode active | time=%.2f" % (Time.get_ticks_msec() / 1000.0))
		return

	var damage := int(ceil(GameConfig.player_max_hp * BOSS_CONTACT_DAMAGE_PERCENT))

	# Set boss-specific contact cooldown (NOT global i-frames)
	var iframes_sec: float = GameConfig.boss_contact_iframes_sec if GameConfig else BOSS_CONTACT_IFRAMES
	_contact_cooldown = iframes_sec

	# Apply damage to player
	var old_hp := RuntimeState.player_hp
	RuntimeState.player_hp = maxi(0, RuntimeState.player_hp - damage)
	RuntimeState.damage_received += damage

	# Debug logging per spec
	print("[Boss] CONTACT damage: %d | player HP: %d -> %d | cooldown: %.1fs | time=%.2f" % [
		damage, old_hp, RuntimeState.player_hp, iframes_sec, Time.get_ticks_msec() / 1000.0
	])

	# Emit event for UI/stats
	if EventBus:
		EventBus.emit_player_damaged(damage, RuntimeState.player_hp, "boss_contact")

	# Check player death
	if RuntimeState.player_hp <= 0:
		print("[Boss] Player killed by contact damage")
		if EventBus:
			EventBus.emit_player_died()
		if StateManager:
			StateManager.change_state(GameState.State.GAME_OVER)


func _perform_aoe_attack() -> void:
	## CANON: AoE attack centered on BOSS position (NOT player)
	## CANON: Radius 8 tiles
	## CANON: Player takes damage ONLY if within radius
	## CANON: Fires ONCE per attack event (NOT every frame)
	if not RuntimeState or not GameConfig:
		return

	var tile_size: int = GameConfig.tile_size if GameConfig else 32
	var aoe_radius_pixels: float = BOSS_AOE_RADIUS_TILES * tile_size

	# Get positions
	var boss_pos_2d := position
	var player_pos_2d := Vector2(RuntimeState.player_pos.x, RuntimeState.player_pos.y)

	# Calculate distance from boss to player
	var distance := boss_pos_2d.distance_to(player_pos_2d)

	# Emit AoE attack event for VFX (always, to show the attack animation)
	if EventBus:
		var boss_pos_v3 := Vector3(boss_pos_2d.x, boss_pos_2d.y, 0)
		EventBus.emit_boss_aoe_attack(boss_pos_v3, BOSS_AOE_RADIUS_TILES)

	# Check if player is within AoE radius
	if distance > aoe_radius_pixels:
		# Player is OUTSIDE AoE range - no damage
		print("[Boss] AoE attack MISSED | player distance: %.0f > radius: %.0f | time=%.2f" % [
			distance, aoe_radius_pixels, Time.get_ticks_msec() / 1000.0
		])
		return

	# Check GodMode
	if GameConfig.god_mode:
		print("[Boss] AoE blocked - GodMode active | time=%.2f" % (Time.get_ticks_msec() / 1000.0))
		return

	# Player is within AoE - apply damage ONCE
	var old_hp := RuntimeState.player_hp
	RuntimeState.player_hp = maxi(0, RuntimeState.player_hp - BOSS_AOE_DAMAGE)
	RuntimeState.damage_received += BOSS_AOE_DAMAGE

	# Debug logging per spec
	print("[Boss] AoE damage: %d | player HP: %d -> %d | distance: %.0f | time=%.2f" % [
		BOSS_AOE_DAMAGE, old_hp, RuntimeState.player_hp, distance, Time.get_ticks_msec() / 1000.0
	])

	# Emit event for UI/stats
	if EventBus:
		EventBus.emit_player_damaged(BOSS_AOE_DAMAGE, RuntimeState.player_hp, "boss_aoe")

	# Check player death
	if RuntimeState.player_hp <= 0:
		print("[Boss] Player killed by AoE damage")
		if EventBus:
			EventBus.emit_player_died()
		if StateManager:
			StateManager.change_state(GameState.State.GAME_OVER)


## Take damage from projectiles
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
		print("[Boss] Player entered contact zone | time=%.2f" % (Time.get_ticks_msec() / 1000.0))


func _on_hitbox_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_contact = false
		print("[Boss] Player exited contact zone | time=%.2f" % (Time.get_ticks_msec() / 1000.0))


## Get current position as Vector3 (CANON)
func get_position_v3() -> Vector3:
	return Vector3(position.x, position.y, 0)


## Static helper: Get valid spawn position for boss (>= 10 tiles from player)
static func get_safe_spawn_position(player_pos: Vector2, arena_min: Vector2, arena_max: Vector2, tile_size: int) -> Vector2:
	var min_distance: float = BOSS_MIN_SPAWN_DISTANCE_TILES * tile_size

	# Try to find valid position
	for attempt in range(20):
		var x := randf_range(arena_min.x, arena_max.x)
		var y := randf_range(arena_min.y, arena_max.y)
		var pos := Vector2(x, y)

		if pos.distance_to(player_pos) >= min_distance:
			return pos

	# Fallback: spawn at furthest corner from player
	var corners: Array[Vector2] = [
		arena_min,
		Vector2(arena_max.x, arena_min.y),
		Vector2(arena_min.x, arena_max.y),
		arena_max
	]

	var best_pos := corners[0]
	var best_dist := 0.0
	for corner in corners:
		var dist := corner.distance_to(player_pos)
		if dist > best_dist:
			best_dist = dist
			best_pos = corner

	return best_pos
