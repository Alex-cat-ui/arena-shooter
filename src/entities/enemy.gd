## enemy.gd
## Base enemy entity.
## CANON: Uses modular perception + pursuit systems.
class_name Enemy
extends CharacterBody2D

const SHOTGUN_SPREAD_SCRIPT := preload("res://src/systems/shotgun_spread.gd")
const ENEMY_DAMAGE_RUNTIME_SCRIPT := preload("res://src/entities/enemy_damage_runtime.gd")
const ENEMY_COMBAT_SEARCH_RUNTIME_SCRIPT := preload("res://src/entities/enemy_combat_search_runtime.gd")
const ENEMY_FIRE_CONTROL_RUNTIME_SCRIPT := preload("res://src/entities/enemy_fire_control_runtime.gd")
const ENEMY_COMBAT_ROLE_RUNTIME_SCRIPT := preload("res://src/entities/enemy_combat_role_runtime.gd")
const ENEMY_ALERT_LATCH_RUNTIME_SCRIPT := preload("res://src/entities/enemy_alert_latch_runtime.gd")
const ENEMY_DETECTION_RUNTIME_SCRIPT := preload("res://src/entities/enemy_detection_runtime.gd")
const ENEMY_DEBUG_SNAPSHOT_RUNTIME_SCRIPT := preload("res://src/entities/enemy_debug_snapshot_runtime.gd")
const ENEMY_PERCEPTION_SYSTEM_SCRIPT := preload("res://src/systems/enemy_perception_system.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
const ENEMY_ALERT_MARKER_PRESENTER_SCRIPT := preload("res://src/systems/enemy_alert_marker_presenter.gd")
const FLASHLIGHT_CONE_SCRIPT := preload("res://src/systems/stealth/flashlight_cone.gd")
const SUSPICION_RING_PRESENTER_SCRIPT := preload("res://src/systems/stealth/suspicion_ring_presenter.gd")
const WEAPON_SHOTGUN := "shotgun"

const DEFAULT_SIGHT_FOV_DEG := 120.0
const DEFAULT_SIGHT_MAX_DISTANCE_PX := 600.0
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
const AWARENESS_SUSPICIOUS := "SUSPICIOUS"
const AWARENESS_ALERT := "ALERT"
const AWARENESS_COMBAT := "COMBAT"
const TEST_LOOK_LOS_GRACE_SEC := 0.25
const TEST_FACING_LOG_DELTA_RAD := 0.35
const INTENT_STABILITY_LOCK_SEC := 0.45
const INTENT_STABILITY_SUSPICION_MIN := 0.05
const COMBAT_LAST_SEEN_GRACE_SEC := 1.5
const COMBAT_ROOM_MIGRATION_HYSTERESIS_SEC := 0.2
const COMBAT_FIRST_ATTACK_DELAY_MIN_SEC := 1.2
const COMBAT_FIRST_ATTACK_DELAY_MAX_SEC := 2.0
const COMBAT_FIRST_SHOT_MAX_PAUSE_SEC := 2.5
const COMBAT_TELEGRAPH_MAX_PAUSE_SEC := 0.6
const COMBAT_TELEGRAPH_PRODUCTION_MIN_SEC := 0.10
const COMBAT_TELEGRAPH_PRODUCTION_MAX_SEC := 0.18
const COMBAT_TELEGRAPH_DEBUG_MIN_SEC := 0.35
const COMBAT_TELEGRAPH_DEBUG_MAX_SEC := 0.60
const ENEMY_FIRE_MIN_COOLDOWN_SEC := 0.25
const FRIENDLY_BLOCK_REPOSITION_COOLDOWN_SEC := 0.8
const FRIENDLY_BLOCK_STREAK_TRIGGER := 2
const FRIENDLY_BLOCK_SIDESTEP_DISTANCE_PX := 96.0
const ZONE_STATE_LOCKDOWN := 2
const SQUAD_ROLE_PRESSURE := 0
const SQUAD_ROLE_HOLD := 1
const SQUAD_ROLE_FLANK := 2
const COMBAT_ROLE_LOCK_SEC := 3.0
const COMBAT_ROLE_REASSIGN_LOST_LOS_SEC := 1.0
const COMBAT_ROLE_REASSIGN_STUCK_SEC := 1.2
const COMBAT_ROLE_REASSIGN_PATH_FAILED_COUNT := 3
const COMBAT_SEARCH_ROOM_BUDGET_MIN_SEC := 4.0
const COMBAT_SEARCH_ROOM_BUDGET_MAX_SEC := 8.0
const COMBAT_SEARCH_TOTAL_CAP_SEC := 24.0
const COMBAT_SEARCH_UNVISITED_PENALTY := 220.0
const COMBAT_SEARCH_DOOR_COST_PER_HOP := 80.0
const COMBAT_SEARCH_PROGRESS_THRESHOLD := 0.8
const COMBAT_DARK_SEARCH_NODE_STATE_NONE := 0
const COMBAT_DARK_SEARCH_NODE_STATE_NEEDS_SHADOW_SCAN := 1
const COMBAT_DARK_SEARCH_NODE_STATE_SEARCH_DWELL := 2
const COMBAT_DARK_SEARCH_NODE_STATE_COVERED := 3
const COMBAT_DARK_SEARCH_NODE_SAMPLE_OFFSETS := [Vector2.ZERO, Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
const COMBAT_DARK_SEARCH_NODE_DEDUP_PX := 12.0
const COMBAT_DARK_SEARCH_POCKET_COVERAGE_WEIGHT := 1.0
const COMBAT_DARK_SEARCH_BOUNDARY_COVERAGE_WEIGHT := 0.5
const COMBAT_NO_CONTACT_WINDOW_SEC := 8.0
const COMBAT_NO_CONTACT_WINDOW_LOCKDOWN_SEC := 12.0
const FLASHLIGHT_NEAR_THRESHOLD_PX := 400.0
const SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_CHANCE := 0.30
const SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_BUCKET_COUNT := 10
const SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_ACTIVE_BUCKETS := 3
const RUNTIME_BUDGET_ORPHAN_FALLBACK_SEC := 2.0
const TRANSITION_BLOCK_SINGLE_TICK := "single_transition_per_tick"
const SHOTGUN_FIRE_BLOCK_NO_COMBAT_STATE := "no_combat_state"
const SHOTGUN_FIRE_BLOCK_NO_LOS := "no_los"
const SHOTGUN_FIRE_BLOCK_OUT_OF_RANGE := "out_of_range"
const SHOTGUN_FIRE_BLOCK_COOLDOWN := "cooldown"
const SHOTGUN_FIRE_BLOCK_FIRST_ATTACK_DELAY := "first_attack_delay"
const SHOTGUN_FIRE_BLOCK_TELEGRAPH := "telegraph"
const SHOTGUN_FIRE_BLOCK_SHADOW_BLOCKED := "shadow_blocked"
const SHOTGUN_FIRE_BLOCK_FRIENDLY_BLOCK := "friendly_block"
const SHOTGUN_FIRE_BLOCK_REPOSITION := "reposition"
const SHOTGUN_FIRE_BLOCK_SYNC_WINDOW := "sync_window"
const COMBAT_FIRE_PHASE_PEEK := 0
const COMBAT_FIRE_PHASE_FIRE := 1
const COMBAT_FIRE_PHASE_REPOSITION := 2
const COMBAT_FIRE_REPOSITION_SEC := 0.35
const REASON_TEAMMATE_CALL := "teammate_call"

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

## Room/nav wiring (kept for compatibility with NavigationService)
var nav_system: Node = null
var home_room_id: int = -1
var alert_system: Node = null
var squad_system: Node = null
var _zone_director: Node = null

## Weapon timing
var _shot_cooldown: float = 0.0
var _player_visible_prev: bool = false
var _confirmed_visual_prev: bool = false
var _shot_rng := RandomNumberGenerator.new()
var _perception_rng: RandomNumberGenerator = null
var _reaction_warmup_timer: float = 0.0
var _had_visual_los_last_frame: bool = false
var _last_seen_pos: Vector2 = Vector2.ZERO
var _last_seen_age: float = INF
var _investigate_anchor: Vector2 = Vector2.ZERO
var _investigate_anchor_valid: bool = false
var _investigate_target_in_shadow: bool = false
var _last_seen_grace_timer: float = 0.0
var _current_alert_level: int = ENEMY_ALERT_LEVELS_SCRIPT.CALM
var _flashlight_hit_override: bool = false
var _flashlight_activation_delay_timer: float = 0.0
var _shadow_check_flashlight_override: bool = false
var _shadow_linger_flashlight: bool = false
var _flashlight_scanner_allowed: bool = true
var _shadow_scan_active: bool = false
var _shadow_scan_completed: bool = false
var _shadow_scan_completed_reason: String = "none"
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
var _debug_last_room_alert_level: int = ENEMY_ALERT_LEVELS_SCRIPT.CALM
var _debug_last_room_alert_effective: int = ENEMY_ALERT_LEVELS_SCRIPT.CALM
var _debug_last_room_alert_transient: int = ENEMY_ALERT_LEVELS_SCRIPT.CALM
var _debug_last_room_latch_count: int = 0
var _debug_last_latched: bool = false
var _debug_last_target_is_last_seen: bool = false
var _debug_last_flashlight_inactive_reason: String = "state_blocked"
var _debug_last_transition_from: String = ""
var _debug_last_transition_to: String = ""
var _debug_last_transition_reason: String = ""
var _debug_last_transition_blocked_by: String = ""
var _debug_last_transition_source: String = ""
var _debug_last_transition_tick_id: int = -1
var _debug_transition_count_this_tick: int = 0
var _debug_last_shotgun_fire_block_reason: String = SHOTGUN_FIRE_BLOCK_NO_COMBAT_STATE
var _debug_last_shotgun_fire_requested: bool = false
var _debug_last_shotgun_fire_attempted: bool = false
var _debug_last_shotgun_fire_success: bool = false
var _debug_last_shotgun_can_fire: bool = false
var _debug_last_shotgun_should_fire_now: bool = false
var _debug_tick_id: int = 0
var _debug_last_flashlight_calc_tick_id: int = -1
var _stealth_test_debug_logging_enabled: bool = false
var _debug_last_logged_intent_type: int = -1
var _debug_last_logged_target_facing: Vector2 = Vector2.ZERO
var _test_last_stable_look_dir: Vector2 = Vector2.RIGHT
var _test_los_look_grace_timer: float = 0.0
var _intent_stability_lock_timer: float = 0.0
var _intent_stability_last_type: int = ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL

## Modular AI systems
var _perception = null
var _pursuit = null
var _awareness = null
var _utility_brain = null
var _alert_marker_presenter = null
var _combat_search_runtime = null
var _fire_control_runtime = null
var _combat_role_runtime = null
var _alert_latch_runtime = null
var _detection_runtime = null
var _debug_snapshot_runtime = null
var _flashlight_cone: Node2D = null
var _suspicion_ring: Node = null
var _vision_fill_poly: Polygon2D = null
var _vision_center_line: Line2D = null
var _vision_left_line: Line2D = null
var _vision_right_line: Line2D = null
var _runtime_budget_scheduler_enabled: bool = false
var _runtime_budget_tick_pending: bool = false
var _runtime_budget_tick_delta: float = 0.0
var _runtime_budget_orphan_timer: float = 0.0
var _combat_latched: bool = false
var _combat_latched_room_id: int = -1
var _combat_migration_candidate_room_id: int = -1
var _combat_migration_candidate_elapsed: float = 0.0
var _combat_first_attack_delay_timer: float = 0.0
var _combat_first_shot_delay_armed: bool = false
var _combat_first_shot_fired: bool = false
var _combat_first_shot_target_context_key: String = ""
var _combat_first_shot_pause_elapsed: float = 0.0
var _combat_telegraph_active: bool = false
var _combat_telegraph_timer: float = 0.0
var _combat_telegraph_pause_elapsed: float = 0.0
var _combat_fire_phase: int = COMBAT_FIRE_PHASE_PEEK
var _combat_fire_reposition_left: float = 0.0
var _friendly_block_streak: int = 0
var _friendly_block_reposition_cooldown_left: float = 0.0
var _friendly_block_force_reposition: bool = false
var _debug_last_valid_contact_for_fire: bool = false
var _debug_last_fire_los: bool = false
var _debug_last_fire_inside_fov: bool = false
var _debug_last_fire_in_range: bool = false
var _debug_last_fire_not_occluded_by_world: bool = false
var _debug_last_fire_shadow_rule_passed: bool = false
var _debug_last_fire_weapon_ready: bool = false
var _debug_last_fire_friendly_block: bool = false
var _combat_role_current: int = SQUAD_ROLE_PRESSURE
var _combat_role_lock_timer: float = 0.0
var _combat_role_lost_los_sec: float = 0.0
var _combat_role_stuck_sec: float = 0.0
var _combat_role_path_failed_streak: int = 0
var _combat_role_last_target_room: int = -1
var _combat_role_lost_los_trigger_latched: bool = false
var _combat_role_stuck_trigger_latched: bool = false
var _combat_role_path_failed_trigger_latched: bool = false
var _combat_role_last_reassign_reason: String = ""
var _combat_last_runtime_pos: Vector2 = Vector2.ZERO
var _combat_search_total_elapsed_sec: float = 0.0
var _combat_search_room_elapsed_sec: float = 0.0
var _combat_search_room_budget_sec: float = 0.0
var _combat_search_current_room_id: int = -1
var _combat_search_target_pos: Vector2 = Vector2.ZERO
var _combat_search_room_nodes: Dictionary = {} # room_id -> Array[Dictionary]
var _combat_search_room_node_visited: Dictionary = {} # room_id -> Dictionary[node_key: bool]
var _combat_search_current_node_key: String = ""
var _combat_search_current_node_kind: String = ""
var _combat_search_current_node_requires_shadow_scan: bool = false
var _combat_search_current_node_shadow_scan_done: bool = false
var _combat_search_node_search_dwell_sec: float = 0.0
var _combat_search_last_pursuit_shadow_stage: int = -1
var _combat_search_feedback_intent_type: int = -1
var _combat_search_feedback_intent_target: Vector2 = Vector2.ZERO
var _combat_search_feedback_delta: float = 0.0
var _combat_search_shadow_scan_suppressed_last_tick: bool = false
var _combat_search_recovery_applied_last_tick: bool = false
var _combat_search_recovery_reason_last_tick: String = "none"
var _combat_search_recovery_blocked_point_last: Vector2 = Vector2.ZERO
var _combat_search_recovery_blocked_point_valid_last: bool = false
var _combat_search_recovery_skipped_node_key_last: String = ""
var _combat_search_room_coverage: Dictionary = {} # room_id -> 0..1
var _combat_search_visited_rooms: Dictionary = {} # room_id -> true
var _combat_search_progress: float = 0.0
var _combat_search_total_cap_hit: bool = false


func _ready() -> void:
	print("ENEMY_RUNTIME_MARKER_v20260216")
	add_to_group("enemies")
	_shot_rng.randomize()
	_perception_rng = RandomNumberGenerator.new()
	var perception_layout_seed: int = int(GameConfig.layout_seed) if GameConfig else 0
	_perception_rng.seed = (int(entity_id) * 6364136223846793005) ^ perception_layout_seed
	_reaction_warmup_timer = 0.0
	_had_visual_los_last_frame = false
	_perception = ENEMY_PERCEPTION_SYSTEM_SCRIPT.new(self)
	_pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(self, sprite, speed_tiles)
	var nav_agent := $NavAgent as NavigationAgent2D
	if nav_agent and _pursuit and _pursuit.has_method("configure_nav_agent"):
		_pursuit.configure_nav_agent(nav_agent)
	_awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	_utility_brain = ENEMY_UTILITY_BRAIN_SCRIPT.new()
	_alert_marker_presenter = ENEMY_ALERT_MARKER_PRESENTER_SCRIPT.new()
	_alert_marker_presenter.setup(alert_marker)
	_ensure_runtime_helpers_initialized()
	_awareness.reset()
	_utility_brain.reset()
	set_meta("awareness_state", _awareness.get_state_name())
	set_meta("flashlight_active", false)
	_apply_alert_level(ENEMY_ALERT_LEVELS_SCRIPT.CALM)
	_connect_event_bus_signals()
	_setup_flashlight_cone()
	_setup_suspicion_ring()
	_setup_vision_debug_lines()
	_play_spawn_animation()


func _setup_runtime_helpers() -> void:
	_combat_search_runtime = ENEMY_COMBAT_SEARCH_RUNTIME_SCRIPT.new(self)
	_fire_control_runtime = ENEMY_FIRE_CONTROL_RUNTIME_SCRIPT.new(self)
	_combat_role_runtime = ENEMY_COMBAT_ROLE_RUNTIME_SCRIPT.new(self)
	_alert_latch_runtime = ENEMY_ALERT_LATCH_RUNTIME_SCRIPT.new(self)
	_detection_runtime = ENEMY_DETECTION_RUNTIME_SCRIPT.new(self)
	_debug_snapshot_runtime = ENEMY_DEBUG_SNAPSHOT_RUNTIME_SCRIPT.new(self)


func _ensure_runtime_helpers_initialized() -> void:
	if (
		_combat_search_runtime != null
		and _fire_control_runtime != null
		and _combat_role_runtime != null
		and _alert_latch_runtime != null
		and _detection_runtime != null
		and _debug_snapshot_runtime != null
	):
		return
	_setup_runtime_helpers()


func get_runtime_helper_refs() -> Dictionary:
	return {
		"combat_search_runtime": _combat_search_runtime,
		"fire_control_runtime": _fire_control_runtime,
		"combat_role_runtime": _combat_role_runtime,
		"alert_latch_runtime": _alert_latch_runtime,
		"detection_runtime": _detection_runtime,
		"debug_snapshot_runtime": _debug_snapshot_runtime,
	}


## Initialize enemy with ID and type.
func initialize(id: int, type: String) -> void:
	_ensure_runtime_helpers_initialized()
	entity_id = id
	enemy_type = type

	var stats := _enemy_stats_for_type(type)
	if not stats.is_empty():
		hp = stats.hp
		max_hp = stats.hp
		speed_tiles = stats.speed
	else:
		push_warning("[Enemy] Unknown enemy type: %s" % type)

	if _pursuit:
		_pursuit.set_speed_tiles(speed_tiles)
	if _awareness:
		_awareness.reset()
		set_meta("awareness_state", _awareness.get_state_name())
	if _utility_brain:
		_utility_brain.reset()
	_last_seen_pos = Vector2.ZERO
	_last_seen_age = INF
	_investigate_anchor = Vector2.ZERO
	_investigate_anchor_valid = false
	_investigate_target_in_shadow = false
	_last_seen_grace_timer = 0.0
	_flashlight_activation_delay_timer = 0.0
	_shadow_check_flashlight_override = false
	_shadow_linger_flashlight = false
	_flashlight_scanner_allowed = true
	_shadow_scan_active = false
	_shadow_scan_completed = false
	_shadow_scan_completed_reason = "none"
	_player_visible_prev = false
	_confirmed_visual_prev = false
	_reaction_warmup_timer = 0.0
	_had_visual_los_last_frame = false
	_test_los_look_grace_timer = 0.0
	_intent_stability_lock_timer = 0.0
	_intent_stability_last_type = ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL
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
	_debug_last_room_alert_effective = ENEMY_ALERT_LEVELS_SCRIPT.CALM
	_debug_last_room_alert_transient = ENEMY_ALERT_LEVELS_SCRIPT.CALM
	_debug_last_room_latch_count = 0
	_debug_last_latched = false
	_debug_last_flashlight_inactive_reason = "state_blocked"
	_debug_last_transition_from = ""
	_debug_last_transition_to = ""
	_debug_last_transition_reason = ""
	_debug_last_transition_blocked_by = ""
	_debug_last_transition_source = ""
	_debug_last_transition_tick_id = -1
	_debug_transition_count_this_tick = 0
	_debug_last_shotgun_fire_block_reason = SHOTGUN_FIRE_BLOCK_NO_COMBAT_STATE
	_debug_last_shotgun_fire_requested = false
	_debug_last_shotgun_fire_attempted = false
	_debug_last_shotgun_fire_success = false
	_debug_last_shotgun_can_fire = false
	_debug_last_shotgun_should_fire_now = false
	_debug_last_valid_contact_for_fire = false
	_debug_last_fire_los = false
	_debug_last_fire_inside_fov = false
	_debug_last_fire_in_range = false
	_debug_last_fire_not_occluded_by_world = false
	_debug_last_fire_shadow_rule_passed = false
	_debug_last_fire_weapon_ready = false
	_debug_last_fire_friendly_block = false
	_combat_latched = false
	_combat_latched_room_id = -1
	_reset_combat_runtime_state_bundles()
	_friendly_block_streak = 0
	_friendly_block_reposition_cooldown_left = 0.0
	_friendly_block_force_reposition = false
	set_meta("flashlight_active", false)
	_reset_combat_migration_candidate()
	_update_suspicion_ring(0.0)
	_sync_suspicion_ring_visibility()
	_apply_alert_level(ENEMY_ALERT_LEVELS_SCRIPT.CALM)
	_register_to_squad_system()


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if RuntimeState and RuntimeState.is_frozen:
		return

	_tick_fire_runtime_cooldowns(delta)
	if _flashlight_activation_delay_timer > 0.0:
		_flashlight_activation_delay_timer = maxf(0.0, _flashlight_activation_delay_timer - delta)
	if _shadow_linger_flashlight and not _is_current_position_in_shadow():
		_shadow_linger_flashlight = false

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
			_runtime_budget_orphan_timer += maxf(delta, 0.0)
			if _runtime_budget_orphan_timer >= RUNTIME_BUDGET_ORPHAN_FALLBACK_SEC:
				_runtime_budget_orphan_timer = 0.0
				runtime_budget_tick(delta)
			return
		_runtime_budget_orphan_timer = 0.0
		ai_delta = _runtime_budget_tick_delta if _runtime_budget_tick_delta > 0.0 else delta
		_runtime_budget_tick_pending = false
		_runtime_budget_tick_delta = 0.0

	runtime_budget_tick(ai_delta)


func set_runtime_budget_scheduler_enabled(enabled: bool) -> void:
	_runtime_budget_scheduler_enabled = enabled
	_runtime_budget_orphan_timer = 0.0
	if not enabled:
		_runtime_budget_tick_pending = false
		_runtime_budget_tick_delta = 0.0


func request_runtime_budget_tick(delta: float = 0.0) -> bool:
	if is_dead:
		return false
	if not _runtime_budget_scheduler_enabled:
		return false
	_runtime_budget_orphan_timer = 0.0
	_runtime_budget_tick_pending = true
	_runtime_budget_tick_delta = maxf(_runtime_budget_tick_delta, maxf(delta, 0.0))
	return true


func runtime_budget_tick(delta: float) -> void:
	if not _perception or not _pursuit:
		return
	if AIWatchdog:
		AIWatchdog.begin_ai_tick()
	_debug_tick_id += 1
	_runtime_budget_tick_execute_pipeline(delta)


func _runtime_budget_tick_execute_pipeline(delta: float) -> void:

	var player_valid: bool = bool(_perception.has_player())
	var player_pos: Vector2 = _perception.get_player_position()
	var facing_dir: Vector2 = _pursuit.get_facing_dir() as Vector2
	var flashlight_facing_used: Vector2 = facing_dir
	var sight_fov_deg := _enemy_vision_cfg_float("fov_deg", DEFAULT_SIGHT_FOV_DEG)
	var sight_max_distance_px := _enemy_vision_cfg_float("max_distance_px", DEFAULT_SIGHT_MAX_DISTANCE_PX)
	var raw_player_visible: bool = bool(_perception.can_see_player(
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
	var visibility_factor := float(visibility_snapshot.get("visibility_factor", 0.0))
	var distance_factor := float(visibility_snapshot.get("distance_factor", 0.0))
	var shadow_mul := float(visibility_snapshot.get("shadow_mul", 1.0))
	var distance_to_player := float(visibility_snapshot.get("distance_to_player", INF))
	var in_shadow := shadow_mul < 0.999

	var awareness_state_before := ENEMY_ALERT_LEVELS_SCRIPT.CALM
	if _awareness and _awareness.has_method("get_awareness_state"):
		awareness_state_before = int(_awareness.get_awareness_state())
	var flashlight_active := false
	var flashlight_inactive_reason := "state_blocked"
	if _detection_runtime and _detection_runtime.has_method("compute_flashlight_active"):
		flashlight_active = bool(_detection_runtime.call("compute_flashlight_active", awareness_state_before))
	if flashlight_active:
		flashlight_inactive_reason = ""
	var flashlight_in_cone := false
	var flashlight_hit := false
	var flashlight_bonus_raw := 1.0
	if _flashlight_cone:
		flashlight_bonus_raw = _flashlight_cone.get_flashlight_visibility_bonus()
		var flashlight_eval := _flashlight_cone.evaluate_hit(global_position, flashlight_facing_used, player_pos, raw_player_visible, flashlight_active) as Dictionary
		flashlight_in_cone = bool(flashlight_eval.get("in_cone", false))
		flashlight_hit = bool(flashlight_eval.get("hit", false))
		var eval_reason := String(flashlight_eval.get("inactive_reason", ""))
		if eval_reason != "":
			if eval_reason == "los_blocked" and not flashlight_in_cone:
				flashlight_inactive_reason = "cone_miss"
			else:
				flashlight_inactive_reason = eval_reason
	var force_flashlight_hit := _flashlight_hit_override
	if force_flashlight_hit and raw_player_visible:
		flashlight_hit = true
	if flashlight_hit:
		flashlight_inactive_reason = ""
	elif flashlight_active and flashlight_inactive_reason == "":
		flashlight_inactive_reason = "los_blocked" if not raw_player_visible else "cone_miss"
	if _flashlight_cone:
		_flashlight_cone.update_runtime_debug(flashlight_facing_used, flashlight_active, flashlight_hit, flashlight_inactive_reason)

	var confirm_channel_open := raw_player_visible and (not in_shadow or flashlight_hit)
	var behavior_visible := confirm_channel_open
	var combat_reference_target_pos := player_pos if player_valid else (_last_seen_pos if _last_seen_age < INF else global_position)
	if _combat_search_runtime and _combat_search_runtime.has_method("update_runtime"):
		_combat_search_runtime.call(
			"update_runtime",
			delta,
			confirm_channel_open,
			combat_reference_target_pos,
			awareness_state_before == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
		)

	if behavior_visible and player_valid:
		var look_dir := (player_pos - global_position).normalized()
		if look_dir.length_squared() > 0.0001:
			_test_last_stable_look_dir = look_dir
		_test_los_look_grace_timer = TEST_LOOK_LOS_GRACE_SEC
	else:
		_test_los_look_grace_timer = maxf(0.0, _test_los_look_grace_timer - maxf(delta, 0.0))

	var gated_los := raw_player_visible
	if _detection_runtime and _detection_runtime.has_method("tick_reaction_warmup"):
		gated_los = bool(_detection_runtime.call("tick_reaction_warmup", delta, raw_player_visible))
	if _awareness and _awareness.has_method("process_confirm"):
		_apply_awareness_transitions(_awareness.process_confirm(
			delta,
			gated_los,
			in_shadow,
			flashlight_hit,
			_build_confirm_runtime_config(_stealth_canon_config())
		), "runtime_confirm")
	if _alert_latch_runtime and _alert_latch_runtime.has_method("sync_combat_latch_with_awareness_state"):
		_alert_latch_runtime.call("sync_combat_latch_with_awareness_state", _awareness.get_state_name() if _awareness else AWARENESS_CALM)
	var effective_visibility_pre_clamp := maxf(visibility_factor, 0.0)
	var effective_visibility_post_clamp := clampf(effective_visibility_pre_clamp, 0.0, 1.0)
	var awareness_state_for_bonus := awareness_state_before
	if _awareness and _awareness.has_method("get_awareness_state"):
		awareness_state_for_bonus = int(_awareness.get_awareness_state())
	var bonus_allowed_in_alert := (
		awareness_state_for_bonus == ENEMY_ALERT_LEVELS_SCRIPT.ALERT
		and _flashlight_policy_bonus_in_alert()
	)
	var zone_lockdown_active := false
	if _alert_latch_runtime and _alert_latch_runtime.has_method("is_zone_lockdown"):
		zone_lockdown_active = bool(_alert_latch_runtime.call("is_zone_lockdown"))
	var bonus_allowed_in_combat := (
		(
			awareness_state_for_bonus == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
			or _is_combat_latched()
			or zone_lockdown_active
		)
		and _flashlight_policy_bonus_in_combat()
	)
	var bonus_applied := flashlight_hit and (bonus_allowed_in_alert or bonus_allowed_in_combat)
	if bonus_applied:
		flashlight_bonus_raw = maxf(flashlight_bonus_raw, 1.0)
		effective_visibility_pre_clamp *= flashlight_bonus_raw
		effective_visibility_post_clamp = clampf(effective_visibility_pre_clamp, 0.0, 1.0)
	else:
		flashlight_bonus_raw = 1.0
	var suspicion_now := 0.0
	if _awareness and _awareness.has_method("get_suspicion"):
		suspicion_now = float(_awareness.get_suspicion())
	
	if _awareness and _awareness.has_method("has_confirmed_visual"):
		var confirmed_now := bool(_awareness.has_confirmed_visual())
		if confirmed_now and not _confirmed_visual_prev:
			_handle_confirmed_player_spotted(player_pos, true)
		_confirmed_visual_prev = confirmed_now if player_valid else false
	else:
		if behavior_visible and not _player_visible_prev:
			_handle_confirmed_player_spotted(player_pos, true)

	if behavior_visible:
		_last_seen_pos = player_pos
		_last_seen_age = 0.0
		_last_seen_grace_timer = _combat_last_seen_grace_sec()
	else:
		if is_finite(_last_seen_age):
			_last_seen_age = minf(_last_seen_age + delta, 999.0)
		_last_seen_grace_timer = maxf(0.0, _last_seen_grace_timer - maxf(delta, 0.0))
	_player_visible_prev = behavior_visible if player_valid else false

	var room_alert_snapshot := {
		"effective": ENEMY_ALERT_LEVELS_SCRIPT.CALM,
		"transient": ENEMY_ALERT_LEVELS_SCRIPT.CALM,
		"latch_count": 0,
	}
	if _alert_latch_runtime and _alert_latch_runtime.has_method("resolve_room_alert_snapshot"):
		room_alert_snapshot = _alert_latch_runtime.call("resolve_room_alert_snapshot") as Dictionary
	_current_alert_level = int(room_alert_snapshot.get("effective", ENEMY_ALERT_LEVELS_SCRIPT.CALM))
	_debug_last_room_alert_effective = _current_alert_level
	_debug_last_room_alert_transient = int(room_alert_snapshot.get("transient", ENEMY_ALERT_LEVELS_SCRIPT.CALM))
	_debug_last_room_latch_count = int(room_alert_snapshot.get("latch_count", 0))
	_debug_last_latched = _is_combat_latched()
	var visual_alert_level := maxi(_current_alert_level, _resolve_awareness_alert_level())
	_current_alert_level = visual_alert_level

	var assignment := _resolve_squad_assignment()
	var target_context := {
		"known_target_pos": Vector2.ZERO,
		"target_is_last_seen": false,
		"has_known_target": false,
	}
	if _detection_runtime and _detection_runtime.has_method("resolve_known_target_context"):
		target_context = _detection_runtime.call("resolve_known_target_context", player_valid, player_pos, behavior_visible) as Dictionary
	var context := {}
	if _detection_runtime and _detection_runtime.has_method("build_utility_context"):
		context = _detection_runtime.call("build_utility_context", player_valid, behavior_visible, assignment, target_context) as Dictionary
	_debug_last_target_is_last_seen = bool(context.get("target_is_last_seen", false))
	var pos_before_intent := global_position
	var intent: Dictionary = _utility_brain.update(delta, context) if _utility_brain else {}
	if _utility_brain:
		context["pursuit_mode"] = int(_utility_brain.get_pursuit_mode())
	var consumed_shadow_scan_handoff := false
	if _utility_brain and _utility_brain.has_method("consume_shadow_scan_handoff_selected"):
		consumed_shadow_scan_handoff = bool(_utility_brain.call("consume_shadow_scan_handoff_selected"))
	if consumed_shadow_scan_handoff:
		var keep_shadow_scan_handoff_for_dark_node_dwell := false
		if _combat_search_runtime and _combat_search_runtime.has_method("should_keep_shadow_scan_handoff_for_dark_node_dwell"):
			keep_shadow_scan_handoff_for_dark_node_dwell = bool(
				_combat_search_runtime.call("should_keep_shadow_scan_handoff_for_dark_node_dwell", intent)
			)
		if not keep_shadow_scan_handoff_for_dark_node_dwell:
			_shadow_scan_completed = false
			_shadow_scan_completed_reason = "none"
	intent = _apply_runtime_intent_stability_policy(intent, context, suspicion_now, delta)
	if _friendly_block_force_reposition:
		intent = _inject_friendly_block_reposition_intent(intent, assignment, target_context)
		_friendly_block_force_reposition = false
	if _is_combat_reposition_phase_active():
		intent = _inject_combat_cycle_reposition_intent(intent, assignment, target_context)
	var exec_result: Dictionary = _pursuit.execute_intent(delta, intent, context) if _pursuit and _pursuit.has_method("execute_intent") else {}
	if _combat_search_runtime and _combat_search_runtime.has_method("apply_repath_recovery_feedback"):
		_combat_search_runtime.call("apply_repath_recovery_feedback", intent, exec_result)
	if _combat_search_runtime and _combat_search_runtime.has_method("record_execution_feedback"):
		_combat_search_runtime.call("record_execution_feedback", intent, delta)
	if String(exec_result.get("shadow_scan_status", "inactive")) == "completed":
		_shadow_scan_completed = true
		_shadow_scan_completed_reason = String(exec_result.get("shadow_scan_complete_reason", "none"))
	var moved_distance := global_position.distance_to(pos_before_intent)
	var target_room_id := _resolve_target_room_id(target_context.get("known_target_pos", Vector2.ZERO) as Vector2)
	if _combat_role_runtime and _combat_role_runtime.has_method("update_runtime"):
		_combat_role_runtime.call(
			"update_runtime",
			delta,
			confirm_channel_open,
			bool(exec_result.get("movement_intent", false)),
			moved_distance,
			bool(exec_result.get("path_failed", false)),
			target_room_id,
			float(context.get("dist", INF)),
			assignment
		)
	var facing_after_move: Vector2 = _pursuit.get_facing_dir() as Vector2
	if facing_after_move.length_squared() <= 0.0001:
		facing_after_move = flashlight_facing_used
	var target_facing_after_move: Vector2 = facing_after_move
	if _pursuit and _pursuit.has_method("get_target_facing_dir"):
		target_facing_after_move = _pursuit.get_target_facing_dir() as Vector2
	var fire_contact := _evaluate_fire_contact(
		player_valid,
		player_pos,
		facing_after_move,
		sight_fov_deg,
		sight_max_distance_px,
		in_shadow,
		flashlight_active
	)
	var valid_firing_solution := bool(fire_contact.get("valid_contact_for_fire", false))
	if _fire_control_runtime and _fire_control_runtime.has_method("update_first_shot_delay_runtime"):
		_fire_control_runtime.call("update_first_shot_delay_runtime", delta, valid_firing_solution, _combat_target_context_key(target_context))
	var shotgun_can_fire := false
	if _fire_control_runtime and _fire_control_runtime.has_method("can_fire_contact_allows_shot"):
		shotgun_can_fire = bool(_fire_control_runtime.call("can_fire_contact_allows_shot", fire_contact))
	_update_combat_fire_cycle_runtime(delta, shotgun_can_fire)
	var should_request_fire := bool(exec_result.get("request_fire", false))
	if not should_request_fire and valid_firing_solution and _intent_supports_fire(int(intent.get("type", -1))):
		should_request_fire = true
	var shotgun_should_fire_now := false
	if _fire_control_runtime and _fire_control_runtime.has_method("should_fire_now"):
		shotgun_should_fire_now = bool(_fire_control_runtime.call("should_fire_now", should_request_fire, shotgun_can_fire))
	var shotgun_fire_block_reason := ""
	if _fire_control_runtime and _fire_control_runtime.has_method("resolve_shotgun_fire_block_reason"):
		shotgun_fire_block_reason = String(_fire_control_runtime.call("resolve_shotgun_fire_block_reason", fire_contact))
	if should_request_fire and shotgun_can_fire and not shotgun_should_fire_now:
		if _fire_control_runtime and _fire_control_runtime.has_method("resolve_shotgun_fire_schedule_block_reason"):
			shotgun_fire_block_reason = String(_fire_control_runtime.call("resolve_shotgun_fire_schedule_block_reason"))
	var shotgun_fire_attempted := false
	var shotgun_fire_success := false
	if should_request_fire and shotgun_should_fire_now:
		shotgun_fire_attempted = true
		shotgun_fire_success = _try_fire_at_player(player_pos)
		if not shotgun_fire_success and shotgun_fire_block_reason == "":
			if _fire_control_runtime and _fire_control_runtime.has_method("resolve_shotgun_fire_block_reason"):
				shotgun_fire_block_reason = String(_fire_control_runtime.call("resolve_shotgun_fire_block_reason", fire_contact))
	if shotgun_fire_success:
		_mark_enemy_shot_success()
	elif should_request_fire and shotgun_fire_block_reason == SHOTGUN_FIRE_BLOCK_FRIENDLY_BLOCK:
		if _fire_control_runtime and _fire_control_runtime.has_method("register_friendly_block_and_reposition"):
			_fire_control_runtime.call("register_friendly_block_and_reposition")
	_debug_last_shotgun_fire_requested = should_request_fire
	_debug_last_shotgun_can_fire = shotgun_can_fire
	_debug_last_shotgun_should_fire_now = shotgun_should_fire_now
	_debug_last_shotgun_fire_attempted = shotgun_fire_attempted
	_debug_last_shotgun_fire_success = shotgun_fire_success
	_debug_last_shotgun_fire_block_reason = shotgun_fire_block_reason
	if _alert_latch_runtime and _alert_latch_runtime.has_method("update_combat_latch_migration"):
		_alert_latch_runtime.call("update_combat_latch_migration", delta)
	# Second alert-level capture: reflects any combat-latch changes made during execute_intent().
	# Intentional — not a duplicate. First capture (pre-intent) feeds the utility brain;
	# this second capture ensures the UI and subsequent systems see post-intent latch state.
	room_alert_snapshot = {
		"effective": ENEMY_ALERT_LEVELS_SCRIPT.CALM,
		"transient": ENEMY_ALERT_LEVELS_SCRIPT.CALM,
		"latch_count": 0,
	}
	if _alert_latch_runtime and _alert_latch_runtime.has_method("resolve_room_alert_snapshot"):
		room_alert_snapshot = _alert_latch_runtime.call("resolve_room_alert_snapshot") as Dictionary
	_current_alert_level = int(room_alert_snapshot.get("effective", ENEMY_ALERT_LEVELS_SCRIPT.CALM))
	_debug_last_room_alert_effective = _current_alert_level
	_debug_last_room_alert_transient = int(room_alert_snapshot.get("transient", ENEMY_ALERT_LEVELS_SCRIPT.CALM))
	_debug_last_room_latch_count = int(room_alert_snapshot.get("latch_count", 0))
	_debug_last_latched = _is_combat_latched()
	visual_alert_level = maxi(_current_alert_level, _resolve_awareness_alert_level())
	_current_alert_level = visual_alert_level
	var ui_snap := get_ui_awareness_snapshot()
	if _suspicion_ring and _suspicion_ring.has_method("update_from_snapshot"):
		_suspicion_ring.call("update_from_snapshot", ui_snap)
	if _alert_marker_presenter and _alert_marker_presenter.has_method("update_from_snapshot"):
		_alert_marker_presenter.update_from_snapshot(ui_snap, alert_marker)

	_record_runtime_tick_debug_state({
		"behavior_visible": behavior_visible,
		"visibility_factor": visibility_factor,
		"distance_factor": distance_factor,
		"shadow_mul": shadow_mul,
		"distance_to_player": distance_to_player,
		"flashlight_active": flashlight_active,
		"flashlight_hit": flashlight_hit,
		"flashlight_in_cone": flashlight_in_cone,
		"raw_player_visible": raw_player_visible,
		"valid_firing_solution": valid_firing_solution,
		"fire_contact": fire_contact,
		"flashlight_bonus_raw": flashlight_bonus_raw,
		"flashlight_inactive_reason": flashlight_inactive_reason,
		"effective_visibility_pre_clamp": effective_visibility_pre_clamp,
		"effective_visibility_post_clamp": effective_visibility_post_clamp,
		"intent": intent,
		"last_seen_age": _last_seen_age,
		"room_alert_effective": _debug_last_room_alert_effective,
		"flashlight_facing_used": flashlight_facing_used,
		"facing_after_move": facing_after_move,
		"target_facing_after_move": target_facing_after_move,
		"debug_tick_id": _debug_tick_id,
	})
	_emit_stealth_debug_trace_if_needed(context, suspicion_now)
	if _alert_marker_presenter:
		_alert_marker_presenter.update(delta)
	_update_vision_debug_lines(player_valid, player_pos, raw_player_visible)
	if AIWatchdog:
		AIWatchdog.end_ai_tick()


func set_room_navigation(p_nav_system: Node, p_home_room_id: int) -> void:
	nav_system = p_nav_system
	home_room_id = p_home_room_id
	_resolve_room_id_for_events()
	if _perception and _perception.has_method("set_navigation_service"):
		_perception.set_navigation_service(p_nav_system)
	if _pursuit:
		_pursuit.configure_navigation(p_nav_system, p_home_room_id)


func set_tactical_systems(p_alert_system: Node = null, p_squad_system: Node = null) -> void:
	_ensure_runtime_helpers_initialized()
	if _alert_latch_runtime and _alert_latch_runtime.has_method("handle_alert_system_rebind"):
		_alert_latch_runtime.call("handle_alert_system_rebind", alert_system, p_alert_system)
	elif alert_system != p_alert_system and _is_combat_latched() and alert_system and alert_system.has_method("unregister_enemy_combat") and entity_id > 0:
		alert_system.unregister_enemy_combat(entity_id)
		_combat_latched = false
		_combat_latched_room_id = -1
		_reset_combat_migration_candidate()
	alert_system = p_alert_system
	if squad_system != p_squad_system and squad_system and squad_system.has_method("deregister_enemy") and entity_id > 0:
		squad_system.deregister_enemy(entity_id)
	squad_system = p_squad_system
	_register_to_squad_system()
	if _alert_latch_runtime and _alert_latch_runtime.has_method("sync_combat_latch_with_awareness_state"):
		_alert_latch_runtime.call("sync_combat_latch_with_awareness_state", _awareness.get_state_name() if _awareness else AWARENESS_CALM)


func set_zone_director(director: Node) -> void:
	_zone_director = director


func _set_investigate_anchor_from_event(target_pos: Vector2) -> void:
	_investigate_anchor = target_pos
	_investigate_anchor_valid = true
	_investigate_target_in_shadow = false
	if nav_system and nav_system.has_method("is_point_in_shadow"):
		_investigate_target_in_shadow = bool(nav_system.call("is_point_in_shadow", target_pos))


func _override_alert_hold_from_travel_time(target_pos: Vector2, extra_min_sec: float, extra_max_sec: float) -> void:
	if not _awareness or not _awareness.has_method("override_alert_hold_timer"):
		return
	var tile_size: int = GameConfig.tile_size if GameConfig else 32
	var walk_speed := speed_tiles * float(tile_size)
	var walk_time := global_position.distance_to(target_pos) / maxf(walk_speed, 0.001)
	var dynamic_hold := walk_time + randf_range(extra_min_sec, extra_max_sec)
	_awareness.override_alert_hold_timer(dynamic_hold)


func _override_alert_hold_random(min_sec: float, max_sec: float) -> void:
	if not _awareness or not _awareness.has_method("override_alert_hold_timer"):
		return
	_awareness.override_alert_hold_timer(randf_range(min_sec, max_sec))


func _set_flashlight_activation_delay_for_event(
	target_pos: Vector2,
	near_min_sec: float,
	near_max_sec: float,
	far_min_sec: float,
	far_max_sec: float
) -> void:
	var dist_to_target := global_position.distance_to(target_pos)
	if dist_to_target < FLASHLIGHT_NEAR_THRESHOLD_PX:
		_flashlight_activation_delay_timer = randf_range(near_min_sec, near_max_sec)
	else:
		_flashlight_activation_delay_timer = randf_range(far_min_sec, far_max_sec)


func on_heard_shot(shot_room_id: int, shot_pos: Vector2) -> void:
	if _detection_runtime and _detection_runtime.has_method("on_heard_shot"):
		_detection_runtime.call("on_heard_shot", shot_room_id, shot_pos)
		return
	if _awareness:
		_apply_awareness_transitions(_awareness.register_noise(), "heard_shot")
		_override_alert_hold_from_travel_time(shot_pos, 3.0, 10.0)
	_set_investigate_anchor_from_event(shot_pos)
	_set_flashlight_activation_delay_for_event(shot_pos, 0.5, 1.2, 1.0, 1.8)
	if _pursuit:
		_pursuit.on_heard_shot(shot_room_id, shot_pos)


func apply_room_alert_propagation(_source_enemy_id: int, _source_room_id: int) -> void:
	if _awareness:
		_apply_awareness_transitions(_awareness.register_room_alert_propagation(), "room_alert_propagation")


func apply_teammate_call(_source_enemy_id: int, _source_room_id: int, _call_id: int = -1, shot_pos: Vector2 = Vector2.ZERO) -> bool:
	if _detection_runtime and _detection_runtime.has_method("apply_teammate_call"):
		return bool(_detection_runtime.call("apply_teammate_call", _source_enemy_id, _source_room_id, _call_id, shot_pos))
	if not _awareness:
		return false
	var transitions: Array = _awareness.register_teammate_call()
	if transitions.is_empty():
		return false
	_apply_awareness_transitions(transitions, REASON_TEAMMATE_CALL)
	if shot_pos != Vector2.ZERO:
		_set_investigate_anchor_from_event(shot_pos)
		_override_alert_hold_from_travel_time(shot_pos, 3.0, 10.0)
		_set_flashlight_activation_delay_for_event(shot_pos, 0.3, 0.8, 1.0, 1.8)
	else:
		_override_alert_hold_random(8.0, 15.0)
	return true


func apply_blood_evidence(evidence_pos: Vector2) -> bool:
	if _detection_runtime and _detection_runtime.has_method("apply_blood_evidence"):
		return bool(_detection_runtime.call("apply_blood_evidence", evidence_pos))
	if not _awareness:
		return false
	if _awareness.get_state() != EnemyAwarenessSystem.State.CALM:
		return false
	_investigate_anchor = evidence_pos
	_investigate_anchor_valid = true
	_investigate_target_in_shadow = false
	var transitions: Array[Dictionary] = _awareness.register_blood_evidence()
	_apply_awareness_transitions(transitions, "blood_evidence")
	return transitions.size() > 0


func debug_force_awareness_state(target_state: String) -> void:
	if not _awareness:
		return
	var normalized_state := String(target_state).strip_edges().to_upper()
	match normalized_state:
		AWARENESS_CALM:
			_awareness.reset()
			_confirmed_visual_prev = false
			_player_visible_prev = false
			_last_seen_age = INF
			_flashlight_activation_delay_timer = 0.0
			_shadow_check_flashlight_override = false
			_shadow_scan_active = false
			_shadow_linger_flashlight = false
			_investigate_target_in_shadow = false
			_set_awareness_meta_from_system()
			_apply_alert_level(ENEMY_ALERT_LEVELS_SCRIPT.CALM)
		AWARENESS_ALERT:
			_awareness.reset()
			var alert_transitions: Array[Dictionary] = _awareness.register_noise()
			_apply_awareness_transitions(alert_transitions, "debug_force_alert")
			_flashlight_activation_delay_timer = 0.0
			_shadow_check_flashlight_override = false
			_shadow_scan_active = false
			_shadow_linger_flashlight = false
			_investigate_target_in_shadow = false
			_set_awareness_meta_from_system()
			_apply_alert_level(ENEMY_ALERT_LEVELS_SCRIPT.ALERT)
		AWARENESS_COMBAT:
			var forced_to_combat: bool = false
			if _awareness.has_method("process_confirm"):
				var forced_confirm_config := _confirm_config_with_defaults()
				forced_confirm_config["confirm_time_to_engage"] = 0.001
				_apply_awareness_transitions(_awareness.process_confirm(
					0.05,
					true,
					false,
					true,
					forced_confirm_config
				), "debug_force_combat_confirm")
				forced_to_combat = _awareness.has_method("get_state_name") and String(_awareness.get_state_name()) == AWARENESS_COMBAT
				if not forced_to_combat and _awareness.has_method("_transition_to_combat_from_damage"):
					var damage_transitions_variant: Variant = _awareness.call("_transition_to_combat_from_damage")
					if damage_transitions_variant is Array:
						var damage_transitions: Array[Dictionary] = []
						for transition_variant in (damage_transitions_variant as Array):
							if transition_variant is Dictionary:
								damage_transitions.append(transition_variant as Dictionary)
						_apply_awareness_transitions(damage_transitions, "debug_force_combat_damage")
			_set_awareness_meta_from_system()
			if _awareness.has_method("get_state_name") and String(_awareness.get_state_name()) == AWARENESS_COMBAT:
				_awareness.hostile_contact = true
				_raise_room_alert_for_combat_same_tick()
				_apply_alert_level(maxi(_resolve_room_alert_level(), ENEMY_ALERT_LEVELS_SCRIPT.ALERT))
			else:
				push_warning("[Enemy] debug_force_awareness_state: failed to force COMBAT")
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
		_apply_awareness_transitions(_awareness.register_reinforcement(), "reinforcement_called")


func _handle_confirmed_player_spotted(_player_pos: Vector2, broadcast_event: bool = true) -> void:
	if broadcast_event and EventBus:
		EventBus.emit_enemy_player_spotted(entity_id, Vector3(global_position.x, global_position.y, 0.0))


func _apply_awareness_transitions(transitions: Array[Dictionary], source: String = "unknown") -> void:
	# Guard is per-call (not per physics frame): allows one transition per batch/source.
	# Multiple sources in the same frame (e.g. process_confirm + register_reinforcement)
	# each get their own call and are each allowed one transition.
	var call_count := 0
	for transition_variant in transitions:
		var transition := transition_variant as Dictionary
		if transition.is_empty():
			continue
		var from_state := String(transition.get("from_state", ""))
		var to_state := String(transition.get("to_state", ""))
		var reason := String(transition.get("reason", ""))
		if call_count > 0:
			_debug_last_transition_from = from_state
			_debug_last_transition_to = to_state
			_debug_last_transition_reason = reason
			_debug_last_transition_source = source
			_debug_last_transition_blocked_by = TRANSITION_BLOCK_SINGLE_TICK
			continue
		call_count += 1
		_debug_transition_count_this_tick += 1
		_debug_last_transition_from = from_state
		_debug_last_transition_to = to_state
		_debug_last_transition_reason = reason
		_debug_last_transition_source = source
		_debug_last_transition_blocked_by = ""
		_emit_awareness_transition(transition)
		if transition.has("to_state"):
			set_meta("awareness_state", to_state)
			if _alert_latch_runtime and _alert_latch_runtime.has_method("sync_combat_latch_with_awareness_state"):
				_alert_latch_runtime.call("sync_combat_latch_with_awareness_state", to_state)
			if from_state == AWARENESS_ALERT and to_state != AWARENESS_ALERT:
				_investigate_target_in_shadow = false
				_shadow_linger_flashlight = _is_current_position_in_shadow()
			elif to_state == AWARENESS_ALERT:
				_shadow_linger_flashlight = false
			if to_state == AWARENESS_SUSPICIOUS:
				if source != "blood_evidence" and _last_seen_pos != Vector2.ZERO:
					_investigate_anchor = _last_seen_pos
					_investigate_anchor_valid = true
			elif from_state == AWARENESS_SUSPICIOUS and to_state != AWARENESS_SUSPICIOUS:
				_investigate_anchor_valid = false
				set_shadow_check_flashlight(false)
				set_shadow_scan_active(false)
				_shadow_scan_completed = false
				_shadow_scan_completed_reason = "none"
				if _pursuit and _pursuit.has_method("clear_shadow_scan_state"):
					_pursuit.clear_shadow_scan_state()
			if to_state == AWARENESS_COMBAT:
				if _fire_control_runtime and _fire_control_runtime.has_method("reset_first_shot_delay_state"):
					_fire_control_runtime.call("reset_first_shot_delay_state")
				_raise_room_alert_for_combat_same_tick()


func _set_awareness_meta_from_system() -> void:
	if not _awareness or not _awareness.has_method("get_state_name"):
		return
	var state_name := String(_awareness.get_state_name())
	set_meta("awareness_state", state_name)
	_debug_last_state_name = state_name
	if _alert_latch_runtime and _alert_latch_runtime.has_method("sync_combat_latch_with_awareness_state"):
		_alert_latch_runtime.call("sync_combat_latch_with_awareness_state", state_name)


func _refresh_transition_guard_tick() -> void:
	if _debug_snapshot_runtime and _debug_snapshot_runtime.has_method("refresh_transition_guard_tick"):
		_debug_snapshot_runtime.call("refresh_transition_guard_tick")
		return
	var tick_id := Engine.get_physics_frames()
	if _debug_last_transition_tick_id == tick_id:
		return
	_debug_last_transition_tick_id = tick_id
	_debug_transition_count_this_tick = 0
	_debug_last_transition_blocked_by = ""


func _apply_alert_level(level: int) -> void:
	_current_alert_level = level
	if _alert_marker_presenter:
		_alert_marker_presenter.set_alert_level(level)


func _resolve_room_alert_level() -> int:
	if _alert_latch_runtime and _alert_latch_runtime.has_method("resolve_room_alert_level"):
		return int(_alert_latch_runtime.call("resolve_room_alert_level"))
	var room_alert_snapshot := {
		"effective": ENEMY_ALERT_LEVELS_SCRIPT.CALM,
		"transient": ENEMY_ALERT_LEVELS_SCRIPT.CALM,
		"latch_count": 0,
	}
	if _alert_latch_runtime and _alert_latch_runtime.has_method("resolve_room_alert_snapshot"):
		room_alert_snapshot = _alert_latch_runtime.call("resolve_room_alert_snapshot") as Dictionary
	return int(room_alert_snapshot.get("effective", ENEMY_ALERT_LEVELS_SCRIPT.CALM))


func _resolve_squad_assignment() -> Dictionary:
	if squad_system and squad_system.has_method("get_assignment") and entity_id > 0:
		return squad_system.get_assignment(entity_id) as Dictionary
	return {
		"role": SQUAD_ROLE_PRESSURE,
		"slot_role": SQUAD_ROLE_PRESSURE,
		"slot_position": Vector2.ZERO,
		"path_ok": false,
		"path_status": "unreachable_geometry",
		"path_reason": "nav_service_missing",
		"slot_path_length": INF,
		"slot_path_eta_sec": INF,
		"has_slot": false,
	}


func _is_finite_nonzero_vector2(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y) and value != Vector2.ZERO


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
	if AIWatchdog:
		AIWatchdog.record_transition()


func _resolve_room_id_for_events() -> int:
	var room_id := int(get_meta("room_id", home_room_id))
	if nav_system and nav_system.has_method("room_id_at_point"):
		var detected_room_id := int(nav_system.room_id_at_point(global_position))
		if detected_room_id >= 0:
			room_id = detected_room_id
	if room_id >= 0:
		set_meta("room_id", room_id)
	return room_id


func _resolve_effective_alert_level_for_utility() -> int:
	# DESIGN (Hitman-3-style two-tier): room-COMBAT elevates intent to SEARCH,
	# but hostile_contact=false means this enemy hasn't personally confirmed the threat.
	# Enemies in room-COMBAT without personal LOS will pursue/search but not fire blindly.
	# This is intentional — not a bug. The per-room and per-enemy states are separate authorities.
	var awareness_alert := ENEMY_ALERT_LEVELS_SCRIPT.CALM
	if _awareness and _awareness.has_method("get_awareness_state"):
		awareness_alert = int(_awareness.get_awareness_state())
	if awareness_alert == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT:
		return ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
	return maxi(_current_alert_level, awareness_alert)


func _resolve_awareness_alert_level() -> int:
	var awareness_alert := ENEMY_ALERT_LEVELS_SCRIPT.CALM
	if _awareness and _awareness.has_method("get_awareness_state"):
		awareness_alert = int(_awareness.get_awareness_state())
	return clampi(
		awareness_alert,
		ENEMY_ALERT_LEVELS_SCRIPT.CALM,
		ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
	)


func _is_combat_lock_active() -> bool:
	if _awareness and _awareness.has_method("is_combat_locked"):
		return bool(_awareness.is_combat_locked())
	return _is_combat_awareness_active()


func _raise_room_alert_for_combat_same_tick() -> void:
	if _alert_latch_runtime and _alert_latch_runtime.has_method("raise_room_alert_for_combat_same_tick"):
		_alert_latch_runtime.call("raise_room_alert_for_combat_same_tick")
		return
	if alert_system == null or not alert_system.has_method("raise_combat_immediate"):
		return
	var room_id := _resolve_room_id_for_events()
	if room_id < 0:
		return
	alert_system.raise_combat_immediate(room_id, entity_id)
	_ensure_combat_latch_registered()


func get_current_alert_level() -> int:
	return _current_alert_level


func get_current_intent() -> Dictionary:
	if _utility_brain:
		return _utility_brain.get_current_intent()
	return {}


func debug_set_pursuit_speed_tiles_for_test(speed_tiles_value: float) -> bool:
	if _pursuit == null:
		return false
	if not _pursuit.has_method("set_speed_tiles"):
		return false
	_pursuit.call("set_speed_tiles", speed_tiles_value)
	return true


func debug_set_pursuit_facing_for_test(face_dir: Vector2) -> bool:
	if _pursuit == null:
		return false
	var dir := face_dir.normalized()
	if dir.length_squared() <= 0.0001:
		return false
	_pursuit.set("facing_dir", dir)
	_pursuit.set("_target_facing_dir", dir)
	return true


func debug_get_pursuit_facing_dir_for_test() -> Vector2:
	if _pursuit and _pursuit.has_method("get_facing_dir"):
		return _pursuit.call("get_facing_dir") as Vector2
	return Vector2.RIGHT


func debug_get_pursuit_navigation_policy_snapshot_for_test() -> Dictionary:
	if _pursuit and _pursuit.has_method("debug_get_navigation_policy_snapshot"):
		return _pursuit.call("debug_get_navigation_policy_snapshot") as Dictionary
	return {}


func debug_get_pursuit_system_for_test():
	return _pursuit


func debug_set_confirm_runtime_search_metrics(progress: float, total_elapsed_sec: float, room_elapsed_sec: float, total_cap_hit: bool) -> void:
	_combat_search_progress = progress
	_combat_search_total_elapsed_sec = total_elapsed_sec
	_combat_search_room_elapsed_sec = room_elapsed_sec
	_combat_search_total_cap_hit = total_cap_hit


func debug_build_confirm_runtime_config(base: Dictionary = {}) -> Dictionary:
	_ensure_runtime_helpers_initialized()
	return _build_confirm_runtime_config(base)


func debug_reset_utility_brain() -> void:
	if _utility_brain and _utility_brain.has_method("reset"):
		_utility_brain.reset()


func debug_is_point_in_flashlight_cone(point: Vector2, facing_dir: Vector2 = Vector2.ZERO) -> bool:
	if _flashlight_cone == null or not _flashlight_cone.has_method("is_point_in_cone"):
		return false
	var facing := facing_dir.normalized()
	if facing.length_squared() <= 0.0001:
		facing = debug_get_pursuit_facing_dir_for_test()
	if facing.length_squared() <= 0.0001:
		facing = Vector2.RIGHT
	return bool(_flashlight_cone.is_point_in_cone(global_position, facing, point))


func get_ui_awareness_snapshot() -> Dictionary:
	var zone_state := -1
	if _alert_latch_runtime and _alert_latch_runtime.has_method("get_zone_state"):
		zone_state = int(_alert_latch_runtime.call("get_zone_state"))
	else:
		var room_id := int(get_meta("room_id", -1))
		zone_state = _resolve_zone_state_for_room(room_id)
	if _awareness == null or not _awareness.has_method("get_ui_snapshot"):
		return {
			"state": ENEMY_ALERT_LEVELS_SCRIPT.CALM,
			"combat_phase": 0,
			"confirm01": 0.0,
			"hostile_contact": false,
			"hostile_damaged": false,
			"zone_state": zone_state,
		}
	var snap := (_awareness.get_ui_snapshot() as Dictionary).duplicate(true)
	snap["zone_state"] = zone_state
	return snap


func _resolve_zone_state_for_room(room_id: int) -> int:
	if _alert_latch_runtime and _alert_latch_runtime.has_method("resolve_zone_state_for_room"):
		return int(_alert_latch_runtime.call("resolve_zone_state_for_room", room_id))
	if not _zone_director:
		return -1
	if not _zone_director.has_method("get_zone_for_room") or not _zone_director.has_method("get_zone_state"):
		return -1
	var zone_id := int(_zone_director.get_zone_for_room(room_id))
	return int(_zone_director.get_zone_state(zone_id))


func configure_stealth_test_flashlight(angle_deg: float, distance_px: float, bonus: float) -> void:
	_setup_flashlight_cone()
	if not _flashlight_cone:
		return
	_flashlight_cone.set("cone_angle_deg", clampf(angle_deg, 1.0, 179.0))
	_flashlight_cone.set("cone_distance", maxf(distance_px, 1.0))
	if _flashlight_cone.has_method("set_flashlight_visibility_bonus"):
		_flashlight_cone.call("set_flashlight_visibility_bonus", maxf(bonus, 1.0))


func set_flashlight_hit_for_detection(hit: bool) -> void:
	_flashlight_hit_override = hit


func set_shadow_check_flashlight(active: bool) -> void:
	_shadow_check_flashlight_override = active


func set_shadow_scan_active(active: bool) -> void:
	_shadow_scan_active = active


func set_flashlight_scanner_allowed(allowed: bool) -> void:
	_flashlight_scanner_allowed = allowed


func _suspicious_shadow_scan_flashlight_bucket() -> int:
	var bucket: int = int(
		posmod(
			int(entity_id) + int(_debug_tick_id),
			SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_BUCKET_COUNT
		)
	)
	return bucket


func _suspicious_shadow_scan_flashlight_gate_passes() -> bool:
	var expected_active_buckets := int(
		round(
			SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_CHANCE * float(SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_BUCKET_COUNT)
		)
	)
	if expected_active_buckets != SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_ACTIVE_BUCKETS:
		push_warning("Suspicious shadow-scan flashlight bucket constants are inconsistent")
	return _suspicious_shadow_scan_flashlight_bucket() < SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_ACTIVE_BUCKETS


func is_flashlight_active_for_navigation() -> bool:
	var awareness_state := ENEMY_ALERT_LEVELS_SCRIPT.CALM
	if _awareness and _awareness.has_method("get_awareness_state"):
		awareness_state = int(_awareness.get_awareness_state())
	if _detection_runtime and _detection_runtime.has_method("compute_flashlight_active"):
		return bool(_detection_runtime.call("compute_flashlight_active", awareness_state))
	return false


func set_stealth_test_debug_logging(enabled: bool) -> void:
	if _debug_snapshot_runtime and _debug_snapshot_runtime.has_method("set_debug_logging"):
		_debug_snapshot_runtime.call("set_debug_logging", enabled)
		return
	_stealth_test_debug_logging_enabled = enabled
	if not enabled:
		_debug_last_logged_intent_type = -1
		_debug_last_logged_target_facing = Vector2.ZERO


func get_debug_detection_snapshot() -> Dictionary:
	_refresh_transition_guard_tick()
	if _debug_snapshot_runtime and _debug_snapshot_runtime.has_method("export_snapshot"):
		return _debug_snapshot_runtime.call("export_snapshot") as Dictionary
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
	var combat_search_nodes_total := 0
	var combat_search_nodes_covered := 0
	var combat_search_room_coverage_raw := 0.0
	if _combat_search_current_room_id >= 0:
		var room_nodes_variant: Variant = _combat_search_room_nodes.get(_combat_search_current_room_id, [])
		var room_nodes := room_nodes_variant as Array
		var visited := _combat_search_room_node_visited.get(_combat_search_current_room_id, {}) as Dictionary
		for node_variant in room_nodes:
			var node := node_variant as Dictionary
			var node_key := String(node.get("key", ""))
			var weight := float(node.get("coverage_weight", 0.0))
			if node_key == "" or not is_finite(weight) or weight <= 0.0:
				continue
			combat_search_nodes_total += 1
			if bool(visited.get(node_key, false)):
				combat_search_nodes_covered += 1
		combat_search_room_coverage_raw = clampf(float(_combat_search_room_coverage.get(_combat_search_current_room_id, 0.0)), 0.0, 1.0)
	var fire_profile_mode := "production"
	if _fire_control_runtime and _fire_control_runtime.has_method("resolve_ai_fire_profile_mode"):
		fire_profile_mode = String(_fire_control_runtime.call("resolve_ai_fire_profile_mode"))
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
		"flashlight_inactive_reason": _debug_last_flashlight_inactive_reason,
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
		"room_alert_effective": _debug_last_room_alert_effective,
		"room_alert_transient": _debug_last_room_alert_transient,
		"room_latch_count": _debug_last_room_latch_count,
		"latched": _debug_last_latched,
		"transition_from": _debug_last_transition_from,
		"transition_to": _debug_last_transition_to,
		"transition_reason": _debug_last_transition_reason,
		"transition_source": _debug_last_transition_source,
		"transition_blocked_by": _debug_last_transition_blocked_by,
		"transition_tick_id": _debug_last_transition_tick_id,
		"transition_count_this_tick": _debug_transition_count_this_tick,
		"shotgun_fire_block_reason": _debug_last_shotgun_fire_block_reason,
		"shotgun_fire_requested": _debug_last_shotgun_fire_requested,
		"shotgun_can_fire_contact": _debug_last_shotgun_can_fire,
		"shotgun_should_fire_now": _debug_last_shotgun_should_fire_now,
		"shotgun_fire_attempted": _debug_last_shotgun_fire_attempted,
		"shotgun_fire_success": _debug_last_shotgun_fire_success,
		"weapon_name": WEAPON_SHOTGUN,
		"shotgun_cooldown_left": _shot_cooldown,
		"fire_valid_contact_for_fire": _debug_last_valid_contact_for_fire,
		"fire_los": _debug_last_fire_los,
		"fire_inside_fov": _debug_last_fire_inside_fov,
		"fire_in_range": _debug_last_fire_in_range,
		"fire_not_occluded_by_world": _debug_last_fire_not_occluded_by_world,
		"fire_shadow_rule_passed": _debug_last_fire_shadow_rule_passed,
		"fire_weapon_ready": _debug_last_fire_weapon_ready,
		"fire_friendly_block": _debug_last_fire_friendly_block,
		"fire_profile_mode": fire_profile_mode,
		"shotgun_first_attack_delay_left": _combat_first_attack_delay_timer,
		"shotgun_first_attack_delay_armed": _combat_first_shot_delay_armed,
		"shotgun_first_attack_fired": _combat_first_shot_fired,
		"shotgun_first_attack_target_context_key": _combat_first_shot_target_context_key,
		"shotgun_fire_phase": _combat_fire_phase_name(_combat_fire_phase),
		"shotgun_fire_reposition_left": _combat_fire_reposition_left,
		"shotgun_first_attack_pause_left_before_reset": maxf(0.0, COMBAT_FIRST_SHOT_MAX_PAUSE_SEC - _combat_first_shot_pause_elapsed),
		"shotgun_first_attack_pause_elapsed": _combat_first_shot_pause_elapsed,
		"shotgun_telegraph_active": _combat_telegraph_active,
		"shotgun_telegraph_left": _combat_telegraph_timer,
		"shotgun_telegraph_pause_elapsed": _combat_telegraph_pause_elapsed,
		"shotgun_friendly_block_streak": _friendly_block_streak,
		"shotgun_friendly_block_reposition_cooldown_left": _friendly_block_reposition_cooldown_left,
		"shotgun_friendly_block_reposition_pending": _friendly_block_force_reposition,
		"combat_role_current": _combat_role_current,
		"combat_role_lock_left": _combat_role_lock_timer,
		"combat_role_reassign_reason": _combat_role_last_reassign_reason,
		"combat_search_progress": _combat_search_progress,
		"combat_search_total_elapsed_sec": _combat_search_total_elapsed_sec,
		"combat_search_room_elapsed_sec": _combat_search_room_elapsed_sec,
		"combat_search_room_budget_sec": _combat_search_room_budget_sec,
		"combat_search_current_room_id": _combat_search_current_room_id,
		"combat_search_target_pos": _combat_search_target_pos,
		"combat_search_total_cap_hit": _combat_search_total_cap_hit,
		"combat_search_node_key": _combat_search_current_node_key,
		"combat_search_node_kind": _combat_search_current_node_kind,
		"combat_search_node_requires_shadow_scan": _combat_search_current_node_requires_shadow_scan,
		"combat_search_node_shadow_scan_done": _combat_search_current_node_shadow_scan_done,
		"combat_search_room_nodes_total": combat_search_nodes_total,
		"combat_search_room_nodes_covered": combat_search_nodes_covered,
		"combat_search_room_coverage_raw": combat_search_room_coverage_raw,
		"combat_search_shadow_scan_suppressed": _combat_search_shadow_scan_suppressed_last_tick,
		"combat_search_recovery_applied": _combat_search_recovery_applied_last_tick,
		"combat_search_recovery_reason": _combat_search_recovery_reason_last_tick,
		"combat_search_recovery_blocked_point": _combat_search_recovery_blocked_point_last,
		"combat_search_recovery_blocked_point_valid": _combat_search_recovery_blocked_point_valid_last,
		"combat_search_recovery_skipped_node_key": _combat_search_recovery_skipped_node_key_last,
		"suspicion_ring_progress": _suspicion_ring.call("get_progress") if _suspicion_ring and _suspicion_ring.has_method("get_progress") else suspicion,
		"target_is_last_seen": _debug_last_target_is_last_seen,
		"last_seen_grace_left": _last_seen_grace_timer,
	}


func _record_runtime_tick_debug_state(payload: Dictionary) -> void:
	if _debug_snapshot_runtime and _debug_snapshot_runtime.has_method("record_runtime_tick_debug_state"):
		_debug_snapshot_runtime.call("record_runtime_tick_debug_state", payload)
		return
	var fire_contact := payload.get("fire_contact", {}) as Dictionary
	var intent := payload.get("intent", {}) as Dictionary
	var behavior_visible := bool(payload.get("behavior_visible", false))
	var visibility_factor := float(payload.get("visibility_factor", 0.0))
	var distance_factor := float(payload.get("distance_factor", 0.0))
	var shadow_mul := float(payload.get("shadow_mul", 1.0))
	var distance_to_player := float(payload.get("distance_to_player", INF))
	var flashlight_active := bool(payload.get("flashlight_active", false))
	var flashlight_hit := bool(payload.get("flashlight_hit", false))
	var flashlight_in_cone := bool(payload.get("flashlight_in_cone", false))
	var raw_player_visible := bool(payload.get("raw_player_visible", false))
	var valid_firing_solution := bool(payload.get("valid_firing_solution", false))
	var flashlight_bonus_raw := float(payload.get("flashlight_bonus_raw", 1.0))
	var flashlight_inactive_reason := String(payload.get("flashlight_inactive_reason", "state_blocked"))
	var effective_visibility_pre_clamp := float(payload.get("effective_visibility_pre_clamp", 0.0))
	var effective_visibility_post_clamp := float(payload.get("effective_visibility_post_clamp", 0.0))
	var room_alert_effective := int(payload.get("room_alert_effective", _debug_last_room_alert_effective))
	var flashlight_facing_used := payload.get("flashlight_facing_used", Vector2.RIGHT) as Vector2
	var facing_after_move := payload.get("facing_after_move", Vector2.RIGHT) as Vector2
	var target_facing_after_move := payload.get("target_facing_after_move", Vector2.RIGHT) as Vector2
	var debug_tick_id := int(payload.get("debug_tick_id", _debug_tick_id))

	_debug_last_has_los = behavior_visible
	_debug_last_visibility_factor = visibility_factor
	_debug_last_distance_factor = distance_factor
	_debug_last_shadow_mul = shadow_mul
	_debug_last_distance_to_player = distance_to_player
	_debug_last_flashlight_active = flashlight_active
	set_meta("flashlight_active", flashlight_active)
	_debug_last_flashlight_hit = flashlight_hit
	_debug_last_flashlight_in_cone = flashlight_in_cone
	_debug_last_flashlight_los_to_player = raw_player_visible
	_debug_last_valid_contact_for_fire = valid_firing_solution
	_debug_last_fire_los = bool(fire_contact.get("los", false))
	_debug_last_fire_inside_fov = bool(fire_contact.get("inside_fov", false))
	_debug_last_fire_in_range = bool(fire_contact.get("in_fire_range", false))
	_debug_last_fire_not_occluded_by_world = bool(fire_contact.get("not_occluded_by_world", false))
	_debug_last_fire_shadow_rule_passed = bool(fire_contact.get("shadow_rule_passed", false))
	_debug_last_fire_weapon_ready = bool(fire_contact.get("weapon_ready", false))
	_debug_last_fire_friendly_block = bool(fire_contact.get("friendly_block", false))
	_debug_last_flashlight_bonus_raw = flashlight_bonus_raw
	_debug_last_flashlight_inactive_reason = flashlight_inactive_reason
	_debug_last_effective_visibility_pre_clamp = effective_visibility_pre_clamp
	_debug_last_effective_visibility_post_clamp = effective_visibility_post_clamp
	_debug_last_intent_type = int(intent.get("type", -1))
	_debug_last_intent_target = intent.get("target", Vector2.ZERO) as Vector2
	_debug_last_last_seen_age = _last_seen_age
	_debug_last_room_alert_level = room_alert_effective
	_debug_last_facing_used_for_flashlight = flashlight_facing_used
	_debug_last_facing_after_move = facing_after_move
	_debug_last_flashlight_calc_tick_id = debug_tick_id
	if _awareness and _awareness.has_method("get_state_name"):
		_debug_last_state_name = String(_awareness.get_state_name())
	_debug_last_facing_dir = facing_after_move
	_debug_last_target_facing_dir = target_facing_after_move


func _apply_runtime_intent_stability_policy(intent: Dictionary, context: Dictionary, suspicion_now: float, delta: float) -> Dictionary:
	if _detection_runtime and _detection_runtime.has_method("apply_runtime_intent_stability_policy"):
		return _detection_runtime.call("apply_runtime_intent_stability_policy", intent, context, suspicion_now, delta) as Dictionary
	var out := intent.duplicate(true)
	var intent_type := int(out.get("type", ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL))
	var has_los := bool(context.get("los", false))
	var active_suspicion := suspicion_now >= INTENT_STABILITY_SUSPICION_MIN
	var should_stabilize := has_los or active_suspicion
	_intent_stability_lock_timer = maxf(0.0, _intent_stability_lock_timer - maxf(delta, 0.0))
	var blocked_intent := (
		intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT
		or intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETREAT
	)
	if should_stabilize and blocked_intent and _intent_stability_lock_timer > 0.0:
		if (
			_intent_stability_last_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT
			or _intent_stability_last_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETREAT
		):
			_intent_stability_last_type = ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.HOLD_RANGE
		intent_type = _intent_stability_last_type
		out["type"] = intent_type
		if not out.has("target") or (out.get("target", Vector2.ZERO) as Vector2) == Vector2.ZERO:
			out["target"] = context.get("known_target_pos", context.get("player_pos", global_position)) as Vector2
		return out

	if should_stabilize and blocked_intent:
		var dist := float(context.get("dist", INF))
		var hold_range_max := _utility_cfg_float("hold_range_max_px", 610.0)
		intent_type = ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.HOLD_RANGE if dist <= hold_range_max else ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH
		out["type"] = intent_type
		out["target"] = context.get("known_target_pos", context.get("player_pos", global_position)) as Vector2

	if should_stabilize and (
		intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.HOLD_RANGE
		or intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH
		or intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.INVESTIGATE
	):
		_intent_stability_last_type = intent_type
		_intent_stability_lock_timer = INTENT_STABILITY_LOCK_SEC
	elif not should_stabilize and _intent_stability_lock_timer <= 0.0:
		_intent_stability_last_type = intent_type

	return out


func _emit_stealth_debug_trace_if_needed(context: Dictionary, suspicion_now: float) -> void:
	if _debug_snapshot_runtime and _debug_snapshot_runtime.has_method("emit_stealth_debug_trace_if_needed"):
		_debug_snapshot_runtime.call("emit_stealth_debug_trace_if_needed", context, suspicion_now)
		return
	if not _stealth_test_debug_logging_enabled:
		return
	var intent_type := _debug_last_intent_type
	var target_facing := _debug_last_target_facing_dir
	var facing_delta := 0.0
	if _debug_last_logged_target_facing.length_squared() > 0.0001 and target_facing.length_squared() > 0.0001:
		facing_delta = absf(wrapf(target_facing.angle() - _debug_last_logged_target_facing.angle(), -PI, PI))
	var intent_changed := intent_type != _debug_last_logged_intent_type
	var facing_changed := facing_delta >= TEST_FACING_LOG_DELTA_RAD
	if not intent_changed and not facing_changed:
		return
	print("[EnemyStealthTrace] id=%d state=%s room_alert=%s intent=%d los=%s susp=%.3f vis=%.3f dist=%.1f last_seen_age=%.2f facing_delta=%.3f" % [
		entity_id,
		_debug_last_state_name,
		ENEMY_ALERT_LEVELS_SCRIPT.level_name(_debug_last_room_alert_level),
		intent_type,
		str(bool(context.get("los", false))),
		suspicion_now,
		_debug_last_visibility_factor,
		float(context.get("dist", INF)),
		_debug_last_last_seen_age,
		facing_delta,
	])
	_debug_last_logged_intent_type = intent_type
	_debug_last_logged_target_facing = target_facing


func _is_canon_confirm_mode() -> bool:
	return GameConfig != null and GameConfig.stealth_canon is Dictionary


func _stealth_canon_config() -> Dictionary:
	if _is_canon_confirm_mode():
		return GameConfig.stealth_canon as Dictionary
	return {}


func _confirm_config_with_defaults() -> Dictionary:
	var config := _stealth_canon_config().duplicate(true)
	if config.is_empty():
		config = {}
	config["confirm_time_to_engage"] = float(config.get("confirm_time_to_engage", 5.0))
	config["confirm_decay_rate"] = float(config.get("confirm_decay_rate", 1.25))
	config["confirm_grace_window"] = float(config.get("confirm_grace_window", 0.50))
	config["suspicious_enter"] = float(config.get("suspicious_enter", 0.25))
	config["alert_enter"] = float(config.get("alert_enter", 0.55))
	config["minimum_hold_alert_sec"] = float(config.get("minimum_hold_alert_sec", 2.5))
	return config


func _flashlight_policy_active_in_alert() -> bool:
	if _flashlight_activation_delay_timer > 0.0:
		return false
	return _flashlight_policy_flag("flashlight_active_in_alert", true)


func _flashlight_policy_active_in_calm() -> bool:
	return _shadow_check_flashlight_override


func _flashlight_policy_active_in_combat() -> bool:
	return _flashlight_policy_flag("flashlight_active_in_combat", true)


func _flashlight_policy_active_in_lockdown() -> bool:
	return _flashlight_policy_flag("flashlight_active_in_lockdown", true)


func _flashlight_policy_bonus_in_alert() -> bool:
	return _flashlight_policy_flag("flashlight_bonus_in_alert", true)


func _flashlight_policy_bonus_in_combat() -> bool:
	return _flashlight_policy_flag("flashlight_bonus_in_combat", true)


func _is_current_position_in_shadow() -> bool:
	if nav_system and nav_system.has_method("is_point_in_shadow"):
		return bool(nav_system.call("is_point_in_shadow", global_position))
	return false


func _effective_squad_role_for_context(role: int) -> int:
	var zone_lockdown_active := false
	if _alert_latch_runtime and _alert_latch_runtime.has_method("is_zone_lockdown"):
		zone_lockdown_active = bool(_alert_latch_runtime.call("is_zone_lockdown"))
	if not zone_lockdown_active:
		return role
	if role != SQUAD_ROLE_HOLD:
		return role
	var pressure_ratio := _lockdown_hold_to_pressure_ratio()
	if pressure_ratio <= 0.0:
		return role
	var normalized := float(posmod(entity_id, 1000)) / 1000.0
	if normalized < pressure_ratio:
		return SQUAD_ROLE_PRESSURE
	return role


func _lockdown_hold_to_pressure_ratio() -> float:
	if not (GameConfig and GameConfig.zone_system is Dictionary):
		return 0.0
	var zone_system := GameConfig.zone_system as Dictionary
	return clampf(float(zone_system.get("lockdown_hold_to_pressure_ratio", 0.0)), 0.0, 1.0)


func _flashlight_policy_flag(key: String, fallback: bool) -> bool:
	if not _is_canon_confirm_mode():
		return fallback
	var canon := _stealth_canon_config()
	var canon_key := key
	match key:
		"flashlight_active_in_alert":
			canon_key = "flashlight_works_in_alert"
		"flashlight_active_in_combat":
			canon_key = "flashlight_works_in_combat"
		"flashlight_active_in_lockdown":
			canon_key = "flashlight_works_in_lockdown"
		"flashlight_bonus_in_alert":
			canon_key = "flashlight_works_in_alert"
		"flashlight_bonus_in_combat":
			canon_key = "flashlight_works_in_combat"
		_:
			pass
	return bool(canon.get(canon_key, fallback))


func _utility_cfg_float(key: String, fallback: float) -> float:
	if GameConfig and GameConfig.ai_balance.has("utility"):
		var section := GameConfig.ai_balance["utility"] as Dictionary
		return float(section.get(key, fallback))
	return fallback


func _pursuit_cfg_float(key: String, fallback: float) -> float:
	if GameConfig and GameConfig.ai_balance.has("pursuit"):
		var section := GameConfig.ai_balance["pursuit"] as Dictionary
		return float(section.get(key, fallback))
	return fallback


func _squad_cfg_float(key: String, fallback: float) -> float:
	if GameConfig and GameConfig.ai_balance.has("squad"):
		var section := GameConfig.ai_balance["squad"] as Dictionary
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


func _tick_fire_runtime_cooldowns(delta: float) -> void:
	if _fire_control_runtime and _fire_control_runtime.has_method("tick_cooldowns"):
		_fire_control_runtime.call("tick_cooldowns", delta)
		return
	if _shot_cooldown > 0.0:
		_shot_cooldown = maxf(0.0, _shot_cooldown - maxf(delta, 0.0))
	if _friendly_block_reposition_cooldown_left > 0.0:
		_friendly_block_reposition_cooldown_left = maxf(0.0, _friendly_block_reposition_cooldown_left - maxf(delta, 0.0))


func _try_fire_at_player(player_pos: Vector2) -> bool:
	if _fire_control_runtime and _fire_control_runtime.has_method("try_fire_at_player"):
		return bool(_fire_control_runtime.call("try_fire_at_player", player_pos))
	return false


func _update_combat_fire_cycle_runtime(delta: float, can_fire_contact: bool) -> void:
	if _fire_control_runtime and _fire_control_runtime.has_method("update_combat_fire_cycle_runtime"):
		_fire_control_runtime.call("update_combat_fire_cycle_runtime", delta, can_fire_contact)


func _begin_combat_reposition_phase() -> void:
	if _fire_control_runtime and _fire_control_runtime.has_method("begin_combat_reposition_phase"):
		_fire_control_runtime.call("begin_combat_reposition_phase")


func _is_combat_reposition_phase_active() -> bool:
	if _fire_control_runtime and _fire_control_runtime.has_method("is_combat_reposition_phase_active"):
		return bool(_fire_control_runtime.call("is_combat_reposition_phase_active"))
	return _combat_fire_phase == COMBAT_FIRE_PHASE_REPOSITION and _combat_fire_reposition_left > 0.0


func _inject_combat_cycle_reposition_intent(intent: Dictionary, assignment: Dictionary, target_context: Dictionary) -> Dictionary:
	if _fire_control_runtime and _fire_control_runtime.has_method("inject_friendly_block_reposition_intent"):
		return _fire_control_runtime.call("inject_friendly_block_reposition_intent", intent, assignment, target_context) as Dictionary
	return intent.duplicate(true)


func _reset_combat_fire_cycle_state() -> void:
	if _fire_control_runtime and _fire_control_runtime.has_method("reset_combat_fire_cycle_state"):
		_fire_control_runtime.call("reset_combat_fire_cycle_state")
		return
	_combat_fire_phase = COMBAT_FIRE_PHASE_PEEK
	_combat_fire_reposition_left = 0.0


func _combat_fire_phase_name(phase: int) -> String:
	if _fire_control_runtime and _fire_control_runtime.has_method("combat_fire_phase_name"):
		return String(_fire_control_runtime.call("combat_fire_phase_name", phase))
	return "unknown"


func _anti_sync_fire_gate_open() -> bool:
	if _fire_control_runtime and _fire_control_runtime.has_method("anti_sync_fire_gate_open"):
		return bool(_fire_control_runtime.call("anti_sync_fire_gate_open"))
	return true


func _record_enemy_shot_tick() -> void:
	if _fire_control_runtime and _fire_control_runtime.has_method("record_enemy_shot_tick"):
		_fire_control_runtime.call("record_enemy_shot_tick")


static func debug_reset_fire_sync_gate() -> void:
	ENEMY_FIRE_CONTROL_RUNTIME_SCRIPT.debug_reset_fire_sync_gate()


static func debug_reset_fire_trace_cache_metrics() -> void:
	ENEMY_FIRE_CONTROL_RUNTIME_SCRIPT.debug_reset_fire_trace_cache_metrics()


static func debug_get_fire_trace_cache_metrics() -> Dictionary:
	return ENEMY_FIRE_CONTROL_RUNTIME_SCRIPT.debug_get_fire_trace_cache_metrics()


func _evaluate_fire_contact(
	player_valid: bool,
	player_pos: Vector2,
	facing_dir: Vector2,
	sight_fov_deg: float,
	sight_max_distance_px: float,
	in_shadow: bool,
	flashlight_active: bool
) -> Dictionary:
	if _fire_control_runtime and _fire_control_runtime.has_method("evaluate_fire_contact"):
		return _fire_control_runtime.call(
			"evaluate_fire_contact",
			player_valid,
			player_pos,
			facing_dir,
			sight_fov_deg,
			sight_max_distance_px,
			in_shadow,
			flashlight_active
		) as Dictionary
	return {}


func _trace_fire_line(player_pos: Vector2, ignore_friendlies: bool) -> Dictionary:
	if _fire_control_runtime and _fire_control_runtime.has_method("trace_fire_line"):
		return _fire_control_runtime.call("trace_fire_line", player_pos, ignore_friendlies) as Dictionary
	return {}


static func _rebuild_friendly_fire_excludes_cache(tree: SceneTree) -> void:
	ENEMY_FIRE_CONTROL_RUNTIME_SCRIPT._rebuild_friendly_fire_excludes_cache(tree)


func _is_player_collider_for_fire(collider: Variant) -> bool:
	if _fire_control_runtime and _fire_control_runtime.has_method("is_player_collider_for_fire"):
		return bool(_fire_control_runtime.call("is_player_collider_for_fire", collider))
	return false


func _is_friendly_collider_for_fire(collider: Variant) -> bool:
	if _fire_control_runtime and _fire_control_runtime.has_method("is_friendly_collider_for_fire"):
		return bool(_fire_control_runtime.call("is_friendly_collider_for_fire", collider))
	return false


func _inject_friendly_block_reposition_intent(intent: Dictionary, assignment: Dictionary, target_context: Dictionary) -> Dictionary:
	if _fire_control_runtime and _fire_control_runtime.has_method("inject_friendly_block_reposition_intent"):
		return _fire_control_runtime.call("inject_friendly_block_reposition_intent", intent, assignment, target_context) as Dictionary
	return intent.duplicate(true)


func _intent_supports_fire(intent_type: int) -> bool:
	if _fire_control_runtime and _fire_control_runtime.has_method("intent_supports_fire"):
		return bool(_fire_control_runtime.call("intent_supports_fire", intent_type))
	return false


func _is_combat_awareness_active() -> bool:
	if not _awareness:
		return false
	return _awareness.get_state_name() == AWARENESS_COMBAT


func _reset_combat_runtime_state_bundles() -> void:
	if _fire_control_runtime and _fire_control_runtime.has_method("reset_first_shot_delay_state"):
		_fire_control_runtime.call("reset_first_shot_delay_state")
	if _combat_role_runtime and _combat_role_runtime.has_method("reset_runtime"):
		_combat_role_runtime.call("reset_runtime")
	_reset_combat_search_state()


func _ensure_combat_latch_registered() -> void:
	if _alert_latch_runtime and _alert_latch_runtime.has_method("ensure_combat_latch_registered"):
		_alert_latch_runtime.call("ensure_combat_latch_registered")


func _unregister_combat_latch() -> void:
	if _alert_latch_runtime and _alert_latch_runtime.has_method("unregister_combat_latch"):
		_alert_latch_runtime.call("unregister_combat_latch")
		return
	_combat_latched = false
	_combat_latched_room_id = -1
	_debug_last_latched = false


func _reset_combat_migration_candidate() -> void:
	if _alert_latch_runtime and _alert_latch_runtime.has_method("reset_combat_migration_candidate"):
		_alert_latch_runtime.call("reset_combat_migration_candidate")
		return
	_combat_migration_candidate_room_id = -1
	_combat_migration_candidate_elapsed = 0.0


func _combat_room_migration_hysteresis_sec() -> float:
	if _alert_latch_runtime and _alert_latch_runtime.has_method("combat_room_migration_hysteresis_sec"):
		return float(_alert_latch_runtime.call("combat_room_migration_hysteresis_sec"))
	return COMBAT_ROOM_MIGRATION_HYSTERESIS_SEC


func _is_combat_latched() -> bool:
	if _alert_latch_runtime and _alert_latch_runtime.has_method("is_combat_latched"):
		return bool(_alert_latch_runtime.call("is_combat_latched"))
	return _combat_latched


func _combat_last_seen_grace_sec() -> float:
	return COMBAT_LAST_SEEN_GRACE_SEC


func _arm_first_combat_attack_delay() -> void:
	if _fire_control_runtime and _fire_control_runtime.has_method("arm_first_combat_attack_delay"):
		_fire_control_runtime.call("arm_first_combat_attack_delay")


func _arm_first_shot_telegraph() -> void:
	if _fire_control_runtime and _fire_control_runtime.has_method("arm_first_shot_telegraph"):
		_fire_control_runtime.call("arm_first_shot_telegraph")


func _cancel_first_shot_telegraph() -> void:
	if _fire_control_runtime and _fire_control_runtime.has_method("cancel_first_shot_telegraph"):
		_fire_control_runtime.call("cancel_first_shot_telegraph")


func _is_test_scene_context() -> bool:
	if get_tree() == null:
		return false
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return false
	var scene_path := String(current_scene.scene_file_path)
	return scene_path.begins_with("res://tests/")


func _is_first_shot_gate_ready() -> bool:
	if _fire_control_runtime and _fire_control_runtime.has_method("is_first_shot_gate_ready"):
		return bool(_fire_control_runtime.call("is_first_shot_gate_ready"))
	return false


func _mark_enemy_shot_success() -> void:
	if _fire_control_runtime and _fire_control_runtime.has_method("mark_enemy_shot_success"):
		_fire_control_runtime.call("mark_enemy_shot_success")


func _combat_target_context_key(target_context: Dictionary) -> String:
	if target_context.is_empty():
		return ""
	var has_known_target := bool(target_context.get("has_known_target", false))
	if not has_known_target:
		return ""
	var target_pos := target_context.get("known_target_pos", Vector2.ZERO) as Vector2
	var room_id := _resolve_target_room_id(target_pos)
	var bucket_x := int(round(target_pos.x / 32.0))
	var bucket_y := int(round(target_pos.y / 32.0))
	return "%d:%d:%d" % [room_id, bucket_x, bucket_y]


func _build_confirm_runtime_config(base: Dictionary) -> Dictionary:
	var config := base.duplicate(true)
	config["combat_no_contact_window_sec"] = _combat_no_contact_window_sec()
	config["combat_require_search_progress"] = true
	config["combat_search_progress"] = _combat_search_progress
	config["combat_search_total_elapsed_sec"] = _combat_search_total_elapsed_sec
	config["combat_search_room_elapsed_sec"] = _combat_search_room_elapsed_sec
	config["combat_search_total_cap_sec"] = COMBAT_SEARCH_TOTAL_CAP_SEC
	config["combat_search_force_complete"] = _combat_search_total_cap_hit
	return config


func _combat_no_contact_window_sec() -> float:
	var zone_lockdown_active := false
	if _alert_latch_runtime and _alert_latch_runtime.has_method("is_zone_lockdown"):
		zone_lockdown_active = bool(_alert_latch_runtime.call("is_zone_lockdown"))
	return COMBAT_NO_CONTACT_WINDOW_LOCKDOWN_SEC if zone_lockdown_active else COMBAT_NO_CONTACT_WINDOW_SEC


func _resolve_runtime_combat_role(base_role: int) -> int:
	if _combat_role_runtime and _combat_role_runtime.has_method("resolve_runtime_combat_role"):
		return int(_combat_role_runtime.call("resolve_runtime_combat_role", base_role))
	return base_role


func _current_pursuit_shadow_search_stage() -> int:
	if _combat_search_runtime and _combat_search_runtime.has_method("current_pursuit_shadow_search_stage"):
		return int(_combat_search_runtime.call("current_pursuit_shadow_search_stage"))
	return -1


func _clear_combat_search_current_node(reset_shadow_scan_suppressed: bool = true) -> void:
	if _combat_search_runtime and _combat_search_runtime.has_method("clear_current_node"):
		_combat_search_runtime.call("clear_current_node", reset_shadow_scan_suppressed)


func _apply_combat_search_node_pick(pick: Dictionary) -> void:
	if _combat_search_runtime and _combat_search_runtime.has_method("apply_node_pick"):
		_combat_search_runtime.call("apply_node_pick", pick)


func _reset_combat_search_state() -> void:
	if _combat_search_runtime and _combat_search_runtime.has_method("reset_state"):
		_combat_search_runtime.call("reset_state")


func _ensure_combat_search_room(room_id: int, combat_target_pos: Vector2) -> void:
	if _combat_search_runtime and _combat_search_runtime.has_method("ensure_room"):
		_combat_search_runtime.call("ensure_room", room_id, combat_target_pos)


func _compute_combat_search_room_coverage(room_id: int) -> float:
	if _combat_search_runtime and _combat_search_runtime.has_method("compute_room_coverage"):
		return float(_combat_search_runtime.call("compute_room_coverage", room_id))
	return 0.0


func _mark_combat_search_current_node_covered() -> void:
	if _combat_search_runtime and _combat_search_runtime.has_method("mark_current_node_covered"):
		_combat_search_runtime.call("mark_current_node_covered")


func _door_hops_between(from_room: int, to_room: int) -> int:
	if _combat_search_runtime and _combat_search_runtime.has_method("door_hops_between"):
		return int(_combat_search_runtime.call("door_hops_between", from_room, to_room))
	return 999


func _resolve_target_room_id(pos: Vector2) -> int:
	if nav_system and nav_system.has_method("room_id_at_point"):
		return int(nav_system.room_id_at_point(pos))
	return int(get_meta("room_id", -1))


func _is_last_seen_grace_active() -> bool:
	return _last_seen_grace_timer > 0.0


func _seed_last_seen_from_player_if_missing() -> void:
	if _last_seen_age < INF:
		return
	if _perception == null or not _perception.has_method("has_player") or not _perception.has_method("get_player_position"):
		return
	if not bool(_perception.has_player()):
		return
	var player_pos := _perception.get_player_position() as Vector2
	if player_pos == Vector2.ZERO:
		return
	_last_seen_pos = player_pos
	_last_seen_age = 0.0
	_last_seen_grace_timer = _combat_last_seen_grace_sec()


func _fire_enemy_shotgun(origin: Vector2, aim_dir: Vector2) -> void:
	if not _perception:
		return
	var stats := {}
	if _fire_control_runtime and _fire_control_runtime.has_method("shotgun_stats"):
		stats = _fire_control_runtime.call("shotgun_stats") as Dictionary
	elif GameConfig and GameConfig.weapon_stats.has(WEAPON_SHOTGUN):
		stats = GameConfig.weapon_stats[WEAPON_SHOTGUN] as Dictionary
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

	var applied_damage: int = GameConfig.shotgun_hit_contact_damage if GameConfig else 0

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
	var ring_enabled := true
	if _suspicion_ring.has_method("set_enabled"):
		_suspicion_ring.call("set_enabled", ring_enabled)
	else:
		var ring_canvas := _suspicion_ring as CanvasItem
		if ring_canvas:
			ring_canvas.visible = ring_enabled


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


## Apply damage from any source (projectile, explosion, etc.)
## Reduces HP, emits EventBus signals, handles death once.
func apply_damage(amount: int, source: String, from_player: bool = false) -> void:
	ENEMY_DAMAGE_RUNTIME_SCRIPT.apply_damage(self, amount, source, from_player)


## Apply stagger (blocks movement for duration)
func apply_stagger(sec: float) -> void:
	stagger_timer = maxf(stagger_timer, sec)


## Apply knockback impulse
func apply_knockback(impulse: Vector2) -> void:
	knockback_vel = impulse


## Enemy death
func die() -> void:
	if is_dead:
		return

	is_dead = true
	_unregister_combat_latch()

	if RuntimeState:
		# AUTHORITY: kills tracked HERE only. Any enemy_killed signal listener
		# MUST NOT increment RuntimeState.kills — doing so would double-count.
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
