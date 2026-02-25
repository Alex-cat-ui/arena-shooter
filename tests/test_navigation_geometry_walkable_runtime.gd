extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT = preload("res://src/systems/enemy_pursuit_system.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT = preload("res://src/systems/enemy_utility_brain.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeOwner:
	extends CharacterBody2D

	func set_shadow_check_flashlight(_active: bool) -> void:
		pass

	func set_shadow_scan_active(_active: bool) -> void:
		pass


class FakeNav:
	extends Node

	var geometry_allow: bool = true
	var geometry_calls: int = 0
	var legacy_calls: int = 0

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func build_policy_valid_path(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		return {
			"status": "ok",
			"path_points": [to_pos],
			"reason": "ok",
			"route_source": "navmesh",
			"route_source_reason": "stub_navmesh",
			"obstacle_intersection_detected": false,
		}

	func can_enemy_traverse_geometry_point(_enemy: Node, _point: Vector2) -> bool:
		geometry_calls += 1
		return geometry_allow

	func can_enemy_traverse_point(_enemy: Node, _point: Vector2) -> bool:
		legacy_calls += 1
		return true


class FakePatrolDecision:
	extends RefCounted

	var fixed_target: Vector2 = Vector2.ZERO

	func _init(target: Vector2) -> void:
		fixed_target = target

	func configure(_nav_system: Node, _home_room_id: int) -> void:
		pass

	func update(_delta: float, _facing_dir: Vector2) -> Dictionary:
		return {
			"waiting": false,
			"target": fixed_target,
			"speed_scale": 0.95,
		}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("NAVIGATION GEOMETRY WALKABLE RUNTIME TEST")
	print("============================================================")

	await _test_geometry_api_is_used_when_available()
	await _test_geometry_denial_blocks_motion_without_legacy_fallback()

	_t.summary("NAVIGATION GEOMETRY WALKABLE RUNTIME RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_geometry_api_is_used_when_available() -> void:
	var report := await _run_patrol_case(true)
	_t.run_test(
		"geometry runtime: traverse source is geometry_api when geometry method exists",
		String(report.get("traverse_check_source", "")) == "geometry_api"
	)
	_t.run_test(
		"geometry runtime: geometry API called and legacy not used",
		int(report.get("geometry_calls", 0)) > 0 and int(report.get("legacy_calls", 0)) == 0
	)
	_t.run_test(
		"geometry runtime: movement progresses when geometry allows",
		float(report.get("moved_total", 0.0)) > 0.1
	)


func _test_geometry_denial_blocks_motion_without_legacy_fallback() -> void:
	var report := await _run_patrol_case(false)
	_t.run_test(
		"geometry runtime: geometry denial keeps traverse source geometry_api",
		String(report.get("traverse_check_source", "")) == "geometry_api"
	)
	_t.run_test(
		"geometry runtime: legacy fallback is not called when geometry exists",
		int(report.get("legacy_calls", 0)) == 0 and int(report.get("geometry_calls", 0)) > 0
	)
	_t.run_test(
		"geometry runtime: movement is blocked by geometry deny",
		float(report.get("moved_total", 0.0)) < 0.1
	)


func _run_patrol_case(geometry_allow: bool) -> Dictionary:
	var world := Node2D.new()
	add_child(world)

	var nav := FakeNav.new()
	nav.geometry_allow = geometry_allow
	world.add_child(nav)

	var owner := FakeOwner.new()
	owner.global_position = Vector2.ZERO
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	world.add_child(owner)
	await get_tree().physics_frame

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	pursuit.configure_navigation(nav, 0)
	pursuit.set("_patrol", FakePatrolDecision.new(Vector2(96.0, 0.0)))

	var start_pos := owner.global_position
	for _i in range(8):
		pursuit.execute_intent(
			1.0 / 60.0,
			{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL},
			_patrol_context(Vector2(96.0, 0.0))
		)
		await get_tree().physics_frame

	var snapshot := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
	var moved_total := owner.global_position.distance_to(start_pos)
	var geometry_calls := nav.geometry_calls
	var legacy_calls := nav.legacy_calls

	world.queue_free()
	await get_tree().process_frame
	return {
		"traverse_check_source": String(snapshot.get("traverse_check_source", "")),
		"geometry_calls": geometry_calls,
		"legacy_calls": legacy_calls,
		"moved_total": moved_total,
	}


func _patrol_context(target: Vector2) -> Dictionary:
	return {
		"player_pos": target,
		"known_target_pos": Vector2.ZERO,
		"last_seen_pos": Vector2.ZERO,
		"investigate_anchor": Vector2.ZERO,
		"home_position": Vector2.ZERO,
		"alert_level": 0,
		"los": false,
		"combat_lock": false,
	}
