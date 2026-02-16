extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const FLASHLIGHT_CONE_SCRIPT := preload("res://src/systems/stealth/flashlight_cone.gd")

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
	print("FLASHLIGHT CONE TEST")
	print("============================================================")

	_test_cone_geometry()
	_test_los_requirement()

	_t.summary("FLASHLIGHT CONE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_cone_geometry() -> void:
	var cone = FLASHLIGHT_CONE_SCRIPT.new()
	cone.cone_angle_deg = 60.0
	cone.cone_distance = 500.0

	var origin := Vector2.ZERO
	var forward := Vector2.RIGHT

	_t.run_test("point on center ray is in cone", cone.is_point_in_cone(origin, forward, Vector2(250.0, 0.0)))
	_t.run_test("point outside distance is out of cone", not cone.is_point_in_cone(origin, forward, Vector2(520.0, 0.0)))
	_t.run_test("point outside cone angle is out of cone", not cone.is_point_in_cone(origin, forward, Vector2(100.0, 260.0)))
	_t.run_test("point inside angle and distance is in cone", cone.is_point_in_cone(origin, forward, Vector2(260.0, 120.0)))


func _test_los_requirement() -> void:
	var cone = FLASHLIGHT_CONE_SCRIPT.new()
	cone.cone_angle_deg = 60.0
	cone.cone_distance = 500.0

	var origin := Vector2.ZERO
	var forward := Vector2.RIGHT
	var player_pos := Vector2(220.0, 0.0)

	_t.run_test("flashlight hit requires active state", not cone.is_player_hit(origin, forward, player_pos, true, false))
	_t.run_test("flashlight hit requires LOS", not cone.is_player_hit(origin, forward, player_pos, false, true))
	_t.run_test("flashlight hit true when active + LOS + in cone", cone.is_player_hit(origin, forward, player_pos, true, true))
