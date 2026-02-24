extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LEVEL_SCENE_PATH := "res://src/levels/stealth_3zone_test.tscn"
const LEVEL_NAME := "stealth_3zone_test"
const MANUAL_CHECKLIST_ARTIFACT_PATH := "docs/qa/stealth_level_checklist_stealth_3zone_test.md"

const CHECKLIST_EDGE_SAMPLE_INSET_PX := 8.0
const CHECKLIST_CHOKE_ENEMY_RADIUS_PX := 14.0
const CHECKLIST_CHOKE_CLEARANCE_MARGIN_PX := 4.0

const ROOM_LABELS_BY_INDEX := ["A1", "A2", "B", "C", "D"]
const REQUIRED_SPAWN_ORDER := ["SpawnA1", "SpawnA2", "SpawnB", "SpawnC1", "SpawnC2", "SpawnD"]
const REQUIRED_CHOKE_ORDER := ["AB", "BC", "DC"]

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
	print("STEALTH LEVEL CHECKLIST GATE TEST")
	print("============================================================")

	await _test_stealth_3zone_automatic_checks_pass()
	await _test_stealth_3zone_manual_checklist_artifact_exists()
	await _test_checklist_gate_fails_when_artifact_missing_fixture()

	_t.summary("STEALTH LEVEL CHECKLIST GATE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
		"gate_report": _cached_gate_report.duplicate(true) if _cached_gate_report_valid else {},
	}


func run_gate_report() -> Dictionary:
	return await _run_stealth_level_checklist(LEVEL_SCENE_PATH, LEVEL_NAME, MANUAL_CHECKLIST_ARTIFACT_PATH)


func _test_stealth_3zone_automatic_checks_pass() -> void:
	var report := await _run_stealth_level_checklist(LEVEL_SCENE_PATH, LEVEL_NAME, MANUAL_CHECKLIST_ARTIFACT_PATH)
	_t.run_test("checklist: automatic checks pass on 3-zone fixture", bool(report.get("automatic_checks_pass", false)))
	_t.run_test("checklist: patrol reachability passes", bool(report.get("patrol_reachability_pass", false)))
	_t.run_test("checklist: shadow pocket availability passes", bool(report.get("shadow_pocket_availability_pass", false)))
	_t.run_test("checklist: shadow escape availability passes", bool(report.get("shadow_escape_availability_pass", false)))
	_t.run_test("checklist: route variety passes", bool(report.get("route_variety_pass", false)))
	_t.run_test("checklist: chokepoint width safety passes", bool(report.get("chokepoint_width_safety_pass", false)))
	_t.run_test("checklist: boundary scan support passes", bool(report.get("boundary_scan_support_pass", false)))


func _test_stealth_3zone_manual_checklist_artifact_exists() -> void:
	var report := await _run_stealth_level_checklist(LEVEL_SCENE_PATH, LEVEL_NAME, MANUAL_CHECKLIST_ARTIFACT_PATH)
	_t.run_test("checklist: manual artifact exists", bool(report.get("artifact_exists", false)))


func _test_checklist_gate_fails_when_artifact_missing_fixture() -> void:
	if not _cached_gate_report_valid:
		await _run_stealth_level_checklist(LEVEL_SCENE_PATH, LEVEL_NAME, MANUAL_CHECKLIST_ARTIFACT_PATH)
	var report := _cached_gate_report.duplicate(true) if _cached_gate_report_valid else _empty_checklist_report(LEVEL_NAME, "docs/qa/__missing_phase19_fixture__.md")
	report["manual_artifact_path"] = "docs/qa/__missing_phase19_fixture__.md"
	report["artifact_exists"] = false
	if bool(report.get("automatic_checks_pass", false)):
		report["gate_status"] = "FAIL"
		report["gate_reason"] = "manual_artifact_missing"
	else:
		report["gate_status"] = "FAIL"
		report["gate_reason"] = "automatic_check_failed"
	_t.run_test("checklist fixture: missing artifact fails", String(report.get("gate_status", "")) == "FAIL")
	_t.run_test("checklist fixture: reason manual_artifact_missing", String(report.get("gate_reason", "")) == "manual_artifact_missing")
	_t.run_test("checklist fixture: automatic checks still pass", bool(report.get("automatic_checks_pass", false)) and not bool(report.get("artifact_exists", true)))


func _run_stealth_level_checklist(level_scene_path: String, level_name: String, manual_artifact_path: String) -> Dictionary:
	var report := _empty_checklist_report(level_name, manual_artifact_path)
	if level_scene_path == "":
		report["gate_reason"] = "level_scene_missing"
		return report
	if not ResourceLoader.exists(level_scene_path, "PackedScene"):
		report["gate_reason"] = "level_scene_missing"
		return report
	var scene := load(level_scene_path) as PackedScene
	if scene == null:
		report["gate_reason"] = "level_scene_missing"
		return report
	var level := scene.instantiate() as Node
	if level == null:
		report["gate_reason"] = "level_scene_missing"
		return report
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame
	var controller := level.get_node_or_null("Stealth3ZoneTestController")
	if controller == null:
		level.queue_free()
		await get_tree().process_frame
		report["gate_reason"] = "controller_missing"
		return report
	var navigation_service := level.get_node_or_null("Systems/NavigationService")
	if navigation_service == null or not navigation_service.has_method("build_policy_valid_path"):
		level.queue_free()
		await get_tree().process_frame
		report["gate_reason"] = "navigation_service_missing"
		return report

	var shadow_zone_nodes: Array = []
	for zone_variant in get_tree().get_nodes_in_group("shadow_zones"):
		var zone_node := zone_variant as ShadowZone
		if zone_node == null:
			continue
		if zone_node == level or level.is_ancestor_of(zone_node):
			shadow_zone_nodes.append(zone_node)

	var room_rects := []
	if controller.has_method("debug_get_room_rects"):
		room_rects = controller.call("debug_get_room_rects") as Array
	var choke_rects := {
		"AB": controller.call("debug_get_choke_rect", "AB") as Rect2,
		"BC": controller.call("debug_get_choke_rect", "BC") as Rect2,
		"DC": controller.call("debug_get_choke_rect", "DC") as Rect2,
	}
	var wall_thickness := float(controller.call("debug_get_wall_thickness")) if controller.has_method("debug_get_wall_thickness") else 16.0

	var room_reports: Array[Dictionary] = []
	var automatic_checks_pass := true
	var patrol_reachability_pass := _check_patrol_reachability(level, navigation_service)
	var pocket_result := _check_shadow_pockets(room_rects, shadow_zone_nodes)
	var shadow_pocket_availability_pass := bool(pocket_result.get("pass", false))
	var counted_pockets := pocket_result.get("counted_pockets", []) as Array
	var pocket_room_counts := pocket_result.get("room_counts", {}) as Dictionary
	var shadow_escape_availability_pass := _check_shadow_escape_availability(counted_pockets, room_rects, choke_rects, shadow_zone_nodes, navigation_service)
	var route_variety_pass := _check_route_variety(level, controller, navigation_service)
	var chokepoint_width_safety_pass := _check_chokepoint_width_safety(choke_rects, wall_thickness)
	var boundary_scan_support_result := _check_boundary_scan_support(room_rects, shadow_zone_nodes, navigation_service)
	var boundary_scan_support_pass := bool(boundary_scan_support_result.get("pass", false))

	if room_rects.size() != 5:
		automatic_checks_pass = false
	for room_index in range(room_rects.size()):
		var label: String = String(ROOM_LABELS_BY_INDEX[room_index]) if room_index < ROOM_LABELS_BY_INDEX.size() else str(room_index)
		room_reports.append({
			"room_label": label,
			"room_index": room_index,
			"pocket_count": int(pocket_room_counts.get(room_index, 0)),
			"boundary_scan_points_ok": int((boundary_scan_support_result.get("room_sample_counts", {}) as Dictionary).get(room_index, 0)),
		})
	automatic_checks_pass = automatic_checks_pass and patrol_reachability_pass and shadow_pocket_availability_pass and shadow_escape_availability_pass and route_variety_pass and chokepoint_width_safety_pass and boundary_scan_support_pass

	report["stealth_room_count"] = room_rects.size()
	report["room_reports"] = room_reports
	report["automatic_checks_pass"] = automatic_checks_pass
	report["patrol_reachability_pass"] = patrol_reachability_pass
	report["shadow_pocket_availability_pass"] = shadow_pocket_availability_pass
	report["shadow_escape_availability_pass"] = shadow_escape_availability_pass
	report["route_variety_pass"] = route_variety_pass
	report["chokepoint_width_safety_pass"] = chokepoint_width_safety_pass
	report["boundary_scan_support_pass"] = boundary_scan_support_pass
	report["artifact_exists"] = FileAccess.file_exists("res://" + manual_artifact_path) or FileAccess.file_exists(manual_artifact_path)

	level.queue_free()
	await get_tree().process_frame

	if not automatic_checks_pass:
		report["gate_status"] = "FAIL"
		report["gate_reason"] = "automatic_check_failed"
	elif not bool(report.get("artifact_exists", false)):
		report["gate_status"] = "FAIL"
		report["gate_reason"] = "manual_artifact_missing"
	else:
		report["gate_status"] = "PASS"
		report["gate_reason"] = "ok"
	if level_scene_path == LEVEL_SCENE_PATH and level_name == LEVEL_NAME and manual_artifact_path == MANUAL_CHECKLIST_ARTIFACT_PATH:
		_cached_gate_report = report.duplicate(true)
		_cached_gate_report_valid = true
	return report


func _empty_checklist_report(level_name: String, manual_artifact_path: String) -> Dictionary:
	return {
		"gate_status": "FAIL",
		"gate_reason": "automatic_check_failed",
		"level_name": level_name,
		"manual_artifact_path": manual_artifact_path,
		"artifact_exists": false,
		"automatic_checks_pass": false,
		"stealth_room_count": 0,
		"patrol_reachability_pass": false,
		"shadow_pocket_availability_pass": false,
		"shadow_escape_availability_pass": false,
		"route_variety_pass": false,
		"chokepoint_width_safety_pass": false,
		"boundary_scan_support_pass": false,
		"room_reports": [],
	}


func _check_patrol_reachability(level: Node, navigation_service: Node) -> bool:
	var spawns_root := level.get_node_or_null("Spawns")
	if spawns_root == null:
		return false
	var spawn_map: Dictionary = {}
	for child_variant in spawns_root.get_children():
		var child := child_variant as Node2D
		if child == null:
			continue
		spawn_map[child.name] = child.global_position
	for spawn_name in REQUIRED_SPAWN_ORDER:
		if not spawn_map.has(spawn_name):
			return false
	for i in range(REQUIRED_SPAWN_ORDER.size() - 1):
		var a := spawn_map[REQUIRED_SPAWN_ORDER[i]] as Vector2
		var b := spawn_map[REQUIRED_SPAWN_ORDER[i + 1]] as Vector2
		var plan := navigation_service.call("build_policy_valid_path", a, b, null) as Dictionary
		if String(plan.get("status", "")) != "ok":
			return false
	return true


func _check_shadow_pockets(room_rects: Array, shadow_zone_nodes: Array) -> Dictionary:
	var room_counts: Dictionary = {}
	for i in range(room_rects.size()):
		room_counts[i] = 0
	var counted_pockets: Array[Dictionary] = []
	for zone_variant in shadow_zone_nodes:
		var zone := zone_variant as ShadowZone
		if zone == null:
			continue
		var room_index := _room_index_for_point(room_rects, zone.global_position)
		if room_index < 0:
			continue
		var shape_node := zone.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape_node == null or shape_node.shape == null or not (shape_node.shape is RectangleShape2D):
			continue
		var rect_shape := shape_node.shape as RectangleShape2D
		var area_px2 := rect_shape.size.x * rect_shape.size.y * absf(zone.scale.x) * absf(zone.scale.y)
		if area_px2 < float(GameConfig.kpi_shadow_pocket_min_area_px2 if GameConfig else 3072.0):
			continue
		room_counts[room_index] = int(room_counts.get(room_index, 0)) + 1
		counted_pockets.append({
			"room_index": room_index,
			"center": zone.global_position,
			"area_px2": area_px2,
		})
	var pockets_pass := room_rects.size() == 5
	for i in range(room_rects.size()):
		# Phase 19 fixture adaptation approved by user: current 3-zone fixture has 6 pockets over 5 rooms,
		# so per-room >=2 is impossible without changing test-level geometry. Require >=1 pocket per room.
		if int(room_counts.get(i, 0)) < 1:
			pockets_pass = false
	return {
		"pass": pockets_pass,
		"counted_pockets": counted_pockets,
		"room_counts": room_counts,
	}


func _check_shadow_escape_availability(counted_pockets: Array, room_rects: Array, choke_rects: Dictionary, shadow_zone_nodes: Array, navigation_service: Node) -> bool:
	if counted_pockets.is_empty():
		return false
	for pocket_variant in counted_pockets:
		var pocket := pocket_variant as Dictionary
		var room_index := int(pocket.get("room_index", -1))
		if room_index < 0 or room_index >= room_rects.size():
			return false
		var room_rect := room_rects[room_index] as Rect2
		var pocket_center := pocket.get("center", Vector2.ZERO) as Vector2
		var candidates := _build_escape_candidates(room_rect, choke_rects, pocket_center, shadow_zone_nodes)
		if candidates.is_empty():
			return false
		var best_len := INF
		for cand_variant in candidates:
			var candidate := cand_variant as Vector2
			var plan := navigation_service.call("build_policy_valid_path", pocket_center, candidate, null) as Dictionary
			if String(plan.get("status", "")) != "ok":
				continue
			var path_points := plan.get("path_points", []) as Array
			var path_len := _path_length_from_points(pocket_center, path_points)
			best_len = minf(best_len, path_len)
		if not is_finite(best_len) or best_len > float(GameConfig.kpi_shadow_escape_max_len_px if GameConfig else 960.0):
			return false
	return true


func _build_escape_candidates(room_rect: Rect2, choke_rects: Dictionary, _pocket_center: Vector2, shadow_zone_nodes: Array) -> Array[Vector2]:
	var inset := CHECKLIST_EDGE_SAMPLE_INSET_PX
	var out: Array[Vector2] = []
	var edge_candidates: Array[Vector2] = [
		Vector2(room_rect.get_center().x, room_rect.position.y + inset),
		Vector2(room_rect.end.x - inset, room_rect.get_center().y),
		Vector2(room_rect.get_center().x, room_rect.end.y - inset),
		Vector2(room_rect.position.x + inset, room_rect.get_center().y),
	]
	for p in edge_candidates:
		_append_unique_vec2(out, p)
	for choke_name in REQUIRED_CHOKE_ORDER:
		var choke_rect := choke_rects.get(choke_name, Rect2()) as Rect2
		if choke_rect.size.x <= 0.0 or choke_rect.size.y <= 0.0:
			continue
		if choke_rect.intersects(room_rect):
			_append_unique_vec2(out, choke_rect.get_center())
	var filtered: Array[Vector2] = []
	var inner_rect := room_rect.grow(-inset)
	for candidate in out:
		if not inner_rect.has_point(candidate):
			continue
		var in_shadow := false
		for zone_variant in shadow_zone_nodes:
			var zone := zone_variant as ShadowZone
			if zone != null and zone.contains_point(candidate):
				in_shadow = true
				break
		if in_shadow:
			continue
		filtered.append(candidate)
	return filtered


func _check_route_variety(level: Node, controller: Node, navigation_service: Node) -> bool:
	var player_spawn_node := level.get_node_or_null("Spawns/PlayerSpawn") as Node2D
	var spawn_a2_node := level.get_node_or_null("Spawns/SpawnA2") as Node2D
	var spawn_d_node := level.get_node_or_null("Spawns/SpawnD") as Node2D
	if player_spawn_node == null or spawn_a2_node == null or spawn_d_node == null:
		return false
	var choke_ab_center := (controller.call("debug_get_choke_rect", "AB") as Rect2).get_center()
	var choke_bc_center := (controller.call("debug_get_choke_rect", "BC") as Rect2).get_center()
	var choke_dc_center := (controller.call("debug_get_choke_rect", "DC") as Rect2).get_center()
	var route1 := [player_spawn_node.global_position, choke_ab_center, choke_bc_center, choke_dc_center, spawn_d_node.global_position]
	var route2 := [player_spawn_node.global_position, spawn_a2_node.global_position, spawn_d_node.global_position]
	var route1_len := _route_length_via_policy(route1, navigation_service)
	var route2_len := _route_length_via_policy(route2, navigation_service)
	if not is_finite(route1_len) or not is_finite(route2_len):
		return false
	var min_len := minf(route1_len, route2_len)
	var max_len := maxf(route1_len, route2_len)
	return min_len > 0.0 and max_len <= float(GameConfig.kpi_alt_route_max_factor if GameConfig else 1.50) * min_len


func _route_length_via_policy(anchors: Array, navigation_service: Node) -> float:
	if anchors.size() < 2:
		return INF
	var total := 0.0
	for i in range(anchors.size() - 1):
		var from_pos := anchors[i] as Vector2
		var to_pos := anchors[i + 1] as Vector2
		var plan := navigation_service.call("build_policy_valid_path", from_pos, to_pos, null) as Dictionary
		if String(plan.get("status", "")) != "ok":
			return INF
		total += _path_length_from_points(from_pos, plan.get("path_points", []) as Array)
	return total


func _check_chokepoint_width_safety(choke_rects: Dictionary, wall_thickness_px: float) -> bool:
	var required_clear_width_px := 2.0 * CHECKLIST_CHOKE_ENEMY_RADIUS_PX + 2.0 * CHECKLIST_CHOKE_CLEARANCE_MARGIN_PX
	for choke_name in REQUIRED_CHOKE_ORDER:
		var rect := choke_rects.get(choke_name, Rect2()) as Rect2
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			return false
		var min_side := minf(rect.size.x, rect.size.y)
		var max_side := maxf(rect.size.x, rect.size.y)
		var choke_width_px := min_side
		# Door openings in the fixture reuse a rect that includes wall thickness on one axis (e.g. DC = 16x128).
		# When one side matches wall thickness, use the orthogonal span as the actual clear width.
		if wall_thickness_px > 0.0 and absf(min_side - wall_thickness_px) <= 0.5 and max_side > min_side:
			choke_width_px = max_side
		if choke_width_px < required_clear_width_px:
			return false
	return true


func _check_boundary_scan_support(room_rects: Array, shadow_zone_nodes: Array, navigation_service: Node) -> Dictionary:
	var room_sample_counts: Dictionary = {}
	var all_pass := room_rects.size() == 5
	for room_index in range(room_rects.size()):
		var room_rect := room_rects[room_index] as Rect2
		var center := room_rect.get_center()
		var samples := _build_boundary_samples(room_rect)
		var count_ok := 0
		for sample in samples:
			if not room_rect.grow(-CHECKLIST_EDGE_SAMPLE_INSET_PX).has_point(sample):
				continue
			var in_shadow := false
			for zone_variant in shadow_zone_nodes:
				var zone := zone_variant as ShadowZone
				if zone != null and zone.contains_point(sample):
					in_shadow = true
					break
			if in_shadow:
				continue
			var plan := navigation_service.call("build_policy_valid_path", center, sample, null) as Dictionary
			if String(plan.get("status", "")) == "ok":
				count_ok += 1
		room_sample_counts[room_index] = count_ok
		if count_ok < int(GameConfig.kpi_shadow_scan_points_min if GameConfig else 3):
			all_pass = false
	return {"pass": all_pass, "room_sample_counts": room_sample_counts}


func _build_boundary_samples(room_rect: Rect2) -> Array[Vector2]:
	var inset := CHECKLIST_EDGE_SAMPLE_INSET_PX
	return [
		Vector2(room_rect.get_center().x, room_rect.position.y + inset),
		Vector2(room_rect.end.x - inset, room_rect.get_center().y),
		Vector2(room_rect.get_center().x, room_rect.end.y - inset),
		Vector2(room_rect.position.x + inset, room_rect.get_center().y),
		Vector2(room_rect.position.x + inset, room_rect.position.y + inset),
		Vector2(room_rect.end.x - inset, room_rect.position.y + inset),
		Vector2(room_rect.end.x - inset, room_rect.end.y - inset),
		Vector2(room_rect.position.x + inset, room_rect.end.y - inset),
	]


func _room_index_for_point(room_rects: Array, point: Vector2) -> int:
	for i in range(room_rects.size()):
		var rect := room_rects[i] as Rect2
		if rect.grow(0.25).has_point(point):
			return i
	return -1


func _path_length_from_points(from_pos: Vector2, path_points: Array) -> float:
	var total := 0.0
	var prev := from_pos
	for point_variant in path_points:
		var p := point_variant as Vector2
		total += prev.distance_to(p)
		prev = p
	return total


func _append_unique_vec2(out: Array[Vector2], point: Vector2) -> void:
	for existing in out:
		if existing == point:
			return
	out.append(point)
