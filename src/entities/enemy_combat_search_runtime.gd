## enemy_combat_search_runtime.gd
## Phase 3 owner for combat-search domain.
class_name EnemyCombatSearchRuntime
extends RefCounted

const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")

const COMBAT_SEARCH_ROOM_BUDGET_MIN_SEC := 4.0
const COMBAT_SEARCH_ROOM_BUDGET_MAX_SEC := 8.0
const COMBAT_SEARCH_TOTAL_CAP_SEC := 24.0
const COMBAT_SEARCH_UNVISITED_PENALTY := 220.0
const COMBAT_SEARCH_DOOR_COST_PER_HOP := 80.0
const COMBAT_SEARCH_PROGRESS_THRESHOLD := 0.8
const COMBAT_DARK_SEARCH_NODE_SAMPLE_OFFSETS := [Vector2.ZERO, Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
const COMBAT_DARK_SEARCH_NODE_DEDUP_PX := 12.0
const COMBAT_DARK_SEARCH_POCKET_COVERAGE_WEIGHT := 1.0
const COMBAT_DARK_SEARCH_BOUNDARY_COVERAGE_WEIGHT := 0.5

var _owner: Node = null


func _init(owner: Node = null) -> void:
	_owner = owner


func bind(owner: Node) -> void:
	_owner = owner


func get_owner() -> Node:
	return _owner


func has_owner() -> bool:
	return _owner != null


func get_state_value(key: String, default_value: Variant = null) -> Variant:
	if _owner == null:
		return default_value
	var value: Variant = _owner.get(key)
	return default_value if value == null else value


func set_state_value(key: String, value: Variant) -> void:
	if _owner == null:
		return
	_owner.set(key, value)


func set_state_patch(values: Dictionary) -> void:
	if _owner == null:
		return
	for key_variant in values.keys():
		var key := String(key_variant)
		_owner.set(key, values[key_variant])


func record_execution_feedback(intent: Dictionary, delta: float) -> void:
	if _owner == null:
		return
	_owner.set(
		"_combat_search_feedback_intent_type",
		int(intent.get("type", ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL))
	)
	_owner.set("_combat_search_feedback_intent_target", intent.get("target", Vector2.ZERO) as Vector2)
	_owner.set("_combat_search_feedback_delta", maxf(delta, 0.0))


func apply_repath_recovery_feedback(intent: Dictionary, exec_result: Dictionary) -> void:
	if _owner == null:
		return
	_owner.set("_combat_search_recovery_applied_last_tick", false)
	_owner.set("_combat_search_recovery_reason_last_tick", "none")
	_owner.set("_combat_search_recovery_blocked_point_last", Vector2.ZERO)
	_owner.set("_combat_search_recovery_blocked_point_valid_last", false)
	_owner.set("_combat_search_recovery_skipped_node_key_last", "")

	var required_keys := [
		"repath_recovery_request_next_search_node",
		"repath_recovery_reason",
		"repath_recovery_blocked_point",
		"repath_recovery_blocked_point_valid",
		"repath_recovery_repeat_count",
		"repath_recovery_preserve_intent",
		"repath_recovery_intent_target",
	]
	for key_variant in required_keys:
		var key := String(key_variant)
		if not exec_result.has(key):
			return

	var request_next := bool(exec_result.get("repath_recovery_request_next_search_node", false))
	var preserve_intent := bool(exec_result.get("repath_recovery_preserve_intent", false))
	if not request_next or not preserve_intent:
		return

	var current_room_id := int(_owner.get("_combat_search_current_room_id"))
	if current_room_id < 0:
		return
	var current_node_key := String(_owner.get("_combat_search_current_node_key"))
	if current_node_key == "":
		return

	var intent_type := int(intent.get("type", -1))
	if (
		intent_type != ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH
		and intent_type != ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SHADOW_BOUNDARY_SCAN
	):
		return

	var intent_target_variant: Variant = exec_result.get("repath_recovery_intent_target", Vector2.ZERO)
	if not (intent_target_variant is Vector2):
		return
	var intent_target := intent_target_variant as Vector2
	if not is_finite(intent_target.x) or not is_finite(intent_target.y):
		return

	var target_pos := _owner.get("_combat_search_target_pos") as Vector2
	var target_match_radius := maxf(_pursuit_cfg_float("repath_recovery_intent_target_match_radius_px", 28.0), 0.0)
	if intent_target.distance_to(target_pos) > target_match_radius:
		return

	var blocked_point_valid := bool(exec_result.get("repath_recovery_blocked_point_valid", false))
	var blocked_point := exec_result.get("repath_recovery_blocked_point", Vector2.ZERO) as Vector2
	if blocked_point_valid and (not is_finite(blocked_point.x) or not is_finite(blocked_point.y)):
		return

	var skipped_key := current_node_key
	mark_current_node_covered()
	clear_current_node()

	var select_result := select_next_dark_search_node(current_room_id, target_pos)
	var select_status := String(select_result.get("status", "room_invalid"))
	if select_status == "ok":
		apply_node_pick(select_result)
	elif select_status == "no_nodes" or select_status == "all_blocked":
		var visited_rooms := _owner.get("_combat_search_visited_rooms") as Dictionary
		visited_rooms[current_room_id] = true
		_owner.set("_combat_search_visited_rooms", visited_rooms)
		var next_room := select_next_room(current_room_id, target_pos)
		ensure_room(next_room, target_pos)

	update_progress()
	_owner.set("_combat_search_recovery_applied_last_tick", true)
	_owner.set("_combat_search_recovery_reason_last_tick", String(exec_result.get("repath_recovery_reason", "none")))
	_owner.set("_combat_search_recovery_blocked_point_last", blocked_point if blocked_point_valid else Vector2.ZERO)
	_owner.set("_combat_search_recovery_blocked_point_valid_last", blocked_point_valid)
	_owner.set("_combat_search_recovery_skipped_node_key_last", skipped_key)


func current_pursuit_shadow_search_stage() -> int:
	if _owner == null:
		return -1
	var pursuit: Variant = _owner.get("_pursuit")
	if pursuit == null:
		return -1
	if not pursuit.has_method("get_shadow_search_stage"):
		return -1
	return int(pursuit.get_shadow_search_stage())


func clear_current_node(reset_shadow_scan_suppressed: bool = true) -> void:
	if _owner == null:
		return
	_owner.set("_combat_search_current_node_key", "")
	_owner.set("_combat_search_current_node_kind", "")
	_owner.set("_combat_search_current_node_requires_shadow_scan", false)
	_owner.set("_combat_search_current_node_shadow_scan_done", false)
	_owner.set("_combat_search_node_search_dwell_sec", 0.0)
	if reset_shadow_scan_suppressed:
		_owner.set("_combat_search_shadow_scan_suppressed_last_tick", false)


func apply_node_pick(pick: Dictionary) -> void:
	if _owner == null:
		return
	_owner.set("_combat_search_current_node_key", String(pick.get("node_key", "")))
	_owner.set("_combat_search_current_node_kind", String(pick.get("node_kind", "")))
	_owner.set("_combat_search_target_pos", pick.get("target_pos", Vector2.ZERO) as Vector2)
	_owner.set("_combat_search_current_node_requires_shadow_scan", bool(pick.get("requires_shadow_boundary_scan", false)))
	_owner.set("_combat_search_current_node_shadow_scan_done", false)
	_owner.set("_combat_search_node_search_dwell_sec", 0.0)
	_owner.set("_combat_search_shadow_scan_suppressed_last_tick", false)


func reset_state() -> void:
	if _owner == null:
		return
	_owner.set("_combat_search_total_elapsed_sec", 0.0)
	_owner.set("_combat_search_room_elapsed_sec", 0.0)
	_owner.set("_combat_search_room_budget_sec", 0.0)
	_owner.set("_combat_search_current_room_id", -1)
	_owner.set("_combat_search_target_pos", Vector2.ZERO)
	(_owner.get("_combat_search_room_nodes") as Dictionary).clear()
	(_owner.get("_combat_search_room_node_visited") as Dictionary).clear()
	clear_current_node()
	_owner.set("_combat_search_last_pursuit_shadow_stage", -1)
	_owner.set("_combat_search_feedback_intent_type", -1)
	_owner.set("_combat_search_feedback_intent_target", Vector2.ZERO)
	_owner.set("_combat_search_feedback_delta", 0.0)
	_owner.set("_combat_search_shadow_scan_suppressed_last_tick", false)
	_owner.set("_combat_search_recovery_applied_last_tick", false)
	_owner.set("_combat_search_recovery_reason_last_tick", "none")
	_owner.set("_combat_search_recovery_blocked_point_last", Vector2.ZERO)
	_owner.set("_combat_search_recovery_blocked_point_valid_last", false)
	_owner.set("_combat_search_recovery_skipped_node_key_last", "")
	(_owner.get("_combat_search_room_coverage") as Dictionary).clear()
	(_owner.get("_combat_search_visited_rooms") as Dictionary).clear()
	_owner.set("_combat_search_progress", 0.0)
	_owner.set("_combat_search_total_cap_hit", false)


func update_runtime(
	delta: float,
	has_valid_contact: bool,
	combat_target_pos: Vector2,
	was_combat_before_confirm: bool
) -> void:
	if _owner == null:
		return
	if not was_combat_before_confirm:
		reset_state()
		return
	if has_valid_contact:
		return

	if int(_owner.get("_combat_search_current_room_id")) < 0:
		var start_room := _resolve_room_id_for_events()
		ensure_room(start_room, combat_target_pos)

	var clamped_delta := maxf(delta, 0.0)
	var total_elapsed := float(_owner.get("_combat_search_total_elapsed_sec")) + clamped_delta
	var room_elapsed := float(_owner.get("_combat_search_room_elapsed_sec")) + clamped_delta
	_owner.set("_combat_search_total_elapsed_sec", total_elapsed)
	_owner.set("_combat_search_room_elapsed_sec", room_elapsed)
	if total_elapsed >= COMBAT_SEARCH_TOTAL_CAP_SEC:
		_owner.set("_combat_search_total_cap_hit", true)

	var stage_now := current_pursuit_shadow_search_stage()
	var current_node_key := String(_owner.get("_combat_search_current_node_key"))
	var current_node_requires_scan := bool(_owner.get("_combat_search_current_node_requires_shadow_scan"))
	var current_node_scan_done := bool(_owner.get("_combat_search_current_node_shadow_scan_done"))
	var last_stage := int(_owner.get("_combat_search_last_pursuit_shadow_stage"))
	if current_node_requires_scan and not current_node_scan_done and current_node_key != "":
		if last_stage >= 0 and last_stage != 0 and stage_now == 0:
			_owner.set("_combat_search_current_node_shadow_scan_done", true)
			_owner.set("_combat_search_node_search_dwell_sec", 0.0)
	_owner.set("_combat_search_last_pursuit_shadow_stage", stage_now)

	var can_accumulate_dwell := (
		current_node_key != ""
		and int(_owner.get("_combat_search_feedback_intent_type")) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH
		and (_owner.get("_combat_search_feedback_intent_target") as Vector2).distance_to(_owner.get("_combat_search_target_pos") as Vector2) <= 0.5
		and (not current_node_requires_scan or bool(_owner.get("_combat_search_current_node_shadow_scan_done")))
	)
	if can_accumulate_dwell:
		_owner.set(
			"_combat_search_node_search_dwell_sec",
			float(_owner.get("_combat_search_node_search_dwell_sec")) + float(_owner.get("_combat_search_feedback_delta"))
		)
	else:
		_owner.set("_combat_search_node_search_dwell_sec", 0.0)

	if (
		String(_owner.get("_combat_search_current_node_key")) != ""
		and float(_owner.get("_combat_search_node_search_dwell_sec")) >= _pursuit_cfg_float("combat_dark_search_node_dwell_sec", 1.25)
	):
		mark_current_node_covered()
		_owner.set("_shadow_scan_completed", false)
		_owner.set("_shadow_scan_completed_reason", "none")
		clear_current_node()

	var current_room := int(_owner.get("_combat_search_current_room_id"))
	var current_coverage := compute_room_coverage(current_room)
	if current_room >= 0:
		var room_coverage := _owner.get("_combat_search_room_coverage") as Dictionary
		room_coverage[current_room] = current_coverage
		_owner.set("_combat_search_room_coverage", room_coverage)
	var room_done_by_coverage := current_coverage >= COMBAT_SEARCH_PROGRESS_THRESHOLD
	var room_done_by_timeout := float(_owner.get("_combat_search_room_elapsed_sec")) >= float(_owner.get("_combat_search_room_budget_sec"))
	if current_room >= 0 and (room_done_by_coverage or room_done_by_timeout):
		var visited_rooms := _owner.get("_combat_search_visited_rooms") as Dictionary
		visited_rooms[current_room] = true
		_owner.set("_combat_search_visited_rooms", visited_rooms)
		var next_room := select_next_room(current_room, combat_target_pos)
		ensure_room(next_room, combat_target_pos)

	current_room = int(_owner.get("_combat_search_current_room_id"))
	if String(_owner.get("_combat_search_current_node_key")) == "" and current_room >= 0:
		var pick := select_next_dark_search_node(current_room, combat_target_pos)
		var pick_status := String(pick.get("status", "room_invalid"))
		if pick_status == "ok":
			apply_node_pick(pick)
		elif pick_status == "no_nodes" or pick_status == "all_blocked":
			var visited_rooms := _owner.get("_combat_search_visited_rooms") as Dictionary
			visited_rooms[current_room] = true
			_owner.set("_combat_search_visited_rooms", visited_rooms)
			var next_room_after_empty := select_next_room(current_room, combat_target_pos)
			ensure_room(next_room_after_empty, combat_target_pos)

	update_progress()


func ensure_room(room_id: int, combat_target_pos: Vector2) -> void:
	if _owner == null:
		return
	var valid_room := room_id
	if valid_room < 0:
		valid_room = _resolve_room_id_for_events()
	if valid_room < 0:
		return

	_owner.set("_combat_search_current_room_id", valid_room)
	_owner.set("_combat_search_room_elapsed_sec", 0.0)
	_owner.set("_combat_search_room_budget_sec", _roll_room_budget())
	var room_nodes := _owner.get("_combat_search_room_nodes") as Dictionary
	room_nodes[valid_room] = build_dark_search_nodes(valid_room, combat_target_pos)
	_owner.set("_combat_search_room_nodes", room_nodes)

	if not (_owner.get("_combat_search_room_node_visited") as Dictionary).has(valid_room):
		var room_visited := _owner.get("_combat_search_room_node_visited") as Dictionary
		room_visited[valid_room] = {}
		_owner.set("_combat_search_room_node_visited", room_visited)

	clear_current_node()
	var first_pick := select_next_dark_search_node(valid_room, combat_target_pos)
	if String(first_pick.get("status", "room_invalid")) == "ok":
		apply_node_pick(first_pick)
	else:
		_owner.set("_combat_search_target_pos", _owner_global_position())

	var room_coverage := _owner.get("_combat_search_room_coverage") as Dictionary
	room_coverage[valid_room] = compute_room_coverage(valid_room)
	_owner.set("_combat_search_room_coverage", room_coverage)


func build_dark_search_nodes(room_id: int, combat_target_pos: Vector2) -> Array[Dictionary]:
	var _unused_target := combat_target_pos
	var nodes: Array[Dictionary] = []
	var room_center := _owner_global_position()
	var nav := _nav_system()
	if nav and nav.has_method("get_room_center"):
		var center := nav.get_room_center(room_id) as Vector2
		if center != Vector2.ZERO:
			room_center = center
	var room_rect := Rect2()
	if nav and nav.has_method("get_room_rect"):
		room_rect = nav.get_room_rect(room_id) as Rect2

	var sample_radius := _pursuit_cfg_float("combat_dark_search_node_sample_radius_px", 64.0)
	var boundary_radius := _pursuit_cfg_float("combat_dark_search_boundary_radius_px", 96.0)
	var sample_index := 0
	for offset_variant in COMBAT_DARK_SEARCH_NODE_SAMPLE_OFFSETS:
		var offset := offset_variant as Vector2
		var sample := room_center if offset == Vector2.ZERO else room_center + offset * sample_radius
		if room_rect.size.x > 0.0 and room_rect.size.y > 0.0:
			var clamp_rect := room_rect.grow(-4.0)
			if clamp_rect.size.x <= 0.0 or clamp_rect.size.y <= 0.0:
				clamp_rect = room_rect
			sample.x = clampf(sample.x, clamp_rect.position.x, clamp_rect.position.x + clamp_rect.size.x)
			sample.y = clampf(sample.y, clamp_rect.position.y, clamp_rect.position.y + clamp_rect.size.y)

		var sample_in_shadow := false
		if nav and nav.has_method("is_point_in_shadow"):
			sample_in_shadow = bool(nav.call("is_point_in_shadow", sample))

		var boundary_candidate := {
			"key": "r%d:boundary:%d" % [room_id, sample_index],
			"kind": "boundary_point",
			"target_pos": sample,
			"approach_pos": sample,
			"target_in_shadow": sample_in_shadow,
			"requires_shadow_boundary_scan": false,
			"coverage_weight": COMBAT_DARK_SEARCH_BOUNDARY_COVERAGE_WEIGHT,
		}
		var boundary_drop := false
		for existing_variant in nodes:
			var existing := existing_variant as Dictionary
			if String(existing.get("kind", "")) != "boundary_point":
				continue
			var existing_target := existing.get("target_pos", Vector2.ZERO) as Vector2
			if existing_target.distance_to(sample) <= COMBAT_DARK_SEARCH_NODE_DEDUP_PX:
				boundary_drop = true
				break
		if not boundary_drop:
			nodes.append(boundary_candidate)

		if sample_in_shadow and nav and nav.has_method("get_nearest_non_shadow_point"):
			var boundary := nav.get_nearest_non_shadow_point(sample, boundary_radius) as Vector2
			if boundary != Vector2.ZERO:
				var dark_candidate := {
					"key": "r%d:dark:%d" % [room_id, sample_index],
					"kind": "dark_pocket",
					"target_pos": sample,
					"approach_pos": boundary,
					"target_in_shadow": true,
					"requires_shadow_boundary_scan": true,
					"coverage_weight": COMBAT_DARK_SEARCH_POCKET_COVERAGE_WEIGHT,
				}
				var dark_drop := false
				for existing_variant in nodes:
					var existing := existing_variant as Dictionary
					if String(existing.get("kind", "")) != "dark_pocket":
						continue
					var existing_target := existing.get("target_pos", Vector2.ZERO) as Vector2
					if existing_target.distance_to(sample) <= COMBAT_DARK_SEARCH_NODE_DEDUP_PX:
						dark_drop = true
						break
				if not dark_drop:
					nodes.append(dark_candidate)
		sample_index += 1

	if nodes.is_empty():
		var fallback_in_shadow := false
		if nav and nav.has_method("is_point_in_shadow"):
			fallback_in_shadow = bool(nav.call("is_point_in_shadow", room_center))
		nodes.append({
			"key": "r%d:boundary:fallback" % room_id,
			"kind": "boundary_point",
			"target_pos": room_center,
			"approach_pos": room_center,
			"target_in_shadow": fallback_in_shadow,
			"requires_shadow_boundary_scan": false,
			"coverage_weight": 1.0,
		})
	return nodes


func select_next_dark_search_node(room_id: int, combat_target_pos: Vector2) -> Dictionary:
	var invalid_out := {
		"status": "room_invalid",
		"reason": "room_invalid",
		"room_id": room_id,
		"node_key": "",
		"node_kind": "",
		"target_pos": Vector2.ZERO,
		"approach_pos": Vector2.ZERO,
		"target_in_shadow": false,
		"requires_shadow_boundary_scan": false,
		"score_uncovered": 0.0,
		"score_path_len_px": INF,
		"score_tactical_priority": -1,
		"score_total": INF,
	}
	if room_id < 0 or not is_finite(combat_target_pos.x) or not is_finite(combat_target_pos.y):
		return invalid_out

	var node_list_variant: Variant = (_owner.get("_combat_search_room_nodes") as Dictionary).get(room_id, [])
	var node_list := node_list_variant as Array
	if node_list.is_empty():
		var no_nodes_out := invalid_out.duplicate(true)
		no_nodes_out["status"] = "no_nodes"
		no_nodes_out["reason"] = "node_list_empty"
		return no_nodes_out

	var visited := ((_owner.get("_combat_search_room_node_visited") as Dictionary).get(room_id, {}) as Dictionary)
	var best_found := false
	var best_score_total := INF
	var best_score_path := INF
	var best_score_tactical := 999999
	var best_key := ""
	var best_node: Dictionary = {}
	var best_score_uncovered := 0.0

	var uncovered_bonus := _pursuit_cfg_float("combat_dark_search_node_uncovered_bonus", 1000.0)
	var tactical_priority_weight := _pursuit_cfg_float("combat_dark_search_node_tactical_priority_weight", 80.0)
	var nav := _nav_system()
	var owner_pos := _owner_global_position()
	for node_variant in node_list:
		var node := node_variant as Dictionary
		var node_key := String(node.get("key", ""))
		if node_key == "":
			continue
		if bool(visited.get(node_key, false)):
			continue

		var approach_pos := node.get("approach_pos", Vector2.ZERO) as Vector2
		if not is_finite(approach_pos.x) or not is_finite(approach_pos.y):
			continue
		var path_len := INF
		if nav and nav.has_method("nav_path_length"):
			path_len = float(nav.call("nav_path_length", owner_pos, approach_pos, _owner))
		else:
			path_len = owner_pos.distance_to(approach_pos)
		if not is_finite(path_len):
			continue

		var score_uncovered := float(node.get("coverage_weight", 0.0))
		if not is_finite(score_uncovered):
			continue
		var node_kind := String(node.get("kind", "boundary_point"))
		var score_tactical_priority := 0 if node_kind == "dark_pocket" else 1
		var score_total := (
			(uncovered_bonus - score_uncovered * uncovered_bonus)
			+ path_len
			+ float(score_tactical_priority) * tactical_priority_weight
		)

		var better := false
		if not best_found:
			better = true
		elif score_total < best_score_total:
			better = true
		elif is_equal_approx(score_total, best_score_total) and path_len < best_score_path:
			better = true
		elif is_equal_approx(score_total, best_score_total) and is_equal_approx(path_len, best_score_path) and score_tactical_priority < best_score_tactical:
			better = true
		elif (
			is_equal_approx(score_total, best_score_total)
			and is_equal_approx(path_len, best_score_path)
			and score_tactical_priority == best_score_tactical
			and (best_key == "" or node_key < best_key)
		):
			better = true

		if better:
			best_found = true
			best_score_total = score_total
			best_score_path = path_len
			best_score_tactical = score_tactical_priority
			best_key = node_key
			best_node = node.duplicate(true)
			best_score_uncovered = score_uncovered

	if not best_found:
		var blocked_out := invalid_out.duplicate(true)
		blocked_out["status"] = "all_blocked"
		blocked_out["reason"] = "all_candidates_blocked"
		return blocked_out

	var selected_kind := String(best_node.get("kind", ""))
	var out := {
		"status": "ok",
		"reason": "selected_dark_pocket" if selected_kind == "dark_pocket" else "selected_boundary_point",
		"room_id": room_id,
		"node_key": String(best_node.get("key", "")),
		"node_kind": selected_kind,
		"target_pos": best_node.get("target_pos", Vector2.ZERO) as Vector2,
		"approach_pos": best_node.get("approach_pos", Vector2.ZERO) as Vector2,
		"target_in_shadow": bool(best_node.get("target_in_shadow", false)),
		"requires_shadow_boundary_scan": bool(best_node.get("requires_shadow_boundary_scan", false)),
		"score_uncovered": best_score_uncovered,
		"score_path_len_px": best_score_path,
		"score_tactical_priority": best_score_tactical,
		"score_total": best_score_total,
	}
	return out


func compute_room_coverage(room_id: int) -> float:
	if _owner == null:
		return 0.0
	if room_id < 0:
		return 0.0
	var node_list_variant: Variant = (_owner.get("_combat_search_room_nodes") as Dictionary).get(room_id, [])
	var node_list := node_list_variant as Array
	if node_list.is_empty():
		return 0.0
	var visited := ((_owner.get("_combat_search_room_node_visited") as Dictionary).get(room_id, {}) as Dictionary)
	var total_weight := 0.0
	var covered_weight := 0.0
	for node_variant in node_list:
		var node := node_variant as Dictionary
		var node_key := String(node.get("key", ""))
		var weight := float(node.get("coverage_weight", 0.0))
		if node_key == "" or not is_finite(weight) or weight <= 0.0:
			continue
		total_weight += weight
		if bool(visited.get(node_key, false)):
			covered_weight += weight
	if total_weight <= 0.0:
		return 0.0
	return clampf(covered_weight / total_weight, 0.0, 1.0)


func mark_current_node_covered() -> void:
	if _owner == null:
		return
	var current_room := int(_owner.get("_combat_search_current_room_id"))
	if current_room < 0:
		return
	var current_key := String(_owner.get("_combat_search_current_node_key"))
	if current_key == "":
		return
	var room_visited := _owner.get("_combat_search_room_node_visited") as Dictionary
	if not room_visited.has(current_room):
		room_visited[current_room] = {}
	var visited := room_visited[current_room] as Dictionary
	visited[current_key] = true
	room_visited[current_room] = visited
	_owner.set("_combat_search_room_node_visited", room_visited)
	var room_coverage := _owner.get("_combat_search_room_coverage") as Dictionary
	room_coverage[current_room] = compute_room_coverage(current_room)
	_owner.set("_combat_search_room_coverage", room_coverage)


func update_progress() -> void:
	if _owner == null:
		return
	var current_room := int(_owner.get("_combat_search_current_room_id"))
	if current_room < 0:
		_owner.set("_combat_search_progress", 0.0)
		return
	var room_coverage := _owner.get("_combat_search_room_coverage") as Dictionary
	var current_coverage := clampf(float(room_coverage.get(current_room, 0.0)), 0.0, 1.0)
	var neighbor_max := 0.0
	var nav := _nav_system()
	var neighbors: Array = nav.get_neighbors(current_room) if nav and nav.has_method("get_neighbors") else []
	for rid_variant in neighbors:
		var rid := int(rid_variant)
		neighbor_max = maxf(neighbor_max, clampf(float(room_coverage.get(rid, 0.0)), 0.0, 1.0))
	if bool(_owner.get("_combat_search_total_cap_hit")):
		_owner.set("_combat_search_progress", COMBAT_SEARCH_PROGRESS_THRESHOLD)
		return
	if current_coverage >= COMBAT_SEARCH_PROGRESS_THRESHOLD and neighbor_max >= COMBAT_SEARCH_PROGRESS_THRESHOLD:
		_owner.set(
			"_combat_search_progress",
			maxf(COMBAT_SEARCH_PROGRESS_THRESHOLD, clampf((current_coverage + neighbor_max) * 0.5, 0.0, 1.0))
		)
		return
	_owner.set("_combat_search_progress", minf(current_coverage, COMBAT_SEARCH_PROGRESS_THRESHOLD - 0.01))


func select_next_room(current_room: int, combat_target_pos: Vector2) -> int:
	if _owner == null:
		return -1
	if current_room < 0:
		return _resolve_room_id_for_events()
	var nav := _nav_system()
	if not nav or not nav.has_method("get_neighbors"):
		return current_room
	var neighbors := nav.get_neighbors(current_room) as Array
	if neighbors.is_empty():
		return current_room
	var best_room := current_room
	var best_score := INF
	for rid_variant in neighbors:
		var room_id := int(rid_variant)
		if room_id < 0:
			continue
		var room_center := combat_target_pos
		if nav.has_method("get_room_center"):
			room_center = nav.get_room_center(room_id) as Vector2
		var dist_to_target := room_center.distance_to(combat_target_pos)
		var visited_rooms := _owner.get("_combat_search_visited_rooms") as Dictionary
		var unvisited_penalty := 0.0 if not visited_rooms.has(room_id) else COMBAT_SEARCH_UNVISITED_PENALTY
		var door_hops := door_hops_between(current_room, room_id)
		var door_cost := COMBAT_SEARCH_DOOR_COST_PER_HOP * float(door_hops)
		var score := dist_to_target + unvisited_penalty + door_cost
		if score < best_score or (is_equal_approx(score, best_score) and room_id < best_room):
			best_score = score
			best_room = room_id
	return best_room


func door_hops_between(from_room: int, to_room: int) -> int:
	if from_room < 0 or to_room < 0:
		return 999
	if from_room == to_room:
		return 0
	var nav := _nav_system()
	if not nav or not nav.has_method("get_neighbors"):
		return 999
	var visited: Dictionary = {from_room: true}
	var frontier: Array[int] = [from_room]
	var hops := 0
	while not frontier.is_empty() and hops < 64:
		hops += 1
		var next_frontier: Array[int] = []
		for room_id in frontier:
			var neighbors := nav.get_neighbors(room_id) as Array
			for neighbor_variant in neighbors:
				var neighbor := int(neighbor_variant)
				if visited.has(neighbor):
					continue
				if neighbor == to_room:
					return hops
				visited[neighbor] = true
				next_frontier.append(neighbor)
		frontier = next_frontier
	return 999


func should_keep_shadow_scan_handoff_for_dark_node_dwell(intent: Dictionary) -> bool:
	if _owner == null:
		return false
	return (
		String(_owner.get("_combat_search_current_node_key")) != ""
		and bool(_owner.get("_combat_search_current_node_requires_shadow_scan"))
		and bool(_owner.get("_combat_search_current_node_shadow_scan_done"))
		and int(intent.get("type", -1)) == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH
		and ((intent.get("target", Vector2.ZERO) as Vector2).distance_to(_owner.get("_combat_search_target_pos") as Vector2) <= 0.5)
	)


func compute_shadow_scan_suppressed_for_context(
	has_known_target: bool,
	known_target_pos: Vector2,
	has_shadow_scan_target: bool,
	shadow_scan_target: Vector2
) -> bool:
	if _owner == null:
		return false
	var search_target := _owner.get("_combat_search_target_pos") as Vector2
	var suppressed := (
		String(_owner.get("_combat_search_current_node_key")) != ""
		and bool(_owner.get("_combat_search_current_node_requires_shadow_scan"))
		and bool(_owner.get("_combat_search_current_node_shadow_scan_done"))
		and has_known_target
		and known_target_pos.distance_to(search_target) <= 0.5
		and has_shadow_scan_target
		and shadow_scan_target.distance_to(search_target) <= 0.5
	)
	_owner.set("_combat_search_shadow_scan_suppressed_last_tick", suppressed)
	return suppressed


func _resolve_room_id_for_events() -> int:
	if _owner == null:
		return -1
	if not _owner.has_method("_resolve_room_id_for_events"):
		return -1
	return int(_owner.call("_resolve_room_id_for_events"))


func _roll_room_budget() -> float:
	if _owner == null:
		return COMBAT_SEARCH_ROOM_BUDGET_MIN_SEC
	var shot_rng: Variant = _owner.get("_shot_rng")
	if shot_rng != null and shot_rng is RandomNumberGenerator:
		return float(shot_rng.randf_range(COMBAT_SEARCH_ROOM_BUDGET_MIN_SEC, COMBAT_SEARCH_ROOM_BUDGET_MAX_SEC))
	return COMBAT_SEARCH_ROOM_BUDGET_MIN_SEC


func _owner_global_position() -> Vector2:
	if _owner == null:
		return Vector2.ZERO
	var pos_variant: Variant = _owner.get("global_position")
	return pos_variant as Vector2 if pos_variant is Vector2 else Vector2.ZERO


func _nav_system() -> Node:
	if _owner == null:
		return null
	var nav_variant: Variant = _owner.get("nav_system")
	return nav_variant as Node if nav_variant is Node else null


func _pursuit_cfg_float(key: String, fallback: float) -> float:
	if _owner == null:
		return fallback
	if not _owner.has_method("_pursuit_cfg_float"):
		return fallback
	return float(_owner.call("_pursuit_cfg_float", key, fallback))
