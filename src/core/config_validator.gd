## config_validator.gd
## Validates GameConfig before level start.
## CANON: If invalid, UI clamps and shows hint; cannot start until OK.
class_name ConfigValidator
extends RefCounted

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

	if GameConfig.enemies_per_wave < 1:
		result.add_error("enemies_per_wave must be at least 1")

	if GameConfig.waves_per_level < 1:
		result.add_error("waves_per_level must be at least 1")

	if GameConfig.waves_per_level > 200:
		result.add_warning("waves_per_level > 200 may result in very long levels")

	if GameConfig.spawn_tick_sec < 0.1:
		result.add_error("spawn_tick_sec must be at least 0.1")

	if GameConfig.spawn_batch_size < 1:
		result.add_error("spawn_batch_size must be at least 1")

	if GameConfig.wave_advance_threshold < 0 or GameConfig.wave_advance_threshold > 1:
		result.add_error("wave_advance_threshold must be between 0.0 and 1.0")

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

	return result


## Clamp all GameConfig values to valid ranges
## Returns list of fields that were clamped
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

	if GameConfig.enemies_per_wave < 1:
		GameConfig.enemies_per_wave = 1
		clamped.append("enemies_per_wave")

	if GameConfig.waves_per_level < 1:
		GameConfig.waves_per_level = 1
		clamped.append("waves_per_level")
	elif GameConfig.waves_per_level > 200:
		GameConfig.waves_per_level = 200
		clamped.append("waves_per_level")

	if GameConfig.spawn_tick_sec < 0.1:
		GameConfig.spawn_tick_sec = 0.1
		clamped.append("spawn_tick_sec")

	if GameConfig.spawn_batch_size < 1:
		GameConfig.spawn_batch_size = 1
		clamped.append("spawn_batch_size")

	GameConfig.wave_advance_threshold = clampf(GameConfig.wave_advance_threshold, 0.0, 1.0)

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
