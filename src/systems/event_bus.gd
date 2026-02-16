## event_bus.gd
## EventBus for Phase 1 - Core Gameplay.
## CANON: Systems MUST NOT call each other directly - use EventBus.
## CANON: Deterministic order - priority HIGH/NORMAL/LOW, within priority FIFO.
## CANON: No direct recursive event calls - use event queue flushed per frame.
extends Node

const GAME_STATE_SCRIPT := preload("res://src/core/game_state.gd")

## Event priorities
enum Priority {
	HIGH = 0,
	NORMAL = 1,
	LOW = 2
}

## ============================================================================
## SIGNALS - State & Level
## ============================================================================

## State changed event
signal state_changed(old_state: GAME_STATE_SCRIPT.State, new_state: GAME_STATE_SCRIPT.State)

## Level started event (after bootstrap complete)
signal level_started()

## Mission changed in the same level scene (north transition)
signal mission_transitioned(mission_index: int)

## Level ended event (game over or complete)
signal level_ended(is_victory: bool)

## Start delay finished
signal start_delay_finished()

## ============================================================================
## SIGNALS - Enemy
## ============================================================================

## Enemy spawned
signal enemy_spawned(enemy_id: int, enemy_type: String, position: Vector3)

## Enemy killed
signal enemy_killed(enemy_id: int, enemy_type: String)

## Enemy reached player (for contact damage)
signal enemy_contact(enemy_id: int, enemy_type: String, damage: int)

## Enemy fired weapon (for SFX/AI reactions)
signal enemy_shot(enemy_id: int, weapon_type: String, position: Vector3, direction: Vector3)

## Enemy spotted player (first visual detection in a visibility episode)
signal enemy_player_spotted(enemy_id: int, position: Vector3)

## Enemy awareness state changed (CALM/ALERT/COMBAT)
signal enemy_state_changed(enemy_id: int, from_state: String, to_state: String, room_id: int, reason: String)

## Enemy called reinforcement for room group
signal enemy_reinforcement_called(source_enemy_id: int, source_room_id: int, target_room_ids: Array)

## ============================================================================
## SIGNALS - Player
## ============================================================================

## Player damaged event
signal player_damaged(amount: int, new_hp: int, source: String)

## Player died event
signal player_died()

## Player shot (for stats/effects)
signal player_shot(weapon_type: String, position: Vector3, direction: Vector3)

## ============================================================================
## SIGNALS - Projectile
## ============================================================================

## Projectile spawned
signal projectile_spawned(projectile_id: int, projectile_type: String, position: Vector3)

## Projectile hit enemy
signal projectile_hit(projectile_id: int, enemy_id: int, damage: int, projectile_type: String, shot_id: int, shot_total_pellets: int, shot_total_damage: float)

## Projectile destroyed (TTL or collision)
signal projectile_destroyed(projectile_id: int, reason: String)

## ============================================================================
## SIGNALS - Combat (Damage Pipeline)
## ============================================================================

## Damage dealt (after all modifiers)
signal damage_dealt(target_id: int, amount: int, source: String)

## ============================================================================
## SIGNALS - VFX (Phase 2)
## ============================================================================

## Blood decal spawned
signal blood_spawned(position: Vector3, size: float)

## Corpse spawned
signal corpse_spawned(position: Vector3, enemy_type: String, rotation: float)

## Corpses baked (limit reached)
signal corpses_baked(count: int)

## Footprint spawned
signal footprint_spawned(position: Vector3, rotation: float)

## ============================================================================
## SIGNALS - Weapons & Polish (Phase 3)
## ============================================================================

## Weapon changed by player
signal weapon_changed(weapon_name: String, weapon_index: int)

## Rocket exploded (for camera shake)
signal rocket_exploded(position: Vector3)

## Chain lightning arc hit (for VFX)
signal chain_lightning_hit(origin: Vector3, target: Vector3)

## ============================================================================
## INTERNAL STATE
## ============================================================================

## Event queue for deferred processing
var _event_queue: Array[Dictionary] = []

## Is currently processing queue (prevent recursion)
var _is_processing: bool = false


## ============================================================================
## PUBLIC API - State & Level
## ============================================================================

func emit_state_changed(old_state: GAME_STATE_SCRIPT.State, new_state: GAME_STATE_SCRIPT.State) -> void:
	_queue_event("state_changed", [old_state, new_state])

func emit_level_started() -> void:
	_queue_event("level_started", [])

func emit_mission_transitioned(mission_index: int) -> void:
	_queue_event("mission_transitioned", [mission_index])

func emit_level_ended(is_victory: bool) -> void:
	_queue_event("level_ended", [is_victory])

func emit_start_delay_finished() -> void:
	_queue_event("start_delay_finished", [])

## ============================================================================
## PUBLIC API - Enemy
## ============================================================================

func emit_enemy_spawned(enemy_id: int, enemy_type: String, position: Vector3) -> void:
	_queue_event("enemy_spawned", [enemy_id, enemy_type, position])

func emit_enemy_killed(enemy_id: int, enemy_type: String) -> void:
	_queue_event("enemy_killed", [enemy_id, enemy_type], Priority.HIGH)

func emit_enemy_contact(enemy_id: int, enemy_type: String, damage: int) -> void:
	_queue_event("enemy_contact", [enemy_id, enemy_type, damage])

func emit_enemy_shot(enemy_id: int, weapon_type: String, position: Vector3, direction: Vector3) -> void:
	_queue_event("enemy_shot", [enemy_id, weapon_type, position, direction])

func emit_enemy_player_spotted(enemy_id: int, position: Vector3) -> void:
	_queue_event("enemy_player_spotted", [enemy_id, position], Priority.HIGH)

func emit_enemy_state_changed(enemy_id: int, from_state: String, to_state: String, room_id: int, reason: String) -> void:
	_queue_event("enemy_state_changed", [enemy_id, from_state, to_state, room_id, reason], Priority.HIGH)

func emit_enemy_reinforcement_called(source_enemy_id: int, source_room_id: int, target_room_ids: Array) -> void:
	_queue_event("enemy_reinforcement_called", [source_enemy_id, source_room_id, target_room_ids.duplicate()], Priority.HIGH)

## ============================================================================
## PUBLIC API - Player
## ============================================================================

func emit_player_damaged(amount: int, new_hp: int, source: String = "unknown") -> void:
	_queue_event("player_damaged", [amount, new_hp, source])

func emit_player_died() -> void:
	_queue_event("player_died", [], Priority.HIGH)

func emit_player_shot(weapon_type: String, position: Vector3, direction: Vector3) -> void:
	_queue_event("player_shot", [weapon_type, position, direction])

## ============================================================================
## PUBLIC API - Projectile
## ============================================================================

func emit_projectile_spawned(projectile_id: int, projectile_type: String, position: Vector3) -> void:
	_queue_event("projectile_spawned", [projectile_id, projectile_type, position])

func emit_projectile_hit(projectile_id: int, enemy_id: int, damage: int, projectile_type: String = "", shot_id: int = -1, shot_total_pellets: int = 0, shot_total_damage: float = 0.0) -> void:
	_queue_event("projectile_hit", [projectile_id, enemy_id, damage, projectile_type, shot_id, shot_total_pellets, shot_total_damage])

func emit_projectile_destroyed(projectile_id: int, reason: String) -> void:
	_queue_event("projectile_destroyed", [projectile_id, reason])

## ============================================================================
## PUBLIC API - Combat
## ============================================================================

func emit_damage_dealt(target_id: int, amount: int, source: String) -> void:
	_queue_event("damage_dealt", [target_id, amount, source])

## ============================================================================
## PUBLIC API - VFX (Phase 2)
## ============================================================================

func emit_blood_spawned(position: Vector3, size: float) -> void:
	_queue_event("blood_spawned", [position, size])

func emit_corpse_spawned(position: Vector3, enemy_type: String, rotation: float) -> void:
	_queue_event("corpse_spawned", [position, enemy_type, rotation])

func emit_corpses_baked(count: int) -> void:
	_queue_event("corpses_baked", [count])

func emit_footprint_spawned(position: Vector3, rotation: float) -> void:
	_queue_event("footprint_spawned", [position, rotation])

## ============================================================================
## PUBLIC API - Weapons & Polish (Phase 3)
## ============================================================================

func emit_weapon_changed(weapon_name: String, weapon_index: int) -> void:
	_queue_event("weapon_changed", [weapon_name, weapon_index])

func emit_rocket_exploded(position: Vector3) -> void:
	_queue_event("rocket_exploded", [position], Priority.HIGH)

func emit_chain_lightning_hit(origin: Vector3, target: Vector3) -> void:
	_queue_event("chain_lightning_hit", [origin, target])

## ============================================================================
## INTERNAL METHODS
## ============================================================================

## Queue an event for processing
func _queue_event(event_name: String, args: Array, priority: Priority = Priority.NORMAL) -> void:
	_event_queue.append({
		"name": event_name,
		"args": args,
		"priority": priority,
		"order": _event_queue.size()
	})


## Process queued events (called each frame)
func _process(_delta: float) -> void:
	if _is_processing or _event_queue.is_empty():
		return

	_is_processing = true

	# Sort by priority, then by order (FIFO)
	_event_queue.sort_custom(_compare_events)

	# Process all queued events
	var events_to_process := _event_queue.duplicate()
	_event_queue.clear()

	for event in events_to_process:
		_dispatch_event(event)

	_is_processing = false


## Compare events for sorting (priority first, then FIFO order)
func _compare_events(a: Dictionary, b: Dictionary) -> bool:
	if a["priority"] != b["priority"]:
		return int(a["priority"]) < int(b["priority"])
	return int(a["order"]) < int(b["order"])


## Dispatch a single event
func _dispatch_event(event: Dictionary) -> void:
	match event.name:
		# State & Level
		"state_changed":
			state_changed.emit(event.args[0], event.args[1])
		"level_started":
			level_started.emit()
		"mission_transitioned":
			mission_transitioned.emit(event.args[0])
		"level_ended":
			level_ended.emit(event.args[0])
		"start_delay_finished":
			start_delay_finished.emit()
		# Enemy
		"enemy_spawned":
			enemy_spawned.emit(event.args[0], event.args[1], event.args[2])
		"enemy_killed":
			enemy_killed.emit(event.args[0], event.args[1])
		"enemy_contact":
			enemy_contact.emit(event.args[0], event.args[1], event.args[2])
		"enemy_shot":
			enemy_shot.emit(event.args[0], event.args[1], event.args[2], event.args[3])
		"enemy_player_spotted":
			enemy_player_spotted.emit(event.args[0], event.args[1])
		"enemy_state_changed":
			enemy_state_changed.emit(event.args[0], event.args[1], event.args[2], event.args[3], event.args[4])
		"enemy_reinforcement_called":
			enemy_reinforcement_called.emit(event.args[0], event.args[1], event.args[2])
		# Player
		"player_damaged":
			player_damaged.emit(event.args[0], event.args[1], event.args[2])
		"player_died":
			player_died.emit()
		"player_shot":
			player_shot.emit(event.args[0], event.args[1], event.args[2])
		# Projectile
		"projectile_spawned":
			projectile_spawned.emit(event.args[0], event.args[1], event.args[2])
		"projectile_hit":
			projectile_hit.emit(event.args[0], event.args[1], event.args[2], event.args[3], event.args[4], event.args[5], event.args[6])
		"projectile_destroyed":
			projectile_destroyed.emit(event.args[0], event.args[1])
		# Combat
		"damage_dealt":
			damage_dealt.emit(event.args[0], event.args[1], event.args[2])
		# VFX (Phase 2)
		"blood_spawned":
			blood_spawned.emit(event.args[0], event.args[1])
		"corpse_spawned":
			corpse_spawned.emit(event.args[0], event.args[1], event.args[2])
		"corpses_baked":
			corpses_baked.emit(event.args[0])
		"footprint_spawned":
			footprint_spawned.emit(event.args[0], event.args[1])
		# Weapons & Polish (Phase 3)
		"weapon_changed":
			weapon_changed.emit(event.args[0], event.args[1])
		"rocket_exploded":
			rocket_exploded.emit(event.args[0])
		"chain_lightning_hit":
			chain_lightning_hit.emit(event.args[0], event.args[1])
		_:
			push_warning("Unknown event: %s" % event.name)
