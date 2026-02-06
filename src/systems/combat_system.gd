## combat_system.gd
## CombatSystem handles all damage application.
## CANON: Contact damage with global i-frames (0.7s).
## CANON: Respects GodMode.
## CANON: All damage passes through DamagePipeline.
class_name CombatSystem
extends Node

## Reference to player node (set by level)
var player_node: Node2D = null

## Global i-frame timer for contact damage
var _contact_iframes_remaining: float = 0.0

## Pending contact damages this frame (to select max)
var _pending_contact_damages: Array[Dictionary] = []


func _ready() -> void:
	# Subscribe to events
	if EventBus:
		EventBus.enemy_contact.connect(_on_enemy_contact)
		EventBus.projectile_hit.connect(_on_projectile_hit)


## Update called each frame
func update(delta: float) -> void:
	# Update i-frame timer
	if _contact_iframes_remaining > 0:
		_contact_iframes_remaining -= delta

	# Process pending contact damages (select max)
	if not _pending_contact_damages.is_empty() and _contact_iframes_remaining <= 0:
		_process_contact_damage()
		_pending_contact_damages.clear()
	else:
		_pending_contact_damages.clear()


## ============================================================================
## DAMAGE PIPELINE
## ============================================================================

## Apply damage to player
func damage_player(amount: int, source: String) -> void:
	if not RuntimeState:
		return

	# Check invulnerability (dash slash i-frames)
	if RuntimeState.is_player_invulnerable:
		return

	# Check GodMode
	if GameConfig and GameConfig.god_mode:
		print("[CombatSystem] GodMode active - damage blocked")
		return

	# Apply damage
	var old_hp := RuntimeState.player_hp
	RuntimeState.player_hp = maxi(0, RuntimeState.player_hp - amount)
	var new_hp := RuntimeState.player_hp

	# Track stats
	RuntimeState.damage_received += amount

	# Emit event
	if EventBus:
		EventBus.emit_player_damaged(amount, new_hp, source)

	print("[CombatSystem] Player took %d damage from %s (HP: %d -> %d)" % [amount, source, old_hp, new_hp])

	# Check death
	if new_hp <= 0:
		_player_died()


## Apply damage to enemy
func damage_enemy(enemy: Node, amount: int, source: String) -> void:
	if not enemy or not enemy.has_method("take_damage"):
		return

	# Track stats
	if RuntimeState:
		RuntimeState.damage_dealt += amount

	# Apply damage
	enemy.take_damage(amount)

	# Emit event
	if EventBus and "entity_id" in enemy:
		EventBus.emit_damage_dealt(enemy.entity_id, amount, source)


## ============================================================================
## CONTACT DAMAGE (CANON: i-frames)
## ============================================================================

func _on_enemy_contact(enemy_id: int, enemy_type: String, damage: int) -> void:
	## CANON: Contact damage uses global i-frames
	## Every 0.7s apply damage_tick from ONE source (max damage)
	_pending_contact_damages.append({
		"enemy_id": enemy_id,
		"enemy_type": enemy_type,
		"damage": damage
	})


func _process_contact_damage() -> void:
	if _pending_contact_damages.is_empty():
		return

	# Find max damage among touching enemies (CANON)
	var max_damage := 0
	var max_source := "contact"
	for contact in _pending_contact_damages:
		if contact.damage > max_damage:
			max_damage = contact.damage
			max_source = "contact_%s" % contact.enemy_type

	# Calculate damage tick: Damage(type) * 0.7
	# Actually per ТЗ: DPS = Damage(type) HP/sec, tick = Damage * 0.7
	var iframes_sec: float = GameConfig.contact_iframes_sec if GameConfig else 0.7
	var damage_tick := int(ceil(max_damage * iframes_sec))

	# Apply damage
	damage_player(damage_tick, max_source)

	# Reset i-frames
	_contact_iframes_remaining = iframes_sec


## ============================================================================
## PROJECTILE DAMAGE
## ============================================================================

func _on_projectile_hit(projectile_id: int, enemy_id: int, damage: int) -> void:
	# Find enemy by ID
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if "entity_id" in enemy and enemy.entity_id == enemy_id:
			damage_enemy(enemy, damage, "projectile_%d" % projectile_id)
			break


## ============================================================================
## PLAYER DEATH
## ============================================================================

func _player_died() -> void:
	print("[CombatSystem] Player died!")

	if EventBus:
		EventBus.emit_player_died()

	# Transition to GAME_OVER
	if StateManager:
		StateManager.change_state(GameState.State.GAME_OVER)
