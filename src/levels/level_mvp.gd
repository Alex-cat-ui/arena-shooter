## level_mvp.gd
## MVP level controller - Phase 1 + Phase 3 (Arena Polish + Weapons).
## CANON: Camera is TOP-DOWN ORTHOGRAPHIC, no rotation.
## CANON: ESC toggles pause, F1/F2 for debug state changes.
## CANON: StartDelaySec - player CAN move, enemies MUST NOT spawn.
extends Node2D

## Scene references
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const BOSS_SCENE := preload("res://scenes/entities/boss.tscn")

## Node references
@onready var player: CharacterBody2D = $Entities/Player
@onready var camera: Camera2D = $Camera2D
@onready var hud: CanvasLayer = $HUD
@onready var hp_label: Label = $HUD/HUDContainer/HPLabel
@onready var state_label: Label = $HUD/HUDContainer/StateLabel
@onready var wave_label: Label = $HUD/HUDContainer/WaveLabel
@onready var time_label: Label = $HUD/HUDContainer/TimeLabel
@onready var boss_hp_label: Label = $HUD/HUDContainer/BossHPLabel
@onready var weapon_label: Label = $HUD/HUDContainer/WeaponLabel

## Container nodes
@onready var entities_container: Node2D = $Entities
@onready var projectiles_container: Node2D = $Projectiles
@onready var decals_container: Node2D = $Decals
@onready var corpses_container: Node2D = $Corpses
@onready var footprints_container: Node2D = $Footprints

## Systems (Phase 1-2)
var wave_manager: WaveManager = null
var combat_system: CombatSystem = null
var projectile_system: ProjectileSystem = null
var vfx_system: VFXSystem = null
var footprint_system: FootprintSystem = null

## Systems (Phase 3: Arena Polish + Weapons)
var ability_system: AbilitySystem = null
var camera_shake: CameraShake = null
var wave_overlay: WaveOverlay = null
var arena_boundary: ArenaBoundary = null

## Systems (Phase 4: Katana / Melee)
var melee_system: MeleeSystem = null

## Start delay timer
var _start_delay_timer: float = 0.0
var _start_delay_finished: bool = false

## Arena bounds
var _arena_min := Vector2(-500, -500)
var _arena_max := Vector2(500, 500)


func _ready() -> void:
	print("[LevelMVP] Ready - Phase 3")

	# CANON: Camera must not rotate
	camera.rotation = 0

	# Initialize RuntimeState
	_init_runtime_state()

	# Initialize systems
	_init_systems()

	# Connect player to systems
	if player and projectile_system:
		player.projectile_system = projectile_system
	if player and ability_system:
		player.ability_system = ability_system

	# Start the start delay timer
	_start_delay_timer = GameConfig.start_delay_sec if GameConfig else 1.5

	# Subscribe to events
	_subscribe_to_events()

	_update_hud()

	print("[LevelMVP] Level bootstrap complete, start delay: %.1f sec" % _start_delay_timer)


func _init_runtime_state() -> void:
	if RuntimeState:
		RuntimeState.player_hp = GameConfig.player_max_hp if GameConfig else 100
		RuntimeState.is_level_active = true
		RuntimeState.is_frozen = false
		RuntimeState.time_elapsed = 0.0
		RuntimeState.current_wave = 0
		RuntimeState.kills = 0
		RuntimeState.damage_dealt = 0
		RuntimeState.damage_received = 0


func _init_systems() -> void:
	# Create WaveManager
	wave_manager = WaveManager.new()
	wave_manager.name = "WaveManager"
	wave_manager.enemy_scene = ENEMY_SCENE
	wave_manager.boss_scene = BOSS_SCENE  # Phase 2: boss scene
	wave_manager.entities_container = entities_container
	# Set arena bounds based on floor size
	wave_manager.arena_min = _arena_min
	wave_manager.arena_max = _arena_max
	add_child(wave_manager)

	# Initialize WaveManager with waves count from config
	var total_waves: int = GameConfig.waves_per_level if GameConfig else 3
	wave_manager.initialize(total_waves)

	# Create CombatSystem
	combat_system = CombatSystem.new()
	combat_system.name = "CombatSystem"
	combat_system.player_node = player
	add_child(combat_system)

	# Create ProjectileSystem
	projectile_system = ProjectileSystem.new()
	projectile_system.name = "ProjectileSystem"
	projectile_system.projectiles_container = projectiles_container
	add_child(projectile_system)

	# Create VFXSystem (Phase 2)
	vfx_system = VFXSystem.new()
	vfx_system.name = "VFXSystem"
	add_child(vfx_system)
	vfx_system.initialize(decals_container, corpses_container)

	# Create FootprintSystem (Phase 2)
	footprint_system = FootprintSystem.new()
	footprint_system.name = "FootprintSystem"
	add_child(footprint_system)
	footprint_system.initialize(footprints_container, vfx_system)

	# Phase 3: Create AbilitySystem
	ability_system = AbilitySystem.new()
	ability_system.name = "AbilitySystem"
	ability_system.projectile_system = projectile_system
	ability_system.combat_system = combat_system
	add_child(ability_system)

	# Phase 3: Create CameraShake
	camera_shake = CameraShake.new()
	camera_shake.name = "CameraShake"
	add_child(camera_shake)
	camera_shake.initialize(camera)

	# Phase 3: Create WaveOverlay
	wave_overlay = WaveOverlay.new()
	wave_overlay.name = "WaveOverlay"
	add_child(wave_overlay)

	# Phase 3: Create ArenaBoundary (added before Entities for z-ordering)
	arena_boundary = ArenaBoundary.new()
	arena_boundary.name = "ArenaBoundary"
	arena_boundary.z_index = -1  # Behind entities
	add_child(arena_boundary)
	arena_boundary.initialize(_arena_min, _arena_max)

	# Phase 4: Create MeleeSystem (Katana)
	if GameConfig and GameConfig.katana_enabled:
		melee_system = MeleeSystem.new()
		melee_system.name = "MeleeSystem"
		melee_system.player_node = player
		melee_system.entities_container = entities_container
		add_child(melee_system)

	print("[LevelMVP] Systems initialized (Phase 4: Weapons + Arena Polish + Katana)")


func _subscribe_to_events() -> void:
	if EventBus:
		EventBus.wave_started.connect(_on_wave_started)
		EventBus.player_damaged.connect(_on_player_damaged)
		EventBus.player_died.connect(_on_player_died)
		EventBus.all_waves_completed.connect(_on_all_waves_completed)
		# Phase 2: Boss events
		EventBus.boss_spawned.connect(_on_boss_spawned)
		EventBus.boss_killed.connect(_on_boss_killed)
		EventBus.boss_damaged.connect(_on_boss_damaged)
		# Phase 3: Rocket explosion -> camera shake
		EventBus.rocket_exploded.connect(_on_rocket_exploded)


func _process(delta: float) -> void:
	# Handle input
	_handle_input()

	# Skip updates if frozen
	if RuntimeState and RuntimeState.is_frozen:
		return

	# Update time
	if RuntimeState:
		RuntimeState.time_elapsed += delta

	# Handle start delay
	if not _start_delay_finished:
		_start_delay_timer -= delta
		if _start_delay_timer <= 0:
			_start_delay_finished = true
			print("[LevelMVP] Start delay finished, waves beginning")
			if EventBus:
				EventBus.emit_start_delay_finished()

	# Update systems
	if wave_manager:
		wave_manager.update(delta)
	if combat_system:
		combat_system.update(delta)
	if melee_system:
		melee_system.update(delta)
	if footprint_system:
		footprint_system.update(delta)

	# Camera follows player (CANON: no rotation)
	if player and camera:
		camera.position = player.position
		camera.rotation = 0  # Ensure no rotation
		# Phase 3: Apply camera shake
		if camera_shake:
			camera_shake.update(delta)

	# Update HUD
	_update_hud()


func _handle_input() -> void:
	# ESC - toggle pause
	if Input.is_action_just_pressed("pause"):
		if StateManager:
			if StateManager.is_playing():
				StateManager.change_state(GameState.State.PAUSED)
			elif StateManager.is_paused():
				StateManager.change_state(GameState.State.PLAYING)

	# Debug: F1 - force game over
	if Input.is_action_just_pressed("debug_game_over"):
		if StateManager and StateManager.is_playing():
			print("[LevelMVP] Debug: Forcing GAME_OVER")
			StateManager.change_state(GameState.State.GAME_OVER)

	# Debug: F2 - force level complete
	if Input.is_action_just_pressed("debug_level_complete"):
		if StateManager and StateManager.is_playing():
			print("[LevelMVP] Debug: Forcing LEVEL_COMPLETE")
			StateManager.change_state(GameState.State.LEVEL_COMPLETE)


func _update_hud() -> void:
	if not RuntimeState:
		return

	if hp_label:
		hp_label.text = "HP: %d / %d" % [RuntimeState.player_hp, GameConfig.player_max_hp if GameConfig else 100]

	if state_label and StateManager:
		var state_text := GameState.state_to_string(StateManager.current_state)
		if not _start_delay_finished and StateManager.is_playing():
			state_text += " (%.1f)" % _start_delay_timer
		state_label.text = "State: %s" % state_text

	if wave_label:
		var wave_text := "Wave: %d" % RuntimeState.current_wave
		if wave_manager:
			wave_text += " / %d" % (GameConfig.waves_per_level if GameConfig else 3)
			if RuntimeState.current_wave > 0:
				wave_text += " (Alive: %d)" % wave_manager.alive_total
		wave_label.text = wave_text

	if time_label:
		time_label.text = "Time: %.1f | Kills: %d" % [RuntimeState.time_elapsed, RuntimeState.kills]

	# Phase 2: Boss HP display
	if boss_hp_label and wave_manager:
		if wave_manager.boss_spawned and wave_manager.boss_node and is_instance_valid(wave_manager.boss_node):
			var boss := wave_manager.boss_node
			if "hp" in boss and "max_hp" in boss:
				boss_hp_label.text = "BOSS: %d / %d" % [boss.hp, boss.max_hp]
			else:
				boss_hp_label.text = "BOSS ACTIVE"
		elif wave_manager._boss_phase and not wave_manager.boss_spawned:
			boss_hp_label.text = "Boss incoming..."
		else:
			boss_hp_label.text = ""

	# Phase 3: Weapon display + Phase 4: Mode display
	if weapon_label and ability_system:
		var mode_str := "KATANA" if RuntimeState.katana_mode else "GUN"
		if RuntimeState.katana_mode:
			var melee_state := ""
			if melee_system and melee_system.is_busy():
				melee_state = " (SLASH)"
			weapon_label.text = "Mode: %s%s | Q=switch" % [mode_str, melee_state]
		else:
			weapon_label.text = "Mode: %s | %s [%d/6]" % [
				mode_str,
				ability_system.get_current_weapon().to_upper(),
				ability_system.current_weapon_index + 1
			]


## ============================================================================
## EVENT HANDLERS
## ============================================================================

func _on_wave_started(wave_index: int, wave_size: int) -> void:
	print("[LevelMVP] Wave %d started (size: %d)" % [wave_index, wave_size])
	# Phase 3: Show wave overlay
	if wave_overlay:
		wave_overlay.show_wave(wave_index)


func _on_player_damaged(amount: int, new_hp: int, source: String) -> void:
	print("[LevelMVP] Player damaged: %d (HP: %d, source: %s)" % [amount, new_hp, source])
	# Visual feedback on player
	if player and player.has_method("take_damage"):
		player.take_damage(amount)


func _on_player_died() -> void:
	print("[LevelMVP] Player died!")


func _on_all_waves_completed() -> void:
	# Phase 2: Don't trigger LEVEL_COMPLETE here - boss must be killed first
	print("[LevelMVP] All waves completed! Waiting for boss...")


## Phase 3: Rocket explosion -> camera shake
func _on_rocket_exploded(_pos: Vector3) -> void:
	if camera_shake:
		var amp: float = GameConfig.rocket_shake_amplitude if GameConfig else 3.0
		var dur: float = GameConfig.rocket_shake_duration if GameConfig else 0.15
		camera_shake.shake(amp, dur)


## ============================================================================
## BOSS EVENT HANDLERS (Phase 2)
## ============================================================================

func _on_boss_spawned(boss_id: int, pos: Vector3) -> void:
	print("[LevelMVP] BOSS SPAWNED at position (%d, %d)!" % [int(pos.x), int(pos.y)])


func _on_boss_damaged(boss_id: int, amount: int, new_hp: int) -> void:
	print("[LevelMVP] Boss damaged: %d (HP: %d)" % [amount, new_hp])


func _on_boss_killed(boss_id: int) -> void:
	print("[LevelMVP] BOSS DEFEATED! VICTORY!")

	# CANON: After boss death - stop gameplay, stop spawns, no damage, show LEVEL_COMPLETE
	if RuntimeState:
		RuntimeState.is_frozen = true
		RuntimeState.is_level_active = false

	if StateManager:
		StateManager.change_state(GameState.State.LEVEL_COMPLETE)


## ============================================================================
## PAUSE/RESUME
## ============================================================================

## Called by AppRoot when pausing
func pause() -> void:
	if RuntimeState:
		RuntimeState.is_frozen = true
	print("[LevelMVP] Paused")


## Called by AppRoot when resuming
func resume() -> void:
	if RuntimeState:
		RuntimeState.is_frozen = false
	print("[LevelMVP] Resumed")
