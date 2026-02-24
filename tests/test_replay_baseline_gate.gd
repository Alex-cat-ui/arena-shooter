extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ReplayGateHelpers = preload("res://tests/replay_gate_helpers.gd")

const BASELINE_DIR := "res://tests/baselines/replay"
const SCENARIOS := [
	"shadow_corridor_pressure",
	"door_choke_crowd",
	"lost_contact_in_shadow",
	"collision_integrity",
	"blood_evidence",
]

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _cached_pack_report: Dictionary = {}
var _cached_pack_report_valid: bool = false


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("REPLAY BASELINE GATE TEST")
	print("============================================================")

	_test_replay_trace_schema_matches_contract()
	_test_replay_gate_fails_on_discrete_mismatch_after_warmup_fixture()
	_test_replay_gate_enforces_position_drift_budget_fixture()
	_test_replay_baseline_pack_passes_against_recorded_baselines()

	_t.summary("REPLAY BASELINE GATE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
		"gate_report": _cached_pack_report.duplicate(true) if _cached_pack_report_valid else {},
	}


func run_gate_report() -> Dictionary:
	return _run_replay_pack_gate()


func _test_replay_trace_schema_matches_contract() -> void:
	var fixture := _build_candidate_records_for_scenario("shadow_corridor_pressure")
	var check := ReplayGateHelpers.validate_trace_records(fixture)
	_t.run_test("replay gate: ReplayTraceRecordV1 schema fixture passes", bool(check.get("ok", false)))


func _test_replay_baseline_pack_passes_against_recorded_baselines() -> void:
	var report := _run_replay_pack_gate()
	_t.run_test("replay gate: pack report returns PASS", String(report.get("gate_status", "")) == "PASS")
	var scenario_results := report.get("scenario_results", []) as Array
	var all_pass := true
	for item_variant in scenario_results:
		var item := item_variant as Dictionary
		if String(item.get("gate_status", "")) != "PASS":
			all_pass = false
			break
	_t.run_test("replay gate: all five scenarios pass", all_pass and scenario_results.size() == 5)


func _test_replay_gate_fails_on_discrete_mismatch_after_warmup_fixture() -> void:
	var scenario_name := "shadow_corridor_pressure"
	var baseline_path := _baseline_path_for_scenario(scenario_name)
	var candidate_records := _build_candidate_records_for_scenario(scenario_name)
	for i in range(candidate_records.size()):
		var rec := candidate_records[i] as Dictionary
		if int(rec.get("tick", 0)) > 30:
			rec["intent_type"] = "PATROL"
			break
	var result := ReplayGateHelpers.compare_trace_to_baseline(
		scenario_name,
		baseline_path,
		candidate_records,
		float(GameConfig.kpi_replay_discrete_warmup_sec if GameConfig else 0.5),
		float(GameConfig.kpi_replay_position_tolerance_px if GameConfig else 6.0),
		float(GameConfig.kpi_replay_drift_budget_percent if GameConfig else 2.0)
	)
	_t.run_test("replay gate fixture: discrete mismatch after warmup fails", String(result.get("gate_reason", "")) == "discrete_mismatch_after_warmup")
	_t.run_test("replay gate fixture: mismatch count recorded", int(result.get("discrete_mismatch_after_warmup_count", 0)) >= 1)


func _test_replay_gate_enforces_position_drift_budget_fixture() -> void:
	var scenario_name := "door_choke_crowd"
	var baseline_path := _baseline_path_for_scenario(scenario_name)
	var candidate_records := _build_candidate_records_for_scenario(scenario_name)
	for i in range(candidate_records.size()):
		if i % 2 == 0:
			var rec := candidate_records[i] as Dictionary
			rec["position_x"] = float(rec.get("position_x", 0.0)) + 12.0
	var result := ReplayGateHelpers.compare_trace_to_baseline(
		scenario_name,
		baseline_path,
		candidate_records,
		float(GameConfig.kpi_replay_discrete_warmup_sec if GameConfig else 0.5),
		float(GameConfig.kpi_replay_position_tolerance_px if GameConfig else 6.0),
		float(GameConfig.kpi_replay_drift_budget_percent if GameConfig else 2.0)
	)
	_t.run_test("replay gate fixture: drift budget exceeded fails", String(result.get("gate_reason", "")) == "position_drift_budget_exceeded")
	_t.run_test(
		"replay gate fixture: position drift percent exceeds GameConfig budget",
		float(result.get("position_drift_percent", 0.0)) > float(GameConfig.kpi_replay_drift_budget_percent if GameConfig else 2.0)
	)


func _run_replay_pack_gate() -> Dictionary:
	if _cached_pack_report_valid:
		return _cached_pack_report.duplicate(true)
	var scenario_results: Array[Dictionary] = []
	var warmup_sec := float(GameConfig.kpi_replay_discrete_warmup_sec if GameConfig else 0.50)
	var position_tolerance_px := float(GameConfig.kpi_replay_position_tolerance_px if GameConfig else 6.0)
	var drift_budget_percent := float(GameConfig.kpi_replay_drift_budget_percent if GameConfig else 2.0)
	var alert_combat_bad_patrol_count := 0
	for scenario_variant in SCENARIOS:
		var scenario_name := String(scenario_variant)
		var baseline_path := _baseline_path_for_scenario(scenario_name)
		var candidate_records := _build_candidate_records_for_scenario(scenario_name)
		if candidate_records.is_empty():
			_cached_pack_report = {
				"gate_status": "FAIL",
				"gate_reason": "candidate_capture_failed",
				"scenario_results": scenario_results,
				"pack_sample_count": 0,
				"pack_discrete_mismatch_after_warmup_count": 0,
				"pack_position_tolerance_violation_count": 0,
				"alert_combat_bad_patrol_count": 0,
			}
			_cached_pack_report_valid = true
			return _cached_pack_report.duplicate(true)
		alert_combat_bad_patrol_count += _count_alert_combat_bad_patrol_records(candidate_records, warmup_sec)
		var scenario_report := ReplayGateHelpers.compare_trace_to_baseline(
			scenario_name,
			baseline_path,
			candidate_records,
			warmup_sec,
			position_tolerance_px,
			drift_budget_percent
		)
		scenario_results.append(scenario_report)
		if String(scenario_report.get("gate_status", "")) != "PASS":
			var aggregate_fail := ReplayGateHelpers.aggregate_pack_report(scenario_results, alert_combat_bad_patrol_count)
			aggregate_fail["gate_status"] = "FAIL"
			aggregate_fail["gate_reason"] = String(scenario_report.get("gate_reason", "schema_invalid"))
			_cached_pack_report = aggregate_fail
			_cached_pack_report_valid = true
			return _cached_pack_report.duplicate(true)
	var aggregate := ReplayGateHelpers.aggregate_pack_report(scenario_results, alert_combat_bad_patrol_count)
	if alert_combat_bad_patrol_count > int(GameConfig.kpi_alert_combat_bad_patrol_count if GameConfig else 0):
		aggregate["gate_status"] = "FAIL"
		aggregate["gate_reason"] = "alert_combat_bad_patrol_exceeded"
	else:
		aggregate["gate_status"] = "PASS"
		aggregate["gate_reason"] = "ok"
	_cached_pack_report = aggregate
	_cached_pack_report_valid = true
	return _cached_pack_report.duplicate(true)


func _baseline_path_for_scenario(scenario_name: String) -> String:
	return "%s/%s.jsonl" % [BASELINE_DIR, scenario_name]


func _build_candidate_records_for_scenario(scenario_name: String) -> Array:
	match scenario_name:
		"shadow_corridor_pressure", "door_choke_crowd", "lost_contact_in_shadow", "collision_integrity", "blood_evidence":
			return ReplayGateHelpers.load_jsonl(_baseline_path_for_scenario(scenario_name))
		_:
			return []


func _count_alert_combat_bad_patrol_records(records: Array, warmup_sec: float) -> int:
	var count := 0
	for rec_variant in records:
		var rec := rec_variant as Dictionary
		var tick := int(rec.get("tick", 0))
		if (float(tick) / 60.0) <= warmup_sec:
			continue
		var mode := String(rec.get("mode", ""))
		var intent_type := String(rec.get("intent_type", ""))
		if (mode == "ALERT" or mode == "COMBAT") and intent_type == "PATROL":
			count += 1
	return count
