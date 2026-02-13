## procedural_layout_v2.gd
## Fresh center-out room generator (flower growth) with post-geometry door carving.
class_name ProceduralLayoutV2
extends RefCounted

const V2_MAX_ATTEMPTS := 64
const DOOR_LEN := 50.0
const DOOR_ROOM_MIN_SPACING := 120.0
const SECOND_DOOR_CHANCE := 0.10
const ROOM_OVERHANG := 280.0
const CONTACT_MIN := 122.0
const CONTACT_EPS := 0.75
const WALK_GRID_CELL := 16.0
const WALK_CLEARANCE_RADIUS := 16.0
const MAX_UNREACHABLE_WALK_CELLS := 1
const PLAYER_SPAWN_NORTH_OFFSET := 100.0

const ROOM_TYPE_WEIGHTS := {"RECT": 0.40, "SQUARE": 0.20, "L": 0.20, "U": 0.20}
const ROOM_SMALL_MAX_SIDE := 200.0
const ROOM_MEDIUM_MIN_SIDE := 200.0
const ROOM_MEDIUM_MAX_SIDE := 400.0
const ROOM_LARGE_MIN_SIDE := 400.0
const ROOM_LARGE_MAX_SIDE := 600.0
const CLOSET_COUNT_MIN := 1
const CLOSET_COUNT_MAX := 4
const CLOSET_SIZE_MIN := 60.0
const CLOSET_SIZE_MAX := 70.0
const CLOSET_LONG_SIDE_FACTOR := 2.0
const CLOSET_LONG_SIZE_MIN := CLOSET_SIZE_MIN * CLOSET_LONG_SIDE_FACTOR
const CLOSET_LONG_SIZE_MAX := CLOSET_SIZE_MAX * CLOSET_LONG_SIDE_FACTOR
const CLOSET_CONTACT_MIN := 58.0
const OUTER_RUN_BREAK_MIN := 420.0
const OUTER_RUN_TARGET_PCT := 24.0
const OUTER_RUN_MAX_PASSES := 4
const MAX_OUTCROPS_PER_LAYOUT := 3
const OUTCROP_DEPTH_MIN := 110.0
const OUTCROP_DEPTH_MAX := 220.0
const OUTCROP_SPAN_MIN := 160.0
const OUTCROP_SPAN_MAX := 320.0
const ROOM_PLACEMENT_ATTEMPTS := 96
const MULTI_CONTACT_TARGET_RATIO := 0.28
const MULTI_CONTACT_TARGET_MAX := 3
const TARGET_MIN_EXTRA_LOOPS := 1
const CORE_ROOM_TARGET_RATIO := 0.42
const CORE_RADIUS_MIN := 520.0
const CORE_RADIUS_MAX := 700.0
const CORE_RADIUS_PER_ROOM := 16.0
const CORE_SPLIT_GIANT_AREA_MIN := 190000.0
const CORE_SPLIT_GIANT_SIDE_MIN := 520.0
const CORE_DOOR_DENSITY_TARGET_PCT := 58.0
const MICRO_GAP_BRIDGE_MAX := 5.0
const NORTH_GATE_MIN_WIDTH := 88.0
static var _cached_wall_white_tex: ImageTexture = null

var mission_index: int = 3
var room_generation_memory: Array = []
var room_type_preset_name: String = ""
var uses_color_fill: bool = true
var walkable_fill_color: Color = Color(0.58, 0.58, 0.58, 1.0)
var non_walkable_fill_color: Color = Color(0.0, 0.0, 0.0, 1.0)
var north_exit_rect: Rect2 = Rect2()

## Layout output (v2 autonomous contract)
var rooms: Array = []
var corridors: Array = []
var void_rects: Array = []
var doors: Array = []
var player_room_id: int = -1
var player_spawn_pos: Vector2 = Vector2.ZERO
var layout_seed: int = 0
var valid: bool = false

## Stats
var max_doors_stat: int = 0
var extra_loops: int = 0
var isolated_fixed: int = 0
var big_rooms_count: int = 0
var avg_degree: float = 0.0
var missing_adjacent_doors_stat: int = 0

## Internal state used by level/debug/tests
var _arena: Rect2 = Rect2()
var _cell_size: float = 8.0
var _split_segs: Array = []
var _wall_segs: Array = []
var _door_adj: Dictionary = {}
var _door_map: Array = []
var _logical_corr_count: int = 0
var _big_leaf_set: Array = []
var _hub_ids: Array = []
var _core_ids: Array = []
var _ring_ids: Array = []
var _low_priority_ids: Array = []
var _void_ids: Array = []
var _leaf_adj: Dictionary = {}
var layout_mode_name: String = ""
var _leaves: Array = []
var _l_room_ids: Array = []
var _l_room_notches: Array = []
var _perimeter_notches: Array = []
var _t_u_reserved_ids: Array = []
var _t_u_room_ids: Array = []
var _complex_shape_wall_segs: Array = []
var _interior_blocker_segs: Array = []
var _master_envelope_rects: Array = []
var _master_envelope_bounds: Rect2 = Rect2()
var _entry_gate: Rect2 = Rect2()
var walk_unreachable_cells_stat: int = 0
var main_path_turns_stat: int = 0
var main_path_edges_stat: int = 0
var main_path_straight_run_stat: int = 0
var pseudo_gap_count_stat: int = 0
var north_core_exit_fail_stat: int = 0
var outcrop_count_stat: int = 0
var outer_longest_run_pct_stat: float = 0.0
var validate_fail_reason: String = ""
var composition_fail_reason: String = ""
var generation_attempts_stat: int = 0
var _core_radius: float = 0.0
var _core_target_non_closet: int = 0


static func generate_and_build(arena_rect: Rect2, p_seed: int, walls_node: Node2D, debug_node: Node2D, player_node: Node2D, p_mission: int = 3) -> ProceduralLayoutV2:
	var layout := new()
	layout._arena = arena_rect
	layout.mission_index = p_mission

	for attempt in range(V2_MAX_ATTEMPTS):
		var attempt_seed := p_seed + attempt * 7919
		seed(attempt_seed)
		layout.layout_seed = attempt_seed
		layout.generation_attempts_stat = attempt + 1
		if layout._generate_v2_once():
			layout.valid = true
			break

	if layout.valid:
		layout._build_walls(walls_node)
		layout._recolor_walls_white(walls_node)
		layout._place_player(player_node)
		var game_config := _get_game_config_singleton()
		if game_config and bool(game_config.get("layout_debug_draw")):
			layout._build_debug(debug_node)
		else:
			layout._clear_node_children_detached(debug_node)
		print("[ProceduralLayoutV2] OK seed=%d mission=%d rooms=%d doors=%d loops=%d preset=%s attempts=%d" % [
			layout.layout_seed,
			layout.mission_index,
			layout.rooms.size(),
			layout.doors.size(),
			layout.extra_loops,
			layout.room_type_preset_name,
			layout.generation_attempts_stat,
		])
	else:
		print("[ProceduralLayoutV2][WARN] FAILED after %d attempts (seed=%d mission=%d)" % [
			V2_MAX_ATTEMPTS, p_seed, p_mission
		])

	return layout


func _recolor_walls_white(walls_node: Node2D) -> void:
	if not walls_node:
		return
	for child in walls_node.get_children():
		if child is CanvasItem:
			(child as CanvasItem).modulate = Color.WHITE


static func _get_game_config_singleton() -> Node:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null("/root/GameConfig")


func _generate_v2_once() -> bool:
	_reset_v2_state()
	layout_mode_name = "FLOWER_V2"

	var target_range := _mission_room_range(mission_index)
	var target_count := randi_range(int(target_range.x), int(target_range.y))
	if target_count < 3:
		target_count = 3

	var preset := ROOM_TYPE_WEIGHTS
	room_type_preset_name = "FIXED_40_20_20_20"
	var closets_target := _pick_closet_target(target_count)
	_configure_core_quota(target_count, closets_target)
	var closet_slots: Dictionary = {}
	var placeable_ids: Array = []
	for rid in range(1, target_count):
		placeable_ids.append(rid)
	placeable_ids.shuffle()
	for i in range(mini(closets_target, placeable_ids.size())):
		closet_slots[int(placeable_ids[i])] = true

	var center_type := _pick_center_room_type_equal()
	var center_shape := _build_room_shape(center_type, true)
	if center_shape.is_empty():
		return false

	var center_rects := _translate_shape_to_center(center_shape["rects"] as Array, _arena.get_center())
	var center_room := {
		"id": 0,
		"room_type": center_type,
		"rects": center_rects,
		"center": _area_weighted_center(center_rects),
		"is_corridor": false,
		"is_void": false,
	}
	rooms.append(center_room)
	_hub_ids = [0]
	_core_ids = [0]

	for rid in range(1, target_count):
		var forced_type := "CLOSET" if closet_slots.has(rid) else ""
		if not _place_next_room(rid, preset, forced_type):
			composition_fail_reason = "room_placement_failed"
			return false

	if _count_closet_rooms() != closets_target:
		composition_fail_reason = "closet_count_mismatch"
		return false

	if not _enforce_core_topology_compaction():
		composition_fail_reason = "core_quota_unmet"
		return false

	_apply_outer_run_outcrops()
	_collapse_micro_room_gaps()
	_rebuild_core_room_ids()

	var edges := _build_room_adjacency_edges()
	if edges.size() < rooms.size() - 1:
		composition_fail_reason = "disconnected_adjacency_graph"
		return false

	var multi_contact_rooms := _count_non_closet_rooms_with_min_adjacency(edges, 2)
	if multi_contact_rooms < _required_multi_contact_rooms():
		composition_fail_reason = "insufficient_multi_contact_rooms"
		return false

	if _count_non_closet_rooms_with_min_adjacency(edges, 3) < 1:
		composition_fail_reason = "missing_hub_room"
		return false

	if not _carve_doors_from_edges(edges):
		return false

	_compute_north_exit()
	if _entry_gate == Rect2():
		validate_fail_reason = "missing_north_exit"
		return false

	_find_player_room()
	_compute_v2_stats()
	_build_room_generation_memory(edges)
	return _validate_v2_basic(target_count)


func _reset_v2_state() -> void:
	rooms.clear()
	corridors.clear()
	void_rects.clear()
	_void_ids.clear()
	doors.clear()
	_door_adj.clear()
	_door_map.clear()
	_split_segs.clear()
	_wall_segs.clear()
	_leaves.clear()
	_leaf_adj.clear()
	_hub_ids.clear()
	_core_ids.clear()
	_ring_ids.clear()
	_low_priority_ids.clear()
	_l_room_ids.clear()
	_l_room_notches.clear()
	_perimeter_notches.clear()
	_t_u_reserved_ids.clear()
	_t_u_room_ids.clear()
	_complex_shape_wall_segs.clear()
	_interior_blocker_segs.clear()
	_master_envelope_rects.clear()
	_master_envelope_bounds = Rect2()
	_entry_gate = Rect2()
	north_exit_rect = Rect2()
	room_generation_memory.clear()
	validate_fail_reason = ""
	composition_fail_reason = ""
	valid = false
	player_room_id = -1
	player_spawn_pos = Vector2.ZERO
	layout_mode_name = ""
	max_doors_stat = 0
	avg_degree = 0.0
	extra_loops = 0
	isolated_fixed = 0
	big_rooms_count = 0
	missing_adjacent_doors_stat = 0
	pseudo_gap_count_stat = 0
	main_path_edges_stat = 0
	main_path_turns_stat = 0
	main_path_straight_run_stat = 0
	walk_unreachable_cells_stat = 0
	outer_longest_run_pct_stat = 0.0
	_core_radius = 0.0
	_core_target_non_closet = 0


func _mission_room_range(mission_id: int) -> Vector2i:
	match mission_id:
		1:
			return Vector2i(3, 4)
		2:
			return Vector2i(5, 8)
		_:
			return Vector2i(9, 14)


func _pick_center_room_type_equal() -> String:
	var roll := randi() % 4
	match roll:
		0:
			return "RECT"
		1:
			return "SQUARE"
		2:
			return "L"
		_:
			return "U"


func _pick_room_type_weighted(weights: Dictionary) -> String:
	var roll := randf()
	var acc := 0.0
	for key in ["RECT", "SQUARE", "L", "U"]:
		acc += float(weights.get(key, 0.0))
		if roll <= acc:
			return key
	return "RECT"


func _pick_closet_target(total_rooms: int) -> int:
	var max_allowed := mini(CLOSET_COUNT_MAX, maxi(1, total_rooms - 1))
	var min_allowed := mini(CLOSET_COUNT_MIN, max_allowed)
	return randi_range(min_allowed, max_allowed)


func _configure_core_quota(total_rooms: int, closets_target: int) -> void:
	var non_closet_target := maxi(total_rooms - closets_target, 1)
	_core_radius = clampf(420.0 + float(total_rooms) * CORE_RADIUS_PER_ROOM, CORE_RADIUS_MIN, CORE_RADIUS_MAX)
	if non_closet_target <= 2:
		_core_target_non_closet = non_closet_target
		return
	var scaled := int(round(float(non_closet_target) * CORE_ROOM_TARGET_RATIO))
	_core_target_non_closet = clampi(scaled, 2, mini(non_closet_target, 6))


func _is_point_in_core_radius(point: Vector2) -> bool:
	if _core_radius <= 1.0:
		return false
	return point.distance_to(_arena.get_center()) <= _core_radius


func _is_room_in_core_radius(room_id: int) -> bool:
	if room_id < 0 or room_id >= rooms.size():
		return false
	if room_id in _void_ids:
		return false
	var center := rooms[room_id]["center"] as Vector2
	return _is_point_in_core_radius(center)


func _rebuild_core_room_ids() -> void:
	_core_ids.clear()
	for room_id in range(rooms.size()):
		if room_id in _void_ids:
			continue
		if _is_room_in_core_radius(room_id):
			_core_ids.append(room_id)
	if _core_ids.is_empty() and not rooms.is_empty():
		_core_ids.append(0)


func _core_non_closet_ids() -> Array:
	var ids: Array = []
	for rid_variant in _core_ids:
		var rid := int(rid_variant)
		if rid < 0 or rid >= rooms.size():
			continue
		if _is_closet_room(rid):
			continue
		ids.append(rid)
	return ids


func _count_core_non_closet_rooms() -> int:
	var count := 0
	for room_id in range(rooms.size()):
		if room_id in _void_ids:
			continue
		if _is_closet_room(room_id):
			continue
		if _is_room_in_core_radius(room_id):
			count += 1
	return count


func _needs_more_core_non_closet_rooms() -> bool:
	return _count_core_non_closet_rooms() < _core_target_non_closet


func _enforce_core_topology_compaction() -> bool:
	_rebuild_core_room_ids()
	_split_central_giant_once()
	_rebuild_core_room_ids()
	if not _needs_more_core_non_closet_rooms():
		return true

	var candidates := _outer_non_closet_room_ids_sorted()
	for rid_variant in candidates:
		if not _needs_more_core_non_closet_rooms():
			break
		var rid := int(rid_variant)
		if _try_relocate_room_to_core(rid):
			_rebuild_core_room_ids()
	return not _needs_more_core_non_closet_rooms()


func _pick_central_giant_room_id() -> int:
	var best_id := -1
	var best_score := -INF
	for rid in range(rooms.size()):
		if rid in _void_ids:
			continue
		if _is_closet_room(rid):
			continue
		if not _is_room_in_core_radius(rid):
			continue
		var bbox := _room_bounding_box(rid)
		var area := bbox.get_area()
		var max_side := maxf(bbox.size.x, bbox.size.y)
		if area < CORE_SPLIT_GIANT_AREA_MIN or max_side < CORE_SPLIT_GIANT_SIDE_MIN:
			continue
		var dist := bbox.get_center().distance_to(_arena.get_center())
		var score := area - dist * 220.0
		if score > best_score:
			best_score = score
			best_id = rid
	return best_id


func _split_central_giant_once() -> void:
	var giant_id := _pick_central_giant_room_id()
	if giant_id < 0:
		return

	var edges := _build_room_adjacency_edges()
	var giant_non_closet_contacts := 0
	for edge_variant in edges:
		var edge := edge_variant as Dictionary
		var a := int(edge["a"])
		var b := int(edge["b"])
		if a != giant_id and b != giant_id:
			continue
		var other := b if a == giant_id else a
		if _is_closet_room(other):
			continue
		giant_non_closet_contacts += 1
	if giant_non_closet_contacts >= 3:
		return

	var candidates := _outer_non_closet_room_ids_sorted()
	for rid_variant in candidates:
		var rid := int(rid_variant)
		if rid == giant_id:
			continue
		if _try_relocate_room_to_core(rid, giant_id):
			return


func _outer_non_closet_room_ids_sorted() -> Array:
	var ids: Array = []
	var center := _arena.get_center()
	for rid in range(rooms.size()):
		if rid in _void_ids:
			continue
		if _is_closet_room(rid):
			continue
		if _is_room_in_core_radius(rid):
			continue
		ids.append(rid)
	ids.sort_custom(func(a, b):
		var da := (rooms[int(a)]["center"] as Vector2).distance_to(center)
		var db := (rooms[int(b)]["center"] as Vector2).distance_to(center)
		return da > db
	)
	return ids


func _try_relocate_room_to_core(room_id: int, preferred_anchor_id: int = -1) -> bool:
	if room_id < 0 or room_id >= rooms.size():
		return false
	if room_id in _void_ids:
		return false
	if _is_closet_room(room_id):
		return false
	var original_rects := rooms[room_id]["rects"] as Array
	var local_rects := _normalize_rects_to_origin(original_rects)
	var local_bbox := _bbox_from_rects(local_rects)
	if local_bbox == Rect2():
		return false

	var anchors: Array = []
	if preferred_anchor_id >= 0 and preferred_anchor_id < rooms.size() and preferred_anchor_id != room_id:
		if not _is_closet_room(preferred_anchor_id):
			anchors.append(preferred_anchor_id)
	for core_id_variant in _core_non_closet_ids():
		var core_id := int(core_id_variant)
		if core_id == room_id:
			continue
		if core_id in anchors:
			continue
		anchors.append(core_id)
	if anchors.is_empty():
		anchors = [0]

	for anchor_variant in anchors:
		var anchor_id := int(anchor_variant)
		if anchor_id < 0 or anchor_id >= rooms.size() or anchor_id == room_id:
			continue
		var anchor_bbox := _room_bounding_box(anchor_id)
		var sides: Array[String] = ["N", "S", "E", "W"]
		sides.shuffle()
		for side in sides:
			var placed_rects := _dock_shape_to_side(local_rects, local_bbox, anchor_bbox, side, CONTACT_MIN)
			if placed_rects.is_empty():
				continue
			if not _rects_within_generation_bounds(placed_rects):
				continue
			if _overlaps_existing_rooms_excluding(room_id, placed_rects):
				continue
			var candidate_center := _area_weighted_center(placed_rects)
			if not _is_point_in_core_radius(candidate_center):
				continue
			var contact_ids := _contact_room_ids_for_rects_excluding(placed_rects, CONTACT_MIN, room_id)
			if contact_ids.is_empty():
				continue
			rooms[room_id]["rects"] = placed_rects
			rooms[room_id]["center"] = candidate_center
			return true
	return false


func _normalize_rects_to_origin(rects: Array) -> Array:
	var bbox := _bbox_from_rects(rects)
	var out: Array = []
	for rect_variant in rects:
		var r := rect_variant as Rect2
		out.append(Rect2(r.position - bbox.position, r.size))
	return out


func _overlaps_existing_rooms_excluding(skip_room_id: int, candidate_rects: Array) -> bool:
	for rid in range(rooms.size()):
		if rid == skip_room_id:
			continue
		for ex_variant in (rooms[rid]["rects"] as Array):
			var ex := ex_variant as Rect2
			for cand_variant in candidate_rects:
				var c := cand_variant as Rect2
				if c.grow(-2.0).intersects(ex.grow(-2.0)):
					return true
	return false


func _contact_room_ids_for_rects_excluding(candidate_rects: Array, min_contact: float, skip_room_id: int) -> Array:
	var ids: Array = []
	for rid in range(rooms.size()):
		if rid == skip_room_id:
			continue
		if _contact_span_with_room(rid, candidate_rects) >= min_contact - CONTACT_EPS:
			ids.append(rid)
	return ids


func _collapse_micro_room_gaps() -> void:
	var changed := true
	var guard := 0
	while changed and guard < 24:
		changed = false
		guard += 1
		for a in range(rooms.size()):
			if a in _void_ids:
				continue
			for b in range(a + 1, rooms.size()):
				if b in _void_ids:
					continue
				if _try_bridge_micro_gap_pair(a, b):
					changed = true
					break
			if changed:
				break


func _try_bridge_micro_gap_pair(a: int, b: int) -> bool:
	if a < 0 or b < 0 or a >= rooms.size() or b >= rooms.size():
		return false
	var min_span := _min_adjacency_span_for_pair(a, b) - CONTACT_EPS
	var rects_a := rooms[a]["rects"] as Array
	var rects_b := rooms[b]["rects"] as Array
	for ai in range(rects_a.size()):
		var ra := rects_a[ai] as Rect2
		for bi in range(rects_b.size()):
			var rb := rects_b[bi] as Rect2
			var y0 := maxf(ra.position.y, rb.position.y)
			var y1 := minf(ra.end.y, rb.end.y)
			var y_span := y1 - y0
			var x0 := maxf(ra.position.x, rb.position.x)
			var x1 := minf(ra.end.x, rb.end.x)
			var x_span := x1 - x0

			var gap_lr := rb.position.x - ra.end.x
			if gap_lr > CONTACT_EPS and gap_lr <= MICRO_GAP_BRIDGE_MAX and y_span >= min_span:
				if _try_expand_room_rect_to_gap(a, ai, "RIGHT", gap_lr, b):
					return true
				if _try_expand_room_rect_to_gap(b, bi, "LEFT", gap_lr, a):
					return true

			var gap_rl := ra.position.x - rb.end.x
			if gap_rl > CONTACT_EPS and gap_rl <= MICRO_GAP_BRIDGE_MAX and y_span >= min_span:
				if _try_expand_room_rect_to_gap(b, bi, "RIGHT", gap_rl, a):
					return true
				if _try_expand_room_rect_to_gap(a, ai, "LEFT", gap_rl, b):
					return true

			var gap_tb := rb.position.y - ra.end.y
			if gap_tb > CONTACT_EPS and gap_tb <= MICRO_GAP_BRIDGE_MAX and x_span >= min_span:
				if _try_expand_room_rect_to_gap(a, ai, "DOWN", gap_tb, b):
					return true
				if _try_expand_room_rect_to_gap(b, bi, "UP", gap_tb, a):
					return true

			var gap_bt := ra.position.y - rb.end.y
			if gap_bt > CONTACT_EPS and gap_bt <= MICRO_GAP_BRIDGE_MAX and x_span >= min_span:
				if _try_expand_room_rect_to_gap(b, bi, "DOWN", gap_bt, a):
					return true
				if _try_expand_room_rect_to_gap(a, ai, "UP", gap_bt, b):
					return true
	return false


func _try_expand_room_rect_to_gap(room_id: int, rect_idx: int, dir: String, amount: float, other_room_id: int) -> bool:
	if amount <= CONTACT_EPS:
		return false
	if room_id < 0 or room_id >= rooms.size():
		return false
	var rects := rooms[room_id]["rects"] as Array
	if rect_idx < 0 or rect_idx >= rects.size():
		return false
	var old := rects[rect_idx] as Rect2
	var expanded := old
	match dir:
		"RIGHT":
			expanded = Rect2(old.position, Vector2(old.size.x + amount, old.size.y))
		"LEFT":
			expanded = Rect2(old.position - Vector2(amount, 0.0), Vector2(old.size.x + amount, old.size.y))
		"DOWN":
			expanded = Rect2(old.position, Vector2(old.size.x, old.size.y + amount))
		"UP":
			expanded = Rect2(old.position - Vector2(0.0, amount), Vector2(old.size.x, old.size.y + amount))
		_:
			return false
	if not _arena.grow(ROOM_OVERHANG).encloses(expanded):
		return false
	if _expanded_rect_hits_other_rooms(room_id, rect_idx, expanded, other_room_id):
		return false
	rects[rect_idx] = expanded
	rooms[room_id]["rects"] = rects
	rooms[room_id]["center"] = _area_weighted_center(rects)
	return true


func _expanded_rect_hits_other_rooms(room_id: int, rect_idx: int, expanded: Rect2, other_room_id: int) -> bool:
	for rid in range(rooms.size()):
		if rid in _void_ids:
			continue
		for other_idx in range((rooms[rid]["rects"] as Array).size()):
			if rid == room_id and other_idx == rect_idx:
				continue
			if rid == room_id:
				continue
			var ex := ((rooms[rid]["rects"] as Array)[other_idx]) as Rect2
			if rid == other_room_id:
				if expanded.grow(-1.5).intersects(ex.grow(-1.5)):
					return true
			elif expanded.grow(-1.5).intersects(ex.grow(-1.5)):
				return true
	return false


func _build_room_shape(room_type: String, is_center: bool) -> Dictionary:
	match room_type:
		"RECT":
			return _build_rect_shape(is_center)
		"SQUARE":
			return _build_square_shape(is_center)
		"L":
			return _build_l_shape_l1(is_center)
		"U":
			return _build_u_shape_u1(is_center)
		"CLOSET":
			return _build_closet_shape()
	return {}


func _build_rect_shape(is_center: bool) -> Dictionary:
	var w := _pick_span_for_room_class(is_center)
	var h := _pick_span_for_room_class(is_center)
	# Keep rects readable as rooms, avoid accidental corridor-like strips.
	if maxf(w, h) / maxf(minf(w, h), 1.0) > 2.2:
		h = clampf(w * randf_range(0.6, 1.4), ROOM_MEDIUM_MIN_SIDE * 0.85, ROOM_LARGE_MAX_SIDE)
	if randf() < 0.5:
		var t := w
		w = h
		h = t
	return {"type": "RECT", "rects": [Rect2(0.0, 0.0, w, h)]}


func _build_square_shape(is_center: bool) -> Dictionary:
	var s := _pick_span_for_room_class(is_center)
	s = clampf(s, ROOM_MEDIUM_MIN_SIDE, ROOM_LARGE_MAX_SIDE)
	return {"type": "SQUARE", "rects": [Rect2(0.0, 0.0, s, s)]}


func _pick_span_for_room_class(is_center: bool) -> float:
	var roll := randf()
	if is_center:
		# Center room should not be tiny.
		if roll < 0.55:
			return randf_range(ROOM_MEDIUM_MIN_SIDE + 20.0, ROOM_MEDIUM_MAX_SIDE - 10.0)
		return randf_range(ROOM_LARGE_MIN_SIDE, ROOM_LARGE_MAX_SIDE - 20.0)
	# Non-center distribution: mostly medium/large, rare small.
	if roll < 0.15:
		return randf_range(160.0, ROOM_SMALL_MAX_SIDE)
	if roll < 0.70:
		return randf_range(ROOM_MEDIUM_MIN_SIDE, ROOM_MEDIUM_MAX_SIDE)
	return randf_range(ROOM_LARGE_MIN_SIDE, ROOM_LARGE_MAX_SIDE)


func _build_closet_shape() -> Dictionary:
	var short_side := randf_range(CLOSET_SIZE_MIN, CLOSET_SIZE_MAX)
	var long_side := short_side * CLOSET_LONG_SIDE_FACTOR
	var horizontal := randf() < 0.5
	var w := long_side if horizontal else short_side
	var h := short_side if horizontal else long_side
	return {"type": "CLOSET", "rects": [Rect2(0.0, 0.0, w, h)]}


func _build_l_shape_l1(is_center: bool) -> Dictionary:
	var w := randf_range(320.0, 560.0) if is_center else randf_range(300.0, 520.0)
	var h := w * randf_range(0.8, 1.25)
	h = clampf(h, 300.0, 560.0 if is_center else 520.0)
	var tmax := minf(w, h) * 0.45
	var thickness := randf_range(128.0, maxf(148.0, tmax))
	if thickness >= minf(w, h) - 40.0:
		return {}
	var corner := randi() % 4
	var rects: Array = []
	match corner:
		0:  # NW
			rects = [Rect2(0.0, 0.0, thickness, h), Rect2(thickness, 0.0, w - thickness, thickness)]
		1:  # NE
			rects = [Rect2(w - thickness, 0.0, thickness, h), Rect2(0.0, 0.0, w - thickness, thickness)]
		2:  # SW
			rects = [Rect2(0.0, 0.0, thickness, h), Rect2(thickness, h - thickness, w - thickness, thickness)]
		_:
			rects = [Rect2(w - thickness, 0.0, thickness, h), Rect2(0.0, h - thickness, w - thickness, thickness)]
	return {"type": "L", "rects": rects}


func _build_u_shape_u1(is_center: bool) -> Dictionary:
	const U_MIN_THICKNESS := 128.0
	var cavity_w := randf_range(110.0, 230.0)
	var cavity_d := randf_range(120.0, 260.0)
	var leg_t := randf_range(U_MIN_THICKNESS, 190.0)
	var bridge_t := randf_range(U_MIN_THICKNESS, 190.0)
	var orientation := randi() % 4
	var rects: Array = []
	match orientation:
		0:  # open top
			var total_w := cavity_w + leg_t * 2.0
			var total_h := cavity_d + bridge_t
			rects = [
				Rect2(0.0, 0.0, leg_t, total_h),
				Rect2(total_w - leg_t, 0.0, leg_t, total_h),
				Rect2(leg_t, total_h - bridge_t, cavity_w, bridge_t),
			]
		1:  # open bottom
			var total_w := cavity_w + leg_t * 2.0
			var total_h := cavity_d + bridge_t
			rects = [
				Rect2(0.0, 0.0, leg_t, total_h),
				Rect2(total_w - leg_t, 0.0, leg_t, total_h),
				Rect2(leg_t, 0.0, cavity_w, bridge_t),
			]
		2:  # open left
			var total_w := cavity_w + bridge_t
			var total_h := cavity_d + leg_t * 2.0
			rects = [
				Rect2(0.0, 0.0, total_w, leg_t),
				Rect2(0.0, total_h - leg_t, total_w, leg_t),
				Rect2(total_w - bridge_t, leg_t, bridge_t, cavity_d),
			]
		_:  # open right
			var total_w := cavity_w + bridge_t
			var total_h := cavity_d + leg_t * 2.0
			rects = [
				Rect2(0.0, 0.0, total_w, leg_t),
				Rect2(0.0, total_h - leg_t, total_w, leg_t),
				Rect2(0.0, leg_t, bridge_t, cavity_d),
			]
	var bbox := _bbox_from_rects(rects)
	if bbox == Rect2():
		return {}
	var min_side := 340.0 if is_center else 300.0
	var max_side := 640.0 if is_center else 600.0
	if bbox.size.x < min_side or bbox.size.y < min_side:
		var sx := maxf(min_side / maxf(bbox.size.x, 1.0), 1.0)
		var sy := maxf(min_side / maxf(bbox.size.y, 1.0), 1.0)
		var s := minf(maxf(sx, sy), max_side / maxf(maxf(bbox.size.x, bbox.size.y), 1.0))
		var scaled: Array = []
		for rect_variant in rects:
			var r := rect_variant as Rect2
			scaled.append(Rect2(r.position * s, r.size * s))
		rects = scaled
		bbox = _bbox_from_rects(rects)
	if bbox.size.x > max_side or bbox.size.y > max_side:
		var s2 := minf(max_side / maxf(bbox.size.x, 1.0), max_side / maxf(bbox.size.y, 1.0))
		var scaled2: Array = []
		for rect_variant in rects:
			var r2 := rect_variant as Rect2
			scaled2.append(Rect2(r2.position * s2, r2.size * s2))
		rects = scaled2
	for rect_variant in rects:
		var r3 := rect_variant as Rect2
		if minf(r3.size.x, r3.size.y) < U_MIN_THICKNESS:
			return {}
	return {"type": "U", "rects": rects}


func _translate_shape_to_center(rects: Array, center: Vector2) -> Array:
	var bbox := _bbox_from_rects(rects)
	var delta := center - bbox.get_center()
	var out: Array = []
	for rect_variant in rects:
		var r := rect_variant as Rect2
		out.append(Rect2(r.position + delta, r.size))
	return out


func _place_next_room(room_id: int, weights: Dictionary, forced_room_type: String = "") -> bool:
	var best: Dictionary = {}
	var best_score := -INF
	var prefer_core_anchor := forced_room_type != "CLOSET" and _needs_more_core_non_closet_rooms()
	for _attempt in range(ROOM_PLACEMENT_ATTEMPTS):
		var room_type := forced_room_type if forced_room_type != "" else _pick_room_type_weighted(weights)
		var shape := _build_room_shape(room_type, false)
		if shape.is_empty():
			continue
		var local_rects: Array = shape["rects"] as Array
		var local_bbox := _bbox_from_rects(local_rects)
		if local_bbox == Rect2():
			continue
		var required_contact := _contact_min_for_room_type(room_type)

		var anchor_candidates := _anchor_candidates_for_room_type(room_type, prefer_core_anchor)
		if anchor_candidates.is_empty():
			continue

		var anchor_id := int(anchor_candidates[randi() % anchor_candidates.size()])
		var anchor_bbox := _room_bounding_box(anchor_id)
		var side_options: Array[String] = ["E", "W", "N", "S"]
		var side: String = side_options[randi() % side_options.size()]
		var placed_rects := _dock_shape_to_side(local_rects, local_bbox, anchor_bbox, side, required_contact)
		if placed_rects.is_empty():
			continue
		if not _rects_within_generation_bounds(placed_rects):
			continue
		if _overlaps_existing_rooms(placed_rects):
			continue

		var contact_len := _contact_span_with_room(anchor_id, placed_rects)
		if contact_len < required_contact - CONTACT_EPS:
			continue
		var contact_ids := _contact_room_ids_for_rects(placed_rects, required_contact)
		var contact_count := contact_ids.size()
		var require_multi_contact := room_type != "CLOSET" and (prefer_core_anchor or room_id >= 5 or _should_force_multi_contact_for_room(room_id, room_type))
		if room_type == "CLOSET":
			if contact_count != 1:
				continue
		else:
			if contact_count < 1:
				continue
			if require_multi_contact and _attempt < int(ROOM_PLACEMENT_ATTEMPTS * 0.85) and contact_count < 2:
				continue

		var candidate_bbox := _bbox_from_rects(placed_rects)
		var in_core := _is_point_in_core_radius(candidate_bbox.get_center())
		var score := _placement_score(anchor_bbox, candidate_bbox, side, room_type, in_core, prefer_core_anchor)
		if room_type != "CLOSET":
			score += float(maxi(contact_count - 1, 0)) * 1.15
			if contact_count == 1 and room_id >= 8:
				score -= 0.55
		if score > best_score:
			best_score = score
			best = {
				"type": room_type,
				"rects": placed_rects,
			}
	if best.is_empty():
		return false

	var rects := best["rects"] as Array
	rooms.append({
		"id": room_id,
		"room_type": best["type"] as String,
		"rects": rects,
		"center": _area_weighted_center(rects),
		"is_corridor": false,
		"is_void": false,
	})
	return true


func _anchor_candidates_for_room_type(room_type: String, prefer_core: bool) -> Array:
	var all_ids: Array = []
	var core_ids: Array = []
	for idx in range(rooms.size()):
		if room_type != "CLOSET" and _is_closet_room(idx):
			continue
		all_ids.append(idx)
		if prefer_core and _is_room_in_core_radius(idx):
			core_ids.append(idx)
	if prefer_core and not core_ids.is_empty():
		core_ids.shuffle()
		return core_ids
	return all_ids


func _contact_min_for_room_type(room_type: String) -> float:
	return CLOSET_CONTACT_MIN if room_type == "CLOSET" else CONTACT_MIN


func _should_force_multi_contact_for_room(room_id: int, room_type: String) -> bool:
	if room_type == "CLOSET":
		return false
	if room_id < 6:
		return false
	if room_type == "L" or room_type == "U":
		return true
	return room_id % 4 == 0


func _dock_shape_to_side(local_rects: Array, local_bbox: Rect2, anchor_bbox: Rect2, side: String, min_contact: float = CONTACT_MIN) -> Array:
	var overlap := 0.0
	var tx := 0.0
	var ty := 0.0
	if side == "E" or side == "W":
		overlap = clampf(minf(anchor_bbox.size.y, local_bbox.size.y) * randf_range(0.45, 0.82), min_contact, minf(anchor_bbox.size.y, local_bbox.size.y) - 2.0)
		if overlap < min_contact:
			return []
		var ay0 := randf_range(anchor_bbox.position.y, anchor_bbox.end.y - overlap)
		var ly0 := randf_range(local_bbox.position.y, local_bbox.end.y - overlap)
		ty = ay0 - ly0
		if side == "E":
			tx = anchor_bbox.end.x - local_bbox.position.x
		else:
			tx = anchor_bbox.position.x - local_bbox.end.x
	else:
		overlap = clampf(minf(anchor_bbox.size.x, local_bbox.size.x) * randf_range(0.45, 0.82), min_contact, minf(anchor_bbox.size.x, local_bbox.size.x) - 2.0)
		if overlap < min_contact:
			return []
		var ax0 := randf_range(anchor_bbox.position.x, anchor_bbox.end.x - overlap)
		var lx0 := randf_range(local_bbox.position.x, local_bbox.end.x - overlap)
		tx = ax0 - lx0
		if side == "S":
			ty = anchor_bbox.end.y - local_bbox.position.y
		else:
			ty = anchor_bbox.position.y - local_bbox.end.y

	var out: Array = []
	for rect_variant in local_rects:
		var r := rect_variant as Rect2
		out.append(Rect2(r.position + Vector2(tx, ty), r.size))
	return out


func _count_contacts_for_rects(candidate_rects: Array, min_contact: float) -> int:
	return _contact_room_ids_for_rects(candidate_rects, min_contact).size()


func _contact_room_ids_for_rects(candidate_rects: Array, min_contact: float) -> Array:
	var ids: Array = []
	for rid in range(rooms.size()):
		if _contact_span_with_room(rid, candidate_rects) >= min_contact - CONTACT_EPS:
			ids.append(rid)
	return ids


func _rects_within_generation_bounds(rects: Array) -> bool:
	var bounds := _arena.grow(ROOM_OVERHANG)
	for rect_variant in rects:
		var r := rect_variant as Rect2
		if not bounds.encloses(r):
			return false
	return true


func _overlaps_existing_rooms(candidate_rects: Array) -> bool:
	for room in rooms:
		for ex_variant in (room["rects"] as Array):
			var ex := ex_variant as Rect2
			for cand_variant in candidate_rects:
				var c := cand_variant as Rect2
				if c.grow(-2.0).intersects(ex.grow(-2.0)):
					return true
	return false


func _contact_span_with_room(room_id: int, rects: Array) -> float:
	var best := 0.0
	for ex_variant in (rooms[room_id]["rects"] as Array):
		var a := ex_variant as Rect2
		for cand_variant in rects:
			var b := cand_variant as Rect2
			if absf(a.end.x - b.position.x) < 1.0 or absf(b.end.x - a.position.x) < 1.0:
				best = maxf(best, minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y))
			if absf(a.end.y - b.position.y) < 1.0 or absf(b.end.y - a.position.y) < 1.0:
				best = maxf(best, minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x))
	return best


func _placement_score(anchor_bbox: Rect2, candidate_bbox: Rect2, side: String, room_type: String, in_core: bool, prefer_core_anchor: bool) -> float:
	var cdist := candidate_bbox.get_center().distance_to(_arena.get_center())
	var score := cdist * 0.01 + randf() * 0.3
	if side == "E" or side == "W":
		if absf(candidate_bbox.size.x - anchor_bbox.size.x) < 18.0:
			score -= 0.7
	else:
		if absf(candidate_bbox.size.y - anchor_bbox.size.y) < 18.0:
			score -= 0.7
	var combined := _compute_solid_bbox().merge(candidate_bbox) if not rooms.is_empty() else candidate_bbox
	var aspect := combined.size.x / maxf(combined.size.y, 1.0)
	if aspect > 1.9 or aspect < 0.53:
		score -= 0.5
	if room_type != "CLOSET":
		if prefer_core_anchor:
			score += 5.5 if in_core else -5.5
		elif in_core:
			score += 0.35
	return score


func _build_room_adjacency_edges() -> Array:
	var edges: Array = []
	var best_by_key: Dictionary = {}
	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			var edge := _best_shared_edge_between(i, j, _min_adjacency_span_for_pair(i, j))
			if edge.is_empty():
				continue
			var key := "%d:%d" % [i, j]
			best_by_key[key] = edge
	for key in best_by_key.keys():
		edges.append(best_by_key[key])
	return edges


func _required_multi_contact_rooms() -> int:
	var non_closet_count := maxi(rooms.size() - _count_closet_rooms(), 0)
	if non_closet_count <= 0:
		return 0
	var scaled := int(floor(float(non_closet_count) * MULTI_CONTACT_TARGET_RATIO))
	var required := maxi(1, scaled)
	return mini(required, MULTI_CONTACT_TARGET_MAX)


func _count_non_closet_rooms_with_min_adjacency(edges: Array, min_degree: int) -> int:
	var neighbors: Dictionary = {}
	for i in range(rooms.size()):
		neighbors[i] = {}
	for edge_variant in edges:
		var edge := edge_variant as Dictionary
		var a := int(edge["a"])
		var b := int(edge["b"])
		(neighbors[a] as Dictionary)[b] = true
		(neighbors[b] as Dictionary)[a] = true

	var count := 0
	for i in range(rooms.size()):
		if i in _void_ids:
			continue
		if _is_closet_room(i):
			continue
		if (neighbors[i] as Dictionary).size() >= min_degree:
			count += 1
	return count


func _contact_min_for_pair(a: int, b: int) -> float:
	return CLOSET_CONTACT_MIN if _is_closet_room(a) or _is_closet_room(b) else CONTACT_MIN


func _min_adjacency_span_for_pair(a: int, b: int) -> float:
	var base := _contact_min_for_pair(a, b)
	var required_for_door := _door_opening_len() + _door_margin_for_pair(a, b) * 2.0
	return maxf(base, required_for_door)


func _best_shared_edge_between(a: int, b: int, min_span: float) -> Dictionary:
	var best := {}
	var best_span := 0.0
	for ra_variant in (rooms[a]["rects"] as Array):
		var ra := ra_variant as Rect2
		for rb_variant in (rooms[b]["rects"] as Array):
			var rb := rb_variant as Rect2
			if absf(ra.end.x - rb.position.x) < 1.0:
				var y0 := maxf(ra.position.y, rb.position.y)
				var y1 := minf(ra.end.y, rb.end.y)
				var span := y1 - y0
				if span > best_span and span >= min_span - CONTACT_EPS:
					best_span = span
					best = {"a": a, "b": b, "type": "V", "pos": ra.end.x, "t0": y0, "t1": y1}
			elif absf(rb.end.x - ra.position.x) < 1.0:
				var y0b := maxf(ra.position.y, rb.position.y)
				var y1b := minf(ra.end.y, rb.end.y)
				var spanb := y1b - y0b
				if spanb > best_span and spanb >= min_span - CONTACT_EPS:
					best_span = spanb
					best = {"a": a, "b": b, "type": "V", "pos": rb.end.x, "t0": y0b, "t1": y1b}
			if absf(ra.end.y - rb.position.y) < 1.0:
				var x0 := maxf(ra.position.x, rb.position.x)
				var x1 := minf(ra.end.x, rb.end.x)
				var span2 := x1 - x0
				if span2 > best_span and span2 >= min_span - CONTACT_EPS:
					best_span = span2
					best = {"a": a, "b": b, "type": "H", "pos": ra.end.y, "t0": x0, "t1": x1}
			elif absf(rb.end.y - ra.position.y) < 1.0:
				var x0b := maxf(ra.position.x, rb.position.x)
				var x1b := minf(ra.end.x, rb.end.x)
				var span2b := x1b - x0b
				if span2b > best_span and span2b >= min_span - CONTACT_EPS:
					best_span = span2b
					best = {"a": a, "b": b, "type": "H", "pos": rb.end.y, "t0": x0b, "t1": x1b}
	return best


func _carve_doors_from_edges(edges: Array) -> bool:
	for i in range(rooms.size()):
		_door_adj[i] = []

	var door_centers: Dictionary = {}
	for i in range(rooms.size()):
		door_centers[i] = []

	var edge_by_key: Dictionary = {}
	for edge_variant in edges:
		var edge := edge_variant as Dictionary
		edge_by_key[_edge_key(edge)] = edge

	var used_edge_keys: Dictionary = {}
	var visited: Dictionary = {0: true}
	while visited.size() < rooms.size():
		var frontier: Array = []
		for edge_variant in edges:
			var edge := edge_variant as Dictionary
			var a := int(edge["a"])
			var b := int(edge["b"])
			var va := visited.has(a)
			var vb := visited.has(b)
			if va == vb:
				continue
			frontier.append(edge)
		if frontier.is_empty():
			validate_fail_reason = "tree_disconnected"
			return false
		frontier.sort_custom(func(x, y):
			var sx := float(x["t1"]) - float(x["t0"])
			var sy := float(y["t1"]) - float(y["t0"])
			if absf(sx - sy) > 0.1:
				return sx > sy
			var xa := mini(int(x["a"]), int(x["b"]))
			var xb := mini(int(y["a"]), int(y["b"]))
			if xa != xb:
				return xa < xb
			var ya := maxi(int(x["a"]), int(x["b"]))
			var yb := maxi(int(y["a"]), int(y["b"]))
			return ya < yb
		)

		var linked := false
		for edge_variant in frontier:
			var edge := edge_variant as Dictionary
			var a := int(edge["a"])
			var b := int(edge["b"])
			if not _can_add_door_between(a, b):
				continue
			var door := _door_for_edge(edge, door_centers)
			if door == Rect2():
				continue
			doors.append(door)
			_register_door_connection(a, b, door)
			used_edge_keys[_edge_key(edge)] = true
			visited[a] = true
			visited[b] = true
			linked = true
			break
		if not linked:
			validate_fail_reason = "tree_door_geom"
			return false

	var extra_added := 0
	var prioritized_rooms: Array = []
	for rid in range(rooms.size()):
		if _room_requires_full_adjacency(rid):
			prioritized_rooms.append(rid)
	prioritized_rooms.sort_custom(func(a, b): return _room_total_area(int(a)) > _room_total_area(int(b)))

	for rid_variant in prioritized_rooms:
		var rid := int(rid_variant)
		var candidate_edges: Array = []
		for edge_variant in edges:
			var edge := edge_variant as Dictionary
			var a := int(edge["a"])
			var b := int(edge["b"])
			if a != rid and b != rid:
				continue
			var other := b if a == rid else a
			if _is_closet_room(other):
				continue
			var key := _edge_key(edge)
			if used_edge_keys.has(key):
				continue
			if not _edge_is_geometrically_doorable(edge):
				continue
			candidate_edges.append(edge)
		candidate_edges.sort_custom(func(x, y): return (float(x["t1"]) - float(x["t0"])) > (float(y["t1"]) - float(y["t0"])))
		for edge_variant in candidate_edges:
			var edge := edge_variant as Dictionary
			var a := int(edge["a"])
			var b := int(edge["b"])
			if not _can_add_door_between(a, b):
				continue
			var door := _door_for_edge(edge, door_centers)
			if door == Rect2():
				continue
			doors.append(door)
			_register_door_connection(a, b, door)
			used_edge_keys[_edge_key(edge)] = true
			extra_added += 1

	var target_loops := _target_min_extra_loops()
	if extra_added < target_loops:
		var optional_edges: Array = []
		for edge_variant in edges:
			var edge := edge_variant as Dictionary
			var a := int(edge["a"])
			var b := int(edge["b"])
			var key := _edge_key(edge)
			if used_edge_keys.has(key):
				continue
			if _is_closet_room(a) or _is_closet_room(b):
				continue
			if not _edge_is_geometrically_doorable(edge):
				continue
			optional_edges.append(edge)
			optional_edges.sort_custom(func(x, y):
				var x_deg := _door_degree(int(x["a"])) + _door_degree(int(x["b"]))
				var y_deg := _door_degree(int(y["a"])) + _door_degree(int(y["b"]))
				if x_deg != y_deg:
					return x_deg < y_deg
				return (float(x["t1"]) - float(x["t0"])) > (float(y["t1"]) - float(y["t0"]))
			)
		for edge_variant in optional_edges:
			if extra_added >= target_loops:
				break
			var edge := edge_variant as Dictionary
			var a := int(edge["a"])
			var b := int(edge["b"])
			if not _can_add_door_between(a, b):
				continue
			var door := _door_for_edge(edge, door_centers)
			if door == Rect2():
				continue
			doors.append(door)
			_register_door_connection(a, b, door)
			used_edge_keys[_edge_key(edge)] = true
			extra_added += 1

		extra_added += _apply_core_door_density(edges, used_edge_keys, door_centers)
		extra_added += _apply_dead_end_relief_doors(edges, used_edge_keys, door_centers)

	missing_adjacent_doors_stat = _count_missing_required_adjacency_edges(edge_by_key, used_edge_keys)
	if missing_adjacent_doors_stat > 0:
		validate_fail_reason = "missing_adjacent_doors"
		return false

	if not _validate_closet_door_contract():
		validate_fail_reason = "closet_door_contract"
		return false

	extra_loops = extra_added
	return true


func _build_spanning_tree(edges: Array) -> Array:
	var visited: Dictionary = {0: true}
	var tree: Array = []
	while visited.size() < rooms.size():
		var frontier: Array = []
		for edge_variant in edges:
			var e := edge_variant as Dictionary
			var a := int(e["a"])
			var b := int(e["b"])
			var va := visited.has(a)
			var vb := visited.has(b)
			if va == vb:
				continue
			frontier.append(e)
		if frontier.is_empty():
			return []
		frontier.sort_custom(func(x, y):
			var sx := float(x["t1"]) - float(x["t0"])
			var sy := float(y["t1"]) - float(y["t0"])
			if absf(sx - sy) > 0.1:
				return sx > sy
			var xa := mini(int(x["a"]), int(x["b"]))
			var xb := mini(int(y["a"]), int(y["b"]))
			if xa != xb:
				return xa < xb
			var ya := maxi(int(x["a"]), int(x["b"]))
			var yb := maxi(int(y["a"]), int(y["b"]))
			return ya < yb)
		var chosen := frontier[0] as Dictionary
		tree.append(chosen)
		visited[int(chosen["a"])] = true
		visited[int(chosen["b"])] = true
	return tree


func _edge_key(edge: Dictionary) -> String:
	var a := mini(int(edge["a"]), int(edge["b"]))
	var b := maxi(int(edge["a"]), int(edge["b"]))
	return "%d:%d" % [a, b]


func _target_min_extra_loops() -> int:
	var non_closet_count := maxi(rooms.size() - _count_closet_rooms(), 0)
	if non_closet_count < 6:
		return 0
	if non_closet_count >= 10:
		return 2
	return TARGET_MIN_EXTRA_LOOPS


func _count_deg3plus_for_room_ids(room_ids: Array) -> int:
	var count := 0
	for rid_variant in room_ids:
		var rid := int(rid_variant)
		if rid < 0 or rid >= rooms.size():
			continue
		if _is_closet_room(rid):
			continue
		if _door_degree(rid) >= 3:
			count += 1
	return count


func _apply_core_door_density(edges: Array, used_edge_keys: Dictionary, door_centers: Dictionary) -> int:
	var core_non_closet := _core_non_closet_ids()
	if core_non_closet.size() < 3:
		return 0
	var target_deg3plus := int(ceil(float(core_non_closet.size()) * CORE_DOOR_DENSITY_TARGET_PCT * 0.01))
	target_deg3plus = clampi(target_deg3plus, 1, core_non_closet.size())
	if _count_deg3plus_for_room_ids(core_non_closet) >= target_deg3plus:
		return 0

	var core_set: Dictionary = {}
	for rid_variant in core_non_closet:
		core_set[int(rid_variant)] = true

	var candidates: Array = []
	for edge_variant in edges:
		var edge := edge_variant as Dictionary
		var a := int(edge["a"])
		var b := int(edge["b"])
		var key := _edge_key(edge)
		if used_edge_keys.has(key):
			continue
		if _is_closet_room(a) or _is_closet_room(b):
			continue
		if not _edge_is_geometrically_doorable(edge):
			continue
		var core_touch := (1 if core_set.has(a) else 0) + (1 if core_set.has(b) else 0)
		if core_touch <= 0:
			continue
		var pressure := maxi(0, 3 - _door_degree(a)) + maxi(0, 3 - _door_degree(b))
		var span := float(edge["t1"]) - float(edge["t0"])
		candidates.append({
			"edge": edge,
			"core_touch": core_touch,
			"pressure": pressure,
			"span": span,
		})

	candidates.sort_custom(func(x, y):
		var cx := int(x["core_touch"])
		var cy := int(y["core_touch"])
		if cx != cy:
			return cx > cy
		var px := int(x["pressure"])
		var py := int(y["pressure"])
		if px != py:
			return px > py
		return float(x["span"]) > float(y["span"])
	)

	var added := 0
	for item_variant in candidates:
		if _count_deg3plus_for_room_ids(core_non_closet) >= target_deg3plus:
			break
		var item := item_variant as Dictionary
		var edge := item["edge"] as Dictionary
		var a := int(edge["a"])
		var b := int(edge["b"])
		if not _can_add_door_between(a, b):
			continue
		var door := _door_for_edge(edge, door_centers)
		if door == Rect2():
			continue
		doors.append(door)
		_register_door_connection(a, b, door)
		used_edge_keys[_edge_key(edge)] = true
		added += 1
	return added


func _count_non_closet_dead_ends_from_doors() -> int:
	var count := 0
	for rid in range(rooms.size()):
		if rid in _void_ids:
			continue
		if _is_closet_room(rid):
			continue
		if _door_degree(rid) <= 1:
			count += 1
	return count


func _target_non_closet_dead_ends() -> int:
	var non_closet := maxi(rooms.size() - _count_closet_rooms(), 0)
	if non_closet <= 4:
		return 1
	var scaled := int(floor(float(non_closet) * 0.30))
	return clampi(scaled, 1, 4)


func _apply_dead_end_relief_doors(edges: Array, used_edge_keys: Dictionary, door_centers: Dictionary) -> int:
	if _count_non_closet_dead_ends_from_doors() <= _target_non_closet_dead_ends():
		return 0
	var candidates: Array = []
	for edge_variant in edges:
		var edge := edge_variant as Dictionary
		var a := int(edge["a"])
		var b := int(edge["b"])
		var key := _edge_key(edge)
		if used_edge_keys.has(key):
			continue
		if _is_closet_room(a) or _is_closet_room(b):
			continue
		if not _edge_is_geometrically_doorable(edge):
			continue
		var dead_touch := (1 if _door_degree(a) <= 1 else 0) + (1 if _door_degree(b) <= 1 else 0)
		if dead_touch <= 0:
			continue
		candidates.append({
			"edge": edge,
			"dead_touch": dead_touch,
			"deg_sum": _door_degree(a) + _door_degree(b),
			"span": float(edge["t1"]) - float(edge["t0"]),
		})

	candidates.sort_custom(func(x, y):
		var dx := int(x["dead_touch"])
		var dy := int(y["dead_touch"])
		if dx != dy:
			return dx > dy
		var gx := int(x["deg_sum"])
		var gy := int(y["deg_sum"])
		if gx != gy:
			return gx < gy
		return float(x["span"]) > float(y["span"])
	)

	var added := 0
	for item_variant in candidates:
		if _count_non_closet_dead_ends_from_doors() <= _target_non_closet_dead_ends():
			break
		var item := item_variant as Dictionary
		var edge := item["edge"] as Dictionary
		var a := int(edge["a"])
		var b := int(edge["b"])
		if not _can_add_door_between(a, b):
			continue
		var door := _door_for_edge(edge, door_centers)
		if door == Rect2():
			continue
		doors.append(door)
		_register_door_connection(a, b, door)
		used_edge_keys[_edge_key(edge)] = true
		added += 1
	return added


func _door_adjacent_room_ids(door: Rect2) -> Array:
	var ids: Dictionary = {}
	var center := door.get_center()
	var probe := maxf(_door_wall_thickness() * 0.8, 8.0)
	if door.size.y > door.size.x:
		var left_id := _room_id_at_point(Vector2(center.x - probe, center.y))
		var right_id := _room_id_at_point(Vector2(center.x + probe, center.y))
		if left_id >= 0:
			ids[left_id] = true
		if right_id >= 0:
			ids[right_id] = true
	else:
		var top_id := _room_id_at_point(Vector2(center.x, center.y - probe))
		var bottom_id := _room_id_at_point(Vector2(center.x, center.y + probe))
		if top_id >= 0:
			ids[top_id] = true
		if bottom_id >= 0:
			ids[bottom_id] = true
	return ids.keys()


func _validate_closet_door_contract() -> bool:
	for i in range(rooms.size()):
		if not _is_closet_room(i):
			continue
		var linked_doors: Array = []
		for item_variant in _door_map:
			var item := item_variant as Dictionary
			var a := int(item["a"])
			var b := int(item["b"])
			if a == i or b == i:
				linked_doors.append(item)
		if linked_doors.size() != 1:
			return false
		var door_rect := linked_doors[0]["rect"] as Rect2
		var adjacent_ids := _door_adjacent_room_ids(door_rect)
		if adjacent_ids.size() != 2:
			return false
		if not adjacent_ids.has(i):
			return false
	return true


func _door_degree(room_id: int) -> int:
	if not _door_adj.has(room_id):
		return 0
	return (_door_adj[room_id] as Array).size()


func _room_size_class(room_id: int) -> String:
	if _is_closet_room(room_id):
		return "CLOSET"
	var bbox := _room_bounding_box(room_id)
	var min_side := minf(bbox.size.x, bbox.size.y)
	var max_side := maxf(bbox.size.x, bbox.size.y)
	if min_side <= ROOM_SMALL_MAX_SIDE:
		return "SMALL"
	if max_side <= ROOM_MEDIUM_MAX_SIDE:
		return "MEDIUM"
	return "LARGE"


func _room_requires_full_adjacency(room_id: int) -> bool:
	if room_id < 0 or room_id >= rooms.size():
		return false
	if room_id in _void_ids:
		return false
	if _is_closet_room(room_id):
		return false
	if _is_room_in_core_radius(room_id):
		return true
	if _room_touch_perimeter(room_id):
		return false
	var size_class := _room_size_class(room_id)
	return size_class == "MEDIUM" or size_class == "LARGE"


func _max_doors_for_room(room_id: int) -> int:
	if _is_closet_room(room_id):
		return 1
	var perimeter := _room_touch_perimeter(room_id)
	var size_class := _room_size_class(room_id)
	match size_class:
		"SMALL":
			return 2 if perimeter else 3
		"MEDIUM":
			return 4 if perimeter else 5
		_:
			return 5 if perimeter else 6


func _can_add_door_between(a: int, b: int) -> bool:
	return _door_degree(a) < _max_doors_for_room(a) and _door_degree(b) < _max_doors_for_room(b)


func _edge_is_geometrically_doorable(edge: Dictionary) -> bool:
	var a := int(edge["a"])
	var b := int(edge["b"])
	var span := float(edge["t1"]) - float(edge["t0"])
	var margin := _door_margin_for_pair(a, b)
	return span >= _door_opening_len() + margin * 2.0


func _count_missing_required_adjacency_edges(edge_by_key: Dictionary, used_edge_keys: Dictionary) -> int:
	var missing := 0
	for key_variant in edge_by_key.keys():
		var key := str(key_variant)
		if used_edge_keys.has(key):
			continue
		var edge := edge_by_key[key] as Dictionary
		var a := int(edge["a"])
		var b := int(edge["b"])
		if _is_closet_room(a) or _is_closet_room(b):
			continue
		if not _edge_is_geometrically_doorable(edge):
			continue
		if _room_requires_full_adjacency(a) or _room_requires_full_adjacency(b):
			missing += 1
	return missing


func _door_for_edge(edge: Dictionary, door_centers: Dictionary) -> Rect2:
	var edge_type := edge["type"] as String
	var pos := float(edge["pos"])
	var a := int(edge["a"])
	var b := int(edge["b"])
	var side_margin := _door_margin_for_pair(a, b)
	var door_len := _door_opening_len()
	var t0 := float(edge["t0"]) + side_margin
	var t1 := float(edge["t1"]) - side_margin
	if t1 - t0 < door_len:
		return Rect2()
	var wall_t := _door_wall_thickness()
	var starts: Array = []
	var center_start := clampf((t0 + t1) * 0.5 - door_len * 0.5, t0, t1 - door_len)
	starts.append(center_start)
	starts.append(clampf(t0 + (t1 - t0) * 0.25 - door_len * 0.5, t0, t1 - door_len))
	starts.append(clampf(t0 + (t1 - t0) * 0.75 - door_len * 0.5, t0, t1 - door_len))
	for start_variant in starts:
		var s := float(start_variant)
		var rect := Rect2()
		var center := Vector2.ZERO
		if edge_type == "V":
			rect = Rect2(pos - wall_t * 0.5, s, wall_t, door_len)
			center = Vector2(pos, s + door_len * 0.5)
		else:
			rect = Rect2(s, pos - wall_t * 0.5, door_len, wall_t)
			center = Vector2(s + door_len * 0.5, pos)
		if _door_center_is_valid(a, center, door_centers) and _door_center_is_valid(b, center, door_centers):
			(door_centers[a] as Array).append(center)
			(door_centers[b] as Array).append(center)
			return rect
	return Rect2()


func _door_margin_for_pair(a: int, b: int) -> float:
	if _is_closet_room(a) or _is_closet_room(b):
		return 4.0
	return 36.0


func _door_center_is_valid(room_id: int, center: Vector2, door_centers: Dictionary) -> bool:
	var centers := door_centers[room_id] as Array
	for c_variant in centers:
		var c := c_variant as Vector2
		if c.distance_to(center) < DOOR_ROOM_MIN_SPACING:
			return false
	return true


func _compute_north_exit() -> void:
	_entry_gate = Rect2()
	north_exit_rect = Rect2()
	var desired_gate_w := maxf(_door_opening_len(), NORTH_GATE_MIN_WIDTH)
	var choice := _pick_north_exit_candidate(desired_gate_w)
	if choice.is_empty():
		choice = _pick_north_exit_candidate(_door_opening_len())
	if choice.is_empty():
		return
	_entry_gate = choice["gate"] as Rect2
	north_exit_rect = _entry_gate


func _pick_north_exit_candidate(min_gate_w: float) -> Dictionary:
	var candidates: Array = []
	var solid_bbox := _compute_solid_bbox()
	var center_x := solid_bbox.get_center().x if solid_bbox != Rect2() else _arena.get_center().x
	for rid in range(rooms.size()):
		if rid in _void_ids:
			continue
		if _is_closet_room(rid):
			continue
		var top_spans := _room_exposed_top_spans(rid)
		for span_variant in top_spans:
			var span := span_variant as Dictionary
			var x0 := float(span["x0"])
			var x1 := float(span["x1"])
			var y := float(span["y"])
			var span_w := x1 - x0
			if span_w < min_gate_w - CONTACT_EPS:
				continue
			candidates.append({
				"room_id": rid,
				"x0": x0,
				"x1": x1,
				"y": y,
				"span_w": span_w,
				"dx": absf((x0 + x1) * 0.5 - center_x),
			})
	candidates.sort_custom(func(a, b):
		var ay := float(a["y"])
		var by := float(b["y"])
		if absf(ay - by) > 0.5:
			return ay < by
		var adx := float(a["dx"])
		var bdx := float(b["dx"])
		if absf(adx - bdx) > 0.5:
			return adx < bdx
		return float(a["span_w"]) > float(b["span_w"])
	)
	for item_variant in candidates:
		var item := item_variant as Dictionary
		var gate := _build_north_gate_for_span(item, min_gate_w, center_x)
		if gate != Rect2():
			return {
				"room_id": int(item["room_id"]),
				"gate": gate,
			}
	return {}


func _build_north_gate_for_span(span: Dictionary, min_gate_w: float, layout_center_x: float) -> Rect2:
	var room_id := int(span["room_id"])
	var x0 := float(span["x0"])
	var x1 := float(span["x1"])
	var y := float(span["y"])
	var wall_t := _door_wall_thickness()
	var side_margin := maxf(24.0, wall_t * 1.2 + 10.0)
	var usable_w := (x1 - x0) - side_margin * 2.0
	var gate_w := maxf(min_gate_w, _door_opening_len())
	if usable_w < gate_w - CONTACT_EPS:
		return Rect2()
	var min_center_x := x0 + side_margin + gate_w * 0.5
	var max_center_x := x1 - side_margin - gate_w * 0.5
	if max_center_x <= min_center_x:
		return Rect2()
	var span_center_x := (x0 + x1) * 0.5
	var centers: Array = []
	centers.append(clampf(layout_center_x, min_center_x, max_center_x))
	centers.append(clampf(span_center_x, min_center_x, max_center_x))
	centers.append(clampf(span_center_x - gate_w * 0.35, min_center_x, max_center_x))
	centers.append(clampf(span_center_x + gate_w * 0.35, min_center_x, max_center_x))
	for center_variant in centers:
		var cx := float(center_variant)
		var gate := Rect2(cx - gate_w * 0.5, y - wall_t * 0.5, gate_w, wall_t)
		if _north_gate_has_clearance(room_id, gate):
			return gate
	return Rect2()


func _north_gate_has_clearance(room_id: int, gate: Rect2) -> bool:
	var center := gate.get_center()
	if _room_id_at_point(center + Vector2(0.0, -6.0)) >= 0:
		return false
	var lateral := minf(gate.size.x * 0.32, 24.0)
	var x_offsets := PackedFloat32Array([-lateral, 0.0, lateral])
	var depth_samples := PackedFloat32Array([10.0, 22.0, 36.0, 52.0])
	for dy in depth_samples:
		for dx in x_offsets:
			var sample := center + Vector2(dx, dy)
			if _room_id_at_point(sample) != room_id:
				return false
	return true


func _room_exposed_top_spans(room_id: int) -> Array:
	var spans: Array = []
	if room_id < 0 or room_id >= rooms.size():
		return spans
	var room_rects := rooms[room_id]["rects"] as Array
	for rect_variant in room_rects:
		var r := rect_variant as Rect2
		var cuts := _collect_same_room_edge_cuts(room_rects, r, "TOP")
		var open_spans := _subtract_1d_intervals(r.position.x, r.end.x, cuts)
		for span_variant in open_spans:
			var span := span_variant as Dictionary
			var x0 := float(span["t0"])
			var x1 := float(span["t1"])
			if x1 <= x0 + 2.0:
				continue
			var mid_x := (x0 + x1) * 0.5
			var inside := _room_id_at_point(Vector2(mid_x, r.position.y + 2.0))
			var outside := _room_id_at_point(Vector2(mid_x, r.position.y - 2.0))
			if inside != room_id:
				continue
			if outside >= 0:
				continue
			spans.append({"y": r.position.y, "x0": x0, "x1": x1})
	if spans.is_empty():
		return spans
	return _merge_top_spans_by_y(spans)


func _merge_top_spans_by_y(spans: Array) -> Array:
	var by_y: Dictionary = {}
	for span_variant in spans:
		var span := span_variant as Dictionary
		var y_key := _quantize_coord(float(span["y"]))
		if not by_y.has(y_key):
			by_y[y_key] = []
		(by_y[y_key] as Array).append({
			"t0": float(span["x0"]),
			"t1": float(span["x1"]),
		})
	var merged: Array = []
	for y_variant in by_y.keys():
		var y := float(y_variant)
		var intervals := by_y[y_variant] as Array
		intervals.sort_custom(func(a, b): return float(a["t0"]) < float(b["t0"]))
		if intervals.is_empty():
			continue
		var cursor := (intervals[0] as Dictionary).duplicate()
		for i in range(1, intervals.size()):
			var curr := intervals[i] as Dictionary
			if float(curr["t0"]) <= float(cursor["t1"]) + 0.75:
				cursor["t1"] = maxf(float(cursor["t1"]), float(curr["t1"]))
			else:
				merged.append({"y": y, "x0": float(cursor["t0"]), "x1": float(cursor["t1"])})
				cursor = curr.duplicate()
		merged.append({"y": y, "x0": float(cursor["t0"]), "x1": float(cursor["t1"])})
	return merged


func _compute_v2_stats() -> void:
	var max_deg := 0
	var total_deg := 0.0
	var big_count := 0
	for i in range(rooms.size()):
		var deg := (_door_adj[i] as Array).size() if _door_adj.has(i) else 0
		total_deg += float(deg)
		max_deg = maxi(max_deg, deg)
		var bb := _room_bounding_box(i)
		if bb.size.x >= 320.0 or bb.size.y >= 320.0:
			big_count += 1
	max_doors_stat = max_deg
	avg_degree = total_deg / maxf(float(rooms.size()), 1.0)
	big_rooms_count = big_count
	outer_longest_run_pct_stat = _compute_outer_longest_run_pct()


func center_non_closet_room_count() -> int:
	return _count_core_non_closet_rooms()


func center_deg3plus_pct() -> float:
	var core_non_closet := _core_non_closet_ids()
	if core_non_closet.is_empty():
		return 0.0
	return float(_count_deg3plus_for_room_ids(core_non_closet)) * 100.0 / float(core_non_closet.size())


func _build_room_generation_memory(edges: Array) -> void:
	var neighbors: Dictionary = {}
	for i in range(rooms.size()):
		neighbors[i] = []
	for edge_variant in edges:
		var e := edge_variant as Dictionary
		var a := int(e["a"])
		var b := int(e["b"])
		(neighbors[a] as Array).append(b)
		(neighbors[b] as Array).append(a)

	room_generation_memory.clear()
	for i in range(rooms.size()):
		var bbox := _room_bounding_box(i)
		room_generation_memory.append({
			"id": i,
			"type": str(rooms[i].get("room_type", "RECT")),
			"size_class": _room_size_class(i),
			"bbox": bbox,
			"area": bbox.get_area(),
			"is_perimeter": _room_touch_perimeter(i),
			"is_core": _is_room_in_core_radius(i),
			"requires_full_adjacency": _room_requires_full_adjacency(i),
			"door_degree": (_door_adj[i] as Array).size() if _door_adj.has(i) else 0,
			"neighbors": (neighbors[i] as Array).duplicate(),
		})


func _validate_v2_basic(target_count: int) -> bool:
	if rooms.size() != target_count:
		validate_fail_reason = "room_count_mismatch"
		return false
	var closet_count := 0
	var closet_no_door := 0
	var closet_multi_door := 0
	for i in range(rooms.size()):
		if not _door_adj.has(i):
			validate_fail_reason = "missing_room_adjacency"
			return false
		var deg := (_door_adj[i] as Array).size()
		if deg <= 0:
			validate_fail_reason = "zero_degree_room"
			return false
		if deg > _max_doors_for_room(i):
			validate_fail_reason = "door_cap_exceeded"
			return false
		if _is_closet_room(i):
			closet_count += 1
			if deg < 1:
				closet_no_door += 1
			elif deg > 1:
				closet_multi_door += 1
	if closet_no_door > 0:
		validate_fail_reason = "closet_no_door"
		return false
	if closet_multi_door > 0:
		validate_fail_reason = "closet_multi_door"
		return false
	if closet_count < CLOSET_COUNT_MIN or closet_count > CLOSET_COUNT_MAX:
		validate_fail_reason = "closet_count_out_of_range"
		return false
	if missing_adjacent_doors_stat > 0:
		validate_fail_reason = "missing_adjacent_doors"
		return false
	if _entry_gate == Rect2():
		validate_fail_reason = "missing_north_exit"
		return false
	if not _validate_closet_door_contract():
		validate_fail_reason = "closet_door_contract"
		return false
	return true


func _apply_outer_run_outcrops() -> void:
	outcrop_count_stat = 0
	var pass_idx := 0
	var globally_touched_rooms: Dictionary = {}
	while pass_idx < OUTER_RUN_MAX_PASSES and outcrop_count_stat < MAX_OUTCROPS_PER_LAYOUT:
		var outer_edges := _collect_outer_edges_for_runs()
		if outer_edges.is_empty():
			outer_longest_run_pct_stat = 0.0
			return
		outer_longest_run_pct_stat = _compute_outer_longest_run_pct_from_edges(outer_edges)
		if outer_longest_run_pct_stat <= OUTER_RUN_TARGET_PCT:
			break

		var break_threshold := maxf(OUTER_RUN_BREAK_MIN - float(pass_idx) * 45.0, OUTCROP_SPAN_MIN + 40.0)
		var candidates: Array = []
		for edge_variant in outer_edges:
			var edge := edge_variant as Dictionary
			var span := float(edge["t1"]) - float(edge["t0"])
			if span >= break_threshold:
				candidates.append(edge)
		if candidates.is_empty():
			# If still too boxy, allow the single longest feasible edge as a fallback.
			var longest := _pick_longest_feasible_outer_edge(outer_edges)
			if longest.is_empty():
				break
			candidates.append(longest)

		candidates.sort_custom(func(a, b): return (float(a["t1"]) - float(a["t0"])) > (float(b["t1"]) - float(b["t0"])))
		var pass_added := 0
		for edge_variant in candidates:
			if outcrop_count_stat >= MAX_OUTCROPS_PER_LAYOUT:
				break
			var edge := edge_variant as Dictionary
			var room_id := int(edge["room_id"])
			if room_id < 0 or room_id >= rooms.size():
				continue
			if _is_closet_room(room_id):
				continue
			if globally_touched_rooms.has(room_id):
				continue
			if _try_apply_outcrop_for_edge(room_id, edge):
				globally_touched_rooms[room_id] = true
				outcrop_count_stat += 1
				pass_added += 1
				# Spread silhouette changes across rooms; one successful mutation per pass is enough.
				break
		if pass_added == 0:
			break
		pass_idx += 1

	outer_longest_run_pct_stat = _compute_outer_longest_run_pct()


func _collect_outer_edges_for_runs() -> Array:
	var edges: Array = []
	for room_id in range(rooms.size()):
		if room_id in _void_ids:
			continue
		var room_rects := rooms[room_id]["rects"] as Array
		for rect_variant in room_rects:
			var r := rect_variant as Rect2
			_collect_outer_edges_from_rect(room_id, room_rects, r, edges)
	return _merge_outer_edges_with_room(edges)


func _collect_outer_edges_from_rect(room_id: int, room_rects: Array, r: Rect2, out_edges: Array) -> void:
	var top_spans := _subtract_1d_intervals(r.position.x, r.end.x, _collect_same_room_edge_cuts(room_rects, r, "TOP"))
	for span_variant in top_spans:
		var span := span_variant as Dictionary
		var t0 := float(span["t0"])
		var t1 := float(span["t1"])
		if t1 <= t0 + 0.5:
			continue
		var mid := (t0 + t1) * 0.5
		if _room_id_at_point(Vector2(mid, r.position.y - 2.0)) == -1:
			out_edges.append({"room_id": room_id, "edge": "TOP", "type": "H", "pos": r.position.y, "t0": t0, "t1": t1})

	var bottom_spans := _subtract_1d_intervals(r.position.x, r.end.x, _collect_same_room_edge_cuts(room_rects, r, "BOTTOM"))
	for span_variant in bottom_spans:
		var span := span_variant as Dictionary
		var t0 := float(span["t0"])
		var t1 := float(span["t1"])
		if t1 <= t0 + 0.5:
			continue
		var mid := (t0 + t1) * 0.5
		if _room_id_at_point(Vector2(mid, r.end.y + 2.0)) == -1:
			out_edges.append({"room_id": room_id, "edge": "BOTTOM", "type": "H", "pos": r.end.y, "t0": t0, "t1": t1})

	var left_spans := _subtract_1d_intervals(r.position.y, r.end.y, _collect_same_room_edge_cuts(room_rects, r, "LEFT"))
	for span_variant in left_spans:
		var span := span_variant as Dictionary
		var t0 := float(span["t0"])
		var t1 := float(span["t1"])
		if t1 <= t0 + 0.5:
			continue
		var mid := (t0 + t1) * 0.5
		if _room_id_at_point(Vector2(r.position.x - 2.0, mid)) == -1:
			out_edges.append({"room_id": room_id, "edge": "LEFT", "type": "V", "pos": r.position.x, "t0": t0, "t1": t1})

	var right_spans := _subtract_1d_intervals(r.position.y, r.end.y, _collect_same_room_edge_cuts(room_rects, r, "RIGHT"))
	for span_variant in right_spans:
		var span := span_variant as Dictionary
		var t0 := float(span["t0"])
		var t1 := float(span["t1"])
		if t1 <= t0 + 0.5:
			continue
		var mid := (t0 + t1) * 0.5
		if _room_id_at_point(Vector2(r.end.x + 2.0, mid)) == -1:
			out_edges.append({"room_id": room_id, "edge": "RIGHT", "type": "V", "pos": r.end.x, "t0": t0, "t1": t1})


func _merge_outer_edges_with_room(edges: Array) -> Array:
	if edges.is_empty():
		return []
	var groups: Dictionary = {}
	for edge_variant in edges:
		var edge := edge_variant as Dictionary
		var room_id := int(edge["room_id"])
		var edge_name := edge["edge"] as String
		var seg_type := edge["type"] as String
		var pos := roundf(float(edge["pos"]) * 2.0) / 2.0
		var key := "%d|%s|%s|%.1f" % [room_id, edge_name, seg_type, pos]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append({"room_id": room_id, "edge": edge_name, "type": seg_type, "pos": pos, "t0": float(edge["t0"]), "t1": float(edge["t1"])})

	var merged: Array = []
	for key_variant in groups.keys():
		var group := groups[key_variant] as Array
		group.sort_custom(func(a, b): return float(a["t0"]) < float(b["t0"]))
		if group.is_empty():
			continue
		var current := (group[0] as Dictionary).duplicate()
		for i in range(1, group.size()):
			var next_seg := group[i] as Dictionary
			if float(next_seg["t0"]) <= float(current["t1"]) + 1.0:
				current["t1"] = maxf(float(current["t1"]), float(next_seg["t1"]))
			else:
				merged.append(current)
				current = next_seg.duplicate()
		merged.append(current)
	return merged


func _compute_outer_longest_run_pct() -> float:
	return _compute_outer_longest_run_pct_from_edges(_collect_outer_edges_for_runs())


func _compute_outer_longest_run_pct_from_edges(edges: Array) -> float:
	if edges.is_empty():
		return 0.0
	var longest := 0.0
	for edge_variant in edges:
		var edge := edge_variant as Dictionary
		longest = maxf(longest, float(edge["t1"]) - float(edge["t0"]))
	var solid_bbox := _compute_solid_bbox()
	var ref := maxf(solid_bbox.size.x, solid_bbox.size.y)
	if ref <= 1.0:
		return 0.0
	return clampf((longest / ref) * 100.0, 0.0, 100.0)


func _pick_longest_feasible_outer_edge(edges: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_span := 0.0
	var min_required := OUTCROP_SPAN_MIN + 12.0
	for edge_variant in edges:
		var edge := edge_variant as Dictionary
		var span := float(edge["t1"]) - float(edge["t0"])
		if span < min_required:
			continue
		if span > best_span:
			best_span = span
			best = edge
	return best


func _try_apply_outcrop_for_edge(room_id: int, edge: Dictionary) -> bool:
	var t0 := float(edge["t0"])
	var t1 := float(edge["t1"])
	var span := t1 - t0
	if span < OUTCROP_SPAN_MIN + 12.0:
		return false
	var max_span := minf(OUTCROP_SPAN_MAX, span - 12.0)
	if max_span < OUTCROP_SPAN_MIN:
		return false
	var protrusion_span := randf_range(OUTCROP_SPAN_MIN, max_span)
	var start_min := t0 + 6.0
	var start_max := t1 - protrusion_span - 6.0
	var protrusion_start := start_min if start_max <= start_min else randf_range(start_min, start_max)
	var depth := randf_range(OUTCROP_DEPTH_MIN, OUTCROP_DEPTH_MAX)
	var pos := float(edge["pos"])
	var edge_name := edge["edge"] as String

	var out_rect := Rect2()
	match edge_name:
		"TOP":
			out_rect = Rect2(protrusion_start, pos - depth, protrusion_span, depth)
		"BOTTOM":
			out_rect = Rect2(protrusion_start, pos, protrusion_span, depth)
		"LEFT":
			out_rect = Rect2(pos - depth, protrusion_start, depth, protrusion_span)
		"RIGHT":
			out_rect = Rect2(pos, protrusion_start, depth, protrusion_span)
		_:
			return false

	if minf(out_rect.size.x, out_rect.size.y) < 128.0:
		return false
	if not _arena.grow(ROOM_OVERHANG).encloses(out_rect):
		return false
	if _outcrop_overlaps_existing_geometry(room_id, out_rect):
		return false

	var rects := (rooms[room_id]["rects"] as Array).duplicate()
	rects.append(out_rect)
	rooms[room_id]["rects"] = rects
	rooms[room_id]["center"] = _area_weighted_center(rects)
	rooms[room_id]["is_outcropped"] = true
	return true


func _outcrop_overlaps_existing_geometry(room_id: int, candidate: Rect2) -> bool:
	for rid in range(rooms.size()):
		for rect_variant in (rooms[rid]["rects"] as Array):
			var ex := rect_variant as Rect2
			if rid == room_id:
				if candidate.grow(-1.5).intersects(ex.grow(-1.5)):
					return true
				continue
			if candidate.grow(-1.5).intersects(ex.grow(-1.5)):
				return true
	return false


func _bbox_from_rects(rects: Array) -> Rect2:
	if rects.is_empty():
		return Rect2()
	var out := rects[0] as Rect2
	for i in range(1, rects.size()):
		out = out.merge(rects[i] as Rect2)
	return out


func _area_weighted_center(rects: Array) -> Vector2:
	var sum := Vector2.ZERO
	var total_area := 0.0
	for rect_variant in rects:
		var r := rect_variant as Rect2
		var a := r.get_area()
		sum += r.get_center() * a
		total_area += a
	return sum / maxf(total_area, 1.0)


func _collect_base_wall_segments() -> Array:
	# Boundary classifier:
	# build candidate edge lines from room rects and keep only spans that separate
	# different sides (room/outside or room/other-room). This removes internal
	# same-room artifacts deterministically.
	var h_groups: Dictionary = {}
	var v_groups: Dictionary = {}
	var global_x_breaks: Array = []
	var global_y_breaks: Array = []
	for i in range(rooms.size()):
		if i in _void_ids:
			continue
		for rect_variant in (rooms[i]["rects"] as Array):
			var r := rect_variant as Rect2
			if r.size.x <= 1.0 or r.size.y <= 1.0:
				continue
			global_x_breaks.append(_quantize_coord(r.position.x))
			global_x_breaks.append(_quantize_coord(r.end.x))
			global_y_breaks.append(_quantize_coord(r.position.y))
			global_y_breaks.append(_quantize_coord(r.end.y))
			_append_line_interval(h_groups, r.position.y, r.position.x, r.end.x)
			_append_line_interval(h_groups, r.end.y, r.position.x, r.end.x)
			_append_line_interval(v_groups, r.position.x, r.position.y, r.end.y)
			_append_line_interval(v_groups, r.end.x, r.position.y, r.end.y)

	var segs: Array = []
	segs.append_array(_line_groups_to_segments(h_groups, true, global_x_breaks))
	segs.append_array(_line_groups_to_segments(v_groups, false, global_y_breaks))
	return _merge_collinear_segments(segs)


func _append_line_interval(groups: Dictionary, pos: float, t0: float, t1: float) -> void:
	var p := _quantize_coord(pos)
	var a := _quantize_coord(minf(t0, t1))
	var b := _quantize_coord(maxf(t0, t1))
	if b <= a + 0.5:
		return
	if not groups.has(p):
		groups[p] = []
	(groups[p] as Array).append({"t0": a, "t1": b})


func _line_groups_to_segments(groups: Dictionary, horizontal: bool, global_breaks: Array) -> Array:
	var segs: Array = []
	for key_variant in groups.keys():
		var pos := float(key_variant)
		var intervals := groups[key_variant] as Array
		var points := _collect_sorted_points(intervals)
		if points.size() < 2:
			continue
		var min_t := float(points[0])
		var max_t := float(points[points.size() - 1])
		for bp_variant in global_breaks:
			var bp := float(bp_variant)
			if bp <= min_t + 0.25 or bp >= max_t - 0.25:
				continue
			points.append(bp)
		points.sort()
		points = _dedupe_sorted_points(points)
		if points.size() < 2:
			continue
		for i in range(points.size() - 1):
			var a := float(points[i])
			var b := float(points[i + 1])
			if b <= a + 0.5:
				continue
			var mid := (a + b) * 0.5
			var side_a := -1
			var side_b := -1
			if horizontal:
				side_a = _room_id_at_point(Vector2(mid, pos - 2.0))
				side_b = _room_id_at_point(Vector2(mid, pos + 2.0))
				if side_a == side_b:
					continue
				segs.append({"type": "H", "pos": pos, "t0": a, "t1": b})
			else:
				side_a = _room_id_at_point(Vector2(pos - 2.0, mid))
				side_b = _room_id_at_point(Vector2(pos + 2.0, mid))
				if side_a == side_b:
					continue
				segs.append({"type": "V", "pos": pos, "t0": a, "t1": b})
	return segs


func _collect_sorted_points(intervals: Array) -> Array:
	var points: Array = []
	for interval_variant in intervals:
		var interval := interval_variant as Dictionary
		points.append(float(interval["t0"]))
		points.append(float(interval["t1"]))
	points.sort()
	return _dedupe_sorted_points(points)


func _dedupe_sorted_points(points: Array) -> Array:
	var unique_points: Array = []
	for p_variant in points:
		var p := float(p_variant)
		if unique_points.is_empty() or absf(float(unique_points[unique_points.size() - 1]) - p) > 0.25:
			unique_points.append(p)
	return unique_points


func _quantize_coord(v: float) -> float:
	return roundf(v * 2.0) / 2.0


func _room_bounding_box(room_id: int) -> Rect2:
	var rects: Array = rooms[room_id]["rects"] as Array
	if rects.is_empty():
		return Rect2()
	var bbox := rects[0] as Rect2
	for i in range(1, rects.size()):
		bbox = bbox.merge(rects[i] as Rect2)
	return bbox


func _room_total_area(room_id: int) -> float:
	if room_id < 0 or room_id >= rooms.size():
		return 0.0
	var total := 0.0
	for rect_variant in (rooms[room_id]["rects"] as Array):
		total += (rect_variant as Rect2).get_area()
	return total


func _room_touch_perimeter(room_id: int) -> bool:
	if room_id < 0 or room_id >= rooms.size():
		return false
	for rect_variant in (rooms[room_id]["rects"] as Array):
		var r := rect_variant as Rect2
		if absf(r.position.x - _arena.position.x) < 1.0:
			return true
		if absf(r.end.x - _arena.end.x) < 1.0:
			return true
		if absf(r.position.y - _arena.position.y) < 1.0:
			return true
		if absf(r.end.y - _arena.end.y) < 1.0:
			return true
	return false


func _compute_solid_bbox() -> Rect2:
	var has_bbox := false
	var bbox := Rect2()
	for i in range(rooms.size()):
		if i in _void_ids:
			continue
		var rb := _room_bounding_box(i)
		if rb == Rect2():
			continue
		if not has_bbox:
			bbox = rb
			has_bbox = true
		else:
			bbox = bbox.merge(rb)
	return bbox if has_bbox else Rect2()


func _find_player_room() -> void:
	var solid_bbox := _compute_solid_bbox()
	var center := solid_bbox.get_center() if solid_bbox != Rect2() else _arena.get_center()
	var candidate_ids := _preferred_spawn_room_ids()
	if candidate_ids.is_empty():
		player_room_id = -1
		player_spawn_pos = center
		return

	var best_id := int(candidate_ids[0])
	var best_score := -INF
	for rid_variant in candidate_ids:
		var rid := int(rid_variant)
		var room_center := rooms[rid]["center"] as Vector2
		var area_score := _room_total_area(rid) * 0.0025
		var dist_score := room_center.distance_to(center) * 0.08
		var perimeter_penalty := 35.0 if _room_touch_perimeter(rid) else 0.0
		var score := area_score - dist_score - perimeter_penalty
		if score > best_score:
			best_score = score
			best_id = rid

	player_room_id = best_id
	player_spawn_pos = rooms[best_id]["center"] as Vector2


func _preferred_spawn_room_ids() -> Array:
	var best: Array = []
	for i in range(rooms.size()):
		if i in _void_ids:
			continue
		var room := rooms[i] as Dictionary
		if room.get("is_corridor", false):
			continue
		if _is_closet_room(i):
			continue
		best.append(i)
	if not best.is_empty():
		return best

	var fallback: Array = []
	for i in range(rooms.size()):
		if i in _void_ids:
			continue
		var room := rooms[i] as Dictionary
		if room.get("is_corridor", false):
			continue
		fallback.append(i)
	if not fallback.is_empty():
		return fallback

	var any_rooms: Array = []
	for i in range(rooms.size()):
		if i in _void_ids:
			continue
		any_rooms.append(i)
	return any_rooms


func _place_player(player_node: Node2D) -> void:
	if not player_node or not valid or player_room_id < 0 or player_room_id >= rooms.size():
		return
	var cfg := _get_game_config_singleton()
	var requested_pad := float(cfg.get("inner_padding")) if cfg else 32.0
	var spawn_info := _safe_spawn_rect_for_room(player_room_id, requested_pad)
	var clamp_rect := spawn_info["rect"] as Rect2
	var spawn := clamp_rect.get_center()
	if _entry_gate != Rect2():
		spawn = _entry_gate.get_center() + Vector2(0.0, -PLAYER_SPAWN_NORTH_OFFSET)
	player_spawn_pos = spawn
	player_node.global_position = spawn

	var sprite := player_node.get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		sprite.visible = true
		sprite.modulate = Color.WHITE

	if player_node is CharacterBody2D:
		var cb := player_node as CharacterBody2D
		if (cb.collision_mask & 1) == 0:
			cb.collision_mask |= 1
		var safe := spawn
		var north_search_rect := _arena.grow(ROOM_OVERHANG + PLAYER_SPAWN_NORTH_OFFSET + 200.0)
		if cb.test_move(cb.global_transform, Vector2.ZERO) or _is_character_stuck(cb):
			safe = _spiral_search_safe(cb, spawn, 240.0, north_search_rect)
		if safe == spawn and _is_character_stuck(cb):
			# Fallback: try every room rect in descending area order.
			var room_rects := (rooms[player_room_id]["rects"] as Array).duplicate()
			room_rects.sort_custom(func(a, b): return (a as Rect2).get_area() > (b as Rect2).get_area())
			for rect_variant in room_rects:
				var rr := rect_variant as Rect2
				var safe_rect := _safe_spawn_rect_for_rect(rr, requested_pad)
				var candidate := safe_rect.get_center()
				cb.global_position = candidate
				if cb.test_move(cb.global_transform, Vector2.ZERO):
					candidate = _spiral_search_safe(cb, candidate, 180.0, safe_rect)
				cb.global_position = candidate
				if not cb.test_move(cb.global_transform, Vector2.ZERO) and not _is_character_stuck(cb):
					safe = candidate
					break
		player_node.global_position = safe
		player_spawn_pos = safe


func _safe_spawn_rect_for_room(room_id: int, requested_pad: float) -> Dictionary:
	var rects := rooms[room_id]["rects"] as Array
	if rects.is_empty():
		return {"rect": Rect2(player_spawn_pos, Vector2(1.0, 1.0))}
	var chosen := rects[0] as Rect2
	var best_area := chosen.get_area()
	for i in range(1, rects.size()):
		var r := rects[i] as Rect2
		var area := r.get_area()
		if area > best_area:
			chosen = r
			best_area = area
	return {"rect": _safe_spawn_rect_for_rect(chosen, requested_pad)}


func _safe_spawn_rect_for_rect(room_rect: Rect2, requested_pad: float) -> Rect2:
	var min_half := minf(room_rect.size.x, room_rect.size.y) * 0.5
	var max_pad := maxf(min_half - 6.0, 0.0)
	var pad := clampf(requested_pad, 0.0, max_pad)
	var safe_rect := room_rect.grow(-pad)
	if safe_rect.size.x <= 1.0 or safe_rect.size.y <= 1.0:
		safe_rect = room_rect
	return safe_rect


func _spiral_search_safe(cb: CharacterBody2D, center: Vector2, max_radius: float, clamp_rect: Rect2) -> Vector2:
	var step := _cell_size
	var max_steps := int(ceilf(max_radius / step))
	var orig_pos := cb.global_position
	for ring in range(1, max_steps + 1):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if absi(dx) != ring and absi(dy) != ring:
					continue
				var test_pos := center + Vector2(float(dx) * step, float(dy) * step)
				test_pos.x = clampf(test_pos.x, clamp_rect.position.x, clamp_rect.end.x)
				test_pos.y = clampf(test_pos.y, clamp_rect.position.y, clamp_rect.end.y)
				cb.global_position = test_pos
				if not cb.test_move(cb.global_transform, Vector2.ZERO):
					cb.global_position = orig_pos
					return test_pos
	cb.global_position = orig_pos
	return center


func _is_character_stuck(cb: CharacterBody2D) -> bool:
	var probes := [
		Vector2.RIGHT,
		Vector2.LEFT,
		Vector2.UP,
		Vector2.DOWN,
	]
	for dir_variant in probes:
		var dir := dir_variant as Vector2
		if not cb.test_move(cb.global_transform, dir * 4.0):
			return false
	return true


func _register_door_connection(a: int, b: int, rect: Rect2) -> void:
	if not _door_adj.has(a):
		_door_adj[a] = []
	if not _door_adj.has(b):
		_door_adj[b] = []
	if b not in (_door_adj[a] as Array):
		(_door_adj[a] as Array).append(b)
	if a not in (_door_adj[b] as Array):
		(_door_adj[b] as Array).append(a)
	_door_map.append({"a": a, "b": b, "rect": rect})


func _door_opening_len() -> float:
	var cfg := _get_game_config_singleton()
	if cfg:
		var uniform := float(cfg.get("door_opening_uniform"))
		if uniform > 0.0:
			return clampf(uniform, 40.0, 320.0)
		var avg := (float(cfg.get("door_opening_min")) + float(cfg.get("door_opening_max"))) * 0.5
		return clampf(avg, 40.0, 320.0)
	return DOOR_LEN


func _door_wall_thickness() -> float:
	var cfg := _get_game_config_singleton()
	if cfg:
		return float(cfg.get("wall_thickness"))
	return 16.0


func _rect_aspect(r: Rect2) -> float:
	return maxf(r.size.x, r.size.y) / maxf(minf(r.size.x, r.size.y), 1.0)


func _is_closet_rect(r: Rect2) -> bool:
	var short_min := CLOSET_SIZE_MIN - 1.0
	var short_max := CLOSET_SIZE_MAX + 1.0
	var long_min := CLOSET_LONG_SIZE_MIN - 2.0
	var long_max := CLOSET_LONG_SIZE_MAX + 2.0
	var x_short := r.size.x >= short_min and r.size.x <= short_max
	var y_short := r.size.y >= short_min and r.size.y <= short_max
	var x_long := r.size.x >= long_min and r.size.x <= long_max
	var y_long := r.size.y >= long_min and r.size.y <= long_max
	return (x_short and y_long) or (x_long and y_short)


func _is_closet_room(room_id: int) -> bool:
	if room_id < 0 or room_id >= rooms.size():
		return false
	if room_id in _void_ids:
		return false
	var room := rooms[room_id] as Dictionary
	if room.get("is_corridor", false):
		return false
	if str(room.get("room_type", "")) == "CLOSET":
		return true
	var rects := room.get("rects", []) as Array
	if rects.size() != 1:
		return false
	return _is_closet_rect(rects[0] as Rect2)


func _count_closet_rooms() -> int:
	var count := 0
	for i in range(rooms.size()):
		if _is_closet_room(i):
			count += 1
	return count


func _subtract_1d_intervals(base_t0: float, base_t1: float, cuts: Array) -> Array:
	var result: Array = []
	if base_t1 <= base_t0 + 0.5:
		return result

	var normalized: Array = []
	for cut_variant in cuts:
		var cut := cut_variant as Dictionary
		var c0 := maxf(base_t0, float(cut.get("t0", base_t0)))
		var c1 := minf(base_t1, float(cut.get("t1", base_t1)))
		if c1 <= c0 + 0.5:
			continue
		normalized.append({"t0": c0, "t1": c1})

	if normalized.is_empty():
		result.append({"t0": base_t0, "t1": base_t1})
		return result

	normalized.sort_custom(func(a, b): return float(a["t0"]) < float(b["t0"]))
	var cursor := base_t0
	for cut_variant in normalized:
		var cut := cut_variant as Dictionary
		var c0 := float(cut["t0"])
		var c1 := float(cut["t1"])
		if c0 > cursor + 0.5:
			result.append({"t0": cursor, "t1": c0})
		cursor = maxf(cursor, c1)
		if cursor >= base_t1 - 0.5:
			break
	if cursor < base_t1 - 0.5:
		result.append({"t0": cursor, "t1": base_t1})
	return result


func _collect_same_room_edge_cuts(room_rects: Array, base_rect: Rect2, edge: String) -> Array:
	var cuts: Array = []
	for other_variant in room_rects:
		var other := other_variant as Rect2
		if other == base_rect:
			continue
		match edge:
			"TOP":
				if absf(other.end.y - base_rect.position.y) >= 1.0:
					continue
				var ov0_t := maxf(base_rect.position.x, other.position.x)
				var ov1_t := minf(base_rect.end.x, other.end.x)
				if ov1_t > ov0_t + 0.5:
					cuts.append({"t0": ov0_t, "t1": ov1_t})
			"BOTTOM":
				if absf(other.position.y - base_rect.end.y) >= 1.0:
					continue
				var ov0_b := maxf(base_rect.position.x, other.position.x)
				var ov1_b := minf(base_rect.end.x, other.end.x)
				if ov1_b > ov0_b + 0.5:
					cuts.append({"t0": ov0_b, "t1": ov1_b})
			"LEFT":
				if absf(other.end.x - base_rect.position.x) >= 1.0:
					continue
				var ov0_l := maxf(base_rect.position.y, other.position.y)
				var ov1_l := minf(base_rect.end.y, other.end.y)
				if ov1_l > ov0_l + 0.5:
					cuts.append({"t0": ov0_l, "t1": ov1_l})
			"RIGHT":
				if absf(other.position.x - base_rect.end.x) >= 1.0:
					continue
				var ov0_r := maxf(base_rect.position.y, other.position.y)
				var ov1_r := minf(base_rect.end.y, other.end.y)
				if ov1_r > ov0_r + 0.5:
					cuts.append({"t0": ov0_r, "t1": ov1_r})
	return cuts


func _compute_cut_wall_segments_for_validation() -> Array:
	var wall_t := _door_wall_thickness()
	var base_segs := _collect_base_wall_segments()
	var all_door_rects: Array = doors.duplicate()
	if _entry_gate != Rect2():
		all_door_rects.append(_entry_gate)
	return _finalize_wall_segments(base_segs, all_door_rects, wall_t)


func _finalize_wall_segments(base_segs: Array, all_door_rects: Array, wall_t: float) -> Array:
	var merged := _merge_collinear_segments(base_segs)
	var cut := _cut_doors_from_segments(merged, all_door_rects, wall_t)
	var sealed := _seal_non_door_gaps(cut, all_door_rects, wall_t)
	var final := _merge_collinear_segments(sealed)
	var redundant_pruned := _prune_redundant_wall_segments(final, wall_t)
	var pruned := _prune_redundant_parallel_duplicates(redundant_pruned, wall_t)
	pseudo_gap_count_stat = _count_non_door_gaps(pruned, all_door_rects, wall_t)
	return pruned


func _merge_collinear_segments(segs: Array) -> Array:
	if segs.is_empty():
		return segs
	var h_segs: Array = []
	var v_segs: Array = []
	for s in segs:
		if s["type"] == "H":
			h_segs.append(s)
		else:
			v_segs.append(s)
	var result: Array = []
	result.append_array(_merge_segs_by_pos(h_segs))
	result.append_array(_merge_segs_by_pos(v_segs))
	return result


func _merge_segs_by_pos(segs: Array) -> Array:
	if segs.is_empty():
		return []
	var groups: Dictionary = {}
	for s in segs:
		var pos := float(s["pos"])
		var key := roundf(pos * 2.0) / 2.0
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(s)
	var result: Array = []
	for key_variant in groups.keys():
		var group := groups[key_variant] as Array
		group.sort_custom(func(a, b): return float(a["t0"]) < float(b["t0"]))
		var merged: Array = [group[0].duplicate()]
		for i in range(1, group.size()):
			var last := merged.back() as Dictionary
			var curr := group[i] as Dictionary
			if float(curr["t0"]) <= float(last["t1"]) + 1.0:
				last["t1"] = maxf(float(last["t1"]), float(curr["t1"]))
			else:
				merged.append(curr.duplicate())
		result.append_array(merged)
	return result


func _cut_doors_from_segments(base_segs: Array, door_rects: Array, wall_t: float) -> Array:
	var result: Array = base_segs.duplicate(true)
	var axis_eps := maxf(1.5, wall_t * 0.2)
	for door_variant in door_rects:
		var door := door_variant as Rect2
		var door_is_vertical := door.size.y > door.size.x
		var new_result: Array = []
		for seg_variant in result:
			var seg := seg_variant as Dictionary
			var seg_type := seg["type"] as String
			var seg_pos := float(seg["pos"])
			var seg_t0 := float(seg["t0"])
			var seg_t1 := float(seg["t1"])
			var cut := false
			if seg_type == "V":
				if not door_is_vertical:
					new_result.append(seg)
					continue
				var door_x := door.position.x + door.size.x * 0.5
				if absf(door_x - seg_pos) <= axis_eps:
					var d_t0 := door.position.y
					var d_t1 := door.end.y
					if d_t0 < seg_t1 and d_t1 > seg_t0:
						cut = true
						if d_t0 > seg_t0 + 2.0:
							new_result.append({"type": "V", "pos": seg_pos, "t0": seg_t0, "t1": d_t0})
						if d_t1 < seg_t1 - 2.0:
							new_result.append({"type": "V", "pos": seg_pos, "t0": d_t1, "t1": seg_t1})
			else:
				if door_is_vertical:
					new_result.append(seg)
					continue
				var door_y := door.position.y + door.size.y * 0.5
				if absf(door_y - seg_pos) <= axis_eps:
					var d_t0h := door.position.x
					var d_t1h := door.end.x
					if d_t0h < seg_t1 and d_t1h > seg_t0:
						cut = true
						if d_t0h > seg_t0 + 2.0:
							new_result.append({"type": "H", "pos": seg_pos, "t0": seg_t0, "t1": d_t0h})
						if d_t1h < seg_t1 - 2.0:
							new_result.append({"type": "H", "pos": seg_pos, "t0": d_t1h, "t1": seg_t1})
			if not cut:
				new_result.append(seg)
		result = new_result
	return result


func _tiny_opening_limit() -> float:
	return clampf(_door_opening_len() - 1.0, 24.0, 96.0)


func _pseudo_gap_limit() -> float:
	return _tiny_opening_limit()


func _is_intentional_gap(seg_type: String, seg_pos: float, gap_t0: float, gap_t1: float, door_rects: Array, wall_t: float) -> bool:
	var gap_len := gap_t1 - gap_t0
	if gap_len <= 0.5:
		return true
	for door_variant in door_rects:
		var door := door_variant as Rect2
		var door_is_vertical := door.size.y > door.size.x
		if seg_type == "H":
			if door_is_vertical:
				continue
			var door_y := door.position.y + door.size.y * 0.5
			if absf(door_y - seg_pos) > wall_t:
				continue
			var ov0 := maxf(gap_t0, door.position.x)
			var ov1 := minf(gap_t1, door.end.x)
			if ov1 - ov0 >= minf(gap_len * 0.6, _door_opening_len() * 0.5):
				return true
		else:
			if not door_is_vertical:
				continue
			var door_x := door.position.x + door.size.x * 0.5
			if absf(door_x - seg_pos) > wall_t:
				continue
			var ov0v := maxf(gap_t0, door.position.y)
			var ov1v := minf(gap_t1, door.end.y)
			if ov1v - ov0v >= minf(gap_len * 0.6, _door_opening_len() * 0.5):
				return true
	return false


func _seal_non_door_gaps(segs: Array, door_rects: Array, wall_t: float) -> Array:
	if segs.is_empty():
		return segs
	var grouped: Dictionary = {}
	for seg_variant in segs:
		var seg := seg_variant as Dictionary
		var seg_type := seg["type"] as String
		var seg_pos := float(seg["pos"])
		var key := "%s:%.1f" % [seg_type, roundf(seg_pos * 2.0) / 2.0]
		if not grouped.has(key):
			grouped[key] = []
		(grouped[key] as Array).append(seg)

	var result: Array = []
	var max_gap := _pseudo_gap_limit()
	for key_variant in grouped.keys():
		var group := grouped[key_variant] as Array
		group.sort_custom(func(a, b): return float(a["t0"]) < float(b["t0"]))
		if group.is_empty():
			continue
		var merged_group: Array = [group[0].duplicate()]
		for i in range(1, group.size()):
			var curr := (group[i] as Dictionary).duplicate()
			var last := merged_group[merged_group.size() - 1] as Dictionary
			var last_t1 := float(last["t1"])
			var curr_t0 := float(curr["t0"])
			var curr_t1 := float(curr["t1"])
			var seg_type := last["type"] as String
			var seg_pos := float(last["pos"])
			var gap := curr_t0 - last_t1
			if gap <= 0.5:
				last["t1"] = maxf(last_t1, curr_t1)
				merged_group[merged_group.size() - 1] = last
				continue
			var should_seal := gap <= max_gap and not _is_intentional_gap(seg_type, seg_pos, last_t1, curr_t0, door_rects, wall_t)
			if should_seal:
				last["t1"] = curr_t1
				merged_group[merged_group.size() - 1] = last
				continue
			merged_group.append(curr)
		result.append_array(merged_group)
	return result


func _count_non_door_gaps(segs: Array, door_rects: Array, wall_t: float) -> int:
	if segs.is_empty():
		return 0
	var grouped: Dictionary = {}
	for seg_variant in segs:
		var seg := seg_variant as Dictionary
		var seg_type := seg["type"] as String
		var seg_pos := float(seg["pos"])
		var key := "%s:%.1f" % [seg_type, roundf(seg_pos * 2.0) / 2.0]
		if not grouped.has(key):
			grouped[key] = []
		(grouped[key] as Array).append(seg)
	var count := 0
	var max_gap := _pseudo_gap_limit()
	for key_variant in grouped.keys():
		var group := grouped[key_variant] as Array
		group.sort_custom(func(a, b): return float(a["t0"]) < float(b["t0"]))
		for i in range(1, group.size()):
			var prev := group[i - 1] as Dictionary
			var curr := group[i] as Dictionary
			var gap_t0 := float(prev["t1"])
			var gap_t1 := float(curr["t0"])
			var gap := gap_t1 - gap_t0
			if gap <= 0.5 or gap > max_gap:
				continue
			var seg_type := prev["type"] as String
			var seg_pos := float(prev["pos"])
			if not _is_intentional_gap(seg_type, seg_pos, gap_t0, gap_t1, door_rects, wall_t):
				count += 1
	return count


func _prune_redundant_wall_segments(segs: Array, wall_t: float) -> Array:
	if segs.is_empty():
		return segs
	var pruned: Array = []
	for seg_variant in segs:
		var seg := seg_variant as Dictionary
		if not _is_redundant_wall_segment(seg, wall_t):
			pruned.append(seg)
	return pruned


func _prune_redundant_parallel_duplicates(segs: Array, wall_t: float) -> Array:
	if segs.size() < 2:
		return segs
	var keep: Array = []
	for seg_variant in segs:
		keep.append(true)
	var near_dist := maxf(2.0, wall_t * 0.55)
	for i in range(segs.size()):
		if not keep[i]:
			continue
		var a := segs[i] as Dictionary
		for j in range(i + 1, segs.size()):
			if not keep[j]:
				continue
			var b := segs[j] as Dictionary
			if a["type"] != b["type"]:
				continue
			if absf(float(a["pos"]) - float(b["pos"])) > near_dist:
				continue
			if absf(float(a["t0"]) - float(b["t0"])) > 1.5:
				continue
			if absf(float(a["t1"]) - float(b["t1"])) > 1.5:
				continue
			if not _is_redundant_wall_segment(a, wall_t):
				continue
			if not _is_redundant_wall_segment(b, wall_t):
				continue
			keep[i] = false
			keep[j] = false
	var out: Array = []
	for idx in range(segs.size()):
		if keep[idx]:
			out.append(segs[idx])
	return out


func _is_perimeter_segment(seg: Dictionary) -> bool:
	var seg_type := seg["type"] as String
	var seg_pos := float(seg["pos"])
	if seg_type == "H":
		return absf(seg_pos - _arena.position.y) < 1.0 or absf(seg_pos - _arena.end.y) < 1.0
	return absf(seg_pos - _arena.position.x) < 1.0 or absf(seg_pos - _arena.end.x) < 1.0


func _room_id_at_point(p: Vector2) -> int:
	for i in range(rooms.size()):
		if i in _void_ids:
			continue
		for rect_variant in (rooms[i]["rects"] as Array):
			if (rect_variant as Rect2).grow(0.25).has_point(p):
				return i
	return -1


func _is_redundant_wall_segment(seg: Dictionary, wall_t: float) -> bool:
	if _is_perimeter_segment(seg):
		return false
	var seg_type := seg["type"] as String
	var seg_pos := float(seg["pos"])
	var t0 := float(seg["t0"])
	var t1 := float(seg["t1"])
	var length := t1 - t0
	if length <= 4.0:
		return false
	var side_offset := maxf(wall_t * 0.8, 10.0)
	var checks := PackedFloat32Array([0.15, 0.35, 0.50, 0.65, 0.85])
	var valid_samples := 0
	var same_room_samples := 0
	for ratio in checks:
		var t := lerpf(t0, t1, ratio)
		var p_a: Vector2
		var p_b: Vector2
		if seg_type == "H":
			p_a = Vector2(t, seg_pos - side_offset)
			p_b = Vector2(t, seg_pos + side_offset)
		else:
			p_a = Vector2(seg_pos - side_offset, t)
			p_b = Vector2(seg_pos + side_offset, t)
		var room_a := _room_id_at_point(p_a)
		var room_b := _room_id_at_point(p_b)
		if room_a < 0 or room_b < 0:
			continue
		valid_samples += 1
		if room_a != room_b:
			return false
		same_room_samples += 1
	return valid_samples >= 3 and same_room_samples >= 3


func _build_walls(walls_node: Node2D) -> void:
	if not walls_node:
		return
	var wall_t := _door_wall_thickness()
	var base_segs := _collect_base_wall_segments()
	var all_door_rects: Array = doors.duplicate()
	if _entry_gate != Rect2():
		all_door_rects.append(_entry_gate)
	_wall_segs = _finalize_wall_segments(base_segs, all_door_rects, wall_t)

	var white_tex := _wall_white_texture()
	var walls_body := StaticBody2D.new()
	walls_body.name = "WallsBody"
	walls_body.collision_layer = 1
	walls_body.collision_mask = 1
	walls_node.add_child(walls_body)

	var walls_visual := Node2D.new()
	walls_visual.name = "WallsVisual"
	walls_node.add_child(walls_visual)

	for seg_variant in _wall_segs:
		var seg := seg_variant as Dictionary
		var seg_type := seg["type"] as String
		var seg_pos := float(seg["pos"])
		var seg_t0 := float(seg["t0"])
		var seg_t1 := float(seg["t1"])
		var seg_len := seg_t1 - seg_t0
		if seg_len < 2.0:
			continue

		var shape := RectangleShape2D.new()
		var pos: Vector2
		var sz: Vector2
		if seg_type == "H":
			sz = Vector2(seg_len + 4.0, wall_t)
			pos = Vector2(seg_t0 + seg_len * 0.5 - 2.0, seg_pos)
		else:
			sz = Vector2(wall_t, seg_len + 4.0)
			pos = Vector2(seg_pos, seg_t0 + seg_len * 0.5 - 2.0)
		pos.x = roundf(pos.x * 0.5) * 2.0
		pos.y = roundf(pos.y * 0.5) * 2.0
		sz.x = maxf(roundf(sz.x * 0.5) * 2.0, 2.0)
		sz.y = maxf(roundf(sz.y * 0.5) * 2.0, 2.0)
		shape.size = sz
		var col := CollisionShape2D.new()
		col.shape = shape
		col.position = pos
		walls_body.add_child(col)
		var spr := Sprite2D.new()
		spr.texture = white_tex
		spr.scale = sz
		spr.modulate = Color.WHITE
		spr.position = pos
		walls_visual.add_child(spr)


func _build_debug(debug_node: Node2D) -> void:
	if not debug_node:
		return
	_clear_node_children_detached(debug_node)
	for room_variant in rooms:
		var room := room_variant as Dictionary
		var rid := int(room["id"])
		var is_void := rid in _void_ids
		var color := Color(0.2, 0.8, 0.2, 0.6)
		if is_void:
			color = Color(0.4, 0.4, 0.4, 0.3)
		elif rid in _hub_ids:
			color = Color(1.0, 0.3, 0.3, 0.7)
		for rect_variant in (room["rects"] as Array):
			_draw_rect_outline(debug_node, rect_variant as Rect2, color, 2.0)
	for door_variant in doors:
		_draw_rect_outline(debug_node, door_variant as Rect2, Color(0.2, 0.5, 1.0, 0.7), 2.0)
	if _entry_gate != Rect2():
		_draw_rect_outline(debug_node, _entry_gate, Color(0.0, 1.0, 1.0, 0.8), 3.0)


func _draw_rect_outline(parent: Node2D, r: Rect2, color: Color, width: float) -> void:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.add_point(r.position)
	line.add_point(Vector2(r.end.x, r.position.y))
	line.add_point(r.end)
	line.add_point(Vector2(r.position.x, r.end.y))
	line.add_point(r.position)
	parent.add_child(line)


func _wall_white_texture() -> ImageTexture:
	if _cached_wall_white_tex and is_instance_valid(_cached_wall_white_tex):
		return _cached_wall_white_tex
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.WHITE)
	_cached_wall_white_tex = ImageTexture.create_from_image(img)
	return _cached_wall_white_tex


func _clear_node_children_detached(parent: Node) -> void:
	if not parent:
		return
	var children := parent.get_children()
	for child in children:
		parent.remove_child(child)
		child.queue_free()
