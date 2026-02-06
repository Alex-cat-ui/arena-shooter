## wave_manager.gd
## WaveManager system - spawns enemies in waves per ТЗ v1.13.
## CANON: WaveSize = EnemiesPerWave + (WaveIndex-1)*WaveSizeGrowth
## CANON: Wave transition when AlivePrevWave <= max(2, ceil(PrevWavePeakCount*WaveAdvanceThreshold))
## CANON: WaveIndex starts at 1
## Phase 2: Boss spawns after last wave when AliveTotal == 0, after InterWaveDelaySec
class_name WaveManager
extends Node

## Enemy scene to spawn (set by level)
var enemy_scene: PackedScene = null

## Boss scene to spawn (set by level) - Phase 2
var boss_scene: PackedScene = null

## Reference to entities container (set by level)
var entities_container: Node2D = null

## Arena bounds for spawn positions (set by level)
var arena_min: Vector2 = Vector2(-400, -400)
var arena_max: Vector2 = Vector2(400, 400)

## Minimum distance from player for spawn
var min_spawn_distance: float = 200.0

## ============================================================================
## WAVE STATE (per ТЗ v1.13)
## ============================================================================

## Current wave index (1-based, 0 = not started)
var wave_index: int = 0

## WaveSize = EnemiesPerWave + (WaveIndex-1)*WaveSizeGrowth
var wave_size: int = 0

## WavePeakCount = WaveSize (total enemies to spawn this wave)
var wave_peak_count: int = 0

## Previous wave peak count
var prev_wave_peak_count: int = 0

## Enemies spawned in current wave
var spawned_this_wave: int = 0

## Has current wave finished spawning?
var wave_finished_spawning: bool = false

## Tracking alive enemies per wave
var _alive_by_wave: Dictionary = {}  # wave_id -> count

## Total alive normal enemies
var alive_total: int = 0

## Unique enemy ID counter
var _next_enemy_id: int = 1

## ============================================================================
## TIMERS
## ============================================================================

## Spawn tick timer
var _spawn_timer: float = 0.0

## Inter-wave delay timer
var _inter_wave_timer: float = 0.0
var _waiting_for_inter_wave: bool = false

## Is spawning active?
var _spawning_active: bool = false

## Total waves for this level
var _total_waves: int = 3

## ============================================================================
## BOSS STATE (Phase 2)
## ============================================================================

## Is in boss phase (all waves complete, waiting for boss)
var _boss_phase: bool = false

## Is waiting for AliveTotal == 0 before boss delay
var _waiting_for_clear: bool = false

## Is waiting for InterWaveDelaySec before boss spawn
var _waiting_for_boss_delay: bool = false

## Boss delay timer
var _boss_delay_timer: float = 0.0

## Has boss been spawned
var boss_spawned: bool = false

## Boss entity reference
var boss_node: Node2D = null

## Boss entity ID
var _boss_id: int = 0


func _ready() -> void:
	# Subscribe to events
	if EventBus:
		EventBus.start_delay_finished.connect(_on_start_delay_finished)
		EventBus.enemy_killed.connect(_on_enemy_killed)
		EventBus.state_changed.connect(_on_state_changed)


## Initialize wave manager for new level
func initialize(total_waves: int) -> void:
	_total_waves = total_waves
	wave_index = 0
	wave_size = 0
	wave_peak_count = 0
	prev_wave_peak_count = 0
	spawned_this_wave = 0
	wave_finished_spawning = false
	_alive_by_wave.clear()
	alive_total = 0
	_spawn_timer = 0.0
	_inter_wave_timer = 0.0
	_waiting_for_inter_wave = false
	_spawning_active = false
	_next_enemy_id = 1

	# Reset boss state (Phase 2)
	_boss_phase = false
	_waiting_for_clear = false
	_waiting_for_boss_delay = false
	_boss_delay_timer = 0.0
	boss_spawned = false
	boss_node = null
	_boss_id = 0

	print("[WaveManager] Initialized for %d waves" % total_waves)


## Update called each frame
func update(delta: float) -> void:
	if not _spawning_active:
		return

	# ========================================================================
	# BOSS PHASE (Phase 2)
	# ========================================================================
	if _boss_phase:
		_update_boss_phase(delta)
		return

	# Handle inter-wave delay
	if _waiting_for_inter_wave:
		_inter_wave_timer -= delta
		if _inter_wave_timer <= 0:
			_waiting_for_inter_wave = false
			_start_next_wave()
		return

	# Check if we can transition to next wave
	if wave_finished_spawning and _can_advance_to_next_wave():
		if wave_index >= _total_waves:
			# All waves complete - enter boss phase (Phase 2)
			_enter_boss_phase()
			return
		else:
			# Start inter-wave delay
			_waiting_for_inter_wave = true
			_inter_wave_timer = GameConfig.inter_wave_delay_sec if GameConfig else 1.0
			return

	# Spawn tick
	if not wave_finished_spawning:
		_spawn_timer -= delta
		if _spawn_timer <= 0:
			_spawn_timer = GameConfig.spawn_tick_sec if GameConfig else 0.6
			_spawn_batch()


## ============================================================================
## WAVE LOGIC (CANON per ТЗ v1.13)
## ============================================================================

func _on_start_delay_finished() -> void:
	print("[WaveManager] Start delay finished, beginning waves")
	_spawning_active = true
	_start_next_wave()


func _start_next_wave() -> void:
	# Store previous wave data
	prev_wave_peak_count = wave_peak_count

	# Increment wave
	wave_index += 1
	spawned_this_wave = 0
	wave_finished_spawning = false

	# Calculate wave size: WaveSize = EnemiesPerWave + (WaveIndex-1)*WaveSizeGrowth
	var enemies_per_wave: int = GameConfig.enemies_per_wave if GameConfig else 12
	var wave_growth: int = GameConfig.wave_size_growth if GameConfig else 3
	wave_size = enemies_per_wave + (wave_index - 1) * wave_growth
	wave_peak_count = wave_size

	# For wave 1, prev_wave_peak_count = wave_peak_count (per ТЗ)
	if wave_index == 1:
		prev_wave_peak_count = wave_peak_count

	# Initialize tracking for this wave
	_alive_by_wave[wave_index] = 0

	# Update RuntimeState
	if RuntimeState:
		RuntimeState.current_wave = wave_index

	# Emit event
	if EventBus:
		EventBus.emit_wave_started(wave_index, wave_size)

	print("[WaveManager] Wave %d started (size: %d)" % [wave_index, wave_size])


func _spawn_batch() -> void:
	if not enemy_scene or not entities_container:
		push_warning("[WaveManager] Missing enemy_scene or entities_container")
		return

	var batch_size: int = GameConfig.spawn_batch_size if GameConfig else 6
	var max_alive: int = GameConfig.max_alive_enemies if GameConfig else 64

	var spawned_count: int = 0
	for i in range(batch_size):
		# Check if wave is complete
		if spawned_this_wave >= wave_peak_count:
			break

		# Check alive limit
		if alive_total >= max_alive:
			break

		# Spawn enemy
		_spawn_single_enemy()
		spawned_count += 1

	# Check if wave finished spawning
	if spawned_this_wave >= wave_peak_count and not wave_finished_spawning:
		wave_finished_spawning = true
		if EventBus:
			EventBus.emit_wave_finished_spawning(wave_index)
		print("[WaveManager] Wave %d finished spawning (%d enemies)" % [wave_index, spawned_this_wave])


func _spawn_single_enemy() -> void:
	var spawn_pos := _get_spawn_position()
	var enemy := enemy_scene.instantiate()

	# Set enemy properties
	if enemy.has_method("initialize"):
		enemy.initialize(_next_enemy_id, "zombie", wave_index)
	else:
		# Fallback: set properties directly if available
		if "entity_id" in enemy:
			enemy.entity_id = _next_enemy_id
		if "enemy_type" in enemy:
			enemy.enemy_type = "zombie"
		if "wave_id" in enemy:
			enemy.wave_id = wave_index

	enemy.position = spawn_pos
	entities_container.add_child(enemy)

	# Update tracking
	spawned_this_wave += 1
	alive_total += 1
	_alive_by_wave[wave_index] = _alive_by_wave.get(wave_index, 0) + 1

	# Emit event
	if EventBus:
		var pos_v3 := Vector3(spawn_pos.x, spawn_pos.y, 0)
		EventBus.emit_enemy_spawned(_next_enemy_id, "zombie", wave_index, pos_v3)

	_next_enemy_id += 1


func _get_spawn_position() -> Vector2:
	# Get player position
	var player_pos := Vector2.ZERO
	if RuntimeState:
		player_pos = Vector2(RuntimeState.player_pos.x, RuntimeState.player_pos.y)

	# Try to find valid spawn position (away from player)
	for attempt in range(10):
		var x := randf_range(arena_min.x, arena_max.x)
		var y := randf_range(arena_min.y, arena_max.y)
		var pos := Vector2(x, y)

		if pos.distance_to(player_pos) >= min_spawn_distance:
			return pos

	# Fallback: spawn at edge
	var edge := randi() % 4
	match edge:
		0: return Vector2(randf_range(arena_min.x, arena_max.x), arena_min.y)
		1: return Vector2(randf_range(arena_min.x, arena_max.x), arena_max.y)
		2: return Vector2(arena_min.x, randf_range(arena_min.y, arena_max.y))
		_: return Vector2(arena_max.x, randf_range(arena_min.y, arena_max.y))


func _can_advance_to_next_wave() -> bool:
	## CANON: Wave transition gating
	## Next wave cannot start until previous wave finished spawning
	if not wave_finished_spawning:
		return false

	## CANON: Transition condition
	## AlivePrevWave <= max(2, ceil(PrevWavePeakCount * WaveAdvanceThreshold))
	var threshold: float = GameConfig.wave_advance_threshold if GameConfig else 0.2
	var threshold_count: int = maxi(2, ceili(prev_wave_peak_count * threshold))

	## Special for wave 1: use AliveTotal
	if wave_index == 1:
		return alive_total <= threshold_count

	## For wave 2+: use AlivePrevWave
	var alive_prev_wave: int = _alive_by_wave.get(wave_index - 1, 0)
	return alive_prev_wave <= threshold_count


func _on_enemy_killed(enemy_id: int, enemy_type: String, enemy_wave_id: int) -> void:
	# Decrement counters
	alive_total = maxi(0, alive_total - 1)

	if _alive_by_wave.has(enemy_wave_id):
		_alive_by_wave[enemy_wave_id] = maxi(0, _alive_by_wave[enemy_wave_id] - 1)


## Get current alive enemies from previous wave
func get_alive_prev_wave() -> int:
	if wave_index <= 1:
		return alive_total
	return _alive_by_wave.get(wave_index - 1, 0)


## ============================================================================
## BOSS PHASE (Phase 2)
## CANON: Boss spawns after InterWaveDelaySec when:
##   - last wave finished spawning
##   - AliveTotal == 0
## ============================================================================

func _enter_boss_phase() -> void:
	_boss_phase = true
	_waiting_for_clear = true
	_waiting_for_boss_delay = false

	# Emit all_waves_completed (for HUD/stats purposes)
	if EventBus:
		EventBus.emit_all_waves_completed()

	print("[WaveManager] All %d waves completed! Entering boss phase..." % _total_waves)


func _update_boss_phase(delta: float) -> void:
	# Already spawned boss
	if boss_spawned:
		return

	# Waiting for all enemies to die
	if _waiting_for_clear:
		if alive_total == 0:
			_waiting_for_clear = false
			_waiting_for_boss_delay = true
			_boss_delay_timer = GameConfig.inter_wave_delay_sec if GameConfig else 1.0
			print("[WaveManager] All enemies cleared! Boss spawning in %.1f sec..." % _boss_delay_timer)
		return

	# Waiting for boss delay
	if _waiting_for_boss_delay:
		_boss_delay_timer -= delta
		if _boss_delay_timer <= 0:
			_waiting_for_boss_delay = false
			_spawn_boss()
		return


func _spawn_boss() -> void:
	if not boss_scene or not entities_container:
		push_warning("[WaveManager] Missing boss_scene or entities_container")
		# Fallback: just end the level
		_spawning_active = false
		if StateManager:
			StateManager.change_state(GameState.State.LEVEL_COMPLETE)
		return

	# Get player position for safe spawn calculation
	var player_pos := Vector2.ZERO
	if RuntimeState:
		player_pos = Vector2(RuntimeState.player_pos.x, RuntimeState.player_pos.y)

	# CANON: Boss must spawn >= 10 tiles away from player
	var tile_size: int = GameConfig.tile_size if GameConfig else 32
	var spawn_pos := Boss.get_safe_spawn_position(player_pos, arena_min, arena_max, tile_size)

	boss_node = boss_scene.instantiate()
	_boss_id = _next_enemy_id
	_next_enemy_id += 1

	# Initialize boss
	if boss_node.has_method("initialize"):
		boss_node.initialize(_boss_id)

	boss_node.position = spawn_pos
	entities_container.add_child(boss_node)
	boss_spawned = true

	# Emit boss spawned event
	if EventBus:
		var pos_v3 := Vector3(spawn_pos.x, spawn_pos.y, 0)
		EventBus.emit_boss_spawned(_boss_id, pos_v3)

	var distance_tiles := spawn_pos.distance_to(player_pos) / tile_size
	print("[WaveManager] BOSS SPAWNED! ID: %d | pos: (%.0f, %.0f) | distance from player: %.1f tiles" % [
		_boss_id, spawn_pos.x, spawn_pos.y, distance_tiles
	])


## Check if boss is alive
func is_boss_alive() -> bool:
	return boss_spawned and boss_node != null and is_instance_valid(boss_node) and not boss_node.is_dead


## Safety: stop spawning when leaving gameplay states
func _on_state_changed(_old_state: GameState.State, new_state: GameState.State) -> void:
	if new_state in [GameState.State.MAIN_MENU, GameState.State.GAME_OVER, GameState.State.LEVEL_COMPLETE]:
		_spawning_active = false
