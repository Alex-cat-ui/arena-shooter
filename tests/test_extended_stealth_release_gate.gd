extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")

const AI_PERFORMANCE_GATE_TEST_SCENE := "res://tests/test_ai_performance_gate.tscn"
const REPLAY_BASELINE_GATE_TEST_SCENE := "res://tests/test_replay_baseline_gate.tscn"
const LEVEL_STEALTH_CHECKLIST_TEST_SCENE := "res://tests/test_level_stealth_checklist.tscn"

const LEGACY_ZERO_TOLERANCE_CMD := "rg -n \"\\blegacy_|\\btemporary_|\\bdebug_shadow_override\\b|\\bold_(ai|nav|path|search|shadow|squad|combat|utility|patrol|pursuit|legacy)\" src tests -g '!tests/test_extended_stealth_release_gate.gd' -S"

const DEPENDENCY_GATES := [
	{
		"phase_id": "PHASE-15",
		"command": 'rg -n "target_context_exists|SHADOW_BOUNDARY_SCAN|if not has_los and alert_level >= ENEMY_ALERT_LEVELS_SCRIPT\\.ALERT" src/entities/enemy.gd src/systems/enemy_utility_brain.gd -S',
	},
	{
		"phase_id": "PHASE-16",
		"command": 'rg -n "_record_combat_search_execution_feedback|_select_next_combat_dark_search_node|_combat_search_current_node_key|combat_search_shadow_scan_suppressed" src/entities/enemy.gd -S',
	},
	{
		"phase_id": "PHASE-17",
		"command": 'rg -n "repath_recovery_reason|repath_recovery_request_next_search_node" src/systems/enemy_pursuit_system.gd src/entities/enemy.gd -S',
	},
	{
		"phase_id": "PHASE-18",
		"command": 'rg -n "slot_role|cover_source|cover_los_break_quality|flank_slot_contract_ok" src/systems/enemy_squad_system.gd src/entities/enemy.gd src/systems/enemy_utility_brain.gd -S',
	},
]

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _last_gate_report: Dictionary = {}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("EXTENDED STEALTH RELEASE GATE TEST")
	print("============================================================")

	_test_extended_stealth_release_gate_blocks_on_dependency_gate_failure_fixture()
	_test_extended_stealth_release_gate_blocks_on_legacy_zero_tolerance_fixture()
	_test_extended_stealth_release_gate_pass_fixture_contract()

	_t.summary("EXTENDED STEALTH RELEASE GATE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
		"gate_report": _last_gate_report.duplicate(true),
	}


func run_gate_report() -> Dictionary:
	var report := await _run_release_gate()
	_last_gate_report = report.duplicate(true)
	return report


func _test_extended_stealth_release_gate() -> void:
	# Owner integration entrypoint (not part of default run_suite to avoid long-running subgates in the main runner).
	# Keep callable for Phase 19 release gate ownership and direct execution when needed.
	pass


func _run_release_gate(fixtures: Dictionary = {}) -> Dictionary:
	var report := {
		"final_result": "FAIL",
		"final_reason": "dependency_gate_failed",
		"dependency_gate_pass": false,
		"performance_gate_pass": false,
		"replay_gate_pass": false,
		"checklist_gate_pass": false,
		"legacy_zero_tolerance_pass": false,
		"dependency_gate_results": [],
		"performance_gate_report": {},
		"replay_gate_report": {},
		"checklist_gate_report": {},
		"legacy_zero_tolerance_matches": [],
	}

	var dependency_gate_results: Array = []
	if fixtures.has("dependency_gate_results"):
		dependency_gate_results = fixtures.get("dependency_gate_results", []) as Array
	else:
		dependency_gate_results = _run_dependency_gates()
	report["dependency_gate_results"] = (dependency_gate_results as Array).duplicate(true)
	for item_variant in (dependency_gate_results as Array):
		var item := item_variant as Dictionary
		if not bool(item.get("passed", false)):
			report["final_result"] = "FAIL"
			report["final_reason"] = "dependency_gate_failed"
			return report
	report["dependency_gate_pass"] = true

	var performance_gate_report: Dictionary = {}
	if fixtures.has("performance_gate_report"):
		var performance_fixture: Variant = fixtures.get("performance_gate_report", {})
		if performance_fixture is Callable:
			performance_gate_report = ((performance_fixture as Callable).call() as Dictionary).duplicate(true)
		else:
			performance_gate_report = (performance_fixture as Dictionary).duplicate(true)
	else:
		performance_gate_report = await _run_embedded_gate_scene(AI_PERFORMANCE_GATE_TEST_SCENE)
	report["performance_gate_report"] = performance_gate_report
	if String(performance_gate_report.get("gate_status", "")) != "PASS":
		report["final_result"] = "FAIL"
		report["final_reason"] = "performance_gate_failed"
		return report
	report["performance_gate_pass"] = true

	var replay_gate_report: Dictionary = {}
	if fixtures.has("replay_gate_report"):
		var replay_fixture: Variant = fixtures.get("replay_gate_report", {})
		if replay_fixture is Callable:
			replay_gate_report = ((replay_fixture as Callable).call() as Dictionary).duplicate(true)
		else:
			replay_gate_report = (replay_fixture as Dictionary).duplicate(true)
	else:
		replay_gate_report = await _run_embedded_gate_scene(REPLAY_BASELINE_GATE_TEST_SCENE)
	report["replay_gate_report"] = replay_gate_report
	if String(replay_gate_report.get("gate_status", "")) != "PASS":
		report["final_result"] = "FAIL"
		report["final_reason"] = "replay_gate_failed"
		return report
	report["replay_gate_pass"] = true

	var checklist_gate_report: Dictionary = {}
	if fixtures.has("checklist_gate_report"):
		var checklist_fixture: Variant = fixtures.get("checklist_gate_report", {})
		if checklist_fixture is Callable:
			checklist_gate_report = ((checklist_fixture as Callable).call() as Dictionary).duplicate(true)
		else:
			checklist_gate_report = (checklist_fixture as Dictionary).duplicate(true)
	else:
		checklist_gate_report = await _run_embedded_gate_scene(LEVEL_STEALTH_CHECKLIST_TEST_SCENE)
	report["checklist_gate_report"] = checklist_gate_report
	if String(checklist_gate_report.get("gate_status", "")) != "PASS":
		report["final_result"] = "FAIL"
		report["final_reason"] = "checklist_gate_failed"
		return report
	report["checklist_gate_pass"] = true

	var legacy_matches: Array = []
	if fixtures.has("legacy_zero_tolerance_matches"):
		legacy_matches = (fixtures.get("legacy_zero_tolerance_matches", []) as Array).duplicate(true)
	else:
		legacy_matches = _run_shell_collect_lines(LEGACY_ZERO_TOLERANCE_CMD)
	report["legacy_zero_tolerance_matches"] = legacy_matches.duplicate(true)
	if not legacy_matches.is_empty():
		report["final_result"] = "FAIL"
		report["final_reason"] = "legacy_zero_tolerance_failed"
		return report
	report["legacy_zero_tolerance_pass"] = true
	report["final_result"] = "PASS"
	report["final_reason"] = "ok"
	return report


func _test_extended_stealth_release_gate_blocks_on_dependency_gate_failure_fixture() -> void:
	var calls := {"subgate_calls": 0}
	var dependency_fixture := [
		{"phase_id": "PHASE-15", "command": "x", "passed": true},
		{"phase_id": "PHASE-16", "command": "y", "passed": true},
		{"phase_id": "PHASE-17", "command": "z", "passed": true},
		{"phase_id": "PHASE-18", "command": "w", "passed": false},
	]
	var report := await _run_release_gate({
		"dependency_gate_results": dependency_fixture,
		"performance_gate_report": Callable(self, "_counted_subgate_report").bind(calls, "PASS"),
		"replay_gate_report": Callable(self, "_counted_subgate_report").bind(calls, "PASS"),
		"checklist_gate_report": Callable(self, "_counted_subgate_report").bind(calls, "PASS"),
		"legacy_zero_tolerance_matches": [],
	})
	_t.run_test("release gate fixture: dependency failure blocks final gate", String(report.get("final_reason", "")) == "dependency_gate_failed")
	_t.run_test("release gate fixture: subgates not executed after dependency failure", int(calls.get("subgate_calls", -1)) == 0)


func _test_extended_stealth_release_gate_blocks_on_legacy_zero_tolerance_fixture() -> void:
	var calls := {"subgate_calls": 0}
	var report := await _run_release_gate({
		"dependency_gate_results": _all_dependency_fixtures_pass(),
		"performance_gate_report": Callable(self, "_counted_subgate_report").bind(calls, "PASS"),
		"replay_gate_report": Callable(self, "_counted_subgate_report").bind(calls, "PASS"),
		"checklist_gate_report": Callable(self, "_counted_subgate_report").bind(calls, "PASS"),
		"legacy_zero_tolerance_matches": ["tests/tmp_fixture.gd:1:var temporary_bad := true"],
	})
	_t.run_test("release gate fixture: legacy zero-tolerance match blocks gate", String(report.get("final_reason", "")) == "legacy_zero_tolerance_failed")
	_t.run_test("release gate fixture: all subgates executed before legacy scan", int(calls.get("subgate_calls", 0)) == 3)


func _test_extended_stealth_release_gate_pass_fixture_contract() -> void:
	var calls := {"subgate_calls": 0}
	var report := await _run_release_gate({
		"dependency_gate_results": _all_dependency_fixtures_pass(),
		"performance_gate_report": Callable(self, "_counted_subgate_report").bind(calls, "PASS"),
		"replay_gate_report": Callable(self, "_counted_subgate_report").bind(calls, "PASS"),
		"checklist_gate_report": Callable(self, "_counted_subgate_report").bind(calls, "PASS"),
		"legacy_zero_tolerance_matches": [],
	})
	_t.run_test("release gate fixture: pass returns PASS/ok", String(report.get("final_result", "")) == "PASS" and String(report.get("final_reason", "")) == "ok")
	_t.run_test(
		"release gate fixture: report shape contains subreports and dependency list",
		(report.get("dependency_gate_results", []) as Array).size() == 4
			and report.has("performance_gate_report")
			and report.has("replay_gate_report")
			and report.has("checklist_gate_report")
	)


func _all_dependency_fixtures_pass() -> Array:
	var out: Array = []
	for item_variant in DEPENDENCY_GATES:
		var item := item_variant as Dictionary
		out.append({
			"phase_id": String(item.get("phase_id", "")),
			"command": String(item.get("command", "")),
			"passed": true,
		})
	return out


func _counted_subgate_report(counter: Dictionary, status: String) -> Dictionary:
	counter["subgate_calls"] = int(counter.get("subgate_calls", 0)) + 1
	return {"gate_status": status, "gate_reason": "ok" if status == "PASS" else "fixture_fail"}


func _run_dependency_gates() -> Array:
	var results: Array = []
	for item_variant in DEPENDENCY_GATES:
		var item := item_variant as Dictionary
		var command := String(item.get("command", ""))
		var lines := _run_shell_collect_lines(command)
		var passed := not lines.is_empty()
		var row := {
			"phase_id": String(item.get("phase_id", "")),
			"command": command,
			"passed": passed,
		}
		results.append(row)
		if not passed:
			break
	return results


func _run_embedded_gate_scene(scene_path: String) -> Dictionary:
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		return {"gate_status": "FAIL", "gate_reason": "scene_missing", "scene_path": scene_path}
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return {"gate_status": "FAIL", "gate_reason": "scene_load_failed", "scene_path": scene_path}
	var node := scene.instantiate() as Node
	if node == null:
		return {"gate_status": "FAIL", "gate_reason": "scene_instantiate_failed", "scene_path": scene_path}
	if _has_property(node, "embedded_mode"):
		node.set("embedded_mode", true)
	add_child(node)
	var report: Dictionary = {}
	if node.has_method("run_gate_report"):
		report = await node.call("run_gate_report")
	elif node.has_method("run_suite"):
		var suite_result: Dictionary = await node.call("run_suite")
		report = suite_result.get("gate_report", {}) as Dictionary
	if report.is_empty():
		report = {"gate_status": "FAIL", "gate_reason": "gate_report_missing", "scene_path": scene_path}
	node.queue_free()
	await get_tree().process_frame
	return report


func _run_shell_collect_lines(command: String) -> Array:
	var output: Array = []
	var exit_code := OS.execute("bash", ["-lc", command], output, true)
	if exit_code != 0 and output.is_empty():
		return []
	var lines: Array = []
	for chunk_variant in output:
		var chunk := String(chunk_variant)
		for line_variant in chunk.split("\n", false):
			var line := String(line_variant).strip_edges()
			if line != "":
				lines.append(line)
	return lines


func _has_property(obj: Object, property_name: String) -> bool:
	for p_variant in obj.get_property_list():
		var p := p_variant as Dictionary
		if String(p.get("name", "")) == property_name:
			return true
	return false
