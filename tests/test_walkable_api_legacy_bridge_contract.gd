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

	await _test_legacy_stub_is_fail_closed_by_default()
	await _test_legacy_stub_opt_in_bridge_works()
	await _test_split_stub_prefers_geometry_and_blocks_legacy_fallback()
	await _test_missing_api_rebind_recovers_before_degrade()
	await _test_degraded_mode_remaps_aggressive_intents_without_los()
	await _test_degraded_mode_remaps_to_hold_range_with_los_and_keeps_fire_gate()

	_t.summary("WALKABLE API LEGACY BRIDGE CONTRACT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_legacy_stub_is_fail_closed_by_default() -> void:
	var report := await _run_case(LegacyOnlyNav.new(), false)
	_t.run_test(
		"legacy bridge: default mode is fail-closed when only legacy API exists",
		String(report.get("traverse_check_source", "")) == "missing_traverse_api" and bool(report.get("policy_blocked", false))
	)
	_t.run_test(
		"legacy bridge: legacy method is not called when bridge flag is disabled",
		int(report.get("legacy_calls", 0)) == 0
	)
	_t.run_test(
		"legacy bridge: transient missing-api grace allows short soft movement before block",
		int(report.get("traverse_api_missing_soft_moves", 0)) > 0
	)
	_t.run_test(
		"legacy bridge: missing traverse push_error is suppressed in tests",
		not bool(report.get("missing_traverse_error_log_enabled", true))
	)


func _test_legacy_stub_opt_in_bridge_works() -> void:
	var report := await _run_case(LegacyOnlyNav.new(), true)
	_t.run_test(
		"legacy bridge: opt-in flag allows legacy_shadow_api fallback",
		String(report.get("traverse_check_source", "")) == "legacy_shadow_api"
	)
	_t.run_test(
		"legacy bridge: opt-in calls legacy API",
		int(report.get("legacy_calls", 0)) > 0
	)


func _test_split_stub_prefers_geometry_and_blocks_legacy_fallback() -> void:
	var nav := SplitNav.new()
	var report := await _run_case(nav, true)
	_t.run_test(
		"legacy bridge: geometry_api is used when split API is present",
		String(report.get("traverse_check_source", "")) == "geometry_api"
	)
	_t.run_test(
		"legacy bridge: geometry method called and legacy method not called",
		int(report.get("geometry_calls", 0)) > 0 and int(report.get("legacy_calls", 0)) == 0
	)


func _test_missing_api_rebind_recovers_before_degrade() -> void:
	var legacy_nav := LegacyOnlyNav.new()
	var geometry_nav := SplitNav.new()
	var runtime := await _create_runtime_case(legacy_nav, false, Vector2(96.0, 0.0))
	var owner := runtime.get("owner") as FakeOwner
	var pursuit = runtime.get("pursuit")
	var world := runtime.get("world") as Node2D
	if world:
		world.add_child(geometry_nav)
	for _i in range(18):
		pursuit.execute_intent(
			1.0 / 60.0,
			{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL},
			_patrol_context(Vector2(96.0, 0.0))
		)
		await get_tree().physics_frame
	if owner:
		owner.set_meta("nav_system", geometry_nav)
		owner.global_position = Vector2.ZERO
	pursuit.set("_patrol", FakePatrolDecision.new(Vector2(320.0, 0.0)))
	for _i in range(36):
		pursuit.execute_intent(
			1.0 / 60.0,
			{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL},
			_patrol_context(Vector2(96.0, 0.0))
		)
		await get_tree().physics_frame
	var snapshot := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
	var rebound_nav := pursuit.get("nav_system") as Node
	_t.run_test(
		"missing traverse api: runtime rebind recovers mode to OK before degraded lock-in",
		String(snapshot.get("traverse_runtime_mode", "")) == "ok"
	)
	_t.run_test(
		"missing traverse api: runtime rebind attempts are tracked and provider switches to geometry api",
		int(snapshot.get("traverse_rebind_attempts", 0)) > 0
		and rebound_nav == geometry_nav
	)
	await _cleanup_runtime_case(runtime)


func _test_degraded_mode_remaps_aggressive_intents_without_los() -> void:
	var runtime := await _create_runtime_case(LegacyOnlyNav.new(), false, Vector2(128.0, 0.0))
	var pursuit = runtime.get("pursuit")
	var exec_result: Dictionary = {}
	for _i in range(75):
		exec_result = pursuit.execute_intent(
			1.0 / 60.0,
			{
				"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH,
				"target": Vector2(128.0, 0.0),
			},
			_combat_context(Vector2(128.0, 0.0), false, 128.0)
		)
		await get_tree().physics_frame
	var snapshot := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
	_t.run_test(
		"missing traverse api: after grace runtime enters degraded mode",
		String(snapshot.get("traverse_runtime_mode", "")) == "degraded"
	)
	_t.run_test(
		"degraded mode remaps aggressive PUSH to SEARCH without LOS",
		int(exec_result.get("effective_intent_type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH
		and bool(exec_result.get("traverse_degrade_intent_remapped", false))
	)
	await _cleanup_runtime_case(runtime)


func _test_degraded_mode_remaps_to_hold_range_with_los_and_keeps_fire_gate() -> void:
	var runtime := await _create_runtime_case(LegacyOnlyNav.new(), false, Vector2(100.0, 0.0))
	var pursuit = runtime.get("pursuit")
	var exec_result: Dictionary = {}
	for _i in range(75):
		exec_result = pursuit.execute_intent(
			1.0 / 60.0,
			{
				"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH,
				"target": Vector2(100.0, 0.0),
			},
			_combat_context(Vector2(100.0, 0.0), true, 100.0)
		)
		await get_tree().physics_frame
	var snapshot := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
	_t.run_test(
		"degraded mode with LOS remaps aggressive PUSH to HOLD_RANGE",
		String(snapshot.get("traverse_runtime_mode", "")) == "degraded"
		and int(exec_result.get("effective_intent_type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.HOLD_RANGE
		and bool(exec_result.get("traverse_degrade_intent_remapped", false))
	)
	_t.run_test(
		"degraded mode with LOS preserves fire request gate in HOLD_RANGE",
		bool(exec_result.get("request_fire", false))
	)
	await _cleanup_runtime_case(runtime)


func _run_case(nav: Node, allow_legacy_bridge: bool) -> Dictionary:
	var runtime := await _create_runtime_case(nav, allow_legacy_bridge, Vector2(64.0, 0.0))
	var pursuit = runtime.get("pursuit")

	for _i in range(90):
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
		"policy_blocked": bool(snapshot.get("policy_blocked", false)),
		"traverse_api_missing_soft_moves": int(snapshot.get("traverse_api_missing_soft_moves", 0)),
		"traverse_runtime_mode": String(snapshot.get("traverse_runtime_mode", "")),
		"missing_traverse_error_log_enabled": bool(pursuit.call("_should_emit_missing_traverse_api_error")),
	}
	await _cleanup_runtime_case(runtime)
	return out


func _create_runtime_case(nav: Node, allow_legacy_bridge: bool, patrol_target: Vector2) -> Dictionary:
	var saved_ai_balance := _set_allow_legacy_bridge(allow_legacy_bridge)
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
	pursuit.set("_patrol", FakePatrolDecision.new(patrol_target))
	return {
		"saved_ai_balance": saved_ai_balance,
		"world": world,
		"owner": owner,
		"pursuit": pursuit,
		"nav": nav,
	}


func _cleanup_runtime_case(runtime: Dictionary) -> void:
	var world := runtime.get("world") as Node2D
	var saved_ai_balance := runtime.get("saved_ai_balance", {}) as Dictionary
	if world:
		world.queue_free()
	await get_tree().process_frame
	_restore_ai_balance(saved_ai_balance)


func _set_allow_legacy_bridge(allow_legacy_bridge: bool) -> Dictionary:
	var saved_ai_balance := (GameConfig.ai_balance as Dictionary).duplicate(true) if GameConfig and GameConfig.ai_balance is Dictionary else {}
	if GameConfig and GameConfig.ai_balance is Dictionary:
		var ai := (GameConfig.ai_balance as Dictionary).duplicate(true)
		var pursuit := (ai.get("pursuit", {}) as Dictionary).duplicate(true)
		pursuit["allow_legacy_shadow_api_fallback"] = allow_legacy_bridge
		ai["pursuit"] = pursuit
		GameConfig.ai_balance = ai
	return saved_ai_balance


func _restore_ai_balance(saved_ai_balance: Dictionary) -> void:
	if GameConfig and GameConfig.ai_balance is Dictionary:
		GameConfig.ai_balance = saved_ai_balance.duplicate(true)


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


func _combat_context(player_pos: Vector2, los: bool, dist: float) -> Dictionary:
	return {
		"player_pos": player_pos,
		"known_target_pos": player_pos,
		"last_seen_pos": player_pos,
		"investigate_anchor": Vector2.ZERO,
		"home_position": Vector2.ZERO,
		"alert_level": 3,
		"los": los,
		"dist": dist,
		"combat_lock": true,
	}
