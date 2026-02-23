extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeShadowSearchOwner:
	extends CharacterBody2D

	var shadow_check_flashlight: bool = false
	var scan_flag: bool = false

	func set_shadow_check_flashlight(active: bool) -> void:
		shadow_check_flashlight = active

	func set_shadow_scan_active(active: bool) -> void:
		scan_flag = active

	func is_flashlight_active_for_navigation() -> bool:
		return shadow_check_flashlight or scan_flag


class FakeShadowSearchNav:
	extends Node

	var boundary_point: Vector2 = Vector2(100.0, 0.0)
	var filter_all_probes: bool = false

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func get_nearest_non_shadow_point(_target: Vector2, _radius_px: float) -> Vector2:
		return boundary_point

	func is_point_in_shadow(_point: Vector2) -> bool:
		return filter_all_probes

	func can_enemy_traverse_point(_enemy: Node, _point: Vector2) -> bool:
		return true

	func build_policy_valid_path(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		return {
			"status": "ok",
			"path_points": [to_pos],
			"reason": "ok",
		}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("SHADOW SEARCH STAGE TRANSITION CONTRACT TEST")
	print("============================================================")

	await _test_idle_to_boundary_lock_on_valid_boundary()
	await _test_boundary_lock_to_sweep_on_arrive()
	await _test_sweep_to_probe_when_probe_points_exist()
	await _test_clear_state_on_no_target()

	_t.summary("SHADOW SEARCH STAGE TRANSITION CONTRACT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_idle_to_boundary_lock_on_valid_boundary() -> void:
	var fx := await _create_fixture()
	var pursuit = fx["pursuit"]
	var target := Vector2(200.0, 0.0)
	pursuit._execute_shadow_boundary_scan(0.016, target, true)
	_t.run_test(
		"idle -> boundary_lock on valid boundary",
		int(pursuit.get_shadow_search_stage()) == int(ENEMY_PURSUIT_SYSTEM_SCRIPT.ShadowSearchStage.BOUNDARY_LOCK)
	)
	await _destroy_fixture(fx)


func _test_boundary_lock_to_sweep_on_arrive() -> void:
	var fx := await _create_fixture()
	var pursuit = fx["pursuit"]
	var owner := fx["owner"] as FakeShadowSearchOwner
	var nav := fx["nav"] as FakeShadowSearchNav
	var target := Vector2(200.0, 0.0)
	pursuit._execute_shadow_boundary_scan(0.016, target, true)
	owner.global_position = nav.boundary_point
	pursuit._execute_shadow_boundary_scan(0.016, target, true)
	_t.run_test(
		"boundary_lock -> sweep on arrive",
		int(pursuit.get_shadow_search_stage()) == int(ENEMY_PURSUIT_SYSTEM_SCRIPT.ShadowSearchStage.SWEEP)
	)
	_t.run_test(
		"sweep timer initialized on boundary arrival",
		float(pursuit.get("_shadow_scan_timer")) > 0.0
	)
	await _destroy_fixture(fx)


func _test_sweep_to_probe_when_probe_points_exist() -> void:
	var fx := await _create_fixture()
	var pursuit = fx["pursuit"]
	var target := Vector2(200.0, 0.0)
	pursuit.set("_shadow_search_stage", int(ENEMY_PURSUIT_SYSTEM_SCRIPT.ShadowSearchStage.SWEEP))
	pursuit.set("_shadow_scan_target", target)
	pursuit.set("_shadow_scan_timer", 0.01)
	pursuit._execute_shadow_boundary_scan(0.05, target, true)
	_t.run_test(
		"sweep -> probe when probe points exist",
		int(pursuit.get_shadow_search_stage()) == int(ENEMY_PURSUIT_SYSTEM_SCRIPT.ShadowSearchStage.PROBE)
	)
	await _destroy_fixture(fx)


func _test_clear_state_on_no_target() -> void:
	var fx := await _create_fixture()
	var pursuit = fx["pursuit"]
	pursuit.set("_shadow_search_stage", int(ENEMY_PURSUIT_SYSTEM_SCRIPT.ShadowSearchStage.SWEEP))
	pursuit.set("_shadow_search_coverage", 0.5)
	pursuit.set("_shadow_scan_target", Vector2(120.0, 0.0))
	pursuit._execute_shadow_boundary_scan(0.016, Vector2.ZERO, false)
	_t.run_test(
		"no_target clears stage to idle",
		int(pursuit.get_shadow_search_stage()) == int(ENEMY_PURSUIT_SYSTEM_SCRIPT.ShadowSearchStage.IDLE)
	)
	_t.run_test(
		"no_target resets coverage to zero",
		is_equal_approx(float(pursuit.get_shadow_search_coverage()), 0.0)
	)
	await _destroy_fixture(fx)


func _create_fixture() -> Dictionary:
	var world := Node2D.new()
	add_child(world)

	var nav := FakeShadowSearchNav.new()
	world.add_child(nav)

	var owner := FakeShadowSearchOwner.new()
	owner.global_position = Vector2.ZERO
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	world.add_child(owner)
	await get_tree().physics_frame

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	pursuit.configure_navigation(nav, 0)

	return {
		"world": world,
		"nav": nav,
		"owner": owner,
		"pursuit": pursuit,
	}


func _destroy_fixture(fx: Dictionary) -> void:
	var world := fx.get("world", null) as Node
	if world != null:
		world.queue_free()
		await get_tree().process_frame
