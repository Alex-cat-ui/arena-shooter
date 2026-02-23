extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const NAV_RUNTIME_QUERIES_SCRIPT := preload("res://src/systems/navigation_runtime_queries.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeShadowService:
	extends Node

	func is_point_in_shadow(point: Vector2) -> bool:
		return point.x < 0.0


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("NAVIGATION SHADOW COST PUSH MODE SHORTCUT TEST")
	print("============================================================")

	_test_zero_shadow_weight_selects_shorter_path()
	_test_non_direct_pressure_mode_returns_cautious_weight()
	_test_direct_pressure_mode_returns_zero_shadow_weight()
	_test_positive_shadow_weight_shadow_path_wins()

	_t.summary("NAVIGATION SHADOW COST PUSH MODE SHORTCUT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_zero_shadow_weight_selects_shorter_path() -> void:
	var service := FakeShadowService.new()
	var queries = NAV_RUNTIME_QUERIES_SCRIPT.new(service)
	var score_short := float(queries._score_path_cost([Vector2(100.0, 0.0)], Vector2.ZERO, {"shadow_weight": 0.0}))
	var score_long := float(queries._score_path_cost([Vector2(-300.0, 0.0)], Vector2.ZERO, {"shadow_weight": 0.0}))
	_t.run_test(
		"zero shadow weight prefers shorter path",
		is_equal_approx(score_short, 100.0) and is_equal_approx(score_long, 300.0) and score_short < score_long
	)
	service.free()


func _test_non_direct_pressure_mode_returns_cautious_weight() -> void:
	GameConfig.reset_to_defaults()
	var fixture := _new_pursuit_fixture()
	var pursuit = fixture.get("pursuit", null)
	var profile := pursuit._build_nav_cost_profile({
		"pursuit_mode": int(ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.CONTAIN),
	}) as Dictionary
	_t.run_test(
		"non-DIRECT_PRESSURE mode returns cautious shadow weight",
		is_equal_approx(float(profile.get("shadow_weight", -1.0)), 80.0)
	)
	_free_pursuit_fixture(fixture)


func _test_direct_pressure_mode_returns_zero_shadow_weight() -> void:
	GameConfig.reset_to_defaults()
	var fixture := _new_pursuit_fixture()
	var pursuit = fixture.get("pursuit", null)
	var profile := pursuit._build_nav_cost_profile({
		"pursuit_mode": int(ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.DIRECT_PRESSURE),
	}) as Dictionary
	_t.run_test(
		"DIRECT_PRESSURE mode returns aggressive zero shadow weight",
		is_equal_approx(float(profile.get("shadow_weight", -1.0)), 0.0)
	)
	_free_pursuit_fixture(fixture)


func _test_positive_shadow_weight_shadow_path_wins() -> void:
	var service := FakeShadowService.new()
	var queries = NAV_RUNTIME_QUERIES_SCRIPT.new(service)
	var cost_profile := {
		"shadow_weight": 80.0,
		"shadow_sample_step_px": 16.0,
	}
	var score_lit := float(queries._score_path_cost([Vector2(100.0, 0.0)], Vector2.ZERO, cost_profile))
	var score_shadow := float(queries._score_path_cost([Vector2(-200.0, 0.0)], Vector2.ZERO, cost_profile))
	_t.run_test(
		"positive shadow weight prefers longer shadow-covered path",
		is_equal_approx(score_lit, 660.0) and is_equal_approx(score_shadow, 200.0) and score_shadow < score_lit
	)
	service.free()


func _new_pursuit_fixture() -> Dictionary:
	var owner := CharacterBody2D.new()
	var sprite := Sprite2D.new()
	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	return {
		"owner": owner,
		"sprite": sprite,
		"pursuit": pursuit,
	}


func _free_pursuit_fixture(fixture: Dictionary) -> void:
	var sprite := fixture.get("sprite", null) as Sprite2D
	var owner := fixture.get("owner", null) as CharacterBody2D
	if sprite != null:
		sprite.free()
	if owner != null:
		owner.free()
