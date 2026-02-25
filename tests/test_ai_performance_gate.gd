extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LONG_RUN_STRESS_SCENE := preload("res://tests/test_ai_long_run_stress.tscn")

const FIXED_BENCHMARK_CONFIG := {
	"seed": 1337,
	"duration_sec": 180.0,
	"enemy_count": 12,
	"fixed_physics_frames": 10800,
	"scene_path": "res://src/levels/stealth_3zone_test.tscn",
	"force_collision_repath": true,
}

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _cached_gate_report: Dictionary = {}
var _cached_gate_report_valid: bool = false


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("AI PERFORMANCE GATE TEST")
	print("============================================================")

	await _test_performance_gate_metrics_formulas_and_thresholds()
	await _test_collision_repath_metric_alive_in_forced_collision_stress()
	_test_performance_gate_rejects_threshold_failure_fixture()

	_t.summary("AI PERFORMANCE GATE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
		"gate_report": _cached_gate_report.duplicate(true) if _cached_gate_report_valid else {},
	}


func run_gate_report() -> Dictionary:
	return await _get_or_run_fixed_benchmark_report()


func _test_performance_gate_metrics_formulas_and_thresholds() -> void:
	var report := await _get_or_run_fixed_benchmark_report()
	var duration_sec := float(report.get("duration_sec", 0.0))
	var enemy_count := int(report.get("enemy_count", 0))
	var replans_total := int(report.get("replans_total", 0))
	var detour_total := int(report.get("detour_candidates_evaluated_total", 0))
	var hard_stalls_total := int(report.get("hard_stall_events_total", 0))
	var patrol_hard_stalls_total := int(report.get("patrol_hard_stall_events_total", 0))
	var patrol_route_rebuilds_total := int(report.get("patrol_route_rebuilds_total", 0))
	var expected_replans_per_enemy_per_sec := float(replans_total) / maxf(float(maxi(enemy_count, 1)) * maxf(duration_sec, 0.001), 0.001)
	var expected_detour_candidates_per_replan := float(detour_total) / float(maxi(replans_total, 1))
	var expected_hard_stalls_per_min := float(hard_stalls_total) * 60.0 / maxf(duration_sec, 0.001)
	var expected_patrol_hard_stalls_per_min := float(patrol_hard_stalls_total) * 60.0 / maxf(duration_sec, 0.001)
	var expected_patrol_route_rebuilds_per_min := float(patrol_route_rebuilds_total) * 60.0 / maxf(duration_sec, 0.001)
	var formulas_ok := (
		is_equal_approx(float(report.get("replans_per_enemy_per_sec", -1.0)), expected_replans_per_enemy_per_sec)
		and is_equal_approx(float(report.get("detour_candidates_per_replan", -1.0)), expected_detour_candidates_per_replan)
		and is_equal_approx(float(report.get("hard_stalls_per_min", -1.0)), expected_hard_stalls_per_min)
		and is_equal_approx(float(report.get("patrol_hard_stalls_per_min", -1.0)), expected_patrol_hard_stalls_per_min)
		and is_equal_approx(float(report.get("patrol_route_rebuilds_per_min", -1.0)), expected_patrol_route_rebuilds_per_min)
	)
	var fixed_config_ok := (
		int(report.get("seed", -1)) == 1337
		and is_equal_approx(float(report.get("duration_sec", 0.0)), 180.0)
		and int(report.get("enemy_count", -1)) == 12
		and int(report.get("fixed_physics_frames", -1)) == 10800
	)
	var thresholds_ok := bool((report.get("kpi_threshold_failures", []) as Array).is_empty()) and String(report.get("gate_reason", "")) != "threshold_failed"
	_t.run_test("performance gate: fixed benchmark config is exact", fixed_config_ok)
	_t.run_test("performance gate: derived formulas match contract", formulas_ok)
	_t.run_test(
		"performance gate: fixed benchmark report verdict is PASS/ok",
		String(report.get("gate_status", "")) == "PASS" and String(report.get("gate_reason", "")) == "ok"
	)
	_t.run_test("performance gate: threshold verdict is enforced", thresholds_ok or String(report.get("gate_status", "")) == "FAIL")


func _test_collision_repath_metric_alive_in_forced_collision_stress() -> void:
	var report := await _get_or_run_fixed_benchmark_report()
	_t.run_test(
		"performance gate: collision_repath_events_total > 0 in forced collision stress",
		int(report.get("collision_repath_events_total", 0)) > 0
	)


func _test_performance_gate_rejects_threshold_failure_fixture() -> void:
	var fixture := {
		"seed": 1337,
		"duration_sec": 180.0,
		"enemy_count": 12,
		"fixed_physics_frames": 10800,
		"ai_ms_avg": 0.8,
		"ai_ms_p95": float(GameConfig.kpi_ai_ms_p95_max if GameConfig else 2.5) + 0.1,
		"replans_total": 100,
		"detour_candidates_evaluated_total": 1500,
		"hard_stall_events_total": 10,
		"collision_repath_events_total": 3,
			"patrol_preavoid_events_total": 0,
			"patrol_collision_repath_events_total": 4,
			"patrol_hard_stall_events_total": 40,
			"patrol_zero_progress_windows_total": 12,
			"geometry_walkable_false_positive_total": 1,
			"nav_path_obstacle_intersections_total": 1,
			"room_graph_fallback_when_navmesh_available_total": 1,
			"patrol_route_rebuilds_total": 200,
		}
	var report := _evaluate_thresholds_for_fixture(fixture)
	var failures := report.get("kpi_threshold_failures", []) as Array
	_t.run_test("performance gate fixture: threshold failure rejects", String(report.get("gate_status", "")) == "FAIL")
	_t.run_test("performance gate fixture: reason threshold_failed", String(report.get("gate_reason", "")) == "threshold_failed")
	_t.run_test(
		"performance gate fixture: deterministic failure order includes expanded patrol KPI keys",
		failures.size() >= 4
			and String(failures[0]) == "ai_ms_p95"
			and failures.has("hard_stalls_per_min")
			and failures.has("patrol_preavoid_events_total")
			and failures.has("patrol_hard_stalls_per_min")
	)


func _get_or_run_fixed_benchmark_report() -> Dictionary:
	if _cached_gate_report_valid:
		return _cached_gate_report.duplicate(true)
	var node := LONG_RUN_STRESS_SCENE.instantiate() as Node
	if node == null:
		_cached_gate_report = {
			"gate_status": "FAIL",
			"gate_reason": "scene_bootstrap_failed",
			"seed": 1337,
			"duration_sec": 180.0,
			"enemy_count": 12,
			"fixed_physics_frames": 10800,
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
		_cached_gate_report_valid = true
		return _cached_gate_report.duplicate(true)
	if _has_property(node, "embedded_mode"):
		node.set("embedded_mode", true)
	add_child(node)
	if not node.has_method("run_benchmark_contract"):
		_cached_gate_report = {"gate_status": "FAIL", "gate_reason": "metrics_contract_missing", "kpi_threshold_failures": []}
		_cached_gate_report_valid = true
		node.queue_free()
		await get_tree().process_frame
		return _cached_gate_report.duplicate(true)
	_cached_gate_report = await node.call("run_benchmark_contract", FIXED_BENCHMARK_CONFIG)
	_cached_gate_report_valid = true
	node.queue_free()
	await get_tree().process_frame
	return _cached_gate_report.duplicate(true)


func _evaluate_thresholds_for_fixture(fixture: Dictionary) -> Dictionary:
	var report := fixture.duplicate(true)
	var duration_sec := maxf(float(report.get("duration_sec", 0.0)), 0.001)
	var enemy_count := maxi(int(report.get("enemy_count", 0)), 1)
	var replans_total := maxi(int(report.get("replans_total", 0)), 0)
	var detour_total := maxi(int(report.get("detour_candidates_evaluated_total", 0)), 0)
	var hard_stalls_total := maxi(int(report.get("hard_stall_events_total", 0)), 0)
	var patrol_hard_stalls_total := maxi(int(report.get("patrol_hard_stall_events_total", 0)), 0)
	var patrol_route_rebuilds_total := maxi(int(report.get("patrol_route_rebuilds_total", 0)), 0)
	report["replans_per_enemy_per_sec"] = float(replans_total) / (float(enemy_count) * duration_sec)
	report["detour_candidates_per_replan"] = float(detour_total) / float(maxi(replans_total, 1))
	report["hard_stalls_per_min"] = float(hard_stalls_total) * 60.0 / duration_sec
	report["patrol_hard_stalls_per_min"] = float(patrol_hard_stalls_total) * 60.0 / duration_sec
	report["patrol_route_rebuilds_per_min"] = float(patrol_route_rebuilds_total) * 60.0 / duration_sec
	var failures: Array[String] = []
	if float(report.get("ai_ms_avg", 0.0)) > float(GameConfig.kpi_ai_ms_avg_max if GameConfig else 1.20):
		failures.append("ai_ms_avg")
	if float(report.get("ai_ms_p95", 0.0)) > float(GameConfig.kpi_ai_ms_p95_max if GameConfig else 2.50):
		failures.append("ai_ms_p95")
	if float(report.get("replans_per_enemy_per_sec", 0.0)) > float(GameConfig.kpi_replans_per_enemy_per_sec_max if GameConfig else 1.80):
		failures.append("replans_per_enemy_per_sec")
	if float(report.get("detour_candidates_per_replan", 0.0)) > float(GameConfig.kpi_detour_candidates_per_replan_max if GameConfig else 24.0):
		failures.append("detour_candidates_per_replan")
	if float(report.get("hard_stalls_per_min", 0.0)) > float(GameConfig.kpi_hard_stalls_per_min_max if GameConfig else 1.0):
		failures.append("hard_stalls_per_min")
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
	if int(report.get("collision_repath_events_total", 0)) <= 0:
		report["gate_status"] = "FAIL"
		report["gate_reason"] = "collision_repath_metric_dead"
	elif failures.is_empty():
		report["gate_status"] = "PASS"
		report["gate_reason"] = "ok"
	else:
		report["gate_status"] = "FAIL"
		report["gate_reason"] = "threshold_failed"
	return report


func _has_property(obj: Object, property_name: String) -> bool:
	for p_variant in obj.get_property_list():
		var p := p_variant as Dictionary
		if String(p.get("name", "")) == property_name:
			return true
	return false
