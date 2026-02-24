## enemy_fire_control_runtime.gd
## Phase 4 owner for fire-control domain.
class_name EnemyFireControlRuntime
extends RefCounted

const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")

const WEAPON_SHOTGUN := "shotgun"
const DEFAULT_FIRE_ATTACK_RANGE_MAX_PX := 600.0
const DEFAULT_FIRE_SPAWN_OFFSET_PX := 20.0
const DEFAULT_FIRE_RAY_RANGE_PX := 2000.0
const ENEMY_FIRE_MIN_COOLDOWN_SEC := 0.25
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
const COMBAT_FIRST_ATTACK_DELAY_MIN_SEC := 1.2
const COMBAT_FIRST_ATTACK_DELAY_MAX_SEC := 2.0
const COMBAT_FIRST_SHOT_MAX_PAUSE_SEC := 2.5
const COMBAT_TELEGRAPH_MAX_PAUSE_SEC := 0.6
const COMBAT_TELEGRAPH_PRODUCTION_MIN_SEC := 0.10
const COMBAT_TELEGRAPH_PRODUCTION_MAX_SEC := 0.18
const COMBAT_TELEGRAPH_DEBUG_MIN_SEC := 0.35
const COMBAT_TELEGRAPH_DEBUG_MAX_SEC := 0.60
const COMBAT_FIRE_PHASE_PEEK := 0
const COMBAT_FIRE_PHASE_FIRE := 1
const COMBAT_FIRE_PHASE_REPOSITION := 2
const COMBAT_FIRE_REPOSITION_SEC := 0.35
const FRIENDLY_BLOCK_REPOSITION_COOLDOWN_SEC := 0.8
const FRIENDLY_BLOCK_STREAK_TRIGGER := 2
const FRIENDLY_BLOCK_SIDESTEP_DISTANCE_PX := 96.0

static var _global_enemy_shot_tick: int = -1
static var _friendly_fire_excludes_physics_frame: int = -1
static var _friendly_fire_excludes_cache: Array[RID] = []
static var _friendly_fire_excludes_rebuild_count: int = 0

var _owner: Node = null


func _init(owner: Node = null) -> void:
	_owner = owner


func bind(owner: Node) -> void:
	_owner = owner


func get_owner() -> Node:
	return _owner


func has_owner() -> bool:
	return _owner != null


func get_state_value(key: String, default_value: Variant = null) -> Variant:
	if _owner == null:
		return default_value
	var value: Variant = _owner.get(key)
	return default_value if value == null else value


func set_state_value(key: String, value: Variant) -> void:
	if _owner == null:
		return
	_owner.set(key, value)


func set_state_patch(values: Dictionary) -> void:
	if _owner == null:
		return
	for key_variant in values.keys():
		var key := String(key_variant)
		_owner.set(key, values[key_variant])


func tick_cooldowns(delta: float) -> void:
	var clamped_delta := maxf(delta, 0.0)
	var shot_cooldown := float(get_state_value("_shot_cooldown", 0.0))
	if shot_cooldown > 0.0:
		set_state_value("_shot_cooldown", maxf(0.0, shot_cooldown - clamped_delta))
	var friendly_cooldown := float(get_state_value("_friendly_block_reposition_cooldown_left", 0.0))
	if friendly_cooldown > 0.0:
		set_state_value("_friendly_block_reposition_cooldown_left", maxf(0.0, friendly_cooldown - clamped_delta))


func try_fire_at_player(player_pos: Vector2) -> bool:
	if _owner == null:
		return false
	if float(get_state_value("_shot_cooldown", 0.0)) > 0.0:
		return false
	if not _owner_is_combat_awareness_active():
		return false
	if not is_first_shot_gate_ready():
		return false
	if not _owner.has_method("_fire_enemy_shotgun"):
		return false

	var owner_pos := _owner_global_position()
	var aim_dir := (player_pos - owner_pos).normalized()
	if aim_dir.length_squared() <= 0.0001:
		return false

	var pursuit: Variant = get_state_value("_pursuit", null)
	if pursuit != null and pursuit.has_method("face_towards"):
		pursuit.face_towards(player_pos)

	var muzzle := owner_pos + aim_dir * _owner_enemy_vision_cfg_float("fire_spawn_offset_px", DEFAULT_FIRE_SPAWN_OFFSET_PX)
	_owner.call("_fire_enemy_shotgun", muzzle, aim_dir)
	set_state_value("_shot_cooldown", shotgun_cooldown_sec())

	if EventBus:
		EventBus.emit_enemy_shot(
			int(get_state_value("entity_id", -1)),
			WEAPON_SHOTGUN,
			Vector3(muzzle.x, muzzle.y, 0.0),
			Vector3(aim_dir.x, aim_dir.y, 0.0)
		)
	return true


func resolve_shotgun_fire_block_reason(fire_contact: Dictionary) -> String:
	if not _owner_is_combat_awareness_active():
		return SHOTGUN_FIRE_BLOCK_NO_COMBAT_STATE
	if not bool(fire_contact.get("los", false)):
		return SHOTGUN_FIRE_BLOCK_NO_LOS
	if not bool(fire_contact.get("inside_fov", false)):
		return SHOTGUN_FIRE_BLOCK_NO_LOS
	if not bool(fire_contact.get("in_fire_range", false)):
		return SHOTGUN_FIRE_BLOCK_OUT_OF_RANGE
	if not bool(fire_contact.get("not_occluded_by_world", false)):
		return SHOTGUN_FIRE_BLOCK_NO_LOS
	if not bool(fire_contact.get("shadow_rule_passed", false)):
		return SHOTGUN_FIRE_BLOCK_SHADOW_BLOCKED
	if not bool(fire_contact.get("weapon_ready", false)):
		return SHOTGUN_FIRE_BLOCK_COOLDOWN
	if not is_first_shot_gate_ready():
		if bool(get_state_value("_combat_telegraph_active", false)):
			return SHOTGUN_FIRE_BLOCK_TELEGRAPH
		return SHOTGUN_FIRE_BLOCK_FIRST_ATTACK_DELAY
	if bool(fire_contact.get("friendly_block", false)):
		return SHOTGUN_FIRE_BLOCK_FRIENDLY_BLOCK
	return ""


func can_fire_contact_allows_shot(fire_contact: Dictionary) -> bool:
	return (
		bool(fire_contact.get("valid_contact_for_fire", false))
		and is_first_shot_gate_ready()
		and not bool(fire_contact.get("friendly_block", false))
	)


func resolve_shotgun_fire_schedule_block_reason() -> String:
	if is_combat_reposition_phase_active():
		return SHOTGUN_FIRE_BLOCK_REPOSITION
	if not anti_sync_fire_gate_open():
		return SHOTGUN_FIRE_BLOCK_SYNC_WINDOW
	return ""


func should_fire_now(tactical_request: bool, can_fire_contact: bool) -> bool:
	if not tactical_request or not can_fire_contact:
		return false
	return resolve_shotgun_fire_schedule_block_reason() == ""


func update_combat_fire_cycle_runtime(delta: float, can_fire_contact: bool) -> void:
	if not _owner_is_combat_awareness_active():
		reset_combat_fire_cycle_state()
		return
	var phase := int(get_state_value("_combat_fire_phase", COMBAT_FIRE_PHASE_PEEK))
	if phase == COMBAT_FIRE_PHASE_REPOSITION:
		var reposition_left := maxf(0.0, float(get_state_value("_combat_fire_reposition_left", 0.0)) - maxf(delta, 0.0))
		set_state_value("_combat_fire_reposition_left", reposition_left)
		if reposition_left <= 0.0:
			set_state_value("_combat_fire_phase", COMBAT_FIRE_PHASE_PEEK)
		return
	set_state_value("_combat_fire_phase", COMBAT_FIRE_PHASE_FIRE if can_fire_contact else COMBAT_FIRE_PHASE_PEEK)


func begin_combat_reposition_phase() -> void:
	set_state_value("_combat_fire_phase", COMBAT_FIRE_PHASE_REPOSITION)
	set_state_value("_combat_fire_reposition_left", COMBAT_FIRE_REPOSITION_SEC)


func is_combat_reposition_phase_active() -> bool:
	return (
		int(get_state_value("_combat_fire_phase", COMBAT_FIRE_PHASE_PEEK)) == COMBAT_FIRE_PHASE_REPOSITION
		and float(get_state_value("_combat_fire_reposition_left", 0.0)) > 0.0
	)


func reset_combat_fire_cycle_state() -> void:
	set_state_value("_combat_fire_phase", COMBAT_FIRE_PHASE_PEEK)
	set_state_value("_combat_fire_reposition_left", 0.0)


func combat_fire_phase_name(phase: int) -> String:
	match phase:
		COMBAT_FIRE_PHASE_PEEK:
			return "peek"
		COMBAT_FIRE_PHASE_FIRE:
			return "fire"
		COMBAT_FIRE_PHASE_REPOSITION:
			return "reposition"
		_:
			return "unknown"


func anti_sync_fire_gate_open() -> bool:
	return Engine.get_physics_frames() != _global_enemy_shot_tick


func record_enemy_shot_tick() -> void:
	_global_enemy_shot_tick = Engine.get_physics_frames()


static func debug_reset_fire_sync_gate() -> void:
	_global_enemy_shot_tick = -1


static func debug_reset_fire_trace_cache_metrics() -> void:
	_friendly_fire_excludes_physics_frame = -1
	_friendly_fire_excludes_cache = []
	_friendly_fire_excludes_rebuild_count = 0


static func debug_get_fire_trace_cache_metrics() -> Dictionary:
	return {
		"physics_frame": _friendly_fire_excludes_physics_frame,
		"cache_size": _friendly_fire_excludes_cache.size(),
		"rebuild_count": _friendly_fire_excludes_rebuild_count,
	}


func evaluate_fire_contact(
	player_valid: bool,
	player_pos: Vector2,
	facing_dir: Vector2,
	sight_fov_deg: float,
	sight_max_distance_px: float,
	in_shadow: bool,
	flashlight_active: bool
) -> Dictionary:
	var out := {
		"los": false,
		"inside_fov": false,
		"in_fire_range": false,
		"not_occluded_by_world": false,
		"shadow_rule_passed": false,
		"weapon_ready": false,
		"friendly_block": false,
		"valid_contact_for_fire": false,
		"occlusion_kind": "none",
	}
	if not player_valid:
		return out

	var owner_pos := _owner_global_position()
	var to_player := player_pos - owner_pos
	var dist := to_player.length()
	if dist <= 0.001:
		return out
	var dir_to_player := to_player / dist
	var facing := facing_dir.normalized()
	if facing.length_squared() <= 0.0001:
		facing = dir_to_player
	var min_dot := cos(deg_to_rad(sight_fov_deg) * 0.5)
	var inside_fov := facing.dot(dir_to_player) >= min_dot
	var in_fire_range := dist <= _owner_enemy_vision_cfg_float("fire_attack_range_max_px", DEFAULT_FIRE_ATTACK_RANGE_MAX_PX)
	var trace_with_friendlies := trace_fire_line(player_pos, false)
	var friendly_block := bool(trace_with_friendlies.get("hit_friendly", false))
	var trace_ignore_friendlies := trace_with_friendlies
	if friendly_block:
		trace_ignore_friendlies = trace_fire_line(player_pos, true)
	var not_occluded_by_world := bool(trace_ignore_friendlies.get("hit_player", false))
	var los := not_occluded_by_world and dist <= sight_max_distance_px
	var shadow_rule_passed := (not in_shadow) or flashlight_active
	var weapon_ready := float(get_state_value("_shot_cooldown", 0.0)) <= 0.0
	var valid_contact_for_fire := (
		los
		and inside_fov
		and in_fire_range
		and not_occluded_by_world
		and shadow_rule_passed
		and weapon_ready
	)

	out["los"] = los
	out["inside_fov"] = inside_fov
	out["in_fire_range"] = in_fire_range
	out["not_occluded_by_world"] = not_occluded_by_world
	out["shadow_rule_passed"] = shadow_rule_passed
	out["weapon_ready"] = weapon_ready
	out["friendly_block"] = friendly_block
	out["valid_contact_for_fire"] = valid_contact_for_fire
	out["occlusion_kind"] = String(trace_ignore_friendlies.get("hit_kind", "none"))
	return out


func trace_fire_line(player_pos: Vector2, ignore_friendlies: bool) -> Dictionary:
	var out := {
		"hit_player": false,
		"hit_friendly": false,
		"hit_world": false,
		"hit_kind": "none",
	}
	if _owner == null:
		return out
	var owner_pos := _owner_global_position()
	var to_player := player_pos - owner_pos
	if to_player.length_squared() <= 0.0001:
		return out
	var dir_to_player := to_player.normalized()
	var spawn_offset := _owner_enemy_vision_cfg_float("fire_spawn_offset_px", DEFAULT_FIRE_SPAWN_OFFSET_PX)
	var start_offset := minf(spawn_offset, maxf(to_player.length() - 1.0, 0.0))
	var ray_start := owner_pos + dir_to_player * start_offset
	var query := PhysicsRayQueryParameters2D.create(ray_start, player_pos)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = build_fire_line_excludes(ignore_friendlies)

	var owner_node := _owner as Node2D
	if owner_node == null or owner_node.get_world_2d() == null:
		return out
	var hit := owner_node.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return out
	var collider: Variant = hit.get("collider", null)
	if is_player_collider_for_fire(collider):
		out["hit_player"] = true
		out["hit_kind"] = "player"
	elif is_friendly_collider_for_fire(collider):
		out["hit_friendly"] = true
		out["hit_kind"] = "friendly"
	else:
		out["hit_world"] = true
		out["hit_kind"] = "world"
	return out


func build_fire_line_excludes(ignore_friendlies: bool) -> Array[RID]:
	var excludes := _owner_ray_excludes()
	if not ignore_friendlies:
		return excludes
	if _owner == null:
		return excludes
	var tree := _owner.get_tree()
	if tree == null:
		return excludes
	var frame_id := Engine.get_physics_frames()
	if _friendly_fire_excludes_physics_frame != frame_id:
		_rebuild_friendly_fire_excludes_cache(tree)
		_friendly_fire_excludes_physics_frame = frame_id
	return _friendly_fire_excludes_cache


static func _rebuild_friendly_fire_excludes_cache(tree: SceneTree) -> void:
	var rebuilt: Array[RID] = []
	for enemy_variant in tree.get_nodes_in_group("enemies"):
		var enemy_node := enemy_variant as Node2D
		if enemy_node == null:
			continue
		rebuilt.append(enemy_node.get_rid())
	_friendly_fire_excludes_cache = rebuilt
	_friendly_fire_excludes_rebuild_count += 1


func is_player_collider_for_fire(collider: Variant) -> bool:
	if collider == null:
		return false
	var node := collider as Node
	if node == null:
		return false
	if node.is_in_group("player"):
		return true
	var parent := node.get_parent()
	return parent != null and parent.is_in_group("player")


func is_friendly_collider_for_fire(collider: Variant) -> bool:
	if collider == null:
		return false
	var node := collider as Node
	if node == null:
		return false
	return node != _owner and node.is_in_group("enemies")


func register_friendly_block_and_reposition() -> void:
	var streak := int(get_state_value("_friendly_block_streak", 0)) + 1
	set_state_value("_friendly_block_streak", streak)
	if streak < FRIENDLY_BLOCK_STREAK_TRIGGER:
		return
	if float(get_state_value("_friendly_block_reposition_cooldown_left", 0.0)) > 0.0:
		return
	set_state_value("_friendly_block_force_reposition", true)
	set_state_value("_friendly_block_reposition_cooldown_left", FRIENDLY_BLOCK_REPOSITION_COOLDOWN_SEC)


func inject_friendly_block_reposition_intent(intent: Dictionary, assignment: Dictionary, target_context: Dictionary) -> Dictionary:
	var out := intent.duplicate(true)
	var slot_pos := assignment.get("slot_position", Vector2.ZERO) as Vector2
	var has_slot := bool(assignment.get("has_slot", false))
	var path_ok := bool(assignment.get("path_ok", false))
	if has_slot and path_ok and slot_pos != Vector2.ZERO:
		out["type"] = ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT
		out["target"] = slot_pos
		return out

	var owner_pos := _owner_global_position()
	var known_target := target_context.get("known_target_pos", Vector2.ZERO) as Vector2
	if known_target == Vector2.ZERO:
		known_target = owner_pos + Vector2.RIGHT
	var to_target := (known_target - owner_pos).normalized()
	if to_target.length_squared() <= 0.0001:
		to_target = Vector2.RIGHT
	var side := Vector2(-to_target.y, to_target.x)
	if side.length_squared() <= 0.0001:
		side = Vector2.RIGHT
	var side_sign := 1.0 if (_shot_rng().randi() % 2) == 0 else -1.0
	out["type"] = ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH
	out["target"] = owner_pos + side.normalized() * FRIENDLY_BLOCK_SIDESTEP_DISTANCE_PX * side_sign
	return out


func intent_supports_fire(intent_type: int) -> bool:
	return (
		intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.HOLD_RANGE
		or intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH
	)


func arm_first_combat_attack_delay() -> void:
	var min_delay := COMBAT_FIRST_ATTACK_DELAY_MIN_SEC
	var max_delay := COMBAT_FIRST_ATTACK_DELAY_MAX_SEC
	if max_delay < min_delay:
		var tmp := min_delay
		min_delay = max_delay
		max_delay = tmp
	set_state_value("_combat_first_attack_delay_timer", _shot_rng().randf_range(min_delay, max_delay))


func arm_first_shot_telegraph() -> void:
	set_state_value("_combat_telegraph_active", true)
	set_state_value("_combat_telegraph_timer", roll_telegraph_duration_sec())
	set_state_value("_combat_telegraph_pause_elapsed", 0.0)


func cancel_first_shot_telegraph() -> void:
	set_state_value("_combat_telegraph_active", false)
	set_state_value("_combat_telegraph_timer", 0.0)
	set_state_value("_combat_telegraph_pause_elapsed", 0.0)


func resolve_ai_fire_profile_mode() -> String:
	var mode := "auto"
	if GameConfig and "ai_fire_profile_mode" in GameConfig:
		mode = String(GameConfig.ai_fire_profile_mode).strip_edges().to_lower()
	if mode == "production" or mode == "debug_test":
		return mode
	return "debug_test" if _owner_is_test_scene_context() else "production"


func roll_telegraph_duration_sec() -> float:
	var mode := resolve_ai_fire_profile_mode()
	var min_sec := COMBAT_TELEGRAPH_PRODUCTION_MIN_SEC
	var max_sec := COMBAT_TELEGRAPH_PRODUCTION_MAX_SEC
	if mode == "debug_test":
		min_sec = COMBAT_TELEGRAPH_DEBUG_MIN_SEC
		max_sec = COMBAT_TELEGRAPH_DEBUG_MAX_SEC
	if GameConfig and "ai_fire_profiles" in GameConfig and GameConfig.ai_fire_profiles is Dictionary:
		var profiles := GameConfig.ai_fire_profiles as Dictionary
		var selected_profile := profiles.get(mode, {}) as Dictionary
		min_sec = float(selected_profile.get("telegraph_min_sec", min_sec))
		max_sec = float(selected_profile.get("telegraph_max_sec", max_sec))
	if max_sec < min_sec:
		var tmp := min_sec
		min_sec = max_sec
		max_sec = tmp
	return _shot_rng().randf_range(min_sec, max_sec)


func is_first_shot_gate_ready() -> bool:
	if bool(get_state_value("_combat_first_shot_fired", false)):
		return true
	if not bool(get_state_value("_combat_first_shot_delay_armed", false)):
		return false
	if float(get_state_value("_combat_first_attack_delay_timer", 0.0)) > 0.0:
		return false
	if not bool(get_state_value("_combat_telegraph_active", false)):
		return false
	return float(get_state_value("_combat_telegraph_timer", 0.0)) <= 0.0


func mark_enemy_shot_success() -> void:
	set_state_value("_combat_first_shot_fired", true)
	set_state_value("_combat_first_attack_delay_timer", 0.0)
	set_state_value("_combat_first_shot_pause_elapsed", 0.0)
	cancel_first_shot_telegraph()
	begin_combat_reposition_phase()
	record_enemy_shot_tick()
	set_state_value("_friendly_block_streak", 0)


func reset_first_shot_delay_state() -> void:
	set_state_value("_combat_first_attack_delay_timer", 0.0)
	set_state_value("_combat_first_shot_delay_armed", false)
	set_state_value("_combat_first_shot_fired", false)
	set_state_value("_combat_first_shot_target_context_key", "")
	set_state_value("_combat_first_shot_pause_elapsed", 0.0)
	cancel_first_shot_telegraph()
	reset_combat_fire_cycle_state()


func update_first_shot_delay_runtime(delta: float, has_valid_solution: bool, target_context_key: String) -> void:
	if not _owner_is_combat_awareness_active():
		reset_first_shot_delay_state()
		return
	if bool(get_state_value("_combat_first_shot_fired", false)):
		return
	var min_rearm_delay := -1.0
	var current_context_key := String(get_state_value("_combat_first_shot_target_context_key", ""))
	var has_context_change := (
		bool(get_state_value("_combat_first_shot_delay_armed", false))
		and current_context_key != ""
		and target_context_key != ""
		and target_context_key != current_context_key
	)
	if has_context_change:
		min_rearm_delay = float(get_state_value("_combat_first_attack_delay_timer", 0.0))
		reset_first_shot_delay_state()
	if not bool(get_state_value("_combat_first_shot_delay_armed", false)):
		if has_valid_solution:
			arm_first_combat_attack_delay()
			if min_rearm_delay > 0.0:
				var rearm_floor := minf(COMBAT_FIRST_ATTACK_DELAY_MAX_SEC, min_rearm_delay + 0.001)
				var armed_delay := float(get_state_value("_combat_first_attack_delay_timer", 0.0))
				set_state_value("_combat_first_attack_delay_timer", maxf(armed_delay, rearm_floor))
			set_state_value("_combat_first_shot_delay_armed", true)
			set_state_value("_combat_first_shot_target_context_key", target_context_key)
		return
	if bool(get_state_value("_combat_telegraph_active", false)):
		if has_valid_solution:
			set_state_value("_combat_telegraph_pause_elapsed", 0.0)
			var telegraph_timer := maxf(0.0, float(get_state_value("_combat_telegraph_timer", 0.0)) - maxf(delta, 0.0))
			set_state_value("_combat_telegraph_timer", telegraph_timer)
			return
		var pause_elapsed := float(get_state_value("_combat_telegraph_pause_elapsed", 0.0)) + maxf(delta, 0.0)
		set_state_value("_combat_telegraph_pause_elapsed", pause_elapsed)
		if pause_elapsed > COMBAT_TELEGRAPH_MAX_PAUSE_SEC:
			cancel_first_shot_telegraph()
		return
	if has_valid_solution:
		set_state_value("_combat_first_shot_pause_elapsed", 0.0)
		var delay_left := maxf(0.0, float(get_state_value("_combat_first_attack_delay_timer", 0.0)) - maxf(delta, 0.0))
		set_state_value("_combat_first_attack_delay_timer", delay_left)
		if delay_left <= 0.0:
			arm_first_shot_telegraph()
		return
	var pause_elapsed := float(get_state_value("_combat_first_shot_pause_elapsed", 0.0)) + maxf(delta, 0.0)
	set_state_value("_combat_first_shot_pause_elapsed", pause_elapsed)
	if pause_elapsed > COMBAT_FIRST_SHOT_MAX_PAUSE_SEC:
		reset_first_shot_delay_state()


func shotgun_stats() -> Dictionary:
	if GameConfig and GameConfig.weapon_stats.has(WEAPON_SHOTGUN):
		return GameConfig.weapon_stats[WEAPON_SHOTGUN] as Dictionary
	return {
		"cooldown_sec": 1.2,
		"rpm": 50.0,
		"pellets": 16,
		"cone_deg": 8.0,
	}


func shotgun_cooldown_sec() -> float:
	var stats := shotgun_stats()
	var cooldown_sec := float(stats.get("cooldown_sec", -1.0))
	if cooldown_sec > 0.0:
		return maxf(cooldown_sec, ENEMY_FIRE_MIN_COOLDOWN_SEC)
	var rpm := maxf(float(stats.get("rpm", 60.0)), 1.0)
	return maxf(60.0 / rpm, ENEMY_FIRE_MIN_COOLDOWN_SEC)


func fire_enemy_shotgun(origin: Vector2, aim_dir: Vector2) -> void:
	if _owner == null:
		return
	if _owner.has_method("_fire_enemy_shotgun"):
		_owner.call("_fire_enemy_shotgun", origin, aim_dir)


func force_pursuit_facing_dir_for_test(dir: Vector2) -> void:
	var pursuit: Variant = get_state_value("_pursuit", null)
	if pursuit == null:
		return
	var n_dir := dir.normalized()
	if n_dir.length_squared() <= 0.0001:
		return
	pursuit.set("facing_dir", n_dir)
	pursuit.set("_target_facing_dir", n_dir)


func _owner_global_position() -> Vector2:
	var owner_2d := _owner as Node2D
	if owner_2d == null:
		return Vector2.ZERO
	return owner_2d.global_position


func _owner_enemy_vision_cfg_float(key: String, fallback: float) -> float:
	if _owner == null:
		return fallback
	if _owner.has_method("_enemy_vision_cfg_float"):
		return float(_owner.call("_enemy_vision_cfg_float", key, fallback))
	return fallback


func _owner_ray_excludes() -> Array[RID]:
	var excludes: Array[RID] = []
	if _owner == null:
		return excludes
	if not _owner.has_method("_ray_excludes"):
		return excludes
	var result: Variant = _owner.call("_ray_excludes")
	if not (result is Array):
		return excludes
	for rid_variant in (result as Array):
		if rid_variant is RID:
			excludes.append(rid_variant)
	return excludes


func _owner_is_combat_awareness_active() -> bool:
	if _owner == null:
		return false
	if _owner.has_method("_is_combat_awareness_active"):
		return bool(_owner.call("_is_combat_awareness_active"))
	var awareness: Variant = get_state_value("_awareness", null)
	if awareness == null or not awareness.has_method("get_state_name"):
		return false
	return String(awareness.get_state_name()) == "COMBAT"


func _owner_is_test_scene_context() -> bool:
	if _owner == null:
		return false
	if _owner.has_method("_is_test_scene_context"):
		return bool(_owner.call("_is_test_scene_context"))
	var tree := _owner.get_tree()
	if tree == null:
		return false
	var current_scene := tree.current_scene
	if current_scene == null:
		return false
	var scene_path := String(current_scene.scene_file_path)
	return scene_path.begins_with("res://tests/")


func _shot_rng() -> RandomNumberGenerator:
	var rng_variant: Variant = get_state_value("_shot_rng", null)
	var rng := rng_variant as RandomNumberGenerator
	if rng != null:
		return rng
	rng = RandomNumberGenerator.new()
	rng.randomize()
	set_state_value("_shot_rng", rng)
	return rng
