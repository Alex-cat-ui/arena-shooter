## melee_system.gd
## MeleeSystem - Katana slash state machine with hitstop, knockback, and dash.
## CANON: Reads all tunables from GameConfig.katana_* fields.
## CANON: Uses RuntimeState.player_aim_dir for slash direction.
## CANON: Communicates via EventBus only (no direct system calls).
## Phase 4 - Patch 0.2
class_name MeleeSystem
extends Node

## Melee state machine states
enum MeleeState { IDLE, WINDUP, ACTIVE, RECOVERY, DASHING }

## Move types
enum MoveType { LIGHT, HEAVY, DASH }

## ============================================================================
## PUBLIC REFS (set by LevelMVP)
## ============================================================================
var player_node: CharacterBody2D = null
var entities_container: Node2D = null

## ============================================================================
## STATE
## ============================================================================
var _state: MeleeState = MeleeState.IDLE
var _current_move: MoveType = MoveType.LIGHT
var _state_timer: float = 0.0

## Buffered input
var _buffered_move: MoveType = MoveType.LIGHT
var _buffer_timer: float = 0.0
var _has_buffer: bool = false

## Dash slash cooldown
var _dash_cooldown: float = 0.0

## Track which enemies were hit THIS attack (prevent double hits)
var _hit_ids: Dictionary = {}

## Hitstop state
var _hitstop_timer: float = 0.0
var _hitstop_active: bool = false
var _saved_time_scale: float = 1.0

## Dash movement
var _dash_dir: Vector2 = Vector2.ZERO
var _dash_elapsed: float = 0.0
var _dash_iframes_applied: bool = false

## ============================================================================
## PUBLIC API
## ============================================================================

func request_light_slash() -> void:
	_request_move(MoveType.LIGHT)


func request_heavy_slash() -> void:
	_request_move(MoveType.HEAVY)


func request_dash_slash() -> void:
	if _dash_cooldown > 0:
		return
	_request_move(MoveType.DASH)


func is_busy() -> bool:
	return _state != MeleeState.IDLE


## Called each frame by LevelMVP
func update(delta: float) -> void:
	# Update dash cooldown
	if _dash_cooldown > 0:
		_dash_cooldown -= delta

	# Update invulnerability timer
	if RuntimeState and RuntimeState.invuln_timer > 0:
		RuntimeState.invuln_timer -= delta
		if RuntimeState.invuln_timer <= 0:
			RuntimeState.invuln_timer = 0.0
			RuntimeState.is_player_invulnerable = false

	# Handle hitstop
	if _hitstop_active:
		_hitstop_timer -= delta
		if _hitstop_timer <= 0:
			_end_hitstop()
		return  # Freeze melee logic during hitstop

	# Handle input (only when katana mode ON and not frozen)
	if RuntimeState and RuntimeState.katana_mode and not RuntimeState.is_frozen:
		if Input.is_action_just_pressed("katana_light"):
			request_light_slash()
		elif Input.is_action_just_pressed("katana_heavy"):
			request_heavy_slash()
		elif Input.is_action_just_pressed("katana_dash"):
			request_dash_slash()

	# Update buffer timer
	if _has_buffer:
		_buffer_timer -= delta
		if _buffer_timer <= 0:
			_has_buffer = false

	# State machine
	match _state:
		MeleeState.IDLE:
			_process_idle()
		MeleeState.WINDUP:
			_process_windup(delta)
		MeleeState.ACTIVE:
			_process_active(delta)
		MeleeState.RECOVERY:
			_process_recovery(delta)
		MeleeState.DASHING:
			_process_dashing(delta)


## ============================================================================
## INTERNAL — REQUEST / BUFFER
## ============================================================================

func _request_move(move: MoveType) -> void:
	if _state == MeleeState.IDLE:
		_start_move(move)
	else:
		# Buffer the request
		_buffered_move = move
		_buffer_timer = GameConfig.melee_input_buffer_sec if GameConfig else 0.12
		_has_buffer = true


## ============================================================================
## STATE PROCESSORS
## ============================================================================

func _process_idle() -> void:
	# Check buffer
	if _has_buffer:
		_has_buffer = false
		_start_move(_buffered_move)


func _process_windup(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0:
		_transition(MeleeState.ACTIVE)
		_state_timer = _get_active_duration()
		_hit_ids.clear()


func _process_active(delta: float) -> void:
	_state_timer -= delta
	# Perform arc hit detection each frame during active window
	_perform_arc_hit()
	if _state_timer <= 0:
		_transition(MeleeState.RECOVERY)
		_state_timer = _get_recovery_duration()


func _process_recovery(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0:
		_transition(MeleeState.IDLE)


func _process_dashing(delta: float) -> void:
	_dash_elapsed += delta
	var dash_duration: float = GameConfig.katana_dash_duration_sec if GameConfig else 0.15
	var dash_distance: float = GameConfig.katana_dash_distance_px if GameConfig else 110.0
	var iframes_sec: float = GameConfig.katana_dash_iframes_sec if GameConfig else 0.12
	var active_sec: float = GameConfig.katana_dash_active_sec if GameConfig else 0.08

	# Move player
	if player_node and _dash_dir.length_squared() > 0:
		var speed := dash_distance / dash_duration
		player_node.velocity = _dash_dir * speed
		player_node.move_and_slide()
		# Update RuntimeState position
		if RuntimeState:
			RuntimeState.player_pos = Vector3(player_node.global_position.x, player_node.global_position.y, 0)

	# I-frames: center window of the dash
	var iframes_start := (dash_duration - iframes_sec) / 2.0
	var iframes_end := iframes_start + iframes_sec
	if RuntimeState:
		if _dash_elapsed >= iframes_start and _dash_elapsed <= iframes_end:
			if not _dash_iframes_applied:
				RuntimeState.is_player_invulnerable = true
				RuntimeState.invuln_timer = iframes_sec
				_dash_iframes_applied = true
		elif _dash_elapsed > iframes_end and RuntimeState.is_player_invulnerable and RuntimeState.invuln_timer <= 0:
			RuntimeState.is_player_invulnerable = false

	# Active hit window: last active_sec of the dash
	var hit_start := dash_duration - active_sec
	if _dash_elapsed >= hit_start:
		_perform_arc_hit()

	# End dash
	if _dash_elapsed >= dash_duration:
		# Stop player velocity
		if player_node:
			player_node.velocity = Vector2.ZERO
		# Ensure invuln is cleaned up
		if RuntimeState and RuntimeState.invuln_timer <= 0:
			RuntimeState.is_player_invulnerable = false
		# Set dash cooldown
		_dash_cooldown = GameConfig.katana_dash_cooldown_sec if GameConfig else 1.5
		# Transition to recovery
		_transition(MeleeState.RECOVERY)
		_state_timer = GameConfig.katana_dash_recovery_sec if GameConfig else 0.25


## ============================================================================
## MOVE START / TRANSITION
## ============================================================================

func _start_move(move: MoveType) -> void:
	_current_move = move
	_hit_ids.clear()

	if move == MoveType.DASH:
		_transition(MeleeState.DASHING)
		_dash_elapsed = 0.0
		_dash_iframes_applied = false
		# Aim direction
		if RuntimeState:
			_dash_dir = Vector2(RuntimeState.player_aim_dir.x, RuntimeState.player_aim_dir.y).normalized()
		else:
			_dash_dir = Vector2.RIGHT
	else:
		_transition(MeleeState.WINDUP)
		_state_timer = _get_windup_duration()


func _transition(new_state: MeleeState) -> void:
	_state = new_state


## ============================================================================
## ARC HIT DETECTION
## ============================================================================

func _perform_arc_hit() -> void:
	if not player_node or not RuntimeState:
		return

	var aim_dir := Vector2(RuntimeState.player_aim_dir.x, RuntimeState.player_aim_dir.y).normalized()
	if aim_dir.length_squared() < 0.01:
		aim_dir = Vector2.RIGHT

	var range_px := _get_range_px()
	var arc_deg := _get_arc_deg()
	var half_arc_rad := deg_to_rad(arc_deg / 2.0)
	var max_targets := _get_cleave_max()
	var damage := _get_damage()
	var knockback_str := _get_knockback()
	var stagger_sec := _get_stagger_sec()
	var hitstop_sec := _get_hitstop_sec()

	var player_pos := player_node.position

	# Gather candidates (enemies + boss)
	var candidates: Array[Node] = []
	if entities_container:
		for child in entities_container.get_children():
			if child is CharacterBody2D and child != player_node:
				if "is_dead" in child and child.is_dead:
					continue
				candidates.append(child)
	# Also check tree groups as fallback
	if candidates.is_empty():
		candidates.append_array(get_tree().get_nodes_in_group("enemies"))
		candidates.append_array(get_tree().get_nodes_in_group("boss"))

	# Filter and sort by distance
	var hits: Array[Dictionary] = []
	for candidate in candidates:
		if not candidate is Node2D or not is_instance_valid(candidate):
			continue
		var node: Node2D = candidate as Node2D

		# Skip already hit this attack
		var cid := node.get_instance_id()
		if _hit_ids.has(cid):
			continue

		# Skip dead
		if "is_dead" in node and node.is_dead:
			continue

		var to_enemy := node.position - player_pos
		var dist := to_enemy.length()
		if dist > range_px or dist < 1.0:
			continue

		# Angle check
		var angle_to := absf(aim_dir.angle_to(to_enemy.normalized()))
		if angle_to > half_arc_rad:
			continue

		hits.append({"node": node, "dist": dist})

	# Sort by distance (closest first)
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["dist"] < b["dist"])

	# Apply damage to up to cleave_max targets
	var hit_count := 0
	for hit_data in hits:
		if hit_count >= max_targets:
			break
		var target: Node2D = hit_data["node"]
		if not is_instance_valid(target):
			continue

		var tid := target.get_instance_id()
		_hit_ids[tid] = true
		hit_count += 1

		# Apply damage via enemy's apply_damage method
		if target.has_method("apply_damage"):
			target.apply_damage(damage, _move_type_string())
		elif target.has_method("take_damage"):
			target.take_damage(damage)

		# Knockback
		if target.has_method("apply_knockback"):
			var kb_dir := (target.position - player_pos).normalized()
			target.apply_knockback(kb_dir * knockback_str)

		# Stagger
		if target.has_method("apply_stagger"):
			target.apply_stagger(stagger_sec)

		# VFX: blood + melee_hit event
		if EventBus:
			var hit_pos := Vector3(target.position.x, target.position.y, 0)
			EventBus.emit_blood_spawned(hit_pos, randf_range(0.8, 1.2))
			EventBus.emit_melee_hit(hit_pos, _move_type_string())

	# Hitstop on first hit
	if hit_count > 0 and hitstop_sec > 0 and not _hitstop_active:
		_apply_hitstop(hitstop_sec)


## ============================================================================
## HITSTOP
## ============================================================================

func _apply_hitstop(sec: float) -> void:
	if _hitstop_active:
		return
	_hitstop_active = true
	_hitstop_timer = sec
	_saved_time_scale = Engine.time_scale
	Engine.time_scale = 0.05


func _end_hitstop() -> void:
	_hitstop_active = false
	_hitstop_timer = 0.0
	Engine.time_scale = _saved_time_scale


## ============================================================================
## CONFIG GETTERS (per move type)
## ============================================================================

func _get_windup_duration() -> float:
	if not GameConfig:
		return 0.12
	match _current_move:
		MoveType.LIGHT: return GameConfig.katana_light_windup
		MoveType.HEAVY: return GameConfig.katana_heavy_windup
		_: return 0.12

func _get_active_duration() -> float:
	if not GameConfig:
		return 0.08
	match _current_move:
		MoveType.LIGHT: return GameConfig.katana_light_active
		MoveType.HEAVY: return GameConfig.katana_heavy_active
		MoveType.DASH: return GameConfig.katana_dash_active_sec
		_: return 0.08

func _get_recovery_duration() -> float:
	if not GameConfig:
		return 0.22
	match _current_move:
		MoveType.LIGHT: return GameConfig.katana_light_recovery
		MoveType.HEAVY: return GameConfig.katana_heavy_recovery
		MoveType.DASH: return GameConfig.katana_dash_recovery_sec
		_: return 0.22

func _get_damage() -> int:
	if not GameConfig:
		return 50
	match _current_move:
		MoveType.LIGHT: return GameConfig.katana_light_damage
		MoveType.HEAVY: return GameConfig.katana_heavy_damage
		MoveType.DASH: return GameConfig.katana_dash_damage
		_: return 50

func _get_range_px() -> float:
	if not GameConfig:
		return 55.0
	match _current_move:
		MoveType.LIGHT: return GameConfig.katana_light_range_px
		MoveType.HEAVY: return GameConfig.katana_heavy_range_px
		MoveType.DASH: return GameConfig.katana_dash_range_px
		_: return 55.0

func _get_arc_deg() -> float:
	if not GameConfig:
		return 120.0
	match _current_move:
		MoveType.LIGHT: return GameConfig.katana_light_arc_deg
		MoveType.HEAVY: return GameConfig.katana_heavy_arc_deg
		MoveType.DASH: return GameConfig.katana_dash_arc_deg
		_: return 120.0

func _get_cleave_max() -> int:
	if not GameConfig:
		return 3
	match _current_move:
		MoveType.LIGHT: return GameConfig.katana_light_cleave_max
		MoveType.HEAVY: return GameConfig.katana_heavy_cleave_max
		MoveType.DASH: return 10  # Dash hits all in range
		_: return 3

func _get_knockback() -> float:
	if not GameConfig:
		return 420.0
	match _current_move:
		MoveType.LIGHT: return GameConfig.katana_light_knockback
		MoveType.HEAVY: return GameConfig.katana_heavy_knockback
		MoveType.DASH: return GameConfig.katana_dash_knockback
		_: return 420.0

func _get_stagger_sec() -> float:
	if not GameConfig:
		return 0.15
	match _current_move:
		MoveType.LIGHT: return GameConfig.katana_light_stagger_sec
		MoveType.HEAVY: return GameConfig.katana_heavy_stagger_sec
		MoveType.DASH: return GameConfig.katana_dash_stagger_sec
		_: return 0.15

func _get_hitstop_sec() -> float:
	if not GameConfig:
		return 0.07
	match _current_move:
		MoveType.LIGHT: return GameConfig.katana_light_hitstop_sec
		MoveType.HEAVY: return GameConfig.katana_heavy_hitstop_sec
		MoveType.DASH: return GameConfig.katana_dash_hitstop_sec
		_: return 0.07

func _move_type_string() -> String:
	match _current_move:
		MoveType.LIGHT: return "katana_light"
		MoveType.HEAVY: return "katana_heavy"
		MoveType.DASH: return "katana_dash"
		_: return "katana"
