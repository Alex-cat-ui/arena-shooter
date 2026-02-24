## enemy_squad_system.gd
## Tactical slot assignment around player with stable roles and reservation TTL.
class_name EnemySquadSystem
extends Node

enum Role {
	PRESSURE,
	HOLD,
	FLANK,
}

const REBUILD_INTERVAL_SEC := 0.35
const SLOT_RESERVATION_TTL_SEC := 1.1
const PRESSURE_RADIUS_PX := 380.0
const HOLD_RADIUS_PX := 520.0
const FLANK_RADIUS_PX := 640.0
const PRESSURE_SLOT_COUNT := 6
const HOLD_SLOT_COUNT := 8
const FLANK_SLOT_COUNT := 8
const INVALID_PATH_SCORE_PENALTY := 100000.0
const FLANK_MAX_PATH_PX := 900.0
const FLANK_MAX_TIME_SEC := 3.5
const FLANK_WALK_SPEED_ASSUMED_PX_PER_SEC := 150.0
const COVER_SLOT_WALL_INSET_PX := 12.0
const COVER_SLOT_OBSTACLE_INSET_PX := 10.0
const COVER_SLOT_DEDUP_BUCKET_PX := 24.0
const COVER_LOS_BREAK_WEIGHT := 180.0
const FLANK_ANGLE_SCORE_WEIGHT := 120.0

var player_node: Node2D = null
var navigation_service: Node = null
var entities_container: Node = null

var _members: Dictionary = {}           # enemy_id -> {"enemy_ref": WeakRef, "role": int, "assignment": Dictionary}
var _rebuild_timer: float = 0.0
var _scanner_slots: Dictionary = {}
var _clock_sec: float = 0.0
var runtime_budget_scheduler_enabled: bool = false


func initialize(p_player_node: Node2D, p_navigation_service: Node, p_entities_container: Node = null) -> void:
	player_node = p_player_node
	navigation_service = p_navigation_service
	bind_entities_container(p_entities_container)
	_recompute_assignments()


func bind_entities_container(p_entities_container: Node) -> void:
	if entities_container and entities_container.child_entered_tree.is_connected(_on_entity_child_entered):
		entities_container.child_entered_tree.disconnect(_on_entity_child_entered)
	if entities_container and entities_container.child_exiting_tree.is_connected(_on_entity_child_exiting):
		entities_container.child_exiting_tree.disconnect(_on_entity_child_exiting)

	entities_container = p_entities_container
	if not entities_container:
		return
	if not entities_container.child_entered_tree.is_connected(_on_entity_child_entered):
		entities_container.child_entered_tree.connect(_on_entity_child_entered)
	if not entities_container.child_exiting_tree.is_connected(_on_entity_child_exiting):
		entities_container.child_exiting_tree.connect(_on_entity_child_exiting)
	_register_existing_enemies()


func register_enemy(enemy_id: int, enemy_node: Node) -> void:
	if enemy_id <= 0 or enemy_node == null:
		return
	_members[enemy_id] = {
		"enemy_ref": weakref(enemy_node),
		"role": _stable_role_for_enemy_id(enemy_id),
		"assignment": _default_assignment(_stable_role_for_enemy_id(enemy_id)),
	}


func deregister_enemy(enemy_id: int) -> void:
	_members.erase(enemy_id)


func get_assignment(enemy_id: int) -> Dictionary:
	if not _members.has(enemy_id):
		return _default_assignment(_stable_role_for_enemy_id(enemy_id))
	var member := _members[enemy_id] as Dictionary
	var assignment := member.get("assignment", _default_assignment(int(member.get("role", Role.PRESSURE)))) as Dictionary
	return assignment.duplicate(true)


func recompute_now() -> void:
	_recompute_assignments()


func _process(delta: float) -> void:
	if runtime_budget_scheduler_enabled:
		return
	runtime_budget_tick(delta)


func set_runtime_budget_scheduler_enabled(enabled: bool) -> void:
	runtime_budget_scheduler_enabled = enabled
	set_process(not enabled)


func runtime_budget_tick(delta: float) -> bool:
	_clock_sec += maxf(delta, 0.0)
	_rebuild_timer -= delta
	if _rebuild_timer > 0.0:
		return false
	_rebuild_timer = _squad_cfg_float("rebuild_interval_sec", REBUILD_INTERVAL_SEC)
	_recompute_assignments()
	return true


func _recompute_assignments() -> void:
	_cleanup_stale_members()
	if _members.is_empty() or player_node == null or not is_instance_valid(player_node):
		return

	var slots_by_role := _build_slots(player_node.global_position)
	var used_slot_keys := {}
	var ids: Array[int] = []
	for id_variant in _members.keys():
		ids.append(int(id_variant))
	ids.sort()

	for enemy_id in ids:
		var member := _members[enemy_id] as Dictionary
		var enemy := _member_enemy(member)
		var role := int(member.get("role", Role.PRESSURE))
		if enemy == null:
			member["assignment"] = _default_assignment(role)
			_members[enemy_id] = member
			continue

		var slot_pick := _pick_slot_for_enemy(enemy, role, slots_by_role, used_slot_keys)
		if slot_pick.is_empty():
			member["assignment"] = _default_assignment(role)
			_members[enemy_id] = member
			continue

		var slot_key := String(slot_pick.get("slot_key", slot_pick.get("key", "")))
		used_slot_keys[slot_key] = true
		member["assignment"] = {
			"role": role,
			"slot_role": int(slot_pick.get("slot_role", role)),
			"slot_position": slot_pick.get("pos", slot_pick.get("position", enemy.global_position)) as Vector2,
			"slot_key": slot_key,
			"path_ok": bool(slot_pick.get("path_ok", false)),
			"path_status": String(slot_pick.get("path_status", "unreachable_geometry")),
			"path_reason": String(slot_pick.get("path_reason", "invalid_path_contract")),
			"slot_path_length": float(slot_pick.get("slot_path_length", INF)),
			"slot_path_eta_sec": float(slot_pick.get("slot_path_eta_sec", INF)),
			"blocked_point": slot_pick.get("blocked_point", Vector2.ZERO) as Vector2,
			"blocked_point_valid": bool(slot_pick.get("blocked_point_valid", false)),
			"cover_source": String(slot_pick.get("cover_source", "none")),
			"cover_los_break_quality": clampf(float(slot_pick.get("cover_los_break_quality", 0.0)), 0.0, 1.0),
			"cover_score": float(slot_pick.get("cover_score", 0.0)),
			"has_slot": true,
			"reserved_until": _clock_sec + _squad_cfg_float("slot_reservation_ttl_sec", SLOT_RESERVATION_TTL_SEC),
		}
		_members[enemy_id] = member
	_rebuild_scanner_slots()


func _rebuild_scanner_slots() -> void:
	var cap: int = _squad_cfg_int("flashlight_scanner_cap", 2)
	_scanner_slots.clear()

	var pressure_ids: Array[int] = []
	var hold_ids: Array[int] = []
	for id_variant in _members.keys():
		var enemy_id := int(id_variant)
		var member := _members[id_variant] as Dictionary
		var role := int(member.get("role", Role.PRESSURE))
		if role == Role.PRESSURE:
			pressure_ids.append(enemy_id)
		elif role == Role.HOLD:
			hold_ids.append(enemy_id)

	pressure_ids.sort()
	hold_ids.sort()

	var slots_remaining: int = cap
	for enemy_id in pressure_ids:
		_scanner_slots[enemy_id] = slots_remaining > 0
		if slots_remaining > 0:
			slots_remaining -= 1

	for enemy_id in hold_ids:
		_scanner_slots[enemy_id] = slots_remaining > 0
		if slots_remaining > 0:
			slots_remaining -= 1

	for id_variant in _members.keys():
		var enemy_id := int(id_variant)
		var member := _members[id_variant] as Dictionary
		var role := int(member.get("role", Role.PRESSURE))
		if role == Role.FLANK:
			_scanner_slots[enemy_id] = false

	for id_variant in _members.keys():
		var enemy_id := int(id_variant)
		var member := _members[id_variant] as Dictionary
		var enemy := _member_enemy(member)
		if enemy == null:
			continue
		if enemy.has_method("set_flashlight_scanner_allowed"):
			enemy.call("set_flashlight_scanner_allowed", bool(_scanner_slots.get(enemy_id, false)))


func get_scanner_allowed(enemy_id: int) -> bool:
	return bool(_scanner_slots.get(enemy_id, false))


func _pick_slot_for_enemy(enemy: Node2D, preferred_role: int, slots_by_role: Dictionary, used_slot_keys: Dictionary) -> Dictionary:
	var role_priority := _role_priority(preferred_role)
	var role_priority_index := {}
	for i in range(role_priority.size()):
		role_priority_index[int(role_priority[i])] = i
	var invalid_fallbacks_by_role := {}
	var player_pos := player_node.global_position if player_node and is_instance_valid(player_node) else Vector2.ZERO

	for role_variant in role_priority:
		var role := int(role_variant)
		if not slots_by_role.has(role):
			continue
		var slots := slots_by_role[role] as Array
		var best_valid_for_role := {}
		var best_invalid_for_role := {}
		for slot_variant in slots:
			var slot := slot_variant as Dictionary
			var slot_key := String(slot.get("slot_key", slot.get("key", "")))
			if slot_key == "" or used_slot_keys.has(slot_key):
				continue
			var scored := _score_tactical_slot_candidate(enemy, preferred_role, role, slot, player_pos)
			if bool(scored.get("candidate_valid", false)):
				if _is_scored_candidate_better(scored, best_valid_for_role, role_priority_index):
					best_valid_for_role = scored
			elif _is_scored_candidate_better(scored, best_invalid_for_role, role_priority_index):
				best_invalid_for_role = scored
		if not best_valid_for_role.is_empty():
			return best_valid_for_role
		if not best_invalid_for_role.is_empty():
			invalid_fallbacks_by_role[role] = best_invalid_for_role

	if preferred_role == Role.FLANK:
		for role_variant in role_priority:
			var role := int(role_variant)
			if role == Role.FLANK:
				continue
			if invalid_fallbacks_by_role.has(role):
				return invalid_fallbacks_by_role[role] as Dictionary
		return {}

	var best_invalid_any := {}
	for role_variant in role_priority:
		var role := int(role_variant)
		if not invalid_fallbacks_by_role.has(role):
			continue
		var cand := invalid_fallbacks_by_role[role] as Dictionary
		if _is_scored_candidate_better(cand, best_invalid_any, role_priority_index):
			best_invalid_any = cand
	return best_invalid_any


func _is_scored_candidate_better(candidate: Dictionary, current_best: Dictionary, role_priority_index: Dictionary) -> bool:
	if candidate.is_empty():
		return false
	if current_best.is_empty():
		return true
	var cand_total := float(candidate.get("total_score", INF))
	var best_total := float(current_best.get("total_score", INF))
	if not is_equal_approx(cand_total, best_total):
		return cand_total < best_total
	var cand_valid := bool(candidate.get("candidate_valid", false))
	var best_valid := bool(current_best.get("candidate_valid", false))
	if cand_valid != best_valid:
		return cand_valid and not best_valid
	var cand_role_rank := int(role_priority_index.get(int(candidate.get("slot_role", Role.PRESSURE)), 999))
	var best_role_rank := int(role_priority_index.get(int(current_best.get("slot_role", Role.PRESSURE)), 999))
	if cand_role_rank != best_role_rank:
		return cand_role_rank < best_role_rank
	var cand_len := float(candidate.get("slot_path_length", INF))
	var best_len := float(current_best.get("slot_path_length", INF))
	if not is_equal_approx(cand_len, best_len):
		return cand_len < best_len
	var cand_key := String(candidate.get("slot_key", ""))
	var best_key := String(current_best.get("slot_key", ""))
	return cand_key < best_key


func _sum_path_points_length(from_pos: Vector2, path_points: Array) -> float:
	var total := 0.0
	var prev := from_pos
	for point_variant in path_points:
		var point := point_variant as Vector2
		total += prev.distance_to(point)
		prev = point
	return total


func _build_slot_policy_eval(enemy: Node2D, slot_pos: Vector2) -> Dictionary:
	var out := {
		"path_status": "unreachable_geometry",
		"path_reason": "nav_service_missing",
		"path_ok": false,
		"path_points": [],
		"slot_path_length": INF,
		"slot_path_eta_sec": INF,
		"blocked_point": Vector2.ZERO,
		"blocked_point_valid": false,
	}
	if navigation_service == null:
		return out
	if navigation_service.has_method("room_id_at_point"):
		var slot_room := int(navigation_service.call("room_id_at_point", slot_pos))
		if slot_room < 0:
			out["path_reason"] = "invalid_slot_room"
			return out
	if not navigation_service.has_method("build_policy_valid_path"):
		out["path_reason"] = "path_contract_missing"
		return out

	# Slot path policy contract owner call: build_policy_valid_path(...)
	var plan_variant: Variant = navigation_service.call("build_policy_valid_path", enemy.global_position, slot_pos, enemy)
	if not (plan_variant is Dictionary):
		out["path_reason"] = "invalid_path_contract"
		return out
	var plan := plan_variant as Dictionary

	var path_status := String(plan.get("status", "unreachable_geometry"))
	var path_reason := String(plan.get("reason", "invalid_path_contract"))
	var valid_statuses := ["ok", "unreachable_policy", "unreachable_geometry"]
	var valid_reasons := [
		"ok",
		"policy_blocked",
		"navmesh_no_path",
		"room_graph_no_path",
		"room_graph_unavailable",
		"empty_path",
		"nav_service_missing",
		"path_contract_missing",
		"invalid_slot_room",
		"invalid_path_contract",
	]
	if not valid_statuses.has(path_status):
		out["path_status"] = "unreachable_geometry"
		out["path_reason"] = "invalid_path_contract"
		out["path_ok"] = false
		return out
	if not valid_reasons.has(path_reason):
		out["path_status"] = "unreachable_geometry"
		out["path_reason"] = "invalid_path_contract"
		out["path_ok"] = false
		return out
	out["path_status"] = path_status
	out["path_reason"] = path_reason
	out["path_ok"] = (path_status == "ok")

	if not bool(out.get("path_ok", false)):
		if plan.has("blocked_point"):
			var blocked_variant: Variant = plan.get("blocked_point", null)
			if blocked_variant is Vector2:
				out["blocked_point"] = blocked_variant as Vector2
				out["blocked_point_valid"] = true
		return out

	if not plan.has("path_points") or not (plan.get("path_points", null) is Array):
		out["path_status"] = "unreachable_geometry"
		out["path_reason"] = "invalid_path_contract"
		out["path_ok"] = false
		return out
	var path_points_src := plan.get("path_points", []) as Array
	var path_points: Array = []
	for point_variant in path_points_src:
		if not (point_variant is Vector2):
			out["path_status"] = "unreachable_geometry"
			out["path_reason"] = "invalid_path_contract"
			out["path_ok"] = false
			out["path_points"] = []
			return out
		var point := point_variant as Vector2
		if not is_finite(point.x) or not is_finite(point.y):
			out["path_status"] = "unreachable_geometry"
			out["path_reason"] = "invalid_path_contract"
			out["path_ok"] = false
			out["path_points"] = []
			return out
		path_points.append(point)
	out["path_points"] = path_points
	if path_points.is_empty():
		out["path_status"] = "unreachable_geometry"
		out["path_reason"] = "empty_path"
		out["path_ok"] = false
		return out

	var path_length := _sum_path_points_length(enemy.global_position, path_points)
	out["slot_path_length"] = path_length
	out["slot_path_eta_sec"] = path_length / maxf(_squad_cfg_float("flank_walk_speed_assumed_px_per_sec", FLANK_WALK_SPEED_ASSUMED_PX_PER_SEC), 0.001)
	return out


func _compute_cover_los_break_quality(candidate_pos: Vector2, outward_normal: Vector2, player_pos: Vector2) -> float:
	if (
		not is_finite(candidate_pos.x)
		or not is_finite(candidate_pos.y)
		or not is_finite(outward_normal.x)
		or not is_finite(outward_normal.y)
		or not is_finite(player_pos.x)
		or not is_finite(player_pos.y)
	):
		return 0.0
	if outward_normal.length_squared() <= 0.000001:
		return 0.0
	var to_player := player_pos - candidate_pos
	if to_player.length_squared() <= 0.000001:
		return 0.0
	var n := outward_normal.normalized()
	var to_player_dir := to_player.normalized()
	return clampf(n.dot(-to_player_dir), 0.0, 1.0)


func _build_cover_slots_from_nav_obstacles(player_room_rect: Rect2, player_pos: Vector2) -> Array:
	if player_room_rect.size.x <= 0.0 or player_room_rect.size.y <= 0.0:
		return []
	if navigation_service == null:
		return []
	var layout_variant: Variant = navigation_service.get("layout")
	if layout_variant == null or not (layout_variant is Object):
		return []
	var layout_obj := layout_variant as Object
	if not layout_obj.has_method("_navigation_obstacles"):
		return []
	var obstacles_variant: Variant = layout_obj.call("_navigation_obstacles")
	if not (obstacles_variant is Array):
		return []
	var room_inner := player_room_rect.grow(-1.0)
	var result: Array = []
	for obstacle_variant in (obstacles_variant as Array):
		if not (obstacle_variant is Rect2):
			continue
		var obstacle := obstacle_variant as Rect2
		if (
			not is_finite(obstacle.position.x)
			or not is_finite(obstacle.position.y)
			or not is_finite(obstacle.size.x)
			or not is_finite(obstacle.size.y)
		):
			continue
		if obstacle.size.x <= 0.0 or obstacle.size.y <= 0.0:
			continue
		if not obstacle.intersects(player_room_rect):
			continue
		var candidates := [
			{
				"edge_name": "left",
				"pos": Vector2(obstacle.position.x, obstacle.position.y + obstacle.size.y * 0.5) + Vector2(-COVER_SLOT_OBSTACLE_INSET_PX, 0.0),
				"normal": Vector2.LEFT,
			},
			{
				"edge_name": "right",
				"pos": Vector2(obstacle.position.x + obstacle.size.x, obstacle.position.y + obstacle.size.y * 0.5) + Vector2(COVER_SLOT_OBSTACLE_INSET_PX, 0.0),
				"normal": Vector2.RIGHT,
			},
			{
				"edge_name": "top",
				"pos": Vector2(obstacle.position.x + obstacle.size.x * 0.5, obstacle.position.y) + Vector2(0.0, -COVER_SLOT_OBSTACLE_INSET_PX),
				"normal": Vector2.UP,
			},
			{
				"edge_name": "bottom",
				"pos": Vector2(obstacle.position.x + obstacle.size.x * 0.5, obstacle.position.y + obstacle.size.y) + Vector2(0.0, COVER_SLOT_OBSTACLE_INSET_PX),
				"normal": Vector2.DOWN,
			},
		]
		for candidate_variant in candidates:
			var candidate := candidate_variant as Dictionary
			var candidate_pos := candidate.get("pos", Vector2.ZERO) as Vector2
			if not is_finite(candidate_pos.x) or not is_finite(candidate_pos.y):
				continue
			if not room_inner.has_point(candidate_pos):
				continue
			var edge_name := String(candidate.get("edge_name", "edge"))
			var outward_normal := candidate.get("normal", Vector2.ZERO) as Vector2
			var bucket_x := int(floor(candidate_pos.x / COVER_SLOT_DEDUP_BUCKET_PX))
			var bucket_y := int(floor(candidate_pos.y / COVER_SLOT_DEDUP_BUCKET_PX))
			result.append({
				"pos": candidate_pos,
				"slot_key": "cover:obstacle:%d:%d:%s" % [bucket_x, bucket_y, edge_name],
				"cover_source": "obstacle",
				"cover_los_break_quality": _compute_cover_los_break_quality(candidate_pos, outward_normal, player_pos),
			})
	return result


func _build_cover_slots_from_room_geometry(player_pos: Vector2) -> Array:
	if navigation_service == null:
		return []
	if not navigation_service.has_method("room_id_at_point") or not navigation_service.has_method("get_room_rect"):
		return []
	var player_room_id := int(navigation_service.call("room_id_at_point", player_pos))
	if player_room_id < 0:
		return []
	var player_room_rect := navigation_service.call("get_room_rect", player_room_id) as Rect2
	if player_room_rect.size.x <= 0.0 or player_room_rect.size.y <= 0.0:
		return []

	var combined: Array = []
	var wall_candidates := [
		{
			"edge_name": "left",
			"pos": Vector2(player_room_rect.position.x, player_room_rect.position.y + player_room_rect.size.y * 0.5) + Vector2(COVER_SLOT_WALL_INSET_PX, 0.0),
			"normal": Vector2.LEFT,
		},
		{
			"edge_name": "right",
			"pos": Vector2(player_room_rect.position.x + player_room_rect.size.x, player_room_rect.position.y + player_room_rect.size.y * 0.5) + Vector2(-COVER_SLOT_WALL_INSET_PX, 0.0),
			"normal": Vector2.RIGHT,
		},
		{
			"edge_name": "top",
			"pos": Vector2(player_room_rect.position.x + player_room_rect.size.x * 0.5, player_room_rect.position.y) + Vector2(0.0, COVER_SLOT_WALL_INSET_PX),
			"normal": Vector2.UP,
		},
		{
			"edge_name": "bottom",
			"pos": Vector2(player_room_rect.position.x + player_room_rect.size.x * 0.5, player_room_rect.position.y + player_room_rect.size.y) + Vector2(0.0, -COVER_SLOT_WALL_INSET_PX),
			"normal": Vector2.DOWN,
		},
	]
	for candidate_variant in wall_candidates:
		var candidate := candidate_variant as Dictionary
		var candidate_pos := candidate.get("pos", Vector2.ZERO) as Vector2
		var edge_name := String(candidate.get("edge_name", "edge"))
		var outward_normal := candidate.get("normal", Vector2.ZERO) as Vector2
		combined.append({
			"pos": candidate_pos,
			"slot_key": "cover:wall:%s" % edge_name,
			"cover_source": "wall",
			"cover_los_break_quality": _compute_cover_los_break_quality(candidate_pos, outward_normal, player_pos),
		})

	for obstacle_slot in _build_cover_slots_from_nav_obstacles(player_room_rect, player_pos):
		combined.append(obstacle_slot)

	var deduped: Array = []
	var seen := {}
	for slot_variant in combined:
		var slot := slot_variant as Dictionary
		var pos := slot.get("pos", Vector2.ZERO) as Vector2
		var cover_source := String(slot.get("cover_source", "none"))
		var bucket_x := int(floor(pos.x / COVER_SLOT_DEDUP_BUCKET_PX))
		var bucket_y := int(floor(pos.y / COVER_SLOT_DEDUP_BUCKET_PX))
		var bucket_key := "%s:%d:%d" % [cover_source, bucket_x, bucket_y]
		if seen.has(bucket_key):
			continue
		seen[bucket_key] = true
		deduped.append(slot)
	return deduped


func _score_tactical_slot_candidate(
	enemy: Node2D,
	_preferred_role: int,
	slot_role: int,
	slot: Dictionary,
	player_pos: Vector2
) -> Dictionary:
	var effective_slot_role := int(slot.get("slot_role", slot_role))
	var cover_source := String(slot.get("cover_source", "ring"))
	var cover_los_break_quality := clampf(float(slot.get("cover_los_break_quality", 0.0)), 0.0, 1.0)
	var pos := slot.get("pos", slot.get("position", enemy.global_position)) as Vector2
	var slot_key := String(slot.get("slot_key", slot.get("key", "")))

	var policy_eval := _build_slot_policy_eval(enemy, pos)
	var flank_path_len_ok := true
	var flank_eta_ok := true
	if effective_slot_role == Role.FLANK:
		flank_path_len_ok = float(policy_eval.get("slot_path_length", INF)) <= _squad_cfg_float("flank_max_path_px", FLANK_MAX_PATH_PX)
		flank_eta_ok = float(policy_eval.get("slot_path_eta_sec", INF)) <= _squad_cfg_float("flank_max_time_sec", FLANK_MAX_TIME_SEC)
	var candidate_valid := bool(policy_eval.get("path_ok", false)) and flank_path_len_ok and flank_eta_ok
	var distance_score := enemy.global_position.distance_to(pos)

	var flank_angle_score := 0.0
	if effective_slot_role == Role.FLANK:
		var to_enemy := enemy.global_position - player_pos
		var to_slot := pos - player_pos
		if to_enemy.length_squared() > 0.000001 and to_slot.length_squared() > 0.000001:
			var delta := absf(wrapf(to_enemy.angle_to(to_slot), -PI, PI))
			var perpendicular_error := absf(delta - PI * 0.5)
			flank_angle_score = perpendicular_error * FLANK_ANGLE_SCORE_WEIGHT

	var cover_bonus := 0.0
	if effective_slot_role == Role.HOLD or effective_slot_role == Role.FLANK:
		cover_bonus = cover_los_break_quality * COVER_LOS_BREAK_WEIGHT
	var invalid_penalty := 0.0 if candidate_valid else _squad_cfg_float("invalid_path_score_penalty", INVALID_PATH_SCORE_PENALTY)
	var total_score := distance_score + flank_angle_score + invalid_penalty - cover_bonus

	var scored := slot.duplicate(true)
	scored["slot_role"] = effective_slot_role
	scored["cover_source"] = cover_source
	scored["cover_los_break_quality"] = cover_los_break_quality
	scored["pos"] = pos
	scored["position"] = pos
	scored["slot_key"] = slot_key
	scored["key"] = slot_key
	for key_variant in policy_eval.keys():
		scored[key_variant] = policy_eval[key_variant]
	scored["candidate_valid"] = candidate_valid
	scored["total_score"] = total_score
	scored["distance_score"] = distance_score
	scored["flank_angle_score"] = flank_angle_score
	scored["cover_score"] = cover_bonus
	return scored


func _build_contain_slots_from_exits(player_pos: Vector2) -> Array:
	if navigation_service == null:
		return []
	if not navigation_service.has_method("room_id_at_point"):
		return []
	if not navigation_service.has_method("get_adjacent_room_ids"):
		return []
	if not navigation_service.has_method("get_door_center_between"):
		return []
	var player_room_id: int = int(navigation_service.call("room_id_at_point", player_pos))
	if player_room_id < 0:
		return []
	var adj_rooms: Array = navigation_service.call("get_adjacent_room_ids", player_room_id) as Array
	if adj_rooms.is_empty():
		return []
	var slots: Array = []
	for adj_variant in adj_rooms:
		var adj_id: int = int(adj_variant)
		var door_center: Vector2 = navigation_service.call(
			"get_door_center_between",
			player_room_id,
			adj_id,
			player_pos
		) as Vector2
		if door_center == Vector2.ZERO:
			continue
		slots.append({
			"key": "hold_exit:%d:%d" % [player_room_id, adj_id],
			"position": door_center,
		})
	return slots


func _build_slots(player_pos: Vector2) -> Dictionary:
	var pressure_slots := _annotate_slots(
		_build_ring_slots(
			player_pos,
			_squad_cfg_float("pressure_radius_px", PRESSURE_RADIUS_PX),
			_squad_cfg_int("pressure_slot_count", PRESSURE_SLOT_COUNT),
			Role.PRESSURE,
			0.0
		),
		Role.PRESSURE,
		"ring",
		0.0
	)
	var wall_cover_slots := _annotate_hold_cover_slots(_build_cover_slots_from_room_geometry(player_pos))
	var hold_slots: Array = []
	if not wall_cover_slots.is_empty():
		hold_slots = wall_cover_slots
	else:
		var contain_slots := _build_contain_slots_from_exits(player_pos)
		if not contain_slots.is_empty():
			hold_slots = _annotate_slots(contain_slots, Role.HOLD, "exit", 0.0)
		else:
			hold_slots = _annotate_slots(
				_build_ring_slots(
					player_pos,
					_squad_cfg_float("hold_radius_px", HOLD_RADIUS_PX),
					_squad_cfg_int("hold_slot_count", HOLD_SLOT_COUNT),
					Role.HOLD,
					0.0
				),
				Role.HOLD,
				"ring",
				0.0
			)
	var flank_slots := _annotate_slots(
		_build_ring_slots(
			player_pos,
			_squad_cfg_float("flank_radius_px", FLANK_RADIUS_PX),
			_squad_cfg_int("flank_slot_count", FLANK_SLOT_COUNT),
			Role.FLANK,
			PI / float(maxi(_squad_cfg_int("flank_slot_count", FLANK_SLOT_COUNT), 1))
		),
		Role.FLANK,
		"ring",
		0.0
	)
	return {
		Role.PRESSURE: pressure_slots,
		Role.HOLD: hold_slots,
		Role.FLANK: flank_slots,
	}


func _annotate_hold_cover_slots(slots: Array) -> Array:
	var out: Array = []
	for slot_variant in slots:
		var slot := slot_variant as Dictionary
		var pos := slot.get("pos", Vector2.ZERO) as Vector2
		var slot_key := String(slot.get("slot_key", ""))
		out.append({
			"pos": pos,
			"position": pos,
			"slot_key": slot_key,
			"key": slot_key,
			"slot_role": Role.HOLD,
			"cover_source": String(slot.get("cover_source", "none")),
			"cover_los_break_quality": clampf(float(slot.get("cover_los_break_quality", 0.0)), 0.0, 1.0),
		})
	return out


func _annotate_slots(slots: Array, slot_role: int, cover_source: String, cover_los_break_quality: float) -> Array:
	var out: Array = []
	for slot_variant in slots:
		var slot := slot_variant as Dictionary
		var pos := slot.get("position", slot.get("pos", Vector2.ZERO)) as Vector2
		var slot_key := String(slot.get("key", slot.get("slot_key", "")))
		out.append({
			"pos": pos,
			"position": pos,
			"slot_key": slot_key,
			"key": slot_key,
			"slot_role": slot_role,
			"cover_source": cover_source,
			"cover_los_break_quality": cover_los_break_quality,
		})
	return out


func _build_ring_slots(center: Vector2, radius: float, count: int, role: int, phase: float) -> Array:
	var slots: Array = []
	if count <= 0:
		return slots
	for i in range(count):
		var ang := phase + TAU * float(i) / float(count)
		slots.append({
			"key": "%d:%d" % [role, i],
			"position": center + Vector2.RIGHT.rotated(ang) * radius,
		})
	return slots


func _cleanup_stale_members() -> void:
	var remove_ids: Array[int] = []
	for id_variant in _members.keys():
		var enemy_id := int(id_variant)
		var member := _members[id_variant] as Dictionary
		var enemy := _member_enemy(member)
		if enemy == null:
			remove_ids.append(enemy_id)
			continue
		if "is_dead" in enemy and bool(enemy.is_dead):
			remove_ids.append(enemy_id)
	for enemy_id in remove_ids:
		_members.erase(enemy_id)


func _member_enemy(member: Dictionary) -> Node2D:
	var wref := member.get("enemy_ref", null) as WeakRef
	if wref == null:
		return null
	var node := wref.get_ref() as Node2D
	if node == null or not is_instance_valid(node):
		return null
	return node


func _default_assignment(role: int) -> Dictionary:
	return {
		"role": role,
		"slot_role": role,
		"slot_position": Vector2.ZERO,
		"slot_key": "",
		"path_ok": false,
		"path_status": "unreachable_geometry",
		"path_reason": "nav_service_missing",
		"has_slot": false,
		"slot_path_length": INF,
		"slot_path_eta_sec": INF,
		"blocked_point": Vector2.ZERO,
		"blocked_point_valid": false,
		"cover_source": "none",
		"cover_los_break_quality": 0.0,
		"cover_score": 0.0,
		"reserved_until": 0.0,
	}


func _stable_role_for_enemy_id(enemy_id: int) -> int:
	var bucket := posmod(enemy_id, 6)
	if bucket == 0 or bucket == 3:
		return Role.PRESSURE
	if bucket == 1 or bucket == 4:
		return Role.HOLD
	return Role.FLANK


func _role_priority(primary_role: int) -> Array[int]:
	match primary_role:
		Role.PRESSURE:
			return [Role.PRESSURE, Role.HOLD, Role.FLANK]
		Role.HOLD:
			return [Role.HOLD, Role.FLANK, Role.PRESSURE]
		Role.FLANK:
			return [Role.FLANK, Role.HOLD, Role.PRESSURE]
		_:
			return [Role.PRESSURE, Role.HOLD, Role.FLANK]


func _register_existing_enemies() -> void:
	if not entities_container:
		return
	for child_variant in entities_container.get_children():
		var enemy := child_variant as Node
		if enemy == null or not enemy.is_in_group("enemies"):
			continue
		if not ("entity_id" in enemy):
			continue
		register_enemy(int(enemy.entity_id), enemy)


func _on_entity_child_entered(node: Node) -> void:
	call_deferred("_register_entered_enemy", node)


func _register_entered_enemy(node: Node) -> void:
	if node == null or not node.is_in_group("enemies"):
		return
	if not ("entity_id" in node):
		return
	register_enemy(int(node.entity_id), node)


func _on_entity_child_exiting(node: Node) -> void:
	if node == null or not ("entity_id" in node):
		return
	deregister_enemy(int(node.entity_id))


func _squad_cfg_float(key: String, fallback: float) -> float:
	if GameConfig and GameConfig.ai_balance.has("squad"):
		var section := GameConfig.ai_balance["squad"] as Dictionary
		return float(section.get(key, fallback))
	return fallback


func _squad_cfg_int(key: String, fallback: int) -> int:
	if GameConfig and GameConfig.ai_balance.has("squad"):
		var section := GameConfig.ai_balance["squad"] as Dictionary
		return int(section.get(key, fallback))
	return fallback
