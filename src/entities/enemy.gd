## enemy.gd
## Base enemy entity.
## CANON: Uses modular perception + pursuit systems.
class_name Enemy
extends CharacterBody2D

const SHOTGUN_SPREAD_SCRIPT := preload("res://src/systems/shotgun_spread.gd")
const SHOTGUN_DAMAGE_MODEL_SCRIPT := preload("res://src/systems/shotgun_damage_model.gd")
const ENEMY_PERCEPTION_SYSTEM_SCRIPT := preload("res://src/systems/enemy_perception_system.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
const ENEMY_ALERT_MARKER_PRESENTER_SCRIPT := preload("res://src/systems/enemy_alert_marker_presenter.gd")
const FLASHLIGHT_CONE_SCRIPT := preload("res://src/systems/stealth/flashlight_cone.gd")
const SUSPICION_RING_PRESENTER_SCRIPT := preload("res://src/systems/stealth/suspicion_ring_presenter.gd")
const WEAPON_SHOTGUN := "shotgun"

const DEFAULT_SIGHT_FOV_DEG := 180.0
const DEFAULT_SIGHT_MAX_DISTANCE_PX := 1500.0
const DEFAULT_FIRE_ATTACK_RANGE_MAX_PX := 600.0
const DEFAULT_FIRE_SPAWN_OFFSET_PX := 20.0
const DEFAULT_FIRE_RAY_RANGE_PX := 2000.0
const VISION_DEBUG_COLOR := Color(1.0, 0.96, 0.62, 0.9)
const VISION_DEBUG_COLOR_DIM := Color(1.0, 0.96, 0.62, 0.55)
const VISION_DEBUG_WIDTH := 2.0
const VISION_DEBUG_FILL_COLOR := Color(1.0, 0.96, 0.62, 0.20)
const VISION_DEBUG_FILL_COLOR_DIM := Color(1.0, 0.96, 0.62, 0.11)
const VISION_DEBUG_FILL_RAY_COUNT := 24
const AWARENESS_CALM := "CALM"
const AWARENESS_ALERT := "ALERT"
const AWARENESS_COMBAT := "COMBAT"
const TEST_LOOK_LOS_GRACE_SEC := 0.25
const TEST_INTENT_POLICY_LOCK_SEC := 0.45
const TEST_ACTIVE_SUSPICION_MIN := 0.05
const TEST_FACING_LOG_DELTA_RAD := 0.35

## Enemy stats fallback (canonical values live in GameConfig.enemy_stats).
const DEFAULT_ENEMY_STATS := {
	"zombie": {"hp": 100, "damage": 10, "speed": 2.0},
	"fast": {"hp": 100, "damage": 7, "speed": 4.0},
	"tank": {"hp": 100, "damage": 15, "speed": 1.5},
	"swarm": {"hp": 100, "damage": 5, "speed": 3.0},
}

## Unique entity ID
var entity_id: int = 0

## Enemy type name
var enemy_type: String = "zombie"

## Current HP
var hp: int = 30

## Max HP (for potential HP bars)
var max_hp: int = 30

## Contact damage (kept for compatibility)
var contact_damage: int = 10

## Runtime toggle from LevelMVP (F7).
var weapons_enabled: bool = false

## Movement speed in tiles/sec
var speed_tiles: float = 2.0

## Is enemy dead?
var is_dead: bool = false

## Stagger timer (knockback, blocks movement)
var stagger_timer: float = 0.0

## Knockback velocity (decays over time)
var knockback_vel: Vector2 = Vector2.ZERO

## Reference to sprite
@onready var sprite: Sprite2D = $Sprite2D
@onready var alert_marker: Sprite2D = $AlertMarker

## Reference to collision shape
@onready var collision: CollisionShape2D = $CollisionShape2D

## Room/nav wiring (kept for compatibility with RoomNavSystem)
var nav_system: Node = null
var home_room_id: int = -1
var alert_system: Node = null
var squad_system: Node = null

## Weapon timing
var _shot_cooldown: float = 0.0
var _player_visible_prev: bool = false
var _confirmed_visual_prev: bool = false
var _shot_rng := RandomNumberGenerator.new()
var _last_seen_pos: Vector2 = Vector2.ZERO
var _last_seen_age: float = INF
var _current_alert_level: int = ENEMY_ALERT_LEVELS_SCRIPT.CALM
var _suspicion_test_profile_enabled: bool = false
var _suspicion_test_profile: Dictionary = {}
var _flashlight_hit_override: bool = false
var _debug_last_has_los: bool = false
var _debug_last_visibility_factor: float = 0.0
var _debug_last_distance_factor: float = 0.0
var _debug_last_shadow_mul: float = 1.0
var _debug_last_distance_to_player: float = INF
var _debug_last_flashlight_active: bool = false
var _debug_last_flashlight_hit: bool = false
var _debug_last_flashlight_in_cone: bool = false
var _debug_last_flashlight_los_to_player: bool = false
var _debug_last_flashlight_bonus_raw: float = 1.0
var _debug_last_effective_visibility_pre_clamp: float = 0.0
var _debug_last_effective_visibility_post_clamp: float = 0.0
var _debug_last_intent_type: int = -1
var _debug_last_intent_target: Vector2 = Vector2.ZERO
var _debug_last_facing_dir: Vector2 = Vector2.RIGHT
var _debug_last_target_facing_dir: Vector2 = Vector2.RIGHT
var _debug_last_facing_used_for_flashlight: Vector2 = Vector2.RIGHT
var _debug_last_facing_after_move: Vector2 = Vector2.RIGHT
var _debug_last_state_name: String = "CALM"
var _debug_last_last_seen_age: float = INF
var _debug_last_weapons_enabled: bool = false
var _debug_last_room_alert_level: int = ENEMY_ALERT_LEVELS_SCRIPT.CALM
var _debug_tick_id: int = 0
var _debug_last_flashlight_calc_tick_id: int = -1
var _stealth_test_debug_logging_enabled: bool = false
var _debug_last_logged_intent_type: int = -1
var _debug_last_logged_target_facing: Vector2 = Vector2.ZERO
var _test_last_stable_look_dir: Vector2 = Vector2.RIGHT
var _test_los_look_grace_timer: float = 0.0
var _test_intent_policy_lock_timer: float = 0.0
var _test_intent_policy_last_type: int = ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL

## Modular AI systems
var _perception = null
var _pursuit = null
var _awareness = null
var _utility_brain = null
var _alert_marker_presenter = null
var _flashlight_cone: Node2D = null
var _suspicion_ring: Node = null
var _vision_fill_poly: Polygon2D = null
var _vision_center_line: Line2D = null
var _vision_left_line: Line2D = null
var _vision_right_line: Line2D = null
var _runtime_budget_scheduler_enabled: bool = false
var _runtime_budget_tick_pending: bool = false
var _runtime_budget_tick_delta: float = 0.0


func _ready() -> void:
	print("ENEMY_RUNTIME_MARKER_v20260216")
	add_to_group("enemies")
	_shot_rng.randomize()
	_perception = ENEMY_PERCEPTION_SYSTEM_SCRIPT.new(self)
	_pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(self, sprite, speed_tiles)
	_awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	_utility_brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	_alert_marker_presenter = ENEMY_ALERT_MARKER_PRESENTER_SCRIPT.new()
	_alert_marker_presenter.setup(alert_marker)
	_awareness.reset()
	if _awareness.has_method("set_suspicion_profile_enabled"):
		_awareness.set_suspicion_profile_enabled(_suspicion_test_profile_enabled)
	_utility_brain.reset()
	set_meta("awareness_state", _awareness.get_state_name())
	_apply_alert_level(ENEMY_ALERT_LEVELS_SCRIPT.CALM)
	_connect_event_bus_signals()
	_setup_flashlight_cone()
	_setup_suspicion_ring()
	_setup_vision_debug_lines()
	_play_spawn_animation()


## Initialize enemy with ID and type.
func initialize(id: int, type: String) -> void:
	entity_id = id
	enemy_type = type

	var stats := _enemy_stats_for_type(type)
	if not stats.is_empty():
		hp = stats.hp
		max_hp = stats.hp
		contact_damage = stats.damage
		speed_tiles = stats.speed
	else:
		push_warning("[Enemy] Unknown enemy type: %s" % type)

	if _pursuit:
		_pursuit.set_speed_tiles(speed_tiles)
	if _awareness:
		_awareness.reset()
		if _awareness.has_method("set_suspicion_profile_enabled"):
			_awareness.set_suspicion_profile_enabled(_suspicion_test_profile_enabled)
		set_meta("awareness_state", _awareness.get_state_name())
	if _utility_brain:
		_utility_brain.reset()
	_last_seen_pos = Vector2.ZERO
	_last_seen_age = INF
	_player_visible_prev = false
	_confirmed_visual_prev = false
	_test_los_look_grace_timer = 0.0
	_test_intent_policy_lock_timer = 0.0
	_test_intent_policy_last_type = ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL
	_test_last_stable_look_dir = Vector2.RIGHT
	_debug_last_logged_intent_type = -1
	_debug_last_logged_target_facing = Vector2.ZERO
	_debug_last_flashlight_active = false
	_debug_last_flashlight_hit = false
	_debug_last_flashlight_in_cone = false
	_debug_last_flashlight_los_to_player = false
	_debug_last_flashlight_bonus_raw = 1.0
	_debug_last_effective_visibility_pre_clamp = 0.0
	_debug_last_effective_visibility_post_clamp = 0.0
	_debug_last_facing_used_for_flashlight = Vector2.RIGHT
	_debug_last_facing_after_move = Vector2.RIGHT
	_debug_tick_id = 0
	_debug_last_flashlight_calc_tick_id = -1
	_debug_last_state_name = _awareness.get_state_name() if _awareness else "CALM"
	_update_suspicion_ring(0.0)
	_sync_suspicion_ring_visibility()
	_apply_alert_level(ENEMY_ALERT_LEVELS_SCRIPT.CALM)
	_register_to_squad_system()


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if RuntimeState and RuntimeState.is_frozen:
		return

	if _shot_cooldown > 0.0:
		_shot_cooldown = maxf(0.0, _shot_cooldown - delta)

	# Handle stagger (blocks normal movement)
	if stagger_timer > 0:
		stagger_timer -= delta
		if knockback_vel.length_squared() > 1.0:
			velocity = knockback_vel
			move_and_slide()
			knockback_vel = knockback_vel.lerp(Vector2.ZERO, minf(10.0 * delta, 1.0))
		return

	# Decay any residual knockback
	if knockback_vel.length_squared() > 1.0:
		knockback_vel = knockback_vel.lerp(Vector2.ZERO, minf(10.0 * delta, 1.0))

	var ai_delta := delta
	if _runtime_budget_scheduler_enabled:
		if not _runtime_budget_tick_pending:
			return
		ai_delta = _runtime_budget_tick_delta if _runtime_budget_tick_delta > 0.0 else delta
		_runtime_budget_tick_pending = false
		_runtime_budget_tick_delta = 0.0

	runtime_budget_tick(ai_delta)


func set_runtime_budget_scheduler_enabled(enabled: bool) -> void:
	_runtime_budget_scheduler_enabled = enabled
	if not enabled:
		_runtime_budget_tick_pending = false
		_runtime_budget_tick_delta = 0.0


func request_runtime_budget_tick(delta: float = 0.0) -> bool:
	if is_dead:
		return false
	if not _runtime_budget_scheduler_enabled:
		return false
	_runtime_budget_tick_pending = true
	_runtime_budget_tick_delta = maxf(_runtime_budget_tick_delta, maxf(delta, 0.0))
	return true


func runtime_budget_tick(delta: float) -> void:
	if not _perception or not _pursuit:
		return

	_debug_tick_id += 1

	var player_valid: bool = bool(_perception.has_player())
	var player_pos: Vector2 = _perception.get_player_position()
	var facing_dir: Vector2 = _pursuit.get_facing_dir() as Vector2
	var flashlight_facing_used: Vector2 = facing_dir
	var sight_fov_deg := _enemy_vision_cfg_float("fov_deg", DEFAULT_SIGHT_FOV_DEG)
	var sight_max_distance_px := _enemy_vision_cfg_float("max_distance_px", DEFAULT_SIGHT_MAX_DISTANCE_PX)
	var player_visible: bool = bool(_perception.can_see_player(
		global_position,
		flashlight_facing_used,
		sight_fov_deg,
		sight_max_distance_px,
		_ray_excludes()
	))
	var visibility_snapshot := {
		"distance_to_player": INF,
		"distance_factor": 0.0,
		"shadow_mul": 1.0,
		"visibility_factor": 0.0,
	}
	if _perception:
		if _perception.has_method("get_player_visibility_snapshot"):
			visibility_snapshot = _perception.get_player_visibility_snapshot(global_position, sight_max_distance_px) as Dictionary
		elif _perception.has_method("get_player_visibility_factor"):
			visibility_snapshot["visibility_factor"] = float(_perception.get_player_visibility_factor(global_position, sight_max_distance_px))
	var visibility_factor := float(visibility_snapshot.get("visibility_factor", 0.0))
	var distance_factor := float(visibility_snapshot.get("distance_factor", 0.0))
	var shadow_mul := float(visibility_snapshot.get("shadow_mul", 1.0))
	var distance_to_player := float(visibility_snapshot.get("distance_to_player", INF))

	var awareness_state_before := ENEMY_ALERT_LEVELS_SCRIPT.CALM
	if _awareness and _awareness.has_method("get_awareness_state"):
		awareness_state_before = int(_awareness.get_awareness_state())
	var flashlight_active := _suspicion_test_profile_enabled and awareness_state_before == ENEMY_ALERT_LEVELS_SCRIPT.ALERT
	var flashlight_in_cone := false
	var flashlight_hit := false
	var flashlight_bonus_raw := 1.0
	if _flashlight_cone:
		if _suspicion_test_profile_enabled:
			_flashlight_cone.set_flashlight_visibility_bonus(float(_suspicion_test_profile.get("flashlight_bonus", _flashlight_cone.get_flashlight_visibility_bonus())))
		flashlight_bonus_raw = _flashlight_cone.get_flashlight_visibility_bonus()
		flashlight_in_cone = _flashlight_cone.is_point_in_cone(global_position, flashlight_facing_used, player_pos)
		flashlight_hit = _flashlight_cone.is_player_hit(global_position, flashlight_facing_used, player_pos, player_visible, flashlight_active)
	var force_flashlight_hit := _flashlight_hit_override and _suspicion_test_profile_enabled
	if force_flashlight_hit and player_visible:
		flashlight_hit = true
	if _flashlight_cone:
		_flashlight_cone.update_runtime_debug(flashlight_facing_used, flashlight_active, flashlight_hit)
	if player_visible and player_valid:
		var look_dir := (player_pos - global_position).normalized()
		if look_dir.length_squared() > 0.0001:
			_test_last_stable_look_dir = look_dir
		_test_los_look_grace_timer = _test_profile_look_los_grace_sec()
	else:
		_test_los_look_grace_timer = maxf(0.0, _test_los_look_grace_timer - maxf(delta, 0.0))

	if _awareness:
		if _suspicion_test_profile_enabled and _awareness.has_method("process_suspicion"):
			var suspicion_profile: Dictionary = _suspicion_test_profile
			if _flashlight_cone and not _suspicion_test_profile.is_empty():
				suspicion_profile = _suspicion_test_profile.duplicate(true)
				suspicion_profile["flashlight_bonus"] = _flashlight_cone.get_flashlight_visibility_bonus()
			_apply_awareness_transitions(_awareness.process_suspicion(
				delta,
				player_visible,
				visibility_factor,
				flashlight_hit,
				suspicion_profile
			))
		else:
			_apply_awareness_transitions(_awareness.process(delta, player_visible))
	var effective_visibility_pre_clamp := maxf(visibility_factor, 0.0)
	var effective_visibility_post_clamp := clampf(effective_visibility_pre_clamp, 0.0, 1.0)
	if _suspicion_test_profile_enabled and _awareness and _awareness.has_method("get_last_suspicion_debug"):
		var suspicion_debug := _awareness.get_last_suspicion_debug() as Dictionary
		if not suspicion_debug.is_empty():
			flashlight_bonus_raw = float(suspicion_debug.get("flashlight_bonus_raw", flashlight_bonus_raw))
			effective_visibility_pre_clamp = float(suspicion_debug.get("effective_visibility_pre_clamp", effective_visibility_pre_clamp))
			effective_visibility_post_clamp = float(suspicion_debug.get("effective_visibility_post_clamp", effective_visibility_post_clamp))
	var suspicion_now := 0.0
	if _awareness and _awareness.has_method("get_suspicion"):
		suspicion_now = float(_awareness.get_suspicion())
	_update_suspicion_ring(suspicion_now)

	if _suspicion_test_profile_enabled and _awareness and _awareness.has_method("has_confirmed_visual"):
		var confirmed_now := bool(_awareness.has_confirmed_visual())
		if confirmed_now and not _confirmed_visual_prev and EventBus:
			EventBus.emit_enemy_player_spotted(entity_id, Vector3(player_pos.x, player_pos.y, 0.0))
		_confirmed_visual_prev = confirmed_now if player_valid else false
	else:
		if player_visible and not _player_visible_prev:
			if EventBus:
				EventBus.emit_enemy_player_spotted(entity_id, Vector3(player_pos.x, player_pos.y, 0.0))

	if player_visible:
		_last_seen_pos = player_pos
		_last_seen_age = 0.0
	else:
		if is_finite(_last_seen_age):
			_last_seen_age = minf(_last_seen_age + delta, 999.0)
		if _is_combat_lock_active() and player_valid:
			_last_seen_pos = player_pos
			_last_seen_age = 0.0
	_player_visible_prev = player_visible if player_valid else false

	_current_alert_level = _resolve_room_alert_level()
	_apply_alert_level(_current_alert_level)

	var assignment := _resolve_squad_assignment()
	var context := _build_utility_context(player_valid, player_pos, player_visible, assignment)
	var intent: Dictionary = _utility_brain.update(delta, context) if _utility_brain else {}
	if _suspicion_test_profile_enabled:
		intent = _apply_test_profile_intent_policy(intent, context, suspicion_now, delta)
	var exec_result: Dictionary = _pursuit.execute_intent(delta, intent, context) if _pursuit and _pursuit.has_method("execute_intent") else {}
	if _suspicion_test_profile_enabled and not player_visible and _test_los_look_grace_timer > 0.0 and _pursuit and _pursuit.has_method("set_external_look_dir"):
		_pursuit.set_external_look_dir(_test_last_stable_look_dir, true)
	var facing_after_move: Vector2 = _pursuit.get_facing_dir() as Vector2
	if facing_after_move.length_squared() <= 0.0001:
		facing_after_move = flashlight_facing_used
	var target_facing_after_move: Vector2 = facing_after_move
	if _pursuit and _pursuit.has_method("get_target_facing_dir"):
		target_facing_after_move = _pursuit.get_target_facing_dir() as Vector2
	var should_request_fire := bool(exec_result.get("request_fire", false))
	var should_fire_by_intent := should_request_fire and _should_fire_player_target(player_visible, player_pos)
	var should_fire_by_test_fallback := _suspicion_test_profile_enabled and _is_combat_awareness_active() and _should_fire_player_target(player_visible, player_pos)
	if weapons_enabled and (should_fire_by_intent or should_fire_by_test_fallback):
		_try_fire_at_player(player_pos)

	_debug_last_has_los = player_visible
	_debug_last_visibility_factor = visibility_factor
	_debug_last_distance_factor = distance_factor
	_debug_last_shadow_mul = shadow_mul
	_debug_last_distance_to_player = distance_to_player
	_debug_last_flashlight_active = flashlight_active
	_debug_last_flashlight_hit = flashlight_hit
	_debug_last_flashlight_in_cone = flashlight_in_cone
	_debug_last_flashlight_los_to_player = player_visible
	_debug_last_flashlight_bonus_raw = flashlight_bonus_raw
	_debug_last_effective_visibility_pre_clamp = effective_visibility_pre_clamp
	_debug_last_effective_visibility_post_clamp = effective_visibility_post_clamp
	_debug_last_intent_type = int(intent.get("type", -1))
	_debug_last_intent_target = intent.get("target", Vector2.ZERO) as Vector2
	_debug_last_last_seen_age = _last_seen_age
	_debug_last_weapons_enabled = weapons_enabled
	_debug_last_room_alert_level = _current_alert_level
	_debug_last_facing_used_for_flashlight = flashlight_facing_used
	_debug_last_facing_after_move = facing_after_move
	_debug_last_flashlight_calc_tick_id = _debug_tick_id
	if _awareness and _awareness.has_method("get_state_name"):
		_debug_last_state_name = String(_awareness.get_state_name())
	_debug_last_facing_dir = facing_after_move
	_debug_last_target_facing_dir = target_facing_after_move
	_emit_stealth_debug_trace_if_needed(context, suspicion_now)
	if _alert_marker_presenter:
		_alert_marker_presenter.update(delta)
	_update_vision_debug_lines(player_valid, player_pos, player_visible)


func set_room_navigation(p_nav_system: Node, p_home_room_id: int) -> void:
	nav_system = p_nav_system
	home_room_id = p_home_room_id
	if _pursuit:
		_pursuit.configure_navigation(p_nav_system, p_home_room_id)


func set_tactical_systems(p_alert_system: Node = null, p_squad_system: Node = null) -> void:
	alert_system = p_alert_system
	if squad_system != p_squad_system and squad_system and squad_system.has_method("deregister_enemy") and entity_id > 0:
		squad_system.deregister_enemy(entity_id)
	squad_system = p_squad_system
	_register_to_squad_system()


func on_heard_shot(shot_room_id: int, shot_pos: Vector2) -> void:
	if _awareness:
		_apply_awareness_transitions(_awareness.register_noise())
	if _pursuit:
		_pursuit.on_heard_shot(shot_room_id, shot_pos)


func apply_room_alert_propagation(_source_enemy_id: int, _source_room_id: int) -> void:
	if _awareness:
		_apply_awareness_transitions(_awareness.register_room_alert_propagation())


func debug_force_awareness_state(target_state: String) -> void:
	if not _awareness:
		return
	var normalized_state := String(target_state).strip_edges().to_upper()
	match normalized_state:
		AWARENESS_CALM:
			_awareness.reset()
			if _awareness.has_method("set_suspicion_profile_enabled"):
				_awareness.set_suspicion_profile_enabled(_suspicion_test_profile_enabled)
			_confirmed_visual_prev = false
			_player_visible_prev = false
			_last_seen_age = INF
			_set_awareness_meta_from_system()
			_apply_alert_level(ENEMY_ALERT_LEVELS_SCRIPT.CALM)
		AWARENESS_ALERT:
			_awareness.reset()
			if _awareness.has_method("set_suspicion_profile_enabled"):
				_awareness.set_suspicion_profile_enabled(_suspicion_test_profile_enabled)
			var alert_transitions: Array[Dictionary] = _awareness.register_noise()
			_apply_awareness_transitions(alert_transitions)
			_set_awareness_meta_from_system()
			_apply_alert_level(ENEMY_ALERT_LEVELS_SCRIPT.ALERT)
		AWARENESS_COMBAT:
			var suspicion_profile_enabled_before := _suspicion_test_profile_enabled
			if _awareness.has_method("set_suspicion_profile_enabled"):
				_awareness.set_suspicion_profile_enabled(false)
			var combat_transitions: Array[Dictionary] = _awareness.register_reinforcement()
			_apply_awareness_transitions(combat_transitions)
			if _awareness.has_method("get_state_name") and String(_awareness.get_state_name()) != AWARENESS_COMBAT:
				_apply_awareness_transitions(_awareness.process(0.0, true))
			if _awareness.has_method("set_suspicion_profile_enabled"):
				_awareness.set_suspicion_profile_enabled(suspicion_profile_enabled_before)
			_set_awareness_meta_from_system()
			if _awareness.has_method("get_state_name") and String(_awareness.get_state_name()) == AWARENESS_COMBAT:
				_raise_room_alert_for_combat_same_tick()
				_apply_alert_level(maxi(_resolve_room_alert_level(), ENEMY_ALERT_LEVELS_SCRIPT.ALERT))
		_:
			push_warning("[Enemy] debug_force_awareness_state: unknown target_state='%s'" % normalized_state)


func _connect_event_bus_signals() -> void:
	if not EventBus:
		return
	if EventBus.has_signal("enemy_reinforcement_called") and not EventBus.enemy_reinforcement_called.is_connected(_on_enemy_reinforcement_called):
		EventBus.enemy_reinforcement_called.connect(_on_enemy_reinforcement_called)


func _on_enemy_reinforcement_called(source_enemy_id: int, _source_room_id: int, target_room_ids: Array) -> void:
	if is_dead:
		return
	if source_enemy_id == entity_id:
		return
	var own_room_id := _resolve_room_id_for_events()
	if own_room_id < 0:
		return
	if not target_room_ids.has(own_room_id):
		return
	if _awareness:
		_apply_awareness_transitions(_awareness.register_reinforcement())


func _apply_awareness_transitions(transitions: Array[Dictionary]) -> void:
	for transition_variant in transitions:
		var transition := transition_variant as Dictionary
		if transition.is_empty():
			continue
		_emit_awareness_transition(transition)
		if transition.has("to_state"):
			var to_state := String(transition.get("to_state", ""))
			set_meta("awareness_state", to_state)
			if to_state == AWARENESS_COMBAT:
				_raise_room_alert_for_combat_same_tick()


func _set_awareness_meta_from_system() -> void:
	if not _awareness or not _awareness.has_method("get_state_name"):
		return
	var state_name := String(_awareness.get_state_name())
	set_meta("awareness_state", state_name)
	_debug_last_state_name = state_name


func _apply_alert_level(level: int) -> void:
	_current_alert_level = level
	if _alert_marker_presenter:
		_alert_marker_presenter.set_alert_level(level)


func _resolve_room_alert_level() -> int:
	if alert_system and alert_system.has_method("get_room_alert_level"):
		return int(alert_system.get_room_alert_level(_resolve_room_id_for_events()))
	if nav_system and nav_system.has_method("get_alert_level"):
		return int(nav_system.get_alert_level(_resolve_room_id_for_events()))
	return ENEMY_ALERT_LEVELS_SCRIPT.CALM


func _resolve_squad_assignment() -> Dictionary:
	if squad_system and squad_system.has_method("get_assignment") and entity_id > 0:
		return squad_system.get_assignment(entity_id) as Dictionary
	return {
		"role": 0,
		"slot_position": Vector2.ZERO,
		"path_ok": false,
		"has_slot": false,
	}


func _build_utility_context(player_valid: bool, player_pos: Vector2, player_visible: bool, assignment: Dictionary) -> Dictionary:
	var slot_pos := assignment.get("slot_position", Vector2.ZERO) as Vector2
	var hp_ratio := float(hp) / float(maxi(max_hp, 1))
	var has_last_seen := _last_seen_age < INF
	var home_pos := global_position
	if nav_system and nav_system.has_method("get_room_center") and home_room_id >= 0:
		var nav_home := nav_system.get_room_center(home_room_id) as Vector2
		if nav_home != Vector2.ZERO:
			home_pos = nav_home
	return {
		"dist": global_position.distance_to(player_pos) if player_valid else INF,
		"los": player_visible,
		"alert_level": _resolve_effective_alert_level_for_utility(),
		"combat_lock": _is_combat_lock_active(),
		"last_seen_age": _last_seen_age,
		"last_seen_pos": _last_seen_pos,
		"has_last_seen": has_last_seen,
		"dist_to_last_seen": global_position.distance_to(_last_seen_pos) if has_last_seen else INF,
		"role": int(assignment.get("role", 0)),
		"slot_position": slot_pos,
		"dist_to_slot": global_position.distance_to(slot_pos) if slot_pos != Vector2.ZERO else INF,
		"hp_ratio": hp_ratio,
		"path_ok": bool(assignment.get("path_ok", false)),
		"has_slot": bool(assignment.get("has_slot", false)),
		"player_pos": player_pos,
		"home_position": home_pos,
	}


func _emit_awareness_transition(transition: Dictionary) -> void:
	if not EventBus or not EventBus.has_method("emit_enemy_state_changed"):
		return
	var from_state := String(transition.get("from_state", ""))
	var to_state := String(transition.get("to_state", ""))
	if from_state == "" or to_state == "":
		return
	EventBus.emit_enemy_state_changed(
		entity_id,
		from_state,
		to_state,
		_resolve_room_id_for_events(),
		String(transition.get("reason", "timer"))
	)


func _resolve_room_id_for_events() -> int:
	var room_id := int(get_meta("room_id", home_room_id))
	if room_id < 0 and nav_system and nav_system.has_method("room_id_at_point"):
		room_id = int(nav_system.room_id_at_point(global_position))
		set_meta("room_id", room_id)
	return room_id


func _resolve_effective_alert_level_for_utility() -> int:
	var awareness_alert := ENEMY_ALERT_LEVELS_SCRIPT.CALM
	if _awareness and _awareness.has_method("get_awareness_state"):
		awareness_alert = int(_awareness.get_awareness_state())
	if awareness_alert == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT:
		return ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
	return maxi(_current_alert_level, awareness_alert)


func _is_combat_lock_active() -> bool:
	if _awareness and _awareness.has_method("is_combat_locked"):
		return bool(_awareness.is_combat_locked())
	return _is_combat_awareness_active()


func _raise_room_alert_for_combat_same_tick() -> void:
	if alert_system == null or not alert_system.has_method("raise_combat_immediate"):
		return
	var room_id := _resolve_room_id_for_events()
	if room_id < 0:
		return
	alert_system.raise_combat_immediate(room_id, entity_id)


func get_current_alert_level() -> int:
	return _current_alert_level


func get_current_intent() -> Dictionary:
	if _utility_brain:
		return _utility_brain.get_current_intent()
	return {}


func enable_suspicion_test_profile(profile: Dictionary) -> void:
	_suspicion_test_profile_enabled = true
	_suspicion_test_profile = profile.duplicate(true)
	if _awareness and _awareness.has_method("set_suspicion_profile_enabled"):
		_awareness.set_suspicion_profile_enabled(true)
	_confirmed_visual_prev = false
	_test_los_look_grace_timer = 0.0
	_test_intent_policy_lock_timer = 0.0
	_test_intent_policy_last_type = ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL
	_sync_suspicion_ring_visibility()


func disable_suspicion_test_profile() -> void:
	_suspicion_test_profile_enabled = false
	_suspicion_test_profile.clear()
	if _awareness and _awareness.has_method("set_suspicion_profile_enabled"):
		_awareness.set_suspicion_profile_enabled(false)
	_confirmed_visual_prev = false
	_test_los_look_grace_timer = 0.0
	_test_intent_policy_lock_timer = 0.0
	_update_suspicion_ring(0.0)
	_sync_suspicion_ring_visibility()


func configure_stealth_test_flashlight(angle_deg: float, distance_px: float, bonus: float) -> void:
	_setup_flashlight_cone()
	if not _flashlight_cone:
		return
	_flashlight_cone.set("cone_angle_deg", clampf(angle_deg, 1.0, 179.0))
	_flashlight_cone.set("cone_distance", maxf(distance_px, 1.0))
	if _flashlight_cone.has_method("set_flashlight_visibility_bonus"):
		_flashlight_cone.call("set_flashlight_visibility_bonus", maxf(bonus, 1.0))
	if _suspicion_test_profile_enabled:
		_suspicion_test_profile["flashlight_bonus"] = maxf(bonus, 1.0)


func set_flashlight_hit_for_detection(hit: bool) -> void:
	_flashlight_hit_override = hit


func set_stealth_test_debug_logging(enabled: bool) -> void:
	_stealth_test_debug_logging_enabled = enabled
	if not enabled:
		_debug_last_logged_intent_type = -1
		_debug_last_logged_target_facing = Vector2.ZERO


func get_debug_detection_snapshot() -> Dictionary:
	var state_enum := ENEMY_ALERT_LEVELS_SCRIPT.CALM
	var suspicion := 0.0
	var confirmed := false
	var state_name := _debug_last_state_name
	if _awareness:
		if _awareness.has_method("get_awareness_state"):
			state_enum = int(_awareness.get_awareness_state())
		elif _awareness.has_method("get_state"):
			state_enum = int(_awareness.get_state())
		if _awareness.has_method("get_state_name"):
			state_name = String(_awareness.get_state_name())
		if _awareness.has_method("get_suspicion"):
			suspicion = float(_awareness.get_suspicion())
		if _awareness.has_method("has_confirmed_visual"):
			confirmed = bool(_awareness.has_confirmed_visual())
	return {
		"state": state_enum,
		"state_name": state_name,
		"suspicion": suspicion,
		"has_los": _debug_last_has_los,
		"los_to_player": _debug_last_flashlight_los_to_player,
		"distance_to_player": _debug_last_distance_to_player,
		"distance_factor": _debug_last_distance_factor,
		"shadow_mul": _debug_last_shadow_mul,
		"visibility_factor": _debug_last_visibility_factor,
		"flashlight_active": _debug_last_flashlight_active,
		"in_cone": _debug_last_flashlight_in_cone,
		"flashlight_hit": _debug_last_flashlight_hit,
		"flashlight_bonus_raw": _debug_last_flashlight_bonus_raw,
		"effective_visibility_pre_clamp": _debug_last_effective_visibility_pre_clamp,
		"effective_visibility_post_clamp": _debug_last_effective_visibility_post_clamp,
		"confirmed": confirmed,
		"intent_type": _debug_last_intent_type,
		"intent_target": _debug_last_intent_target,
		"facing_dir": _debug_last_facing_dir,
		"facing_used_for_flashlight": _debug_last_facing_used_for_flashlight,
		"facing_after_move": _debug_last_facing_after_move,
		"target_facing_dir": _debug_last_target_facing_dir,
		"flashlight_calc_tick_id": _debug_last_flashlight_calc_tick_id,
		"last_seen_age": _debug_last_last_seen_age,
		"room_alert_level": _debug_last_room_alert_level,
		"weapons_enabled": _debug_last_weapons_enabled,
		"suspicion_ring_progress": _suspicion_ring.call("get_progress") if _suspicion_ring and _suspicion_ring.has_method("get_progress") else suspicion,
	}


func _apply_test_profile_intent_policy(intent: Dictionary, context: Dictionary, suspicion_now: float, delta: float) -> Dictionary:
	var out := intent.duplicate(true)
	var intent_type := int(out.get("type", ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL))
	var has_los := bool(context.get("los", false))
	var active_suspicion := suspicion_now >= _test_profile_active_suspicion_min()
	var should_stabilize := has_los or active_suspicion
	_test_intent_policy_lock_timer = maxf(0.0, _test_intent_policy_lock_timer - maxf(delta, 0.0))
	var blocked_for_test := (
		intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT
		or intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETREAT
	)
	if should_stabilize and blocked_for_test and _test_intent_policy_lock_timer > 0.0:
		if (
			_test_intent_policy_last_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT
			or _test_intent_policy_last_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETREAT
		):
			_test_intent_policy_last_type = ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.HOLD_RANGE
		intent_type = _test_intent_policy_last_type
		out["type"] = intent_type
		if not out.has("target") or (out.get("target", Vector2.ZERO) as Vector2) == Vector2.ZERO:
			out["target"] = context.get("player_pos", global_position) as Vector2
		return out

	if should_stabilize and blocked_for_test:
		var dist := float(context.get("dist", INF))
		var hold_range_max := _utility_cfg_float("hold_range_max_px", 610.0)
		intent_type = ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.HOLD_RANGE if dist <= hold_range_max else ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH
		out["type"] = intent_type
		out["target"] = context.get("player_pos", global_position) as Vector2

	if should_stabilize and (
		intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.HOLD_RANGE
		or intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH
		or intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.INVESTIGATE
	):
		_test_intent_policy_last_type = intent_type
		_test_intent_policy_lock_timer = _test_profile_intent_lock_sec()
	elif not should_stabilize and _test_intent_policy_lock_timer <= 0.0:
		_test_intent_policy_last_type = intent_type

	return out


func _emit_stealth_debug_trace_if_needed(context: Dictionary, suspicion_now: float) -> void:
	if not _stealth_test_debug_logging_enabled:
		return
	var intent_type := _debug_last_intent_type
	var target_facing := _debug_last_target_facing_dir
	var facing_delta := 0.0
	if _debug_last_logged_target_facing.length_squared() > 0.0001 and target_facing.length_squared() > 0.0001:
		facing_delta = absf(wrapf(target_facing.angle() - _debug_last_logged_target_facing.angle(), -PI, PI))
	var intent_changed := intent_type != _debug_last_logged_intent_type
	var facing_changed := facing_delta >= _test_profile_facing_log_delta_rad()
	if not intent_changed and not facing_changed:
		return
	print("[EnemyStealthTrace] id=%d state=%s room_alert=%s intent=%d los=%s susp=%.3f vis=%.3f dist=%.1f last_seen_age=%.2f weapons=%s facing_delta=%.3f" % [
		entity_id,
		_debug_last_state_name,
		ENEMY_ALERT_LEVELS_SCRIPT.level_name(_debug_last_room_alert_level),
		intent_type,
		str(bool(context.get("los", false))),
		suspicion_now,
		_debug_last_visibility_factor,
		float(context.get("dist", INF)),
		_debug_last_last_seen_age,
		str(_debug_last_weapons_enabled),
		facing_delta,
	])
	_debug_last_logged_intent_type = intent_type
	_debug_last_logged_target_facing = target_facing


func _test_profile_look_los_grace_sec() -> float:
	if _suspicion_test_profile_enabled and not _suspicion_test_profile.is_empty():
		return maxf(float(_suspicion_test_profile.get("look_los_grace_sec", TEST_LOOK_LOS_GRACE_SEC)), 0.0)
	return TEST_LOOK_LOS_GRACE_SEC


func _test_profile_intent_lock_sec() -> float:
	if _suspicion_test_profile_enabled and not _suspicion_test_profile.is_empty():
		return maxf(float(_suspicion_test_profile.get("intent_policy_lock_sec", TEST_INTENT_POLICY_LOCK_SEC)), 0.0)
	return TEST_INTENT_POLICY_LOCK_SEC


func _test_profile_active_suspicion_min() -> float:
	if _suspicion_test_profile_enabled and not _suspicion_test_profile.is_empty():
		return clampf(float(_suspicion_test_profile.get("active_suspicion_min", TEST_ACTIVE_SUSPICION_MIN)), 0.0, 1.0)
	return TEST_ACTIVE_SUSPICION_MIN


func _test_profile_facing_log_delta_rad() -> float:
	if _suspicion_test_profile_enabled and not _suspicion_test_profile.is_empty():
		return maxf(float(_suspicion_test_profile.get("facing_log_delta_rad", TEST_FACING_LOG_DELTA_RAD)), 0.0)
	return TEST_FACING_LOG_DELTA_RAD


func _utility_cfg_float(key: String, fallback: float) -> float:
	if GameConfig and GameConfig.ai_balance.has("utility"):
		var section := GameConfig.ai_balance["utility"] as Dictionary
		return float(section.get(key, fallback))
	return fallback


func _register_to_squad_system() -> void:
	if not squad_system:
		return
	if not squad_system.has_method("register_enemy"):
		return
	if entity_id <= 0:
		return
	squad_system.register_enemy(entity_id, self)


func _try_fire_at_player(player_pos: Vector2) -> void:
	if _shot_cooldown > 0.0:
		return
	if not _is_combat_awareness_active():
		return

	var aim_dir := (player_pos - global_position).normalized()
	if aim_dir.length_squared() <= 0.0001:
		return
	if _pursuit:
		_pursuit.face_towards(player_pos)

	var muzzle := global_position + aim_dir * _enemy_vision_cfg_float("fire_spawn_offset_px", DEFAULT_FIRE_SPAWN_OFFSET_PX)
	_fire_enemy_shotgun(muzzle, aim_dir)
	_shot_cooldown = _shotgun_cooldown_sec()

	if EventBus:
		EventBus.emit_enemy_shot(
			entity_id,
			WEAPON_SHOTGUN,
			Vector3(muzzle.x, muzzle.y, 0),
			Vector3(aim_dir.x, aim_dir.y, 0)
		)


func _should_fire_player_target(player_visible: bool, player_pos: Vector2) -> bool:
	if not player_visible:
		return false
	if not _is_combat_awareness_active():
		return false
	return global_position.distance_to(player_pos) <= _enemy_vision_cfg_float("fire_attack_range_max_px", DEFAULT_FIRE_ATTACK_RANGE_MAX_PX)


func _is_combat_awareness_active() -> bool:
	if not _awareness:
		return false
	return _awareness.get_state_name() == AWARENESS_COMBAT


func _fire_enemy_shotgun(origin: Vector2, aim_dir: Vector2) -> void:
	if not _perception:
		return
	var stats := _shotgun_stats()
	var pellets := maxi(int(stats.get("pellets", 16)), 1)
	var cone_deg := maxf(float(stats.get("cone_deg", 8.0)), 0.0)
	var spread_profile := SHOTGUN_SPREAD_SCRIPT.sample_pellets(pellets, cone_deg, _shot_rng)

	var hits := 0
	for pellet_variant in spread_profile:
		var pellet := pellet_variant as Dictionary
		var angle_offset := float(pellet.get("angle_offset", 0.0))
		var dir := aim_dir.rotated(angle_offset)
		if _perception.ray_hits_player(origin, dir, _enemy_vision_cfg_float("fire_ray_range_px", DEFAULT_FIRE_RAY_RANGE_PX), _ray_excludes()):
			hits += 1

	if hits <= 0 or not EventBus:
		return

	var shot_total_damage := maxf(float(stats.get("shot_damage_total", 25.0)), 0.0)
	var applied_damage := 0
	if SHOTGUN_DAMAGE_MODEL_SCRIPT.is_lethal_hits(hits, pellets):
		applied_damage = _player_lethal_damage()
	else:
		applied_damage = SHOTGUN_DAMAGE_MODEL_SCRIPT.damage_for_hits(hits, pellets, shot_total_damage)

	if applied_damage > 0:
		EventBus.emit_enemy_contact(entity_id, "enemy_shotgun", applied_damage)


func _ray_excludes() -> Array[RID]:
	return [get_rid()]


func _setup_vision_debug_lines() -> void:
	_vision_fill_poly = _create_vision_fill_poly()
	_vision_center_line = _create_vision_line()
	_vision_left_line = _create_vision_line()
	_vision_right_line = _create_vision_line()
	add_child(_vision_fill_poly)
	add_child(_vision_center_line)
	add_child(_vision_left_line)
	add_child(_vision_right_line)


func _setup_flashlight_cone() -> void:
	if _flashlight_cone and is_instance_valid(_flashlight_cone):
		return
	_flashlight_cone = FLASHLIGHT_CONE_SCRIPT.new()
	_flashlight_cone.name = "FlashlightCone"
	_flashlight_cone.position = Vector2.ZERO
	add_child(_flashlight_cone)


func _setup_suspicion_ring() -> void:
	if _suspicion_ring and is_instance_valid(_suspicion_ring):
		return
	_suspicion_ring = SUSPICION_RING_PRESENTER_SCRIPT.new()
	_suspicion_ring.name = "SuspicionRing"
	add_child(_suspicion_ring)
	_update_suspicion_ring(0.0)
	_sync_suspicion_ring_visibility()


func _sync_suspicion_ring_visibility() -> void:
	if _suspicion_ring == null or not is_instance_valid(_suspicion_ring):
		return
	if _suspicion_ring.has_method("set_enabled"):
		_suspicion_ring.call("set_enabled", _suspicion_test_profile_enabled)
	else:
		var ring_canvas := _suspicion_ring as CanvasItem
		if ring_canvas:
			ring_canvas.visible = _suspicion_test_profile_enabled


func _update_suspicion_ring(suspicion_value: float) -> void:
	if _suspicion_ring == null or not is_instance_valid(_suspicion_ring):
		return
	if _suspicion_ring.has_method("set_progress"):
		_suspicion_ring.call("set_progress", clampf(suspicion_value, 0.0, 1.0))


func _create_vision_line() -> Line2D:
	var line := Line2D.new()
	line.width = VISION_DEBUG_WIDTH
	line.default_color = VISION_DEBUG_COLOR
	line.antialiased = true
	line.z_as_relative = false
	line.z_index = 220
	line.points = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	return line


func _create_vision_fill_poly() -> Polygon2D:
	var poly := Polygon2D.new()
	poly.color = VISION_DEBUG_FILL_COLOR_DIM
	poly.z_as_relative = false
	poly.z_index = 210
	poly.polygon = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	return poly


func _update_vision_debug_lines(player_valid: bool, player_pos: Vector2, player_visible: bool) -> void:
	if not _vision_center_line or not _vision_left_line or not _vision_right_line or not _vision_fill_poly:
		return
	var facing: Vector2 = Vector2.RIGHT
	if _pursuit:
		facing = _pursuit.get_facing_dir() as Vector2
	if facing.length_squared() <= 0.0001:
		facing = Vector2.RIGHT

	var sight_fov_deg := _enemy_vision_cfg_float("fov_deg", DEFAULT_SIGHT_FOV_DEG)
	var sight_max_distance_px := _enemy_vision_cfg_float("max_distance_px", DEFAULT_SIGHT_MAX_DISTANCE_PX)
	var half_fov := deg_to_rad(sight_fov_deg) * 0.5
	var left_dir: Vector2 = facing.rotated(-half_fov)
	var right_dir: Vector2 = facing.rotated(half_fov)

	var center_end := _vision_ray_end(facing, sight_max_distance_px)
	var left_end := _vision_ray_end(left_dir, sight_max_distance_px)
	var right_end := _vision_ray_end(right_dir, sight_max_distance_px)
	if player_valid and player_visible:
		center_end = player_pos

	var color := VISION_DEBUG_COLOR if player_visible else VISION_DEBUG_COLOR_DIM
	_vision_fill_poly.color = VISION_DEBUG_FILL_COLOR if player_visible else VISION_DEBUG_FILL_COLOR_DIM
	_vision_center_line.default_color = color
	_vision_left_line.default_color = color
	_vision_right_line.default_color = color

	var fan_points := PackedVector2Array()
	fan_points.append(Vector2.ZERO)
	for i in range(VISION_DEBUG_FILL_RAY_COUNT + 1):
		var t := float(i) / float(VISION_DEBUG_FILL_RAY_COUNT)
		var angle_offset := -half_fov + t * (half_fov * 2.0)
		var sample_dir := facing.rotated(angle_offset)
		var sample_end := _vision_ray_end(sample_dir, sight_max_distance_px)
		fan_points.append(to_local(sample_end))
	_vision_fill_poly.polygon = fan_points

	_set_vision_line_points(_vision_center_line, center_end)
	_set_vision_line_points(_vision_left_line, left_end)
	_set_vision_line_points(_vision_right_line, right_end)


func _set_vision_line_points(line: Line2D, world_end: Vector2) -> void:
	line.points = PackedVector2Array([
		Vector2.ZERO,
		to_local(world_end)
	])


func _vision_ray_end(dir: Vector2, max_range: float) -> Vector2:
	var n_dir := dir.normalized()
	if n_dir.length_squared() <= 0.0001:
		return global_position
	var target := global_position + n_dir * max_range
	var query := PhysicsRayQueryParameters2D.create(global_position, target)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = _ray_excludes()

	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return target
	return hit.get("position", target) as Vector2


func _enemy_stats_for_type(type: String) -> Dictionary:
	if GameConfig and GameConfig.enemy_stats.has(type):
		return GameConfig.enemy_stats[type] as Dictionary
	if DEFAULT_ENEMY_STATS.has(type):
		return DEFAULT_ENEMY_STATS[type] as Dictionary
	return {}


func _enemy_vision_cfg_float(key: String, fallback: float) -> float:
	if GameConfig and GameConfig.ai_balance.has("enemy_vision"):
		var section := GameConfig.ai_balance["enemy_vision"] as Dictionary
		return float(section.get(key, fallback))
	return fallback


func _shotgun_stats() -> Dictionary:
	if GameConfig and GameConfig.weapon_stats.has(WEAPON_SHOTGUN):
		return GameConfig.weapon_stats[WEAPON_SHOTGUN] as Dictionary
	return {
		"cooldown_sec": 1.2,
		"rpm": 50.0,
		"pellets": 16,
		"cone_deg": 8.0,
	}


func _shotgun_cooldown_sec() -> float:
	var stats := _shotgun_stats()
	var cooldown_sec := float(stats.get("cooldown_sec", -1.0))
	if cooldown_sec > 0.0:
		return cooldown_sec
	var rpm := maxf(float(stats.get("rpm", 60.0)), 1.0)
	return 60.0 / rpm


func _player_lethal_damage() -> int:
	if RuntimeState:
		return maxi(int(RuntimeState.player_hp), 1)
	return GameConfig.player_max_hp if GameConfig else 100


## Apply damage from any source (projectile, explosion, etc.)
## Reduces HP, emits EventBus signals, handles death once.
func apply_damage(amount: int, source: String) -> void:
	if is_dead:
		return
	hp -= amount
	if sprite:
		var flash_dur := GameConfig.hit_flash_duration if GameConfig else 0.06
		sprite.modulate = Color(3.0, 3.0, 3.0, 1.0)
		var tween := create_tween()
		tween.tween_property(sprite, "modulate", Color.WHITE, flash_dur)
	if RuntimeState:
		RuntimeState.damage_dealt += amount
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

	if sprite:
		var flash_dur := GameConfig.hit_flash_duration if GameConfig else 0.06
		sprite.modulate = Color(3.0, 3.0, 3.0, 1.0)
		var tween := create_tween()
		tween.tween_property(sprite, "modulate", Color.WHITE, flash_dur)

	if hp <= 0:
		die()


## Enemy death
func die() -> void:
	if is_dead:
		return

	is_dead = true

	if RuntimeState:
		RuntimeState.kills += 1

	if collision:
		collision.set_deferred("disabled", true)

	if EventBus:
		EventBus.emit_enemy_killed(entity_id, enemy_type)

	_play_death_effect()


func _cleanup_after_death() -> void:
	if squad_system and squad_system.has_method("deregister_enemy") and entity_id > 0:
		squad_system.deregister_enemy(entity_id)
	remove_from_group("enemies")
	set_physics_process(false)
	queue_free()


## Spawn scale-in animation + flash
func _play_spawn_animation() -> void:
	if not sprite:
		return
	sprite.scale = Vector2(0.1, 0.1)
	sprite.modulate = Color(2.0, 2.0, 2.0, 1.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.2)


## Kill feedback: scale pop 1.0 -> kill_pop_scale -> 0 + fade
func _play_death_effect() -> void:
	if not sprite:
		call_deferred("_cleanup_after_death")
		return

	var pop_scale := GameConfig.kill_pop_scale if GameConfig else 1.2
	var pop_dur := GameConfig.kill_pop_duration if GameConfig else 0.1

	sprite.modulate = Color(3.0, 3.0, 3.0, 1.0)
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector2(pop_scale, pop_scale), pop_dur * 0.5).set_ease(Tween.EASE_OUT)
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2(0, 0), pop_dur * 0.5).set_ease(Tween.EASE_IN)
	tween.tween_property(sprite, "modulate:a", 0.0, pop_dur * 0.5)
	tween.set_parallel(false)
	tween.tween_callback(_cleanup_after_death)
