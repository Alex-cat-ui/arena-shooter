## combat_system.gd
## CombatSystem handles all damage application.
## CANON: Contact damage with global i-frames (0.7s).
## CANON: Respects GodMode.
## CANON: All damage passes through DamagePipeline.
class_name CombatSystem
extends Node

const SHOTGUN_DAMAGE_MODEL_SCRIPT := preload("res://src/systems/shotgun_damage_model.gd")
const SHOT_RECORD_TTL_MS := 5000
const SHOT_RECORD_CLEANUP_INTERVAL_SEC := 1.0

## Reference to player node (set by level)
var player_node: Node2D = null

## Global i-frame timer for contact damage
var _contact_iframes_remaining: float = 0.0

## Pending contact damages this frame (to select max)
var _pending_contact_damages: Array[Dictionary] = []
var _pellet_shot_enemy_records: Dictionary = {}
var _shot_record_cleanup_timer: float = 0.0


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

	_shot_record_cleanup_timer += delta
	if _shot_record_cleanup_timer >= SHOT_RECORD_CLEANUP_INTERVAL_SEC:
		_shot_record_cleanup_timer = 0.0
		_cleanup_old_shot_records()


## ============================================================================
## DAMAGE PIPELINE
## ============================================================================

## Apply damage to player
func damage_player(amount: int, source: String) -> void:
	if not RuntimeState:
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

	# Contact damage is already precomputed by enemy logic.
	# Keep at most one contact tick per second globally to avoid burst stacking.
	var iframes_sec: float = maxf(GameConfig.contact_iframes_sec if GameConfig else 0.7, 1.0)
	var damage_tick := int(max_damage)

	# Apply damage
	damage_player(damage_tick, max_source)

	# Reset i-frames
	_contact_iframes_remaining = iframes_sec


## ============================================================================
## PROJECTILE DAMAGE
## ============================================================================

func _on_projectile_hit(projectile_id: int, enemy_id: int, damage: int, projectile_type: String = "", shot_id: int = -1, shot_total_pellets: int = 0, shot_total_damage: float = 0.0) -> void:
	# Find enemy by ID
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if "entity_id" in enemy and enemy.entity_id == enemy_id:
			if projectile_type == "pellet":
				_apply_pellet_hit_to_enemy(enemy, projectile_id, shot_id, shot_total_pellets, shot_total_damage, damage)
				return
			if damage <= 0:
				return
			damage_enemy(enemy, damage, "projectile_%d" % projectile_id)
			break


func _apply_pellet_hit_to_enemy(enemy: Node, projectile_id: int, shot_id: int, shot_total_pellets: int, shot_total_damage: float, fallback_damage: int) -> void:
	var pellets_total := maxi(shot_total_pellets, 1)
	if shot_id < 0 or shot_total_pellets <= 0:
		var direct_damage := maxi(fallback_damage, 1)
		damage_enemy(enemy, direct_damage, "projectile_%d" % projectile_id)
		return

	var enemy_id := int(enemy.entity_id)
	var key := "%d|%d" % [shot_id, enemy_id]
	var now_ms := Time.get_ticks_msec()
	var rec := _pellet_shot_enemy_records.get(key, {
		"hits": 0,
		"damage_applied": 0,
		"lethal_applied": false,
		"last_ms": now_ms,
	}) as Dictionary
	if bool(rec.get("lethal_applied", false)):
		_pellet_shot_enemy_records.erase(key)
		return

	var hits := int(rec.get("hits", 0)) + 1
	rec["hits"] = hits
	rec["last_ms"] = now_ms

	var source := "projectile_%d" % projectile_id
	if SHOTGUN_DAMAGE_MODEL_SCRIPT.is_lethal_hits(hits, pellets_total):
		var lethal_damage := _enemy_lethal_damage(enemy)
		if lethal_damage > 0:
			damage_enemy(enemy, lethal_damage, source)
		rec["lethal_applied"] = true
		_pellet_shot_enemy_records.erase(key)
		return

	var target_damage := SHOTGUN_DAMAGE_MODEL_SCRIPT.damage_for_hits(hits, pellets_total, shot_total_damage)
	var already_applied := int(rec.get("damage_applied", 0))
	var delta := maxi(target_damage - already_applied, 0)
	if delta > 0:
		damage_enemy(enemy, delta, source)
		rec["damage_applied"] = already_applied + delta

	if hits >= pellets_total:
		_pellet_shot_enemy_records.erase(key)
		return

	_pellet_shot_enemy_records[key] = rec


func _enemy_lethal_damage(enemy: Node) -> int:
	if "hp" in enemy:
		return maxi(int(enemy.hp), 1)
	return 9999


func _cleanup_old_shot_records() -> void:
	if _pellet_shot_enemy_records.is_empty():
		return
	var now_ms := Time.get_ticks_msec()
	var keys := _pellet_shot_enemy_records.keys()
	for key_variant in keys:
		var key := key_variant as String
		if not _pellet_shot_enemy_records.has(key):
			continue
		var rec := _pellet_shot_enemy_records[key] as Dictionary
		var last_ms := int(rec.get("last_ms", 0))
		if now_ms - last_ms > SHOT_RECORD_TTL_MS:
			_pellet_shot_enemy_records.erase(key)


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
