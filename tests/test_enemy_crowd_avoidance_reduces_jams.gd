extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")

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
	print("ENEMY CROWD AVOIDANCE REDUCES JAMS TEST")
	print("============================================================")

	_test_configure_nav_agent_sets_avoidance_radius()
	_test_configure_nav_agent_sets_avoidance_max_speed()
	_test_configure_nav_agent_null_does_not_crash()

	_t.summary("ENEMY CROWD AVOIDANCE REDUCES JAMS RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_configure_nav_agent_sets_avoidance_radius() -> void:
	var fx := _make_pursuit_fixture()
	var pursuit := fx.get("pursuit") as Object
	var agent := NavigationAgent2D.new()
	pursuit.call("configure_nav_agent", agent)
	_t.run_test(
		"configure_nav_agent sets avoidance radius (12.8)",
		is_equal_approx(agent.radius, 12.8)
	)
	_free_pursuit_fixture(fx)
	agent.free()


func _test_configure_nav_agent_sets_avoidance_max_speed() -> void:
	var fx := _make_pursuit_fixture()
	var pursuit := fx.get("pursuit") as Object
	var agent := NavigationAgent2D.new()
	pursuit.call("configure_nav_agent", agent)
	_t.run_test(
		"configure_nav_agent sets avoidance max_speed (80.0)",
		is_equal_approx(agent.max_speed, 80.0)
	)
	_free_pursuit_fixture(fx)
	agent.free()


func _test_configure_nav_agent_null_does_not_crash() -> void:
	var fx := _make_pursuit_fixture()
	var pursuit := fx.get("pursuit") as Object
	pursuit.call("configure_nav_agent", null)
	_t.run_test(
		"configure_nav_agent(null) does not enable navmesh",
		bool(pursuit.get("_use_navmesh")) == false
	)
	_free_pursuit_fixture(fx)


func _make_pursuit_fixture() -> Dictionary:
	var owner := CharacterBody2D.new()
	owner.global_position = Vector2.ZERO
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	return {
		"owner": owner,
		"sprite": sprite,
		"pursuit": pursuit,
	}


func _free_pursuit_fixture(fx: Dictionary) -> void:
	var owner := fx.get("owner") as Node
	if owner != null:
		owner.free()
