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


class LegacyOnlyNav:
	extends Node

	var legacy_calls: int = 0

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func build_policy_valid_path(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		return {
			"status": "ok",
			"path_points": [to_pos],
			"reason": "ok",
			"route_source": "navmesh",
			"route_source_reason": "legacy_stub",
			"obstacle_intersection_detected": false,
		}

	func can_enemy_traverse_point(_enemy: Node, _point: Vector2) -> bool:
		legacy_calls += 1
		return true


class SplitNav:
	extends LegacyOnlyNav

	var geometry_calls: int = 0

	func can_enemy_traverse_geometry_point(_enemy: Node, _point: Vector2) -> bool:
		geometry_calls += 1
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
	print("WALKABLE API LEGACY BRIDGE CONTRACT TEST")
	print("============================================================")

	await _test_legacy_stub_fallback_is_allowed_when_geometry_missing()
	await _test_split_stub_prefers_geometry_and_blocks_legacy_fallback()

	_t.summary("WALKABLE API LEGACY BRIDGE CONTRACT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_legacy_stub_fallback_is_allowed_when_geometry_missing() -> void:
	var report := await _run_case(LegacyOnlyNav.new())
	_t.run_test(
		"legacy bridge: legacy_shadow_api is used when geometry API is missing",
		String(report.get("traverse_check_source", "")) == "legacy_shadow_api"
	)
	_t.run_test(
		"legacy bridge: legacy method is called in legacy-only stub",
		int(report.get("legacy_calls", 0)) > 0
	)


func _test_split_stub_prefers_geometry_and_blocks_legacy_fallback() -> void:
	var nav := SplitNav.new()
	var report := await _run_case(nav)
	_t.run_test(
		"legacy bridge: geometry_api is used when split API is present",
		String(report.get("traverse_check_source", "")) == "geometry_api"
	)
	_t.run_test(
		"legacy bridge: geometry method called and legacy method not called",
		int(report.get("geometry_calls", 0)) > 0 and int(report.get("legacy_calls", 0)) == 0
	)


func _run_case(nav: Node) -> Dictionary:
	var world := Node2D.new()
	add_child(world)
	world.add_child(nav)

	var owner := FakeOwner.new()
	owner.global_position = Vector2.ZERO
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	world.add_child(owner)
	await get_tree().physics_frame

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	pursuit.configure_navigation(nav, 0)
	pursuit.set("_patrol", FakePatrolDecision.new(Vector2(64.0, 0.0)))

	for _i in range(6):
		pursuit.execute_intent(
			1.0 / 60.0,
			{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL},
			_patrol_context(Vector2(64.0, 0.0))
		)
		await get_tree().physics_frame

	var snapshot := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
	var legacy_calls := int(nav.get("legacy_calls"))
	var geometry_calls := int(nav.get("geometry_calls")) if nav.has_method("can_enemy_traverse_geometry_point") else 0
	var out := {
		"traverse_check_source": String(snapshot.get("traverse_check_source", "")),
		"legacy_calls": legacy_calls,
		"geometry_calls": geometry_calls,
	}
	world.queue_free()
	await get_tree().process_frame
	return out


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
