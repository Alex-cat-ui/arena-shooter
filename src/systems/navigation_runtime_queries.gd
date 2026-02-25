## navigation_runtime_queries.gd
## Runtime query helpers for NavigationService.
class_name NavigationRuntimeQueries
extends RefCounted

var _service: Node = null
const POLICY_SAMPLE_STEP_PX := 12.0
const NAV_COST_SHADOW_SAMPLE_STEP_PX := 16.0
const ROUTE_SOURCE_NAVMESH := "navmesh"
const ROUTE_SOURCE_ROOM_GRAPH := "room_graph"


func _init(service: Node) -> void:
	_service = service


func room_id_at_point(p: Vector2) -> int:
	var layout = _service.layout
	if not layout or not bool(layout.valid):
		return -1
	if not layout.has_method("_room_id_at_point"):
		return -1
	return int(layout._room_id_at_point(p))


func is_adjacent(a: int, b: int) -> bool:
	if a < 0 or b < 0:
		return false
	if not _service._room_graph.has(a):
		return false
	return (_service._room_graph[a] as Array).has(b)


func is_same_or_adjacent_room(room_a: int, room_b: int) -> bool:
	if room_a < 0 or room_b < 0:
		return false
	return room_a == room_b or is_adjacent(room_a, room_b)


func get_enemy_room_id(enemy: Node) -> int:
	if not enemy:
		return -1
	var enemy_node := enemy as Node2D
	if enemy_node and _service.layout and bool(_service.layout.valid):
		var detected_room := room_id_at_point(enemy_node.global_position)
		if detected_room >= 0:
			enemy.set_meta("room_id", detected_room)
			return detected_room
	var room_id := int(enemy.get_meta("room_id", -1))
	if room_id >= 0:
		return room_id
	if not enemy_node:
		return -1
	room_id = room_id_at_point(enemy_node.global_position)
	enemy.set_meta("room_id", room_id)
	return room_id


func get_neighbors(room_id: int) -> Array[int]:
	var result: Array[int] = []
	if room_id < 0 or not _service._room_graph.has(room_id):
		return result
	for rid_variant in (_service._room_graph[room_id] as Array):
		var rid := int(rid_variant)
		if rid >= 0 and rid != room_id:
			result.append(rid)
	result.sort()
	return result


func get_enemy_room_id_by_id(enemy_id: int) -> int:
	if enemy_id <= 0 or not _service.entities_container:
		return -1
	for child_variant in _service.entities_container.get_children():
		var enemy := child_variant as Node
		if not enemy:
			continue
		if not enemy.is_in_group("enemies"):
			continue
		if not ("entity_id" in enemy):
			continue
		if int(enemy.entity_id) != enemy_id:
			continue
		return get_enemy_room_id(enemy)
	return -1


func get_alert_level(room_id: int) -> int:
	if _service.alert_system and _service.alert_system.has_method("get_room_alert_level"):
		return int(_service.alert_system.get_room_alert_level(room_id))
	return 0


func get_alert_level_at_point(p: Vector2) -> int:
	return get_alert_level(room_id_at_point(p))


func get_adjacent_room_ids(room_id: int) -> Array[int]:
	return get_neighbors(room_id)


func get_room_center(room_id: int) -> Vector2:
	if not _service.layout or not bool(_service.layout.valid):
		return Vector2.ZERO
	if room_id < 0 or room_id >= _service.layout.rooms.size():
		return Vector2.ZERO
	var room := _service.layout.rooms[room_id] as Dictionary
	return room.get("center", Vector2.ZERO) as Vector2


func get_room_rect(room_id: int) -> Rect2:
	if not _service.layout or not bool(_service.layout.valid):
		return Rect2()
	if room_id < 0 or room_id >= _service.layout.rooms.size():
		return Rect2()
	var room := _service.layout.rooms[room_id] as Dictionary
	var rects := room.get("rects", []) as Array
	if rects.is_empty():
		return Rect2()
	var best := rects[0] as Rect2
	for rect_variant in rects:
		var r := rect_variant as Rect2
		if r.get_area() > best.get_area():
			best = r
	return best


func get_door_center_between(room_a: int, room_b: int, anchor: Vector2) -> Vector2:
	return _service._select_door_center(room_a, room_b, anchor)


func get_player_position() -> Vector2:
	if _service.player_node and is_instance_valid(_service.player_node):
		return _service.player_node.global_position
	if RuntimeState:
		return Vector2(RuntimeState.player_pos.x, RuntimeState.player_pos.y)
	return Vector2.ZERO


func get_enemies_in_room(room_id: int) -> Array[Node]:
	var result: Array[Node] = []
	if room_id < 0 or not _service.entities_container:
		return result
	for child_variant in _service.entities_container.get_children():
		var enemy := child_variant as Node2D
		if not enemy:
			continue
		if not enemy.is_in_group("enemies"):
			continue
		if "is_dead" in enemy and bool(enemy.is_dead):
			continue
		var own_room := get_enemy_room_id(enemy)
		if own_room == room_id:
			result.append(enemy)
	return result


func pick_top2_neighbor_rooms_for_reinforcement(source_room: int, player_pos: Vector2) -> Array[int]:
	var neighbors := get_neighbors(source_room)
	if neighbors.size() <= 2:
		return neighbors
	var scored: Array[Dictionary] = []
	for room_id in neighbors:
		scored.append({
			"room_id": room_id,
			"dist": get_room_center(room_id).distance_to(player_pos),
		})
	scored.sort_custom(func(a, b):
		var da := float(a.get("dist", INF))
		var db := float(b.get("dist", INF))
		if is_equal_approx(da, db):
			return int(a.get("room_id", -1)) < int(b.get("room_id", -1))
		return da < db
	)
	return [
		int(scored[0].get("room_id", -1)),
		int(scored[1].get("room_id", -1)),
	]


func random_point_in_room(room_id: int, margin: float = 20.0) -> Vector2:
	if not _service.layout or not bool(_service.layout.valid):
		return Vector2.ZERO
	if room_id < 0 or room_id >= _service.layout.rooms.size():
		return Vector2.ZERO
	var room := _service.layout.rooms[room_id] as Dictionary
	var rects := room.get("rects", []) as Array
	if rects.is_empty():
		return room.get("center", Vector2.ZERO) as Vector2

	var pick_rect := rects[0] as Rect2
	for rect_variant in rects:
		var r := rect_variant as Rect2
		if r.get_area() > pick_rect.get_area():
			pick_rect = r
	var safe := pick_rect.grow(-margin)
	if safe.size.x < 4.0 or safe.size.y < 4.0:
		safe = pick_rect.grow(-4.0)
	if safe.size.x < 2.0 or safe.size.y < 2.0:
		return pick_rect.get_center()
	return Vector2(
		_service._rng.randf_range(safe.position.x, safe.end.x),
		_service._rng.randf_range(safe.position.y, safe.end.y)
	)


func build_path_points(from_pos: Vector2, to_pos: Vector2) -> Array[Vector2]:
	var policy_plan := build_policy_valid_path(from_pos, to_pos)
	var path_points := _extract_path_points(policy_plan.get("path_points", []))
	if not path_points.is_empty():
		return path_points
	return [to_pos]


func build_reachable_path_points(from_pos: Vector2, to_pos: Vector2, enemy: Node = null) -> Array[Vector2]:
	var policy_plan := build_policy_valid_path(from_pos, to_pos, enemy)
	if String(policy_plan.get("status", "")) != "ok":
		return []
	return _extract_path_points(policy_plan.get("path_points", []))


func build_policy_valid_path(
	from_pos: Vector2,
	to_pos: Vector2,
	enemy: Node = null,
	cost_profile: Dictionary = {}
) -> Dictionary:
	var geometry_plan := _build_geometry_path_plan(from_pos, to_pos)
	var geometry_status := String(geometry_plan.get("status", "unreachable_geometry"))
	var route_source := String(geometry_plan.get("route_source", ROUTE_SOURCE_NAVMESH))
	var route_source_reason := String(geometry_plan.get("route_source_reason", "unknown"))
	var obstacle_intersection_detected := bool(geometry_plan.get("obstacle_intersection_detected", false))
	if geometry_status != "ok":
		return _finalize_path_plan_result(_build_path_plan_result(
			geometry_status,
			_extract_path_points(geometry_plan.get("path_points", [])),
			String(geometry_plan.get("reason", "path_unreachable")),
			"",
			0,
			route_source,
			route_source_reason,
			obstacle_intersection_detected
		))
	var direct_pts := _extract_path_points(geometry_plan.get("path_points", []))
	if direct_pts.is_empty():
		return _finalize_path_plan_result(_build_path_plan_result(
			"unreachable_geometry",
			[],
			"empty_path",
			"",
			0,
			route_source,
			route_source_reason,
			obstacle_intersection_detected
		))
	var direct_intersects_obstacle := _path_intersects_obstacle(from_pos, direct_pts)
	if direct_intersects_obstacle:
		return _finalize_path_plan_result(_build_path_plan_result(
			"unreachable_geometry",
			[],
			"path_intersects_obstacle",
			"",
			0,
			route_source,
			route_source_reason,
			true
		))
	if enemy == null:
		return _finalize_path_plan_result(_build_path_plan_result(
			"ok",
			direct_pts,
			"ok",
			"direct",
			0,
			route_source,
			route_source_reason,
			false
		))
	var direct_valid := _validate_enemy_policy_path(enemy, from_pos, direct_pts)
	if bool(direct_valid.get("valid", false)):
		return _finalize_path_plan_result(_build_path_plan_result(
			"ok",
			direct_pts,
			"ok",
			"direct",
			0,
			route_source,
			route_source_reason,
			false
		))
	var from_room := room_id_at_point(from_pos)
	var to_room := room_id_at_point(to_pos)
	if from_room < 0 or to_room < 0:
		return _finalize_path_plan_result(_build_path_plan_result(
			"unreachable_policy",
			[],
			"policy_blocked",
			"",
			0,
			route_source,
			route_source_reason,
			false
		))
	var candidates := _build_detour_candidates(from_pos, to_pos, from_room, to_room)
	var detour_candidate_count := maxi(candidates.size(), 0)
	var best_valid: Dictionary = {}
	var best_score: float = INF
	var detour_intersection_detected := false
	for cand_variant in candidates:
		var cand := cand_variant as Dictionary
		var cand_points := _extract_path_points(cand.get("path_points", []))
		if _path_intersects_obstacle(from_pos, cand_points):
			detour_intersection_detected = true
			continue
		var cand_validation := _validate_enemy_policy_path(enemy, from_pos, cand_points)
		var score := _score_path_cost(cand_points, from_pos, cost_profile)
		if bool(cand_validation.get("valid", false)) and score < best_score:
			best_valid = cand
			best_score = score
	if not best_valid.is_empty():
		return _finalize_path_plan_result(_build_path_plan_result(
			"ok",
			_extract_path_points(best_valid.get("path_points", [])),
			"ok",
			String(best_valid.get("route_type", "")),
			detour_candidate_count,
			route_source,
			route_source_reason,
			false
		))
	if detour_intersection_detected:
		return _finalize_path_plan_result(_build_path_plan_result(
			"unreachable_geometry",
			[],
			"path_intersects_obstacle",
			"",
			detour_candidate_count,
			route_source,
			route_source_reason,
			true
		))
	return _finalize_path_plan_result(_build_path_plan_result(
		"unreachable_policy",
		[],
		"policy_blocked",
		"",
		detour_candidate_count,
		route_source,
		route_source_reason,
		false
	))


func _build_geometry_path_plan(from_pos: Vector2, to_pos: Vector2) -> Dictionary:
	if _service and _service.has_method("is_navigation_build_valid"):
		if not bool(_service.call("is_navigation_build_valid")):
			return _build_path_plan_result(
				"unreachable_geometry",
				[],
				"invalid_nav_build",
				"",
				0,
				ROUTE_SOURCE_NAVMESH,
				"invalid_nav_build",
				false
			)
	var map_rid := RID()
	if _service and _service.has_method("get_navigation_map_rid"):
		map_rid = _service.get_navigation_map_rid()
	if map_rid.is_valid():
		var raw_path: PackedVector2Array = NavigationServer2D.map_get_path(map_rid, from_pos, to_pos, true)
		if raw_path.is_empty():
			return _build_path_plan_result(
				"unreachable_geometry",
				[],
				"navmesh_no_path",
				"",
				0,
				ROUTE_SOURCE_NAVMESH,
				"navmesh_path_empty",
				false
			)
		var out: Array[Vector2] = []
		for p in raw_path:
			out.append(p)
		if out.is_empty() or out[out.size() - 1].distance_to(to_pos) > 0.5:
			out.append(to_pos)
		if _path_intersects_obstacle(from_pos, out):
			return _build_path_plan_result(
				"unreachable_geometry",
				[],
				"path_intersects_obstacle",
				"",
				0,
				ROUTE_SOURCE_NAVMESH,
				"navmesh_intersection_validation_failed",
				true
			)
		return _build_path_plan_result(
			"ok",
			out,
			"ok",
			"",
			0,
			ROUTE_SOURCE_NAVMESH,
			"navmesh_map_path",
			false
		)

	if not _allow_room_graph_fallback_without_navmesh_only():
		return _build_path_plan_result(
			"unreachable_geometry",
			[],
			"room_graph_fallback_disabled",
			"",
			0,
			ROUTE_SOURCE_ROOM_GRAPH,
			"navmesh_unavailable_fallback_disabled",
			false
		)
	if _service == null or not _service.has_method("_build_room_graph_path_points_reachable"):
		return _build_path_plan_result(
			"unreachable_geometry",
			[],
			"room_graph_unavailable",
			"",
			0,
			ROUTE_SOURCE_ROOM_GRAPH,
			"navmesh_unavailable_room_graph_missing",
			false
		)
	var room_graph_variant: Variant = _service.call("_build_room_graph_path_points_reachable", from_pos, to_pos)
	var room_graph_path := _extract_path_points(room_graph_variant)
	if room_graph_path.is_empty():
		return _build_path_plan_result(
			"unreachable_geometry",
			[],
			"room_graph_no_path",
			"",
			0,
			ROUTE_SOURCE_ROOM_GRAPH,
			"navmesh_unavailable_room_graph_no_path",
			false
		)
	if room_graph_path[room_graph_path.size() - 1].distance_to(to_pos) > 0.5:
		room_graph_path.append(to_pos)
	if _path_intersects_obstacle(from_pos, room_graph_path):
		return _build_path_plan_result(
			"unreachable_geometry",
			[],
			"path_intersects_obstacle",
			"",
			0,
			ROUTE_SOURCE_ROOM_GRAPH,
			"room_graph_intersection_validation_failed",
			true
		)
	return _build_path_plan_result(
		"ok",
		room_graph_path,
		"ok",
		"",
		0,
		ROUTE_SOURCE_ROOM_GRAPH,
		"navmesh_unavailable_room_graph_fallback",
		false
	)


func _build_path_plan_result(
	status: String,
	path_points: Array[Vector2],
	reason: String,
	route_type: String,
	detour_candidates_evaluated_count: int,
	route_source: String,
	route_source_reason: String,
	obstacle_intersection_detected: bool
	) -> Dictionary:
	return {
		"status": status,
		"path_points": path_points,
		"reason": reason,
		"route_type": route_type,
		"detour_candidates_evaluated_count": maxi(detour_candidates_evaluated_count, 0),
		"route_source": route_source,
		"route_source_reason": route_source_reason,
		"obstacle_intersection_detected": obstacle_intersection_detected,
	}


func _finalize_path_plan_result(result: Dictionary) -> Dictionary:
	_record_path_contract_metrics(result)
	return result


func _record_path_contract_metrics(result: Dictionary) -> void:
	if not AIWatchdog:
		return
	var status := String(result.get("status", ""))
	if status == "ok" and bool(result.get("obstacle_intersection_detected", false)):
		if AIWatchdog.has_method("record_nav_path_obstacle_intersection_event"):
			AIWatchdog.call("record_nav_path_obstacle_intersection_event")
	var route_source := String(result.get("route_source", ""))
	if route_source != ROUTE_SOURCE_ROOM_GRAPH:
		return
	if status != "ok":
		return
	if _service == null or not _service.has_method("get_navigation_map_rid"):
		return
	var map_rid: RID = _service.get_navigation_map_rid()
	if not map_rid.is_valid():
		return
	if NavigationServer2D.map_get_iteration_id(map_rid) <= 0:
		return
	if AIWatchdog.has_method("record_room_graph_fallback_when_navmesh_available_event"):
		AIWatchdog.call("record_room_graph_fallback_when_navmesh_available_event")


func _allow_room_graph_fallback_without_navmesh_only() -> bool:
	if not GameConfig:
		return true
	if not (GameConfig.ai_balance is Dictionary):
		return true
	var nav_cost := GameConfig.ai_balance.get("nav_cost", {}) as Dictionary
	return bool(nav_cost.get("allow_room_graph_fallback_without_navmesh_only", true))


func _path_intersects_obstacle(from_pos: Vector2, path_points: Array[Vector2]) -> bool:
	if _service == null or not _service.has_method("path_intersects_navigation_obstacles"):
		return false
	return bool(_service.call("path_intersects_navigation_obstacles", from_pos, path_points))


func _build_detour_candidates(from_pos: Vector2, to_pos: Vector2, from_room: int, to_room: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var neighbors_from := get_neighbors(from_room)

	for mid in neighbors_from:
		if mid == to_room:
			continue
		if not is_adjacent(mid, to_room):
			continue
		var wp1 := get_door_center_between(from_room, mid, from_pos)
		var wp2 := get_door_center_between(mid, to_room, wp1)
		var pts: Array[Vector2] = [wp1, wp2, to_pos]
		result.append({
			"path_points": pts,
			"euclidean_length": _euclidean_path_length(from_pos, pts),
			"route_type": "1wp",
			"_sort_key": [mid],
		})

	if is_adjacent(from_room, to_room):
		var wp := get_door_center_between(from_room, to_room, from_pos)
		var pts_direct_neighbor: Array[Vector2] = [wp, to_pos]
		result.append({
			"path_points": pts_direct_neighbor,
			"euclidean_length": _euclidean_path_length(from_pos, pts_direct_neighbor),
			"route_type": "1wp",
			"_sort_key": [to_room],
		})

	for mid1 in neighbors_from:
		var neighbors_mid1 := get_neighbors(mid1)
		for mid2 in neighbors_mid1:
			if mid2 == from_room or mid2 == mid1 or mid2 == to_room:
				continue
			if not is_adjacent(mid2, to_room):
				continue
			var wp1 := get_door_center_between(from_room, mid1, from_pos)
			var wp2 := get_door_center_between(mid1, mid2, wp1)
			var wp3 := get_door_center_between(mid2, to_room, wp2)
			var pts_two_wp: Array[Vector2] = [wp1, wp2, wp3, to_pos]
			result.append({
				"path_points": pts_two_wp,
				"euclidean_length": _euclidean_path_length(from_pos, pts_two_wp),
				"route_type": "2wp",
				"_sort_key": [mid1, mid2],
			})

	var deduped: Array[Dictionary] = []
	for cand_variant in result:
		var cand := cand_variant as Dictionary
		var cand_points := _extract_path_points(cand.get("path_points", []))
		var duplicate := false
		for seen_variant in deduped:
			var seen := seen_variant as Dictionary
			var seen_points := _extract_path_points(seen.get("path_points", []))
			if cand_points.size() != seen_points.size():
				continue
			var same_points := true
			for i in range(cand_points.size()):
				var a := cand_points[i]
				var b := seen_points[i]
				if abs(a.x - b.x) >= 0.01 or abs(a.y - b.y) >= 0.01:
					same_points = false
					break
			if same_points:
				duplicate = true
				break
		if not duplicate:
			deduped.append(cand)
	result = deduped

	result.sort_custom(func(a_variant, b_variant):
		var a := a_variant as Dictionary
		var b := b_variant as Dictionary
		var len_a := float(a.get("euclidean_length", INF))
		var len_b := float(b.get("euclidean_length", INF))
		if not is_equal_approx(len_a, len_b):
			return len_a < len_b
		var key_a := a.get("_sort_key", []) as Array
		var key_b := b.get("_sort_key", []) as Array
		var key_count := mini(key_a.size(), key_b.size())
		for i in range(key_count):
			var part_a := int(key_a[i])
			var part_b := int(key_b[i])
			if part_a != part_b:
				return part_a < part_b
		if key_a.size() != key_b.size():
			return key_a.size() < key_b.size()
		var route_a := String(a.get("route_type", ""))
		var route_b := String(b.get("route_type", ""))
		if route_a != route_b:
			return route_a < route_b
		var pts_a := _extract_path_points(a.get("path_points", []))
		var pts_b := _extract_path_points(b.get("path_points", []))
		var point_count := mini(pts_a.size(), pts_b.size())
		for i in range(point_count):
			var pa := pts_a[i]
			var pb := pts_b[i]
			if not is_equal_approx(pa.x, pb.x):
				return pa.x < pb.x
			if not is_equal_approx(pa.y, pb.y):
				return pa.y < pb.y
		return pts_a.size() < pts_b.size()
	)
	return result


func _euclidean_path_length(from_pos: Vector2, path_points: Array[Vector2]) -> float:
	if path_points.is_empty():
		return 0.0
	var total: float = 0.0
	var prev := from_pos
	for p in path_points:
		total += prev.distance_to(p)
		prev = p
	return total


func _score_path_cost(path_points: Array[Vector2], from_pos: Vector2, cost_profile: Dictionary) -> float:
	if path_points.is_empty():
		return INF
	var shadow_weight := float(cost_profile.get("shadow_weight", 0.0))
	var sample_step := maxf(float(cost_profile.get("shadow_sample_step_px", NAV_COST_SHADOW_SAMPLE_STEP_PX)), 1.0)
	var total_len := 0.0
	var lit_count := 0
	var prev := from_pos
	for point in path_points:
		var seg_len := prev.distance_to(point)
		var steps := maxi(int(ceil(seg_len / sample_step)), 1)
		if shadow_weight > 0.0:
			for s in range(1, steps + 1):
				var sample := prev.lerp(point, float(s) / float(steps))
				if _service != null and _service.has_method("is_point_in_shadow"):
					if not bool(_service.call("is_point_in_shadow", sample)):
						lit_count += 1
		total_len += seg_len
		prev = point
	return total_len + shadow_weight * float(lit_count)


func nav_path_length(from_pos: Vector2, to_pos: Vector2, enemy: Node = null) -> float:
	var policy_plan := build_policy_valid_path(from_pos, to_pos, enemy)
	if String(policy_plan.get("status", "")) != "ok":
		return INF
	var path := _extract_path_points(policy_plan.get("path_points", []))
	if path.is_empty():
		return INF
	var total := 0.0
	var prev := from_pos
	for point in path:
		total += prev.distance_to(point)
		prev = point
	return total


func _validate_enemy_policy_path(enemy: Node, from_pos: Vector2, path_points: Array[Vector2]) -> Dictionary:
	if enemy == null:
		return {
			"valid": true,
			"segment_index": -1,
		}
	if _service and _service.has_method("validate_enemy_path_policy"):
		var validation_variant: Variant = _service.call(
			"validate_enemy_path_policy",
			enemy,
			from_pos,
			path_points,
			POLICY_SAMPLE_STEP_PX
		)
		if validation_variant is Dictionary:
			return validation_variant as Dictionary
	if _service and _service.has_method("can_enemy_traverse_shadow_policy_point"):
		var prev := from_pos
		for point in path_points:
			var segment_len := prev.distance_to(point)
			var steps := maxi(int(ceil(segment_len / POLICY_SAMPLE_STEP_PX)), 1)
			for step in range(1, steps + 1):
				var t := float(step) / float(steps)
				var sample := prev.lerp(point, t)
				if not bool(_service.call("can_enemy_traverse_shadow_policy_point", enemy, sample)):
					return {
						"valid": false,
						"segment_index": -1,
						"blocked_point": sample,
					}
			prev = point
	elif _service and _service.has_method("can_enemy_traverse_point"):
		var legacy_prev := from_pos
		for point in path_points:
			var segment_len := legacy_prev.distance_to(point)
			var steps := maxi(int(ceil(segment_len / POLICY_SAMPLE_STEP_PX)), 1)
			for step in range(1, steps + 1):
				var t := float(step) / float(steps)
				var sample := legacy_prev.lerp(point, t)
				if not bool(_service.call("can_enemy_traverse_point", enemy, sample)):
					return {
						"valid": false,
						"segment_index": -1,
						"blocked_point": sample,
					}
			legacy_prev = point
	return {
		"valid": true,
		"segment_index": -1,
	}


func _extract_path_points(points_variant: Variant) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if not (points_variant is Array):
		return out
	for point_variant in (points_variant as Array):
		out.append(point_variant as Vector2)
	return out
