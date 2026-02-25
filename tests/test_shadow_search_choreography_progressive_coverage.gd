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
	print("SHADOW SEARCH CHOREOGRAPHY PROGRESSIVE COVERAGE TEST")
	print("============================================================")

	await _test_coverage_starts_at_zero()
	await _test_coverage_increases_after_first_sweep()
	await _test_coverage_reaches_threshold_after_all_probes()
	await _test_coverage_resets_on_clear_state()

	_t.summary("SHADOW SEARCH CHOREOGRAPHY PROGRESSIVE COVERAGE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_coverage_starts_at_zero() -> void:
	var fx := await _create_fixture()
	var pursuit = fx["pursuit"]
	_t.run_test(
		"coverage starts at zero",
		is_equal_approx(float(pursuit.get_shadow_search_coverage()), 0.0)
	)
	await _destroy_fixture(fx)


func _test_coverage_increases_after_first_sweep() -> void:
	var fx := await _create_fixture()
	var pursuit = fx["pursuit"]
	var target := Vector2(200.0, 0.0)
	_drive_to_sweep_stage(fx, target)
	_expire_current_sweep(pursuit, target)
	_t.run_test(
		"coverage increases after first sweep",
		float(pursuit.get_shadow_search_coverage()) > 0.0
	)
	_t.run_test(
		"first sweep transitions to probe when probes exist",
		int(pursuit.get_shadow_search_stage()) == int(ENEMY_PURSUIT_SYSTEM_SCRIPT.ShadowSearchStage.PROBE)
	)
	await _destroy_fixture(fx)


func _test_coverage_reaches_threshold_after_all_probes() -> void:
	var fx := await _create_fixture()
	var pursuit = fx["pursuit"]
	var owner := fx["owner"] as FakeShadowSearchOwner
	var nav := fx["nav"] as FakeShadowSearchNav
	var target := Vector2(200.0, 0.0)
	_drive_to_sweep_stage(fx, target)

	var coverage_samples: Array = []
	var steps := 0
	while steps < 24:
		steps += 1
		var stage := int(pursuit.get_shadow_search_stage())
		if stage == int(ENEMY_PURSUIT_SYSTEM_SCRIPT.ShadowSearchStage.SWEEP):
			_expire_current_sweep(pursuit, target)
			var coverage := float(pursuit.get_shadow_search_coverage())
			if coverage > 0.0:
				coverage_samples.append(coverage)
		elif stage == int(ENEMY_PURSUIT_SYSTEM_SCRIPT.ShadowSearchStage.PROBE):
			var probe_points := pursuit.get("_shadow_search_probe_points") as Array
			var cursor := int(pursuit.get("_shadow_search_probe_cursor"))
			if cursor < probe_points.size():
				owner.global_position = probe_points[cursor] as Vector2
			pursuit._execute_shadow_boundary_scan(0.016, target, true)
		elif stage == int(ENEMY_PURSUIT_SYSTEM_SCRIPT.ShadowSearchStage.BOUNDARY_LOCK):
			owner.global_position = nav.boundary_point
			pursuit._execute_shadow_boundary_scan(0.016, target, true)
		else:
			break

	var monotonic := true
	var prev := -INF
	for sample_variant in coverage_samples:
		var sample := float(sample_variant)
		if sample <= prev:
			monotonic = false
			break
		prev = sample

	_t.run_test("coverage samples increase monotonically during session", monotonic)
	_t.run_test(
		"coverage threshold reached or session ended idle after all probes",
		float(pursuit.get_shadow_search_coverage()) >= 0.8
			or int(pursuit.get_shadow_search_stage()) == int(ENEMY_PURSUIT_SYSTEM_SCRIPT.ShadowSearchStage.IDLE)
	)

	nav.filter_all_probes = true
	_drive_to_sweep_stage(fx, target)
	_expire_current_sweep(pursuit, target)
	_t.run_test(
		"all probes filtered ends session without entering probe",
		int(pursuit.get_shadow_search_stage()) == int(ENEMY_PURSUIT_SYSTEM_SCRIPT.ShadowSearchStage.IDLE)
	)
	await _destroy_fixture(fx)


func _test_coverage_resets_on_clear_state() -> void:
	var fx := await _create_fixture()
	var pursuit = fx["pursuit"]
	var target := Vector2(200.0, 0.0)
	_drive_to_sweep_stage(fx, target)
	_expire_current_sweep(pursuit, target)
	var before_clear := float(pursuit.get_shadow_search_coverage())
	pursuit.clear_shadow_scan_state()
	_t.run_test("coverage becomes > 0 before clear", before_clear > 0.0)
	_t.run_test(
		"coverage resets on clear_state",
		is_equal_approx(float(pursuit.get_shadow_search_coverage()), 0.0)
	)
	_t.run_test(
		"stage resets to idle on clear_state",
		int(pursuit.get_shadow_search_stage()) == int(ENEMY_PURSUIT_SYSTEM_SCRIPT.ShadowSearchStage.IDLE)
	)
	await _destroy_fixture(fx)


func _drive_to_sweep_stage(fx: Dictionary, target: Vector2) -> void:
	var pursuit = fx["pursuit"]
	var owner := fx["owner"] as FakeShadowSearchOwner
	var nav := fx["nav"] as FakeShadowSearchNav
	pursuit.clear_shadow_scan_state()
	owner.global_position = Vector2.ZERO
	pursuit._execute_shadow_boundary_scan(0.016, target, true)
	owner.global_position = nav.boundary_point
	pursuit._execute_shadow_boundary_scan(0.016, target, true)


func _expire_current_sweep(pursuit, target: Vector2) -> void:
	pursuit.set("_shadow_scan_timer", 0.001)
	pursuit._execute_shadow_boundary_scan(0.05, target, true)


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


func can_enemy_traverse_geometry_point(_enemy: Node, _point: Vector2) -> bool:
	return true
