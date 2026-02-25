extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
const LAYOUT_DOOR_SYSTEM_SCRIPT := preload("res://src/systems/layout_door_system.gd")

const SCENARIO_WALL_DETOUR_PATROL := "wall_detour_patrol"
const SCENARIO_PROP_CLUSTER_PATROL := "prop_cluster_patrol"
const SCENARIO_DOOR_CHOKE_PATROL_MIX := "door_choke_patrol_mix"
const SCENARIO_NARROW_CORRIDOR_PREAVOID := "narrow_corridor_preavoid"
const SNAPSHOT_REQUIRED_KEYS := [
	"preavoid_events_total",
	"patrol_preavoid_events_total",
	"patrol_collision_repath_events_total",
	"patrol_hard_stall_events_total",
	"patrol_zero_progress_windows_total",
	"geometry_walkable_false_positive_total",
	"nav_path_obstacle_intersections_total",
	"room_graph_fallback_when_navmesh_available_total",
	"patrol_route_rebuilds_total",
]

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _cached_gate_report: Dictionary = {}
var _cached_gate_report_valid: bool = false


class FakePatrolDecision:
	extends RefCounted

	var fixed_target: Vector2 = Vector2.ZERO
	var fixed_speed_scale: float = 1.0

	func _init(target: Vector2, speed_scale: float = 1.0) -> void:
		fixed_target = target
		fixed_speed_scale = speed_scale

	func configure(_nav_system: Node, _home_room_id: int) -> void:
		pass

	func update(_delta: float, _facing_dir: Vector2) -> Dictionary:
		return {
			"waiting": false,
			"target": fixed_target,
			"speed_scale": fixed_speed_scale,
		}


class FakeDirectNav:
	extends Node

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func can_enemy_traverse_point(_enemy: Node, _point: Vector2) -> bool:
		return true

	func build_policy_valid_path(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		return {
			"status": "ok",
			"path_points": [to_pos],
			"reason": "ok",
		}


class FakeWallDetourNav:
	extends Node

	var direct_calls: int = 0

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func can_enemy_traverse_point(_enemy: Node, _point: Vector2) -> bool:
		return true

	func build_policy_valid_path(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		if direct_calls == 0:
			direct_calls += 1
			return {
				"status": "ok",
				"path_points": [to_pos],
				"reason": "ok",
			}
		return {
			"status": "ok",
			"path_points": [
				Vector2(52.0, 96.0),
				Vector2(168.0, 96.0),
				to_pos,
			],
			"reason": "ok",
		}


class FakePropsDetourNav:
	extends Node

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func can_enemy_traverse_point(_enemy: Node, _point: Vector2) -> bool:
		return true

	func build_policy_valid_path(_from_pos: Vector2, to_pos: Vector2, _enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		return {
			"status": "ok",
			"path_points": [
				Vector2(72.0, -78.0),
				Vector2(188.0, -78.0),
				to_pos,
			],
			"reason": "ok",
		}


class FakeDoorLayout:
	extends RefCounted

	var valid: bool = true
	var doors: Array = [Rect2(-60.0, -6.0, 120.0, 12.0)]
	var _entry_gate: Rect2 = Rect2()

	func _door_wall_thickness() -> float:
		return 16.0


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("PATROL NAVIGATION KPI GATE TEST")
	print("============================================================")

	await _test_patrol_navigation_kpi_gate_report_contract()
	_test_patrol_navigation_kpi_gate_fixture_threshold_failure()

	_t.summary("PATROL NAVIGATION KPI GATE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
		"gate_report": _cached_gate_report.duplicate(true) if _cached_gate_report_valid else {},
	}


func run_gate_report() -> Dictionary:
	return await _get_or_run_gate_report()


func _test_patrol_navigation_kpi_gate_report_contract() -> void:
	var report := await _get_or_run_gate_report()
	_t.run_test("patrol navigation gate: returns PASS/ok", String(report.get("gate_status", "")) == "PASS" and String(report.get("gate_reason", "")) == "ok")
	_t.run_test(
		"patrol navigation gate: includes four scenario reports",
		(report.get("scenario_reports", []) as Array).size() == 4
	)
	_t.run_test(
		"patrol navigation gate: report has expanded patrol KPI fields",
		report.has("patrol_preavoid_events_total")
			and report.has("patrol_collision_repath_events_total")
			and report.has("patrol_hard_stall_events_total")
			and report.has("patrol_zero_progress_windows_total")
			and report.has("patrol_hard_stalls_per_min")
			and report.has("geometry_walkable_false_positive_total")
			and report.has("nav_path_obstacle_intersections_total")
			and report.has("room_graph_fallback_when_navmesh_available_total")
			and report.has("patrol_route_rebuilds_total")
			and report.has("patrol_route_rebuilds_per_min")
	)


func _test_patrol_navigation_kpi_gate_fixture_threshold_failure() -> void:
	var fixture := {
		"patrol_preavoid_events_total": 0,
		"patrol_collision_repath_events_total": int(GameConfig.kpi_patrol_collision_repath_events_max if GameConfig else 24) + 1,
		"patrol_hard_stall_events_total": 0,
		"patrol_zero_progress_windows_total": int(GameConfig.kpi_patrol_zero_progress_windows_max if GameConfig else 220) + 1,
		"geometry_walkable_false_positive_total": int(GameConfig.kpi_geometry_walkable_false_positive_max if GameConfig else 0) + 1,
		"nav_path_obstacle_intersections_total": int(GameConfig.kpi_nav_path_obstacle_intersections_max if GameConfig else 0) + 1,
		"room_graph_fallback_when_navmesh_available_total": int(GameConfig.kpi_room_graph_fallback_when_navmesh_available_max if GameConfig else 0) + 1,
		"patrol_route_rebuilds_total": 120,
		"duration_sec": 60.0,
	}
	var report := _evaluate_thresholds_for_fixture(fixture)
	var failures := report.get("kpi_threshold_failures", []) as Array
	_t.run_test("patrol navigation gate fixture: threshold failure rejects", String(report.get("gate_status", "")) == "FAIL")
	_t.run_test("patrol navigation gate fixture: reason threshold_failed", String(report.get("gate_reason", "")) == "threshold_failed")
	_t.run_test(
		"patrol navigation gate fixture: deterministic failures include min/max patrol KPI keys",
		failures.size() >= 3
			and String(failures[0]) == "patrol_preavoid_events_total"
			and failures.has("patrol_collision_repath_events_total")
			and failures.has("patrol_zero_progress_windows_total")
			and failures.has("patrol_route_rebuilds_per_min")
	)


func _get_or_run_gate_report() -> Dictionary:
	if _cached_gate_report_valid:
		return _cached_gate_report.duplicate(true)
	_cached_gate_report = await _run_patrol_navigation_kpi_gate()
	_cached_gate_report_valid = true
	return _cached_gate_report.duplicate(true)


func _run_patrol_navigation_kpi_gate() -> Dictionary:
	var report := _build_gate_report_shell()
	if not AIWatchdog or not AIWatchdog.has_method("debug_reset_metrics_for_tests") or not AIWatchdog.has_method("get_snapshot"):
		report["gate_reason"] = "metrics_contract_missing"
		return report

	AIWatchdog.call("debug_reset_metrics_for_tests")
	var base_snapshot := AIWatchdog.get_snapshot() as Dictionary
	if not _snapshot_has_required_keys(base_snapshot):
		report["gate_reason"] = "metrics_contract_missing"
		report["metrics_snapshot"] = base_snapshot
		return report

	var accumulated_duration_sec := 0.0
	var scenario_reports: Array[Dictionary] = []
	var previous_snapshot := base_snapshot.duplicate(true)

	for scenario_variant in _build_scenarios():
		var scenario := scenario_variant as Dictionary
		var scenario_id := String(scenario.get("id", ""))
		var runner := scenario.get("runner", Callable()) as Callable
		if scenario_id == "" or not runner.is_valid():
			report["gate_reason"] = "scenario_bootstrap_failed"
			report["failed_scenario"] = scenario_id
			return report
		var scenario_result_variant: Variant = await runner.call()
		var scenario_result := scenario_result_variant as Dictionary
		var scenario_ok := bool(scenario_result.get("ok", false))
		var duration_sec := maxf(float(scenario_result.get("duration_sec", 0.0)), 0.0)
		if not scenario_ok or duration_sec <= 0.0:
			report["gate_reason"] = "scenario_bootstrap_failed"
			report["failed_scenario"] = scenario_id
			report["failed_reason"] = String(scenario_result.get("reason", "scenario_failed"))
			return report
		accumulated_duration_sec += duration_sec

		var current_snapshot := AIWatchdog.get_snapshot() as Dictionary
		if not _snapshot_has_required_keys(current_snapshot):
			report["gate_reason"] = "metrics_contract_missing"
			report["failed_scenario"] = scenario_id
			report["metrics_snapshot"] = current_snapshot
			return report

		var delta := _metric_delta(previous_snapshot, current_snapshot)
		delta["scenario_id"] = scenario_id
		delta["duration_sec"] = duration_sec
		scenario_reports.append(delta)
		previous_snapshot = current_snapshot.duplicate(true)

	var final_snapshot := AIWatchdog.get_snapshot() as Dictionary
	if not _snapshot_has_required_keys(final_snapshot):
		report["gate_reason"] = "metrics_contract_missing"
		report["metrics_snapshot"] = final_snapshot
		return report

	var patrol_preavoid_events_total := maxi(int(final_snapshot.get("patrol_preavoid_events_total", 0)), 0)
	var patrol_collision_repath_events_total := maxi(int(final_snapshot.get("patrol_collision_repath_events_total", 0)), 0)
	var patrol_hard_stall_events_total := maxi(int(final_snapshot.get("patrol_hard_stall_events_total", 0)), 0)
	var patrol_zero_progress_windows_total := maxi(int(final_snapshot.get("patrol_zero_progress_windows_total", 0)), 0)
	var geometry_walkable_false_positive_total := maxi(int(final_snapshot.get("geometry_walkable_false_positive_total", 0)), 0)
	var nav_path_obstacle_intersections_total := maxi(int(final_snapshot.get("nav_path_obstacle_intersections_total", 0)), 0)
	var room_graph_fallback_when_navmesh_available_total := maxi(int(final_snapshot.get("room_graph_fallback_when_navmesh_available_total", 0)), 0)
	var patrol_route_rebuilds_total := maxi(int(final_snapshot.get("patrol_route_rebuilds_total", 0)), 0)
	var patrol_hard_stalls_per_min := float(patrol_hard_stall_events_total) * 60.0 / maxf(accumulated_duration_sec, 0.001)
	var patrol_route_rebuilds_per_min := float(patrol_route_rebuilds_total) * 60.0 / maxf(accumulated_duration_sec, 0.001)

	report["duration_sec"] = accumulated_duration_sec
	report["scenario_reports"] = scenario_reports
	report["metrics_snapshot"] = final_snapshot.duplicate(true)
	report["preavoid_events_total"] = maxi(int(final_snapshot.get("preavoid_events_total", 0)), 0)
	report["patrol_preavoid_events_total"] = patrol_preavoid_events_total
	report["patrol_collision_repath_events_total"] = patrol_collision_repath_events_total
	report["patrol_hard_stall_events_total"] = patrol_hard_stall_events_total
	report["patrol_zero_progress_windows_total"] = patrol_zero_progress_windows_total
	report["patrol_hard_stalls_per_min"] = patrol_hard_stalls_per_min
	report["geometry_walkable_false_positive_total"] = geometry_walkable_false_positive_total
	report["nav_path_obstacle_intersections_total"] = nav_path_obstacle_intersections_total
	report["room_graph_fallback_when_navmesh_available_total"] = room_graph_fallback_when_navmesh_available_total
	report["patrol_route_rebuilds_total"] = patrol_route_rebuilds_total
	report["patrol_route_rebuilds_per_min"] = patrol_route_rebuilds_per_min

	var threshold_failures: Array[String] = []
	if patrol_preavoid_events_total < int(GameConfig.kpi_patrol_preavoid_events_min if GameConfig else 1):
		threshold_failures.append("patrol_preavoid_events_total")
	if patrol_collision_repath_events_total > int(GameConfig.kpi_patrol_collision_repath_events_max if GameConfig else 24):
		threshold_failures.append("patrol_collision_repath_events_total")
	if patrol_hard_stalls_per_min > float(GameConfig.kpi_patrol_hard_stalls_per_min_max if GameConfig else 8.0):
		threshold_failures.append("patrol_hard_stalls_per_min")
	if patrol_zero_progress_windows_total > int(GameConfig.kpi_patrol_zero_progress_windows_max if GameConfig else 220):
		threshold_failures.append("patrol_zero_progress_windows_total")
	if geometry_walkable_false_positive_total > int(GameConfig.kpi_geometry_walkable_false_positive_max if GameConfig else 0):
		threshold_failures.append("geometry_walkable_false_positive_total")
	if nav_path_obstacle_intersections_total > int(GameConfig.kpi_nav_path_obstacle_intersections_max if GameConfig else 0):
		threshold_failures.append("nav_path_obstacle_intersections_total")
	if room_graph_fallback_when_navmesh_available_total > int(GameConfig.kpi_room_graph_fallback_when_navmesh_available_max if GameConfig else 0):
		threshold_failures.append("room_graph_fallback_when_navmesh_available_total")
	if patrol_route_rebuilds_per_min > float(GameConfig.kpi_patrol_route_rebuilds_per_min_max if GameConfig else 39.0):
		threshold_failures.append("patrol_route_rebuilds_per_min")
	report["kpi_threshold_failures"] = threshold_failures

	if threshold_failures.is_empty():
		report["gate_status"] = "PASS"
		report["gate_reason"] = "ok"
	else:
		report["gate_status"] = "FAIL"
		report["gate_reason"] = "threshold_failed"
	return report


func _build_scenarios() -> Array:
	return [
		{
			"id": SCENARIO_WALL_DETOUR_PATROL,
			"runner": Callable(self, "_run_wall_detour_patrol"),
		},
		{
			"id": SCENARIO_PROP_CLUSTER_PATROL,
			"runner": Callable(self, "_run_prop_cluster_patrol"),
		},
		{
			"id": SCENARIO_DOOR_CHOKE_PATROL_MIX,
			"runner": Callable(self, "_run_door_choke_patrol_mix"),
		},
		{
			"id": SCENARIO_NARROW_CORRIDOR_PREAVOID,
			"runner": Callable(self, "_run_narrow_corridor_preavoid"),
		},
	]


func _run_wall_detour_patrol() -> Dictionary:
	var root := Node2D.new()
	add_child(root)
	TestHelpers.add_wall(root, Vector2(100.0, 0.0), Vector2(24.0, 220.0))
	var enemy := TestHelpers.spawn_mover(root, Vector2(0.0, 0.0), 1, 1, "enemies")
	if enemy == null:
		root.queue_free()
		await get_tree().physics_frame
		return {"ok": false, "reason": "enemy_spawn_failed", "duration_sec": 0.0}

	var nav := FakeWallDetourNav.new()
	root.add_child(nav)
	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(enemy, null, 2.4)
	pursuit.configure_navigation(nav, 0)
	var target := Vector2(220.0, 0.0)
	pursuit.set("_patrol", FakePatrolDecision.new(target, 1.0))

	await get_tree().process_frame
	await get_tree().physics_frame
	var frames := await _simulate_patrol_frames(pursuit, target, 300)
	root.queue_free()
	await get_tree().physics_frame
	return {
		"ok": true,
		"duration_sec": float(frames) / 60.0,
	}


func _run_prop_cluster_patrol() -> Dictionary:
	var root := Node2D.new()
	add_child(root)
	TestHelpers.add_wall(root, Vector2(108.0, -22.0), Vector2(22.0, 22.0))
	TestHelpers.add_wall(root, Vector2(108.0, 22.0), Vector2(22.0, 22.0))
	TestHelpers.add_wall(root, Vector2(138.0, -22.0), Vector2(22.0, 22.0))
	TestHelpers.add_wall(root, Vector2(138.0, 22.0), Vector2(22.0, 22.0))
	var enemy := TestHelpers.spawn_mover(root, Vector2(0.0, 0.0), 1, 1, "enemies")
	if enemy == null:
		root.queue_free()
		await get_tree().physics_frame
		return {"ok": false, "reason": "enemy_spawn_failed", "duration_sec": 0.0}

	var nav := FakePropsDetourNav.new()
	root.add_child(nav)
	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(enemy, null, 2.4)
	pursuit.configure_navigation(nav, 0)
	var target := Vector2(240.0, 0.0)
	pursuit.set("_patrol", FakePatrolDecision.new(target, 0.95))

	await get_tree().process_frame
	await get_tree().physics_frame
	var frames := await _simulate_patrol_frames(pursuit, target, 280)
	root.queue_free()
	await get_tree().physics_frame
	return {
		"ok": true,
		"duration_sec": float(frames) / 60.0,
	}


func _run_door_choke_patrol_mix() -> Dictionary:
	var world := await _create_door_world()
	var root := world.get("root", null) as Node2D
	if root == null:
		return {"ok": false, "reason": "door_world_bootstrap_failed", "duration_sec": 0.0}

	var door_system := world.get("door_system", null) as Node
	var enemy := TestHelpers.spawn_mover(root, Vector2(0.0, 56.0), 2, 1, "enemies")
	if enemy == null:
		await _free_door_world(world)
		return {"ok": false, "reason": "enemy_spawn_failed", "duration_sec": 0.0}
	enemy.set_meta("door_system", door_system)

	var nav := FakeDirectNav.new()
	root.add_child(nav)
	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(enemy, null, 2.4)
	pursuit.configure_navigation(nav, 0)
	var target := Vector2(0.0, -120.0)
	pursuit.set("_patrol", FakePatrolDecision.new(target, 1.0))

	await get_tree().process_frame
	await get_tree().physics_frame
	var frames := await _simulate_patrol_frames(pursuit, target, 420)
	await _free_door_world(world)
	return {
		"ok": true,
		"duration_sec": float(frames) / 60.0,
	}


func _run_narrow_corridor_preavoid() -> Dictionary:
	var root := Node2D.new()
	add_child(root)
	TestHelpers.add_wall(root, Vector2(128.0, -64.0), Vector2(300.0, 16.0))
	TestHelpers.add_wall(root, Vector2(128.0, 64.0), Vector2(300.0, 16.0))
	TestHelpers.add_wall(root, Vector2(84.0, 0.0), Vector2(18.0, 68.0))
	var enemy := TestHelpers.spawn_mover(root, Vector2(0.0, 0.0), 1, 1, "enemies")
	if enemy == null:
		root.queue_free()
		await get_tree().physics_frame
		return {"ok": false, "reason": "enemy_spawn_failed", "duration_sec": 0.0}

	var nav := FakeDirectNav.new()
	root.add_child(nav)
	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(enemy, null, 2.4)
	pursuit.configure_navigation(nav, 0)
	var target := Vector2(236.0, 0.0)
	pursuit.set("_patrol", FakePatrolDecision.new(target, 1.0))

	await get_tree().process_frame
	await get_tree().physics_frame
	var frames := await _simulate_patrol_frames(pursuit, target, 280)
	root.queue_free()
	await get_tree().physics_frame
	return {
		"ok": true,
		"duration_sec": float(frames) / 60.0,
	}


func _simulate_patrol_frames(pursuit, target: Vector2, max_frames: int) -> int:
	var frames := 0
	for _i in range(max_frames):
		pursuit.execute_intent(
			1.0 / 60.0,
			{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL},
			_patrol_context(target)
		)
		frames += 1
		await get_tree().physics_frame
		if pursuit.owner.global_position.distance_to(target) <= 20.0:
			break
	return frames


func _create_door_world() -> Dictionary:
	var root := Node2D.new()
	add_child(root)
	TestHelpers.add_wall(root, Vector2(-180.0, 0.0), Vector2(240.0, 16.0))
	TestHelpers.add_wall(root, Vector2(180.0, 0.0), Vector2(240.0, 16.0))
	var doors_parent := Node2D.new()
	doors_parent.name = "LayoutDoors"
	root.add_child(doors_parent)
	var door_system := LAYOUT_DOOR_SYSTEM_SCRIPT.new()
	door_system.name = "LayoutDoorSystem"
	root.add_child(door_system)
	door_system.initialize(doors_parent)
	door_system.rebuild_for_layout(FakeDoorLayout.new())
	await get_tree().process_frame
	await get_tree().physics_frame
	return {
		"root": root,
		"door_system": door_system,
	}


func _free_door_world(world: Dictionary) -> void:
	var root := world.get("root", null) as Node
	if root:
		root.queue_free()
	await get_tree().physics_frame


func _snapshot_has_required_keys(snapshot: Dictionary) -> bool:
	for key_variant in SNAPSHOT_REQUIRED_KEYS:
		var key := String(key_variant)
		if not snapshot.has(key):
			return false
	return true


func _metric_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	return {
		"preavoid_events_total": maxi(int(after.get("preavoid_events_total", 0)) - int(before.get("preavoid_events_total", 0)), 0),
		"patrol_preavoid_events_total": maxi(int(after.get("patrol_preavoid_events_total", 0)) - int(before.get("patrol_preavoid_events_total", 0)), 0),
		"patrol_collision_repath_events_total": maxi(int(after.get("patrol_collision_repath_events_total", 0)) - int(before.get("patrol_collision_repath_events_total", 0)), 0),
		"patrol_hard_stall_events_total": maxi(int(after.get("patrol_hard_stall_events_total", 0)) - int(before.get("patrol_hard_stall_events_total", 0)), 0),
		"patrol_zero_progress_windows_total": maxi(int(after.get("patrol_zero_progress_windows_total", 0)) - int(before.get("patrol_zero_progress_windows_total", 0)), 0),
		"geometry_walkable_false_positive_total": maxi(int(after.get("geometry_walkable_false_positive_total", 0)) - int(before.get("geometry_walkable_false_positive_total", 0)), 0),
		"nav_path_obstacle_intersections_total": maxi(int(after.get("nav_path_obstacle_intersections_total", 0)) - int(before.get("nav_path_obstacle_intersections_total", 0)), 0),
		"room_graph_fallback_when_navmesh_available_total": maxi(int(after.get("room_graph_fallback_when_navmesh_available_total", 0)) - int(before.get("room_graph_fallback_when_navmesh_available_total", 0)), 0),
		"patrol_route_rebuilds_total": maxi(int(after.get("patrol_route_rebuilds_total", 0)) - int(before.get("patrol_route_rebuilds_total", 0)), 0),
	}


func _evaluate_thresholds_for_fixture(fixture: Dictionary) -> Dictionary:
	var report := fixture.duplicate(true)
	var duration_sec := maxf(float(report.get("duration_sec", 0.0)), 0.001)
	var patrol_hard_stall_events_total := maxi(int(report.get("patrol_hard_stall_events_total", 0)), 0)
	var patrol_route_rebuilds_total := maxi(int(report.get("patrol_route_rebuilds_total", 0)), 0)
	var patrol_hard_stalls_per_min := float(patrol_hard_stall_events_total) * 60.0 / duration_sec
	var patrol_route_rebuilds_per_min := float(patrol_route_rebuilds_total) * 60.0 / duration_sec
	report["patrol_hard_stalls_per_min"] = patrol_hard_stalls_per_min
	report["patrol_route_rebuilds_per_min"] = patrol_route_rebuilds_per_min

	var failures: Array[String] = []
	if int(report.get("patrol_preavoid_events_total", 0)) < int(GameConfig.kpi_patrol_preavoid_events_min if GameConfig else 1):
		failures.append("patrol_preavoid_events_total")
	if int(report.get("patrol_collision_repath_events_total", 0)) > int(GameConfig.kpi_patrol_collision_repath_events_max if GameConfig else 24):
		failures.append("patrol_collision_repath_events_total")
	if float(report.get("patrol_hard_stalls_per_min", 0.0)) > float(GameConfig.kpi_patrol_hard_stalls_per_min_max if GameConfig else 8.0):
		failures.append("patrol_hard_stalls_per_min")
	if int(report.get("patrol_zero_progress_windows_total", 0)) > int(GameConfig.kpi_patrol_zero_progress_windows_max if GameConfig else 220):
		failures.append("patrol_zero_progress_windows_total")
	if int(report.get("geometry_walkable_false_positive_total", 0)) > int(GameConfig.kpi_geometry_walkable_false_positive_max if GameConfig else 0):
		failures.append("geometry_walkable_false_positive_total")
	if int(report.get("nav_path_obstacle_intersections_total", 0)) > int(GameConfig.kpi_nav_path_obstacle_intersections_max if GameConfig else 0):
		failures.append("nav_path_obstacle_intersections_total")
	if int(report.get("room_graph_fallback_when_navmesh_available_total", 0)) > int(GameConfig.kpi_room_graph_fallback_when_navmesh_available_max if GameConfig else 0):
		failures.append("room_graph_fallback_when_navmesh_available_total")
	if float(report.get("patrol_route_rebuilds_per_min", 0.0)) > float(GameConfig.kpi_patrol_route_rebuilds_per_min_max if GameConfig else 39.0):
		failures.append("patrol_route_rebuilds_per_min")
	report["kpi_threshold_failures"] = failures
	if failures.is_empty():
		report["gate_status"] = "PASS"
		report["gate_reason"] = "ok"
	else:
		report["gate_status"] = "FAIL"
		report["gate_reason"] = "threshold_failed"
	return report


func _build_gate_report_shell() -> Dictionary:
	return {
		"gate_status": "FAIL",
		"gate_reason": "scenario_bootstrap_failed",
		"failed_scenario": "",
		"failed_reason": "",
		"duration_sec": 0.0,
		"scenario_reports": [],
		"metrics_snapshot": {},
		"preavoid_events_total": 0,
		"patrol_preavoid_events_total": 0,
			"patrol_collision_repath_events_total": 0,
			"patrol_hard_stall_events_total": 0,
			"patrol_zero_progress_windows_total": 0,
			"patrol_hard_stalls_per_min": 0.0,
			"geometry_walkable_false_positive_total": 0,
			"nav_path_obstacle_intersections_total": 0,
			"room_graph_fallback_when_navmesh_available_total": 0,
			"patrol_route_rebuilds_total": 0,
			"patrol_route_rebuilds_per_min": 0.0,
			"kpi_threshold_failures": [],
		}


func _patrol_context(player_pos: Vector2) -> Dictionary:
	return {
		"player_pos": player_pos,
		"known_target_pos": Vector2.ZERO,
		"last_seen_pos": Vector2.ZERO,
		"investigate_anchor": Vector2.ZERO,
		"home_position": Vector2.ZERO,
		"alert_level": 0,
		"los": false,
		"combat_lock": false,
	}


func can_enemy_traverse_geometry_point(_enemy: Node, _point: Vector2) -> bool:
	return true
