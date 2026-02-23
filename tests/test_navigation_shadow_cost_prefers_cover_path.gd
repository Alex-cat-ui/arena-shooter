extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const NAV_RUNTIME_QUERIES_SCRIPT := preload("res://src/systems/navigation_runtime_queries.gd")

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
	print("NAVIGATION SHADOW COST PREFERS COVER PATH TEST")
	print("============================================================")

	_test_score_path_all_in_shadow()
	_test_score_path_all_lit()
	_test_score_path_zero_shadow_weight()
	_test_score_path_empty_returns_inf()

	_t.summary("NAVIGATION SHADOW COST PREFERS COVER PATH RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_score_path_all_in_shadow() -> void:
	var service := FakeShadowService.new()
	var queries = NAV_RUNTIME_QUERIES_SCRIPT.new(service)
	var score := float(queries._score_path_cost(
		[Vector2(-100.0, 0.0)],
		Vector2.ZERO,
		{"shadow_weight": 80.0, "shadow_sample_step_px": 100.0}
	))
	_t.run_test("all-shadow segment keeps pure length score", is_equal_approx(score, 100.0))
	service.free()


func _test_score_path_all_lit() -> void:
	var service := FakeShadowService.new()
	var queries = NAV_RUNTIME_QUERIES_SCRIPT.new(service)
	var score := float(queries._score_path_cost(
		[Vector2(100.0, 0.0)],
		Vector2.ZERO,
		{"shadow_weight": 80.0, "shadow_sample_step_px": 100.0}
	))
	_t.run_test("all-lit segment adds one shadow penalty sample", is_equal_approx(score, 180.0))
	service.free()


func _test_score_path_zero_shadow_weight() -> void:
	var service := FakeShadowService.new()
	var queries = NAV_RUNTIME_QUERIES_SCRIPT.new(service)
	var score := float(queries._score_path_cost(
		[Vector2(100.0, 0.0)],
		Vector2.ZERO,
		{"shadow_weight": 0.0}
	))
	_t.run_test("zero shadow weight returns pure path length", is_equal_approx(score, 100.0))
	service.free()


func _test_score_path_empty_returns_inf() -> void:
	var service := FakeShadowService.new()
	var queries = NAV_RUNTIME_QUERIES_SCRIPT.new(service)
	var score := float(queries._score_path_cost([], Vector2.ZERO, {"shadow_weight": 80.0}))
	_t.run_test("empty path returns INF", score == INF)
	service.free()
