extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("CONFIG VALIDATOR AI BALANCE TEST")
	print("============================================================")

	_test_empty_ai_balance_is_error()
	_test_missing_ai_section_is_error()
	_test_invalid_ai_type_is_error()
	_test_invalid_ai_range_is_error()
	_test_invalid_enemy_stats_schema_is_error()
	_test_invalid_projectile_ttl_schema_is_error()
	_test_clamp_does_not_touch_combat_schema()

	GameConfig.reset_to_defaults()
	_t.summary("CONFIG VALIDATOR AI BALANCE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_empty_ai_balance_is_error() -> void:
	GameConfig.reset_to_defaults()
	GameConfig.ai_balance = {}
	var result := ConfigValidator.validate()
	_t.run_test(
		"Empty ai_balance is validation error",
		not result.is_valid and _has_error_containing(result, "ai_balance must be a non-empty dictionary")
	)


func _test_missing_ai_section_is_error() -> void:
	GameConfig.reset_to_defaults()
	GameConfig.ai_balance.erase("pursuit")
	var result := ConfigValidator.validate()
	_t.run_test(
		"Missing ai_balance section is validation error",
		not result.is_valid and _has_error_containing(result, "ai_balance.pursuit is required")
	)


func _test_invalid_ai_type_is_error() -> void:
	GameConfig.reset_to_defaults()
	var pursuit := GameConfig.ai_balance.get("pursuit", {}) as Dictionary
	pursuit["search_min_sec"] = "4.0"
	GameConfig.ai_balance["pursuit"] = pursuit
	var result := ConfigValidator.validate()
	_t.run_test(
		"Invalid ai_balance key type is rejected",
		not result.is_valid and _has_error_containing(result, "ai_balance.pursuit.search_min_sec must be a number")
	)


func _test_invalid_ai_range_is_error() -> void:
	GameConfig.reset_to_defaults()
	var utility := GameConfig.ai_balance.get("utility", {}) as Dictionary
	utility["retreat_hp_ratio"] = 1.25
	GameConfig.ai_balance["utility"] = utility
	var result := ConfigValidator.validate()
	_t.run_test(
		"Invalid ai_balance range is rejected",
		not result.is_valid and _has_error_containing(result, "ai_balance.utility.retreat_hp_ratio")
	)


func _test_invalid_enemy_stats_schema_is_error() -> void:
	GameConfig.reset_to_defaults()
	var zombie := GameConfig.enemy_stats.get("zombie", {}) as Dictionary
	zombie.erase("speed")
	GameConfig.enemy_stats["zombie"] = zombie
	var result := ConfigValidator.validate()
	_t.run_test(
		"enemy_stats missing required key is rejected",
		not result.is_valid and _has_error_containing(result, "enemy_stats.zombie.speed is required")
	)


func _test_invalid_projectile_ttl_schema_is_error() -> void:
	GameConfig.reset_to_defaults()
	GameConfig.projectile_ttl["rocket"] = 0.0
	var result := ConfigValidator.validate()
	_t.run_test(
		"projectile_ttl invalid value is rejected",
		not result.is_valid and _has_error_containing(result, "projectile_ttl.rocket")
	)


func _test_clamp_does_not_touch_combat_schema() -> void:
	GameConfig.reset_to_defaults()
	GameConfig.projectile_ttl["bullet"] = -5.0
	GameConfig.enemy_stats["fast"] = {"hp": 100, "damage": 7}
	GameConfig.ai_balance = {}

	var clamped := ConfigValidator.clamp_values()
	var untouched_projectile := is_equal_approx(float(GameConfig.projectile_ttl.get("bullet", 0.0)), -5.0)
	var untouched_enemy_stats := not (GameConfig.enemy_stats.get("fast", {}) as Dictionary).has("speed")
	var untouched_ai_balance := GameConfig.ai_balance.is_empty()
	var no_combat_clamp_paths := not _array_contains_prefix(clamped, "projectile_ttl") \
		and not _array_contains_prefix(clamped, "enemy_stats") \
		and not _array_contains_prefix(clamped, "ai_balance")

	_t.run_test(
		"Clamp keeps combat schema untouched",
		untouched_projectile and untouched_enemy_stats and untouched_ai_balance and no_combat_clamp_paths
	)


func _has_error_containing(result: ConfigValidator.ValidationResult, needle: String) -> bool:
	for err in result.errors:
		if err.findn(needle) >= 0:
			return true
	return false


func _array_contains_prefix(items: Array[String], prefix: String) -> bool:
	for item in items:
		if item.begins_with(prefix):
			return true
	return false
