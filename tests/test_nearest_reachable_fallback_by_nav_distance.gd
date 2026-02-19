extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeNavByDistance:
	extends Node

	var nav_lengths: Dictionary = {}

	func nav_path_length(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null) -> float:
		var key := _key(to_pos)
		if nav_lengths.has(key):
			return float(nav_lengths.get(key, INF))
		return INF

	func _key(point: Vector2) -> String:
		return "%d:%d" % [int(round(point.x)), int(round(point.y))]


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("NEAREST REACHABLE FALLBACK BY NAV DISTANCE TEST")
	print("============================================================")

	_test_fallback_selects_by_nav_distance_then_euclid()

	_t.summary("NEAREST REACHABLE FALLBACK BY NAV DISTANCE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_fallback_selects_by_nav_distance_then_euclid() -> void:
	var owner := CharacterBody2D.new()
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	add_child(owner)

	var nav := FakeNavByDistance.new()
	add_child(nav)

	var target := Vector2(100.0, 100.0)
	var candidate_a := Vector2(110.0, 100.0) # euclid 10, nav 300
	var candidate_b := Vector2(150.0, 100.0) # euclid 50, nav 120
	var candidate_c := Vector2(90.0, 130.0) # euclid ~31.6, nav 120 (tie winner vs B)
	var candidate_d := Vector2(101.0, 101.0) # unreachable (INF)

	nav.nav_lengths[nav._key(candidate_a)] = 300.0
	nav.nav_lengths[nav._key(candidate_b)] = 120.0
	nav.nav_lengths[nav._key(candidate_c)] = 120.0

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	pursuit.configure_navigation(nav, 0)
	var result := pursuit.debug_select_nearest_reachable_fallback(
		target,
		[candidate_a, candidate_b, candidate_c, candidate_d]
	) as Dictionary

	var chosen := result.get("point", Vector2.ZERO) as Vector2
	_t.run_test("fallback selection uses nav_path_length over euclid", chosen != candidate_a)
	_t.run_test("nav distance tie-break resolves by smaller euclid", chosen == candidate_c)
	_t.run_test("unreachable candidates are ignored", bool(result.get("found", false)))

	owner.queue_free()
	nav.queue_free()
