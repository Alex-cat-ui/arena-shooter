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
	print("GAME CONFIG RESET CONSISTENCY (NON-LAYOUT) TEST")
	print("============================================================")

	_test_non_layout_reset_consistency()

	_t.summary("GAME CONFIG RESET CONSISTENCY (NON-LAYOUT) RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_non_layout_reset_consistency() -> void:
	# Mutate all non-layout scalar defaults.
	for key_variant in GameConfig.DEFAULT_NON_LAYOUT_SCALARS.keys():
		var key := String(key_variant)
		var current: Variant = GameConfig.get(key)
		if current is bool:
			GameConfig.set(key, not bool(current))
		elif current is int:
			GameConfig.set(key, int(current) + 1)
		elif current is float:
			GameConfig.set(key, float(current) + 0.123)
		elif current is String:
			GameConfig.set(key, "mutated")

	# Mutate all non-layout dictionary defaults.
	GameConfig.weapon_stats = {}
	GameConfig.enemy_stats = {}
	GameConfig.projectile_ttl = {}
	GameConfig.ai_balance = {}
	GameConfig.ai_fire_profiles = {}
	GameConfig.stealth_canon = {}
	GameConfig.zone_system = {}

	GameConfig.reset_to_defaults()

	var scalars_ok := true
	for key_variant in GameConfig.DEFAULT_NON_LAYOUT_SCALARS.keys():
		var key := String(key_variant)
		var expected: Variant = GameConfig.DEFAULT_NON_LAYOUT_SCALARS.get(key)
		var actual: Variant = GameConfig.get(key)
		if expected is float:
			if not is_equal_approx(float(actual), float(expected)):
				scalars_ok = false
				break
		elif actual != expected:
			scalars_ok = false
			break

	var dicts_ok := (
		GameConfig.weapon_stats == GameConfig.DEFAULT_WEAPON_STATS
		and GameConfig.enemy_stats == GameConfig.DEFAULT_ENEMY_STATS
		and GameConfig.projectile_ttl == GameConfig.DEFAULT_PROJECTILE_TTL
		and GameConfig.ai_balance == GameConfig.DEFAULT_AI_BALANCE
		and GameConfig.ai_fire_profiles == GameConfig.DEFAULT_AI_FIRE_PROFILES
		and GameConfig.stealth_canon == GameConfig.DEFAULT_STEALTH_CANON
		and GameConfig.zone_system == GameConfig.DEFAULT_ZONE_SYSTEM
	)

	var snapshot := GameConfig.get_snapshot() as Dictionary
	var snapshot_has_non_layout := true
	for key_variant in GameConfig.DEFAULT_NON_LAYOUT_SCALARS.keys():
		var key := String(key_variant)
		if not snapshot.has(key):
			snapshot_has_non_layout = false
			break
	_t.run_test("reset restores all non-layout scalar defaults", scalars_ok)
	_t.run_test("reset restores all non-layout dictionary defaults", dicts_ok)
	_t.run_test("get_snapshot includes all non-layout scalar keys", snapshot_has_non_layout)
