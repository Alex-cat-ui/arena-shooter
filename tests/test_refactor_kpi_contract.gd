extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")

const NAV_HELPER_SCRIPTS := [
	"res://src/systems/navigation_runtime_queries.gd",
	"res://src/systems/navigation_shadow_policy.gd",
	"res://src/systems/navigation_enemy_wiring.gd",
]

const ZONE_HELPER_SCRIPTS := [
	"res://src/systems/zone_state_machine_runtime.gd",
	"res://src/systems/zone_reinforcement_runtime.gd",
]

const ENEMY_RUNTIME_HELPER_SCRIPTS := [
	"res://src/entities/enemy_combat_search_runtime.gd",
	"res://src/entities/enemy_fire_control_runtime.gd",
	"res://src/entities/enemy_combat_role_runtime.gd",
	"res://src/entities/enemy_alert_latch_runtime.gd",
	"res://src/entities/enemy_detection_runtime.gd",
	"res://src/entities/enemy_debug_snapshot_runtime.gd",
]

const PHASE10_LEGACY_PREFIX_BAN_IGNORED_PATHS := {
	"res://tests/test_extended_stealth_release_gate.gd": true,
}
const ENEMY_PRIVATE_ACCESS_BAN_IGNORED_PATHS := {
	"res://tests/test_extended_stealth_release_gate.gd": true,
}

var embedded_mode: bool = false
var _t := TestHelpers.new()


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("REFACTOR KPI CONTRACT TEST")
	print("============================================================")

	_test_refactor_kpi_contracts()

	_t.summary("REFACTOR KPI CONTRACT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_refactor_kpi_contracts() -> void:
	var pursuit_text := _read_text("res://src/systems/enemy_pursuit_system.gd")
	_t.run_test(
		"KPI: pursuit runtime has no legacy branch tokens",
		_contains_none(pursuit_text, ["_update_simple_ai", "_update_room_ai", "use_room_nav"])
	)

	var nav_service_text := _read_text("res://src/systems/navigation_service.gd")
	_t.run_test(
		"KPI: navigation service preloads runtime helper modules",
		_contains_all(nav_service_text, ["NAV_RUNTIME_QUERIES_SCRIPT", "NAV_SHADOW_POLICY_SCRIPT", "NAV_ENEMY_WIRING_SCRIPT"])
	)
	_t.run_test(
		"KPI: navigation service has no dead wrapper methods",
		_contains_none(
			nav_service_text,
			[
				"func _is_enemy_flashlight_active",
				"func _build_room_graph_path_points(",
				"func _get_zone_director(",
				"func _resolve_door_system_for_enemy(",
				"func _connect_regions_at_door(",
			]
		)
	)

	var zone_director_text := _read_text("res://src/systems/zone_director.gd")
	_t.run_test(
		"KPI: zone director preloads runtime helper modules",
		_contains_all(zone_director_text, ["ZONE_STATE_MACHINE_RUNTIME_SCRIPT", "ZONE_REINFORCEMENT_RUNTIME_SCRIPT"])
	)

	var game_systems_text := _read_text("res://src/systems/game_systems.gd")
	_t.run_test(
		"KPI: GameSystems no longer contains phase-0 stub markers",
		_contains_none(game_systems_text, ["Phase 0: Stub", "Phase 0 stub"])
	)

	var physics_world_text := _read_text("res://src/systems/physics_world.gd")
	_t.run_test(
		"KPI: PhysicsWorld no longer contains phase-0 stub markers",
		_contains_none(physics_world_text, ["Phase 0: Stub", "Phase 0 stub"])
	)

	var nav_helpers_exist := true
	for script_path_variant in NAV_HELPER_SCRIPTS:
		var script_path := String(script_path_variant)
		if not ResourceLoader.exists(script_path, "Script"):
			nav_helpers_exist = false
			break
	_t.run_test("KPI: navigation helper scripts exist", nav_helpers_exist)

	var zone_helpers_exist := true
	for script_path_variant in ZONE_HELPER_SCRIPTS:
		var script_path := String(script_path_variant)
		if not ResourceLoader.exists(script_path, "Script"):
			zone_helpers_exist = false
			break
	_t.run_test("KPI: zone helper scripts exist", zone_helpers_exist)

	var enemy_runtime_helpers_exist := true
	for script_path_variant in ENEMY_RUNTIME_HELPER_SCRIPTS:
		var script_path := String(script_path_variant)
		if not ResourceLoader.exists(script_path, "Script"):
			enemy_runtime_helpers_exist = false
			break
	_t.run_test("KPI: enemy runtime helper scripts exist", enemy_runtime_helpers_exist)

	var runner_text := _read_text("res://tests/test_runner_node.gd")
	_t.run_test(
		"KPI: test runner uses scene_exists helper for existence checks",
		runner_text.find("_scene_exists(") >= 0
			and runner_text.find("return load(") < 0
	)
	_t.run_test(
		"KPI: runner has no Phase 10 bugfix embedded section markers",
		_contains_none(
			runner_text,
			[
				"SECTION 18c: Bugfix phase unit tests",
				"Phase 1: on_heard_shot",
				"Phase 2: noise->ALERT",
				"Phase 3: stuck patrol",
			]
		)
	)
	_t.run_test(
		"KPI: phase bugfix test scene removed",
		not ResourceLoader.exists("res://tests/test_phase_bugfixes.tscn", "PackedScene")
	)
	_t.run_test(
		"KPI: phase bugfix test script removed",
		not FileAccess.file_exists("res://tests/test_phase_bugfixes.gd")
	)

	var coord_text := _read_text("res://src/systems/enemy_aggro_coordinator.gd")
	_t.run_test(
		"KPI: coordinator has unified escalation source guard",
		coord_text.find("_is_valid_escalation_source") >= 0
			and coord_text.find("_is_valid_teammate_call_source") >= 0
	)
	_t.run_test(
		"KPI: coordinator has no dead room-alert propagation helper",
		coord_text.find("func _propagate_room_alert(") < 0
	)

	var enemy_text := _read_text("res://src/entities/enemy.gd")
	_t.run_test(
		"KPI: enemy has no dead lockdown combat-window helper",
		enemy_text.find("func _lockdown_combat_no_contact_window_sec(") < 0
	)

	var perception_text := _read_text("res://src/systems/enemy_perception_system.gd")
	_t.run_test(
		"KPI: perception has no RuntimeState shadow fallback",
		perception_text.find("RuntimeState") < 0
			or perception_text.find("player_visibility_mul") < 0
	)

	var shadow_policy_text := _read_text("res://src/systems/navigation_shadow_policy.gd")
	_t.run_test(
		"KPI: shadow policy has no meta or snapshot flashlight fallback",
		shadow_policy_text.find("flashlight_active") < 0
			or shadow_policy_text.find("get_meta") < 0
	)

	var game_config_text := _read_text("res://src/core/game_config.gd")
	_t.run_test(
		"KPI: GameConfig declares Phase 19 kpi_* exports",
		_contains_all(
			game_config_text,
			[
				"@export var kpi_ai_ms_avg_max",
				"@export var kpi_ai_ms_p95_max",
				"@export var kpi_replans_per_enemy_per_sec_max",
				"@export var kpi_detour_candidates_per_replan_max",
				"@export var kpi_hard_stalls_per_min_max",
				"@export var kpi_alert_combat_bad_patrol_count",
				"@export var kpi_shadow_pocket_min_area_px2",
				"@export var kpi_shadow_escape_max_len_px",
				"@export var kpi_alt_route_max_factor",
				"@export var kpi_shadow_scan_points_min",
				"@export var kpi_replay_position_tolerance_px",
				"@export var kpi_replay_drift_budget_percent",
				"@export var kpi_replay_discrete_warmup_sec",
			]
		)
	)

	var phase19_gate_scenes := [
		"res://tests/test_ai_performance_gate.tscn",
		"res://tests/test_replay_baseline_gate.tscn",
		"res://tests/test_level_stealth_checklist.tscn",
		"res://tests/test_extended_stealth_release_gate.tscn",
		"res://tests/test_3zone_combat_transition_stress.tscn",
	]
	var phase19_gate_scenes_exist := true
	for scene_path_variant in phase19_gate_scenes:
		var scene_path := String(scene_path_variant)
		if not ResourceLoader.exists(scene_path, "PackedScene"):
			phase19_gate_scenes_exist = false
			break
	_t.run_test("KPI: Phase 19 gate scenes exist", phase19_gate_scenes_exist)

	_t.run_test(
		"KPI: runner registers Phase 19 gate scenes",
		_contains_all(
			runner_text,
			[
				"const AI_PERFORMANCE_GATE_TEST_SCENE := ",
				"const REPLAY_BASELINE_GATE_TEST_SCENE := ",
				"const LEVEL_STEALTH_CHECKLIST_TEST_SCENE := ",
				"const EXTENDED_STEALTH_RELEASE_GATE_TEST_SCENE := ",
				"_scene_exists(AI_PERFORMANCE_GATE_TEST_SCENE)",
				"_scene_exists(REPLAY_BASELINE_GATE_TEST_SCENE)",
				"_scene_exists(LEVEL_STEALTH_CHECKLIST_TEST_SCENE)",
				"_scene_exists(EXTENDED_STEALTH_RELEASE_GATE_TEST_SCENE)",
				"AI performance gate suite",
				"Replay baseline gate suite",
				"Level stealth checklist gate suite",
				"Extended stealth release gate suite",
			]
		)
	)
	var release_gate_text := _read_text("res://tests/test_extended_stealth_release_gate.gd")
	_t.run_test(
		"KPI: release gate enforces endgame crowd-collapse gate",
		_contains_all(
			release_gate_text,
			[
				"const ENDGAME_COLLAPSE_GATE_TEST_SCENE := ",
				"endgame_gate_report",
				"endgame_gate_pass",
				"endgame_gate_failed",
			]
		)
	)

	var baseline_paths := [
		"res://tests/baselines/replay/shadow_corridor_pressure.jsonl",
		"res://tests/baselines/replay/door_choke_crowd.jsonl",
		"res://tests/baselines/replay/lost_contact_in_shadow.jsonl",
		"res://tests/baselines/replay/collision_integrity.jsonl",
		"res://tests/baselines/replay/blood_evidence.jsonl",
	]
	var baselines_exist := true
	for baseline_path_variant in baseline_paths:
		var baseline_path := String(baseline_path_variant)
		if not FileAccess.file_exists(baseline_path):
			baselines_exist = false
			break
	_t.run_test("KPI: Phase 19 replay baseline artifacts exist", baselines_exist)

	_t.run_test(
		"KPI: Phase 19 manual checklist artifact exists",
		FileAccess.file_exists("res://docs/qa/stealth_level_checklist_stealth_3zone_test.md")
	)

	var phase10_prefix_matches := _collect_phase10_prefix_ban_matches()
	_t.run_test("KPI: Phase 10 legacy prefix ban has zero matches", phase10_prefix_matches.is_empty())
	var enemy_private_access_matches := _collect_enemy_private_access_matches()
	_t.run_test("KPI: Enemy private-access test style ban has zero matches", enemy_private_access_matches.is_empty())


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _contains_all(text: String, needles: Array) -> bool:
	for needle_variant in needles:
		var needle := String(needle_variant)
		if text.find(needle) < 0:
			return false
	return true


func _contains_none(text: String, needles: Array) -> bool:
	for needle_variant in needles:
		var needle := String(needle_variant)
		if text.find(needle) >= 0:
			return false
	return true


func _collect_phase10_prefix_ban_matches() -> Array:
	var regex := RegEx.new()
	if regex.compile(_build_phase10_prefix_ban_pattern()) != OK:
		return ["regex_compile_failed"]

	var out: Array = []
	var roots := ["res://src", "res://tests"]
	for root_variant in roots:
		var root := String(root_variant)
		var gd_files := _collect_gd_files(root)
		for path_variant in gd_files:
			var path := String(path_variant)
			if PHASE10_LEGACY_PREFIX_BAN_IGNORED_PATHS.has(path):
				continue
			var text := _read_text(path)
			if text == "":
				continue
			if regex.search(text) != null:
				out.append(path)
	return out


func _build_phase10_prefix_ban_pattern() -> String:
	var legacyPrefix := "\\b" + "legacy" + "_"
	var temporaryPrefix := "\\b" + "temporary" + "_"
	var debugShadowOverride := "\\b" + "debug" + "_" + "shadow" + "_" + "override\\b"
	var oldPrefix := "\\b" + "old" + "_(" + "ai|nav|path|search|shadow|squad|combat|utility|patrol|pursuit|legacy" + ")"
	return "%s|%s|%s|%s" % [legacyPrefix, temporaryPrefix, debugShadowOverride, oldPrefix]


func _collect_enemy_private_access_matches() -> Array:
	var regex := RegEx.new()
	if regex.compile(_build_enemy_private_access_ban_pattern()) != OK:
		return ["regex_compile_failed"]
	var out: Array = []
	var gd_files := _collect_gd_files("res://tests")
	for path_variant in gd_files:
		var path := String(path_variant)
		if ENEMY_PRIVATE_ACCESS_BAN_IGNORED_PATHS.has(path):
			continue
		var text := _read_text(path)
		if text == "":
			continue
		if regex.search(text) != null:
			out.append(path)
	return out


func _build_enemy_private_access_ban_pattern() -> String:
	return "enemy\\._|enemy\\.set\\(\"_|enemy\\.get\\(\"_|enemy\\.call\\(\"_"


func _collect_gd_files(root: String) -> Array:
	var out: Array = []
	_collect_gd_files_recursive(root, out)
	return out


func _collect_gd_files_recursive(root: String, out: Array) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return

	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry == "":
			break
		if entry.begins_with("."):
			continue

		var child_path := root.path_join(entry)
		if dir.current_is_dir():
			_collect_gd_files_recursive(child_path, out)
		elif entry.ends_with(".gd"):
			out.append(child_path)
	dir.list_dir_end()
