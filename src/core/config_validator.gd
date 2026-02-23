## config_validator.gd
## Validates GameConfig before level start.
## CANON: Combat schema must be valid; no fallback clamping for AI/combat dictionaries.
class_name ConfigValidator
extends RefCounted

const REQUIRED_ENEMY_TYPES := ["zombie", "fast", "tank", "swarm"]
const REQUIRED_PROJECTILE_TYPES := ["bullet", "pellet", "plasma", "rocket", "piercing_bullet"]
const REQUIRED_AI_BALANCE_SECTIONS := ["enemy_vision", "pursuit", "utility", "alert", "squad", "patrol", "spawner"]
const REQUIRED_ROOM_SIZE_KEYS := ["LARGE", "MEDIUM", "SMALL"]

## Validation result structure
class ValidationResult:
	var is_valid: bool = true
	var errors: Array[String] = []
	var warnings: Array[String] = []

	func add_error(msg: String) -> void:
		is_valid = false
		errors.append(msg)

	func add_warning(msg: String) -> void:
		warnings.append(msg)


## Validate current GameConfig
## Returns ValidationResult with is_valid flag and error/warning messages
static func validate() -> ValidationResult:
	var result := ValidationResult.new()

	if not GameConfig:
		result.add_error("GameConfig singleton not found")
		return result

	# Core validation
	if GameConfig.tile_size < 8 or GameConfig.tile_size > 128:
		result.add_error("tile_size must be between 8 and 128 (current: %d)" % GameConfig.tile_size)

	if GameConfig.max_alive_enemies < 1:
		result.add_error("max_alive_enemies must be at least 1")

	if GameConfig.max_alive_enemies > 256:
		result.add_warning("max_alive_enemies > 256 may cause performance issues")

	# Spawn validation
	if GameConfig.start_delay_sec < 0:
		result.add_error("start_delay_sec cannot be negative")

	# Combat validation
	if GameConfig.player_max_hp < 1:
		result.add_error("player_max_hp must be at least 1")

	if GameConfig.contact_iframes_sec < 0.1:
		result.add_error("contact_iframes_sec must be at least 0.1")

	# Audio validation
	if GameConfig.music_volume < 0 or GameConfig.music_volume > 1:
		result.add_error("music_volume must be between 0.0 and 1.0")

	# Physics validation
	if GameConfig.player_speed_tiles < 0.1:
		result.add_error("player_speed_tiles must be at least 0.1")

	_validate_enemy_stats(result)
	_validate_projectile_ttl(result)
	_validate_ai_balance(result)

	return result


## Clamp all GameConfig values to valid ranges
## Returns list of fields that were clamped.
## Clamp is intentionally limited to core scalar fields (not AI/combat schema dictionaries).
static func clamp_values() -> Array[String]:
	var clamped: Array[String] = []

	if not GameConfig:
		return clamped

	# Core
	if GameConfig.tile_size < 8:
		GameConfig.tile_size = 8
		clamped.append("tile_size")
	elif GameConfig.tile_size > 128:
		GameConfig.tile_size = 128
		clamped.append("tile_size")

	if GameConfig.max_alive_enemies < 1:
		GameConfig.max_alive_enemies = 1
		clamped.append("max_alive_enemies")
	elif GameConfig.max_alive_enemies > 256:
		GameConfig.max_alive_enemies = 256
		clamped.append("max_alive_enemies")

	# Spawn
	if GameConfig.start_delay_sec < 0:
		GameConfig.start_delay_sec = 0
		clamped.append("start_delay_sec")

	# Combat
	if GameConfig.player_max_hp < 1:
		GameConfig.player_max_hp = 1
		clamped.append("player_max_hp")

	if GameConfig.contact_iframes_sec < 0.1:
		GameConfig.contact_iframes_sec = 0.1
		clamped.append("contact_iframes_sec")

	# Audio
	GameConfig.music_volume = clampf(GameConfig.music_volume, 0.0, 1.0)

	# Physics
	if GameConfig.player_speed_tiles < 0.1:
		GameConfig.player_speed_tiles = 0.1
		clamped.append("player_speed_tiles")

	return clamped


static func _validate_enemy_stats(result: ValidationResult) -> void:
	if not (GameConfig.enemy_stats is Dictionary):
		result.add_error("enemy_stats must be a dictionary")
		return

	var enemy_stats := GameConfig.enemy_stats as Dictionary
	if enemy_stats.is_empty():
		result.add_error("enemy_stats must be a non-empty dictionary")
		return

	for enemy_type in REQUIRED_ENEMY_TYPES:
		var path := "enemy_stats.%s" % enemy_type
		if not enemy_stats.has(enemy_type):
			result.add_error("%s is required" % path)
			continue
		var entry_variant: Variant = enemy_stats.get(enemy_type)
		if not (entry_variant is Dictionary):
			result.add_error("%s must be a dictionary" % path)
			continue
		var entry := entry_variant as Dictionary
		_validate_int_key(result, entry, "hp", path, 1, 10000)
		_validate_int_key(result, entry, "damage", path, 0, 10000)
		_validate_number_key(result, entry, "speed", path, 0.01, 100.0)


static func _validate_projectile_ttl(result: ValidationResult) -> void:
	if not (GameConfig.projectile_ttl is Dictionary):
		result.add_error("projectile_ttl must be a dictionary")
		return

	var projectile_ttl := GameConfig.projectile_ttl as Dictionary
	if projectile_ttl.is_empty():
		result.add_error("projectile_ttl must be a non-empty dictionary")
		return

	for projectile_type in REQUIRED_PROJECTILE_TYPES:
		_validate_number_key(result, projectile_ttl, projectile_type, "projectile_ttl", 0.01, 60.0)


static func _validate_ai_balance(result: ValidationResult) -> void:
	if not (GameConfig.ai_balance is Dictionary):
		result.add_error("ai_balance must be a dictionary")
		return

	var ai_balance := GameConfig.ai_balance as Dictionary
	if ai_balance.is_empty():
		result.add_error("ai_balance must be a non-empty dictionary")
		return

	for section_name in REQUIRED_AI_BALANCE_SECTIONS:
		if not ai_balance.has(section_name):
			result.add_error("ai_balance.%s is required" % section_name)

	var enemy_vision := _ai_section(result, ai_balance, "enemy_vision")
	if not enemy_vision.is_empty():
		var max_distance := _validate_number_key(result, enemy_vision, "max_distance_px", "ai_balance.enemy_vision", 1.0, 10000.0)
		var attack_range := _validate_number_key(result, enemy_vision, "fire_attack_range_max_px", "ai_balance.enemy_vision", 1.0, 10000.0)
		_validate_number_key(result, enemy_vision, "fov_deg", "ai_balance.enemy_vision", 1.0, 360.0)
		_validate_number_key(result, enemy_vision, "fire_spawn_offset_px", "ai_balance.enemy_vision", 0.0, 1000.0)
		var ray_range := _validate_number_key(result, enemy_vision, "fire_ray_range_px", "ai_balance.enemy_vision", 1.0, 10000.0)
		if not is_nan(attack_range) and not is_nan(max_distance) and attack_range > max_distance:
			result.add_error("ai_balance.enemy_vision.fire_attack_range_max_px must be <= max_distance_px")
		if not is_nan(ray_range) and not is_nan(attack_range) and ray_range < attack_range:
			result.add_error("ai_balance.enemy_vision.fire_ray_range_px must be >= fire_attack_range_max_px")

	var pursuit := _ai_section(result, ai_balance, "pursuit")
	if not pursuit.is_empty():
		var attack_range_max := _validate_number_key(result, pursuit, "attack_range_max_px", "ai_balance.pursuit", 1.0, 10000.0)
		var attack_range_pref_min := _validate_number_key(result, pursuit, "attack_range_pref_min_px", "ai_balance.pursuit", 0.0, 10000.0)
		var search_min := _validate_number_key(result, pursuit, "search_min_sec", "ai_balance.pursuit", 0.01, 60.0)
		var search_max := _validate_number_key(result, pursuit, "search_max_sec", "ai_balance.pursuit", 0.01, 120.0)
		_validate_number_key(result, pursuit, "last_seen_reached_px", "ai_balance.pursuit", 1.0, 500.0)
		_validate_number_key(result, pursuit, "return_target_reached_px", "ai_balance.pursuit", 1.0, 500.0)
		_validate_number_key(result, pursuit, "search_sweep_rad", "ai_balance.pursuit", 0.0, TAU)
		_validate_number_key(result, pursuit, "search_sweep_speed", "ai_balance.pursuit", 0.0, 50.0)
		_validate_number_key(result, pursuit, "path_repath_interval_sec", "ai_balance.pursuit", 0.01, 10.0)
		_validate_number_key(result, pursuit, "turn_speed_rad", "ai_balance.pursuit", 0.01, 100.0)
		_validate_number_key(result, pursuit, "accel_time_sec", "ai_balance.pursuit", 0.01, 10.0)
		_validate_number_key(result, pursuit, "decel_time_sec", "ai_balance.pursuit", 0.01, 10.0)
		_validate_number_key(result, pursuit, "retreat_distance_px", "ai_balance.pursuit", 0.0, 5000.0)
		_validate_number_key(result, pursuit, "waypoint_reached_px", "ai_balance.pursuit", 1.0, 500.0)
		_validate_number_key(result, pursuit, "shadow_search_probe_count", "ai_balance.pursuit", 0.0, 20.0)
		_validate_number_key(result, pursuit, "shadow_search_probe_ring_radius_px", "ai_balance.pursuit", 1.0, 2000.0)
		_validate_number_key(result, pursuit, "shadow_search_coverage_threshold", "ai_balance.pursuit", 0.0, 1.0)
		_validate_number_key(result, pursuit, "shadow_search_total_budget_sec", "ai_balance.pursuit", 0.1, 120.0)
		_validate_number_key(result, pursuit, "avoidance_radius_px", "ai_balance.pursuit", 1.0, 64.0)
		_validate_number_key(result, pursuit, "avoidance_max_speed_px_per_sec", "ai_balance.pursuit", 20.0, 400.0)
		if not is_nan(attack_range_pref_min) and not is_nan(attack_range_max) and attack_range_pref_min > attack_range_max:
			result.add_error("ai_balance.pursuit.attack_range_pref_min_px must be <= attack_range_max_px")
		if not is_nan(search_min) and not is_nan(search_max) and search_min > search_max:
			result.add_error("ai_balance.pursuit.search_min_sec must be <= search_max_sec")

	var utility := _ai_section(result, ai_balance, "utility")
	if not utility.is_empty():
		var hold_min := _validate_number_key(result, utility, "hold_range_min_px", "ai_balance.utility", 0.0, 10000.0)
		var hold_max := _validate_number_key(result, utility, "hold_range_max_px", "ai_balance.utility", 0.0, 10000.0)
		_validate_number_key(result, utility, "decision_interval_sec", "ai_balance.utility", 0.01, 10.0)
		_validate_number_key(result, utility, "min_action_hold_sec", "ai_balance.utility", 0.0, 30.0)
		_validate_number_key(result, utility, "retreat_hp_ratio", "ai_balance.utility", 0.0, 1.0)
		_validate_number_key(result, utility, "investigate_max_last_seen_age", "ai_balance.utility", 0.0, 60.0)
		_validate_number_key(result, utility, "slot_reposition_threshold_px", "ai_balance.utility", 0.0, 1000.0)
		_validate_number_key(result, utility, "intent_target_delta_px", "ai_balance.utility", 0.0, 500.0)
		_validate_number_key(result, utility, "mode_min_hold_sec", "ai_balance.utility", 0.1, 5.0)
		if not is_nan(hold_min) and not is_nan(hold_max) and hold_min > hold_max:
			result.add_error("ai_balance.utility.hold_range_min_px must be <= hold_range_max_px")

	var nav_cost := _ai_section(result, ai_balance, "nav_cost")
	if not nav_cost.is_empty():
		_validate_number_key(result, nav_cost, "shadow_weight_cautious", "ai_balance.nav_cost", 0.0, 1000000.0)
		_validate_number_key(result, nav_cost, "shadow_weight_aggressive", "ai_balance.nav_cost", 0.0, 1000000.0)
		_validate_number_key(result, nav_cost, "shadow_sample_step_px", "ai_balance.nav_cost", 1.0, 1000.0)
		_validate_number_key(result, nav_cost, "safe_route_max_len_factor", "ai_balance.nav_cost", 1.0, 10.0)

	var alert := _ai_section(result, ai_balance, "alert")
	if not alert.is_empty():
		_validate_number_key(result, alert, "suspicious_ttl_sec", "ai_balance.alert", 0.01, 120.0)
		_validate_number_key(result, alert, "alert_ttl_sec", "ai_balance.alert", 0.01, 120.0)
		_validate_number_key(result, alert, "combat_ttl_sec", "ai_balance.alert", 0.01, 120.0)
		_validate_number_key(result, alert, "visibility_decay_sec", "ai_balance.alert", 0.0, 120.0)

	var squad := _ai_section(result, ai_balance, "squad")
	if not squad.is_empty():
		var pressure_radius := _validate_number_key(result, squad, "pressure_radius_px", "ai_balance.squad", 1.0, 10000.0)
		var hold_radius := _validate_number_key(result, squad, "hold_radius_px", "ai_balance.squad", 1.0, 10000.0)
		var flank_radius := _validate_number_key(result, squad, "flank_radius_px", "ai_balance.squad", 1.0, 10000.0)
		_validate_number_key(result, squad, "rebuild_interval_sec", "ai_balance.squad", 0.01, 10.0)
		_validate_number_key(result, squad, "slot_reservation_ttl_sec", "ai_balance.squad", 0.01, 30.0)
		_validate_int_key(result, squad, "pressure_slot_count", "ai_balance.squad", 1, 64)
		_validate_int_key(result, squad, "hold_slot_count", "ai_balance.squad", 1, 64)
		_validate_int_key(result, squad, "flank_slot_count", "ai_balance.squad", 1, 64)
		_validate_number_key(result, squad, "invalid_path_score_penalty", "ai_balance.squad", 0.0, 10000000.0)
		_validate_number_key(result, squad, "slot_path_tail_tolerance_px", "ai_balance.squad", 0.0, 1000.0)
		_validate_number_key(result, squad, "flank_max_path_px", "ai_balance.squad", 1.0, 10000.0)
		_validate_number_key(result, squad, "flank_max_time_sec", "ai_balance.squad", 0.1, 60.0)
		_validate_number_key(result, squad, "flank_walk_speed_assumed_px_per_sec", "ai_balance.squad", 1.0, 10000.0)
		_validate_number_key(result, squad, "flashlight_scanner_cap", "ai_balance.squad", 0.0, 32.0)
		if not is_nan(pressure_radius) and not is_nan(hold_radius) and pressure_radius > hold_radius:
			result.add_error("ai_balance.squad.pressure_radius_px must be <= hold_radius_px")
		if not is_nan(hold_radius) and not is_nan(flank_radius) and hold_radius > flank_radius:
			result.add_error("ai_balance.squad.hold_radius_px must be <= flank_radius_px")

	var patrol := _ai_section(result, ai_balance, "patrol")
	if not patrol.is_empty():
		var route_points_min := _validate_int_key(result, patrol, "route_points_min", "ai_balance.patrol", 1, 64)
		var route_points_max := _validate_int_key(result, patrol, "route_points_max", "ai_balance.patrol", 1, 64)
		var route_rebuild_min := _validate_number_key(result, patrol, "route_rebuild_min_sec", "ai_balance.patrol", 0.01, 120.0)
		var route_rebuild_max := _validate_number_key(result, patrol, "route_rebuild_max_sec", "ai_balance.patrol", 0.01, 120.0)
		var pause_min := _validate_number_key(result, patrol, "pause_min_sec", "ai_balance.patrol", 0.0, 30.0)
		var pause_max := _validate_number_key(result, patrol, "pause_max_sec", "ai_balance.patrol", 0.0, 30.0)
		var look_min := _validate_number_key(result, patrol, "look_min_sec", "ai_balance.patrol", 0.0, 30.0)
		var look_max := _validate_number_key(result, patrol, "look_max_sec", "ai_balance.patrol", 0.0, 30.0)
		_validate_number_key(result, patrol, "point_reached_px", "ai_balance.patrol", 1.0, 500.0)
		_validate_number_key(result, patrol, "speed_scale", "ai_balance.patrol", 0.01, 10.0)
		_validate_number_key(result, patrol, "look_chance", "ai_balance.patrol", 0.0, 1.0)
		_validate_number_key(result, patrol, "look_sweep_rad", "ai_balance.patrol", 0.0, TAU)
		_validate_number_key(result, patrol, "look_sweep_speed", "ai_balance.patrol", 0.0, 50.0)
		_validate_number_key(result, patrol, "route_dedup_min_dist_px", "ai_balance.patrol", 0.0, 1000.0)
		if route_points_min != -1 and route_points_max != -1 and route_points_min > route_points_max:
			result.add_error("ai_balance.patrol.route_points_min must be <= route_points_max")
		if not is_nan(route_rebuild_min) and not is_nan(route_rebuild_max) and route_rebuild_min > route_rebuild_max:
			result.add_error("ai_balance.patrol.route_rebuild_min_sec must be <= route_rebuild_max_sec")
		if not is_nan(pause_min) and not is_nan(pause_max) and pause_min > pause_max:
			result.add_error("ai_balance.patrol.pause_min_sec must be <= pause_max_sec")
		if not is_nan(look_min) and not is_nan(look_max) and look_min > look_max:
			result.add_error("ai_balance.patrol.look_min_sec must be <= look_max_sec")

	var spawner := _ai_section(result, ai_balance, "spawner")
	if not spawner.is_empty():
		var enemy_type := _validate_string_key(result, spawner, "enemy_type", "ai_balance.spawner")
		if enemy_type != "" and not REQUIRED_ENEMY_TYPES.has(enemy_type):
			result.add_error("ai_balance.spawner.enemy_type must be one of %s" % str(REQUIRED_ENEMY_TYPES))
		_validate_number_key(result, spawner, "edge_padding_px", "ai_balance.spawner", 0.0, 500.0)
		_validate_number_key(result, spawner, "safe_soft_padding_px", "ai_balance.spawner", 0.0, 500.0)
		_validate_number_key(result, spawner, "min_safe_rect_size_px", "ai_balance.spawner", 0.01, 500.0)
		_validate_number_key(result, spawner, "min_enemy_spacing_px", "ai_balance.spawner", 0.01, 5000.0)
		_validate_int_key(result, spawner, "sample_attempts_per_enemy", "ai_balance.spawner", 1, 100000)
		_validate_number_key(result, spawner, "grid_search_step_px", "ai_balance.spawner", 0.01, 500.0)

		if not spawner.has("room_quota_by_size"):
			result.add_error("ai_balance.spawner.room_quota_by_size is required")
		elif not (spawner["room_quota_by_size"] is Dictionary):
			result.add_error("ai_balance.spawner.room_quota_by_size must be a dictionary")
		else:
			var quotas := spawner["room_quota_by_size"] as Dictionary
			for room_key in REQUIRED_ROOM_SIZE_KEYS:
				_validate_int_key(result, quotas, room_key, "ai_balance.spawner.room_quota_by_size", 0, 128)


static func _ai_section(result: ValidationResult, ai_balance: Dictionary, section_name: String) -> Dictionary:
	if not ai_balance.has(section_name):
		return {}
	var section_variant: Variant = ai_balance.get(section_name)
	if not (section_variant is Dictionary):
		result.add_error("ai_balance.%s must be a dictionary" % section_name)
		return {}
	return section_variant as Dictionary


static func _validate_number_key(
	result: ValidationResult,
	dict: Dictionary,
	key: String,
	path_prefix: String,
	min_value: float,
	max_value: float
) -> float:
	var path := "%s.%s" % [path_prefix, key]
	if not dict.has(key):
		result.add_error("%s is required" % path)
		return NAN
	var value: Variant = dict.get(key)
	if not _is_number(value):
		result.add_error("%s must be a number" % path)
		return NAN
	var numeric := float(value)
	if numeric < min_value or numeric > max_value:
		result.add_error("%s must be in range [%.3f, %.3f]" % [path, min_value, max_value])
	return numeric


static func _validate_int_key(
	result: ValidationResult,
	dict: Dictionary,
	key: String,
	path_prefix: String,
	min_value: int,
	max_value: int
) -> int:
	var path := "%s.%s" % [path_prefix, key]
	if not dict.has(key):
		result.add_error("%s is required" % path)
		return -1
	var value: Variant = dict.get(key)
	if typeof(value) != TYPE_INT:
		result.add_error("%s must be an integer" % path)
		return -1
	var int_value := int(value)
	if int_value < min_value or int_value > max_value:
		result.add_error("%s must be in range [%d, %d]" % [path, min_value, max_value])
	return int_value


static func _validate_string_key(result: ValidationResult, dict: Dictionary, key: String, path_prefix: String) -> String:
	var path := "%s.%s" % [path_prefix, key]
	if not dict.has(key):
		result.add_error("%s is required" % path)
		return ""
	var value: Variant = dict.get(key)
	if typeof(value) != TYPE_STRING:
		result.add_error("%s must be a string" % path)
		return ""
	var out := String(value)
	if out.strip_edges() == "":
		result.add_error("%s must not be empty" % path)
	return out


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
