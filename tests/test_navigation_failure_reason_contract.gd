extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const NAV_RUNTIME_QUERIES_SCRIPT := preload("res://src/systems/navigation_runtime_queries.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeService:
	extends Node

	var layout = null
	var _room_graph: Dictionary = {}
	var geometry_path_points: Array[Vector2] = []
	var policy_validation: Dictionary = {
		"valid": true,
		"segment_index": -1,
	}

	func get_navigation_map_rid() -> RID:
		return RID()

	func _build_room_graph_path_points_reachable(_from_pos: Vector2, _to_pos: Vector2) -> Array[Vector2]:
		return geometry_path_points.duplicate()

	func validate_enemy_path_policy(_enemy: Node, _from_pos: Vector2, _path_points: Array, _sample_step_px: float = 12.0) -> Dictionary:
		return policy_validation.duplicate(true)


class FakeNavMissingPlanner:
	extends Node


class FakeNavInvalidPlanner:
	extends Node

	func build_policy_valid_path(_from_pos: Vector2, _to_pos: Vector2, _enemy: Node = null, _cost_profile: Dictionary = {}) -> Variant:
		return null


class FakeNavValidPlanner:
	extends Node

	var contract: Dictionary = {}

	func build_policy_valid_path(_from_pos: Vector2, _to_pos: Vector2, _enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		return contract.duplicate(true)


class FakeServiceLegacyOnly:
	extends Node

	var layout = null
	var _room_graph: Dictionary = {}
	var geometry_path_points: Array[Vector2] = []
	var legacy_calls: int = 0

	func get_navigation_map_rid() -> RID:
		return RID()

	func _build_room_graph_path_points_reachable(_from_pos: Vector2, _to_pos: Vector2) -> Array[Vector2]:
		return geometry_path_points.duplicate()

	func can_enemy_traverse_point(_enemy: Node, _point: Vector2) -> bool:
		legacy_calls += 1
		return true


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("NAVIGATION FAILURE REASON CONTRACT TEST")
	print("============================================================")

	_test_failure_reason_contract()
	_test_navigation_queries_legacy_policy_bridge_contract()
	_test_pursuit_dispatch_contract_nav_system_missing()

	_t.summary("NAVIGATION FAILURE REASON CONTRACT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_failure_reason_contract() -> void:
	var service := FakeService.new()
	add_child(service)
	var queries = NAV_RUNTIME_QUERIES_SCRIPT.new(service)
	var enemy := Node2D.new()
	add_child(enemy)

	var from_pos := Vector2.ZERO
	var to_pos := Vector2(120.0, 0.0)

	service.geometry_path_points = []
	service.policy_validation = {
		"valid": true,
		"segment_index": -1,
	}
	var no_geometry := queries.build_policy_valid_path(from_pos, to_pos, enemy) as Dictionary
	_t.run_test(
		"contract: missing geometry returns unreachable_geometry",
		String(no_geometry.get("status", "")) == "unreachable_geometry"
			and String(no_geometry.get("reason", "")) == "room_graph_no_path"
			and (no_geometry.get("path_points", []) as Array).is_empty()
	)

	service.geometry_path_points = [to_pos]
	service.policy_validation = {
		"valid": false,
		"segment_index": 0,
		"blocked_point": Vector2(42.0, 0.0),
	}
	var blocked := queries.build_policy_valid_path(from_pos, to_pos, enemy) as Dictionary
	_t.run_test(
		"contract: policy block returns unreachable_policy",
		String(blocked.get("status", "")) == "unreachable_policy"
			and String(blocked.get("reason", "")) == "policy_blocked"
			and not blocked.has("blocked_point")
	)

	service.policy_validation = {
		"valid": true,
		"segment_index": -1,
	}
	var ok_result := queries.build_policy_valid_path(from_pos, to_pos, enemy) as Dictionary
	var ok_path := ok_result.get("path_points", []) as Array
	_t.run_test(
		"contract: valid plan returns ok + path_points",
		String(ok_result.get("status", "")) == "ok"
			and String(ok_result.get("reason", "")) == "ok"
			and not ok_path.is_empty()
			and (ok_path.back() as Vector2).distance_to(to_pos) <= 0.001
	)

	var reachable_points := queries.build_reachable_path_points(from_pos, to_pos, enemy)
	_t.run_test("build_reachable_path_points mirrors contract ok path", not reachable_points.is_empty())

	enemy.queue_free()
	service.queue_free()


func _test_navigation_queries_legacy_policy_bridge_contract() -> void:
	var saved_ai_balance := (GameConfig.ai_balance as Dictionary).duplicate(true) if GameConfig and GameConfig.ai_balance is Dictionary else {}
	var service := FakeServiceLegacyOnly.new()
	add_child(service)
	var queries = NAV_RUNTIME_QUERIES_SCRIPT.new(service)
	var enemy := Node2D.new()
	add_child(enemy)
	var from_pos := Vector2.ZERO
	var to_pos := Vector2(120.0, 0.0)
	service.geometry_path_points = [to_pos]
	service.legacy_calls = 0

	_set_allow_legacy_shadow_api_fallback(false)
	var blocked := queries.build_policy_valid_path(from_pos, to_pos, enemy) as Dictionary
	_t.run_test(
		"navigation queries: legacy policy bridge is fail-closed by default",
		String(blocked.get("status", "")) == "unreachable_policy"
			and String(blocked.get("reason", "")) == "policy_blocked"
			and int(service.legacy_calls) == 0
	)
	_t.run_test(
		"navigation queries: missing traverse policy push_error is suppressed in tests",
		not bool(queries.call("_should_emit_missing_traverse_policy_error"))
	)

	_set_allow_legacy_shadow_api_fallback(true)
	var bridged := queries.build_policy_valid_path(from_pos, to_pos, enemy) as Dictionary
	_t.run_test(
		"navigation queries: legacy policy bridge works only with explicit opt-in",
		String(bridged.get("status", "")) == "ok"
			and String(bridged.get("reason", "")) == "ok"
			and int(service.legacy_calls) > 0
	)

	enemy.queue_free()
	service.queue_free()
	if GameConfig and GameConfig.ai_balance is Dictionary:
		GameConfig.ai_balance = saved_ai_balance.duplicate(true)


func _test_pursuit_dispatch_contract_nav_system_missing() -> void:
	var target := Vector2(100.0, 0.0)

	var null_fixture := _make_pursuit_fixture(null)
	var null_pursuit := null_fixture.get("pursuit", null) as Object
	var null_contract := null_pursuit.call("_request_path_plan_contract", target, true) as Dictionary
	_t.run_test(
		"pursuit dispatch: null nav returns nav_system_missing sentinel",
		String(null_contract.get("status", "")) == "unreachable_geometry"
			and String(null_contract.get("reason", "")) == "nav_system_missing"
			and (null_contract.get("path_points", []) as Array).is_empty()
	)
	_free_pursuit_fixture(null_fixture)

	var missing_nav := FakeNavMissingPlanner.new()
	var missing_fixture := _make_pursuit_fixture(missing_nav)
	var missing_pursuit := missing_fixture.get("pursuit", null) as Object
	var missing_contract := missing_pursuit.call("_request_path_plan_contract", target, true) as Dictionary
	_t.run_test(
		"pursuit dispatch: missing planner method returns nav_system_missing sentinel",
		String(missing_contract.get("status", "")) == "unreachable_geometry"
			and String(missing_contract.get("reason", "")) == "nav_system_missing"
			and (missing_contract.get("path_points", []) as Array).is_empty()
	)
	_free_pursuit_fixture(missing_fixture)

	var invalid_nav := FakeNavInvalidPlanner.new()
	var invalid_fixture := _make_pursuit_fixture(invalid_nav)
	var invalid_pursuit := invalid_fixture.get("pursuit", null) as Object
	var invalid_contract := invalid_pursuit.call("_request_path_plan_contract", target, true) as Dictionary
	_t.run_test(
		"pursuit dispatch: non-dictionary planner result returns nav_system_missing sentinel",
		String(invalid_contract.get("status", "")) == "unreachable_geometry"
			and String(invalid_contract.get("reason", "")) == "nav_system_missing"
			and (invalid_contract.get("path_points", []) as Array).is_empty()
	)
	_free_pursuit_fixture(invalid_fixture)

	var valid_nav := FakeNavValidPlanner.new()
	valid_nav.contract = {
		"status": "ok",
		"path_points": [target],
		"reason": "ok",
	}
	var valid_fixture := _make_pursuit_fixture(valid_nav)
	var valid_pursuit := valid_fixture.get("pursuit", null) as Object
	var valid_contract := valid_pursuit.call("_request_path_plan_contract", target, true) as Dictionary
	var valid_path := valid_contract.get("path_points", []) as Array
	_t.run_test(
		"pursuit dispatch: valid planner dictionary returns as-is",
		String(valid_contract.get("status", "")) == "ok"
			and String(valid_contract.get("reason", "")) == "ok"
			and valid_path.size() == 1
			and (valid_path[0] as Vector2).distance_to(target) <= 0.001
	)
	_free_pursuit_fixture(valid_fixture)


func _make_pursuit_fixture(nav: Node) -> Dictionary:
	var owner := CharacterBody2D.new()
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	add_child(owner)
	if nav != null:
		add_child(nav)
	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	pursuit.configure_navigation(nav, 0)
	return {
		"owner": owner,
		"nav": nav,
		"pursuit": pursuit,
	}


func _free_pursuit_fixture(fixture: Dictionary) -> void:
	var owner := fixture.get("owner", null) as Node
	var nav := fixture.get("nav", null) as Node
	if owner != null:
		owner.queue_free()
	if nav != null:
		nav.queue_free()


func _set_allow_legacy_shadow_api_fallback(enabled: bool) -> void:
	if not (GameConfig and GameConfig.ai_balance is Dictionary):
		return
	var ai := (GameConfig.ai_balance as Dictionary).duplicate(true)
	var pursuit := (ai.get("pursuit", {}) as Dictionary).duplicate(true)
	pursuit["allow_legacy_shadow_api_fallback"] = enabled
	ai["pursuit"] = pursuit
	GameConfig.ai_balance = ai
