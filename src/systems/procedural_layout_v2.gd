## procedural_layout_v2.gd
## Fresh center-out room generator (flower growth) with post-geometry door carving.
class_name ProceduralLayoutV2
extends RefCounted

const LayoutGeometryUtils = preload("res://src/systems/layout_geometry_utils.gd")
const LayoutRoomShapes = preload("res://src/systems/layout_room_shapes.gd")
const LayoutWallBuilder = preload("res://src/systems/layout_wall_builder.gd")
const LayoutDoorCarver = preload("res://src/systems/layout_door_carver.gd")

const V2_MAX_ATTEMPTS := 64
const DOOR_LEN := 75.0
const DOOR_ROOM_MIN_SPACING := 120.0
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
const ROOM_NON_CENTER_LARGE_MAX_SIDE := 540.0
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
const ASPECT_SOFT_MAX := 1.52
const ASPECT_SOFT_MIN := 0.66
const ASPECT_HARD_MAX := 1.90
const ASPECT_HARD_MIN := 0.53
const ASPECT_BALANCE_THRESHOLD := 1.15
const ORTHO_GROWTH_BONUS := 0.50
const ORTHO_GROWTH_PENALTY := 0.25
const MICRO_GAP_BRIDGE_MAX := 5.0
const NORTH_GATE_MIN_WIDTH := 88.0
var _shapes := LayoutRoomShapes.new()
var _wall_builder := LayoutWallBuilder.new()
var _door_carver := LayoutDoorCarver.new()

var mission_index: int = 3
var room_generation_memory: Array = []
var room_type_preset_name: String = ""
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
var _hub_ids: Array = []
var _core_ids: Array = []
var _void_ids: Array = []
var layout_mode_name: String = ""
var _entry_gate: Rect2 = Rect2()
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
	_hub_ids.clear()
	_core_ids.clear()
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
	outer_longest_run_pct_stat = 0.0
	_core_radius = 0.0
	_core_target_non_closet = 0


func _mission_room_range(mission_id: int) -> Vector2i:
	return _shapes.mission_room_range(mission_id)


func _pick_center_room_type_equal() -> String:
	return _shapes.pick_center_room_type_equal()


func _pick_room_type_weighted(weights: Dictionary) -> String:
	return _shapes.pick_room_type_weighted(weights)


func _pick_closet_target(total_rooms: int) -> int:
	return _shapes.pick_closet_target(total_rooms)


func _configure_core_quota(total_rooms: int, closets_target: int) -> void:
	var result := _shapes.configure_core_quota(total_rooms, closets_target)
	_core_radius = result["core_radius"]
	_core_target_non_closet = result["core_target_non_closet"]


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
	return LayoutGeometryUtils.normalize_rects_to_origin(rects)


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
	_sync_door_carver_context()
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
	return _shapes.build_room_shape(room_type, is_center)


func _build_rect_shape(is_center: bool) -> Dictionary:
	return _shapes.build_rect_shape(is_center)


func _build_square_shape(is_center: bool) -> Dictionary:
	return _shapes.build_square_shape(is_center)


func _pick_span_for_room_class(is_center: bool) -> float:
	return _shapes.pick_span_for_room_class(is_center)


func _build_closet_shape() -> Dictionary:
	return _shapes.build_closet_shape()


func _build_l_shape_l1(is_center: bool) -> Dictionary:
	return _shapes.build_l_shape(is_center)


func _build_u_shape_u1(is_center: bool) -> Dictionary:
	return _shapes.build_u_shape(is_center)


func _translate_shape_to_center(rects: Array, center: Vector2) -> Array:
	return LayoutGeometryUtils.translate_shape_to_center(rects, center)


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

		var anchor_pick_window := mini(5, anchor_candidates.size())
		var anchor_id := int(anchor_candidates[randi() % anchor_pick_window])
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
	for idx in range(rooms.size()):
		if room_type != "CLOSET" and _is_closet_room(idx):
			continue
		all_ids.append(idx)
	if all_ids.is_empty():
		return all_ids

	var pool: Array = all_ids
	if prefer_core:
		var core_ids: Array = []
		for idx_variant in all_ids:
			var idx := int(idx_variant)
			if _is_room_in_core_radius(idx):
				core_ids.append(idx)
		if not core_ids.is_empty():
			pool = core_ids

	pool.sort_custom(func(a, b):
		return _anchor_priority_score(int(a), prefer_core) > _anchor_priority_score(int(b), prefer_core)
	)
	return pool


func _anchor_priority_score(room_id: int, prefer_core: bool) -> float:
	if room_id < 0 or room_id >= rooms.size():
		return -INF
	var score := 0.0
	if prefer_core:
		score += 1.2 if _is_room_in_core_radius(room_id) else -1.2
	var center := rooms[room_id]["center"] as Vector2
	score -= center.distance_to(_arena.get_center()) * 0.0009
	if _room_touch_perimeter(room_id):
		score -= 0.2
	return score


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
	var score := randf() * 0.30 - cdist * 0.0012
	if side == "E" or side == "W":
		if absf(candidate_bbox.size.x - anchor_bbox.size.x) < 18.0:
			score -= 0.7
	else:
		if absf(candidate_bbox.size.y - anchor_bbox.size.y) < 18.0:
			score -= 0.7
	var combined := _compute_solid_bbox().merge(candidate_bbox) if not rooms.is_empty() else candidate_bbox
	var aspect := combined.size.x / maxf(combined.size.y, 1.0)
	if aspect > ASPECT_HARD_MAX or aspect < ASPECT_HARD_MIN:
		score -= 1.10
	elif aspect > ASPECT_SOFT_MAX or aspect < ASPECT_SOFT_MIN:
		score -= 0.55
	score += _orthogonal_growth_bias(combined, side)
	if room_type != "CLOSET":
		if prefer_core_anchor:
			score += 5.5 if in_core else -5.5
		elif in_core:
			score += 0.40
	return score


func _orthogonal_growth_bias(combined_bbox: Rect2, side: String) -> float:
	var w := combined_bbox.size.x
	var h := combined_bbox.size.y
	if w <= 1.0 or h <= 1.0:
		return 0.0
	var aspect := w / h
	if aspect > ASPECT_BALANCE_THRESHOLD:
		return ORTHO_GROWTH_BONUS if side == "N" or side == "S" else -ORTHO_GROWTH_PENALTY
	var inv_threshold := 1.0 / ASPECT_BALANCE_THRESHOLD
	if aspect < inv_threshold:
		return ORTHO_GROWTH_BONUS if side == "E" or side == "W" else -ORTHO_GROWTH_PENALTY
	return 0.0


func _sync_door_carver_context(required_multi_contact: Array = []) -> void:
	var total_non_closet := maxi(rooms.size() - _count_closet_rooms(), 0)
	_door_carver.configure_context(
		rooms,
		_void_ids,
		_core_ids,
		_arena,
		_door_opening_len(),
		_door_wall_thickness(),
		_hub_ids,
		total_non_closet,
		required_multi_contact
	)


func _build_room_adjacency_edges() -> Array:
	_sync_door_carver_context()
	return _door_carver.build_room_adjacency_edges(rooms, _void_ids, _door_opening_len(), _door_wall_thickness())


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


func _carve_doors_from_edges(edges: Array) -> bool:
	var required_multi_contact: Array = _core_ids.duplicate()
	var config := {
		"rooms": rooms,
		"void_ids": _void_ids,
		"core_ids": _core_ids,
		"hub_ids": _hub_ids,
		"arena": _arena,
		"door_opening_len": _door_opening_len(),
		"wall_thickness": _door_wall_thickness(),
		"total_non_closet": maxi(rooms.size() - _count_closet_rooms(), 0),
		"required_multi_contact": required_multi_contact,
	}
	var result := _door_carver.carve_doors_from_edges(edges, config)
	doors = result["doors"] as Array
	_door_adj = result["door_adj"] as Dictionary
	_door_map = result["door_map"] as Array
	extra_loops = int(result["extra_loops"])
	missing_adjacent_doors_stat = int(result["missing_adjacent_doors"])
	var error := result["error"] as String
	if error != "":
		validate_fail_reason = error
		return false
	return true


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


func _door_adjacent_room_ids(door: Rect2) -> Array:
	_sync_door_carver_context()
	return _door_carver.door_adjacent_room_ids(door)


func _validate_closet_door_contract() -> bool:
	_sync_door_carver_context()
	return _door_carver.validate_closet_door_contract()


func _door_degree(room_id: int) -> int:
	if not _door_adj.has(room_id):
		return 0
	return (_door_adj[room_id] as Array).size()


func _room_size_class(room_id: int) -> String:
	_sync_door_carver_context()
	return _door_carver.room_size_class(room_id)


func _room_requires_full_adjacency(room_id: int) -> bool:
	_sync_door_carver_context()
	return _door_carver.room_requires_full_adjacency(room_id)


func _max_doors_for_room(room_id: int) -> int:
	_sync_door_carver_context()
	return _door_carver.max_doors_for_room(room_id)


func _contact_min_for_pair(a: int, b: int) -> float:
	_sync_door_carver_context()
	return _door_carver.contact_min_for_pair(a, b)


func _min_adjacency_span_for_pair(a: int, b: int) -> float:
	return _door_carver.min_adjacency_span_for_pair(a, b)


func _door_margin_for_pair(a: int, b: int) -> float:
	_sync_door_carver_context()
	return _door_carver.door_margin_for_pair(a, b)


func _edge_is_geometrically_doorable(edge: Dictionary) -> bool:
	_sync_door_carver_context()
	return _door_carver.edge_is_geometrically_doorable(edge)


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
			if _try_apply_outcrop_for_edge(room_id, edge):
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
	var pos := float(edge["pos"])
	var edge_name := edge["edge"] as String
	for _attempt in range(8):
		var protrusion_span := randf_range(OUTCROP_SPAN_MIN, max_span)
		var start_min := t0 + 6.0
		var start_max := t1 - protrusion_span - 6.0
		var protrusion_start := start_min if start_max <= start_min else randf_range(start_min, start_max)
		var depth := randf_range(OUTCROP_DEPTH_MIN, OUTCROP_DEPTH_MAX)

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
			continue
		if not _arena.grow(ROOM_OVERHANG).encloses(out_rect):
			continue
		if _outcrop_overlaps_existing_geometry(room_id, out_rect):
			continue

		var rects := (rooms[room_id]["rects"] as Array).duplicate()
		rects.append(out_rect)
		rooms[room_id]["rects"] = rects
		rooms[room_id]["center"] = _area_weighted_center(rects)
		rooms[room_id]["is_outcropped"] = true
		rooms[room_id]["is_perimeter_notched"] = true
		return true
	return false


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
	return LayoutGeometryUtils.bbox_from_rects(rects)


func _area_weighted_center(rects: Array) -> Vector2:
	return LayoutGeometryUtils.area_weighted_center(rects)


func _collect_base_wall_segments() -> Array:
	return _wall_builder.collect_base_wall_segments(rooms, _void_ids)


func _quantize_coord(v: float) -> float:
	return LayoutGeometryUtils.quantize_coord(v)


func _room_bounding_box(room_id: int) -> Rect2:
	return LayoutGeometryUtils.room_bounding_box(rooms[room_id])


func _room_total_area(room_id: int) -> float:
	if room_id < 0 or room_id >= rooms.size():
		return 0.0
	return LayoutGeometryUtils.room_total_area(rooms[room_id])


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
	return LayoutGeometryUtils.rect_aspect(r)


func _is_closet_rect(r: Rect2) -> bool:
	return LayoutGeometryUtils.is_closet_rect(r)


func _is_closet_room(room_id: int) -> bool:
	if room_id < 0 or room_id >= rooms.size():
		return false
	return LayoutGeometryUtils.is_closet_room(rooms[room_id], _void_ids, room_id)


func _count_closet_rooms() -> int:
	var count := 0
	for i in range(rooms.size()):
		if _is_closet_room(i):
			count += 1
	return count


func _subtract_1d_intervals(base_t0: float, base_t1: float, cuts: Array) -> Array:
	return LayoutGeometryUtils.subtract_1d_intervals(base_t0, base_t1, cuts)


func _collect_same_room_edge_cuts(room_rects: Array, base_rect: Rect2, edge: String) -> Array:
	return LayoutGeometryUtils.collect_same_room_edge_cuts(room_rects, base_rect, edge)


func _compute_cut_wall_segments_for_validation() -> Array:
	var wall_t := _door_wall_thickness()
	var base_segs := _collect_base_wall_segments()
	var all_door_rects: Array = doors.duplicate()
	if _entry_gate != Rect2():
		all_door_rects.append(_entry_gate)
	var result := _wall_builder.finalize_wall_segments(base_segs, all_door_rects, wall_t, _door_opening_len(), rooms, _void_ids, _arena)
	pseudo_gap_count_stat = int(result["pseudo_gap_count"])
	return result["wall_segs"] as Array


func _is_perimeter_segment(seg: Dictionary) -> bool:
	return _wall_builder.is_perimeter_segment(seg, _arena)


func _room_id_at_point(p: Vector2) -> int:
	return LayoutGeometryUtils.room_id_at_point(rooms, _void_ids, p)


func _build_walls(walls_node: Node2D) -> void:
	var result := _wall_builder.build_walls(walls_node, rooms, _void_ids, doors, _entry_gate, _arena, _door_wall_thickness(), _door_opening_len())
	_wall_segs = result["wall_segs"] as Array
	pseudo_gap_count_stat = int(result["pseudo_gap_count"])


func _build_debug(debug_node: Node2D) -> void:
	_wall_builder.build_debug(debug_node, rooms, _void_ids, _hub_ids, doors, _entry_gate)


func _draw_rect_outline(parent: Node2D, r: Rect2, color: Color, width: float) -> void:
	LayoutWallBuilder.draw_rect_outline(parent, r, color, width)


func _clear_node_children_detached(parent: Node) -> void:
	LayoutWallBuilder.clear_node_children_detached(parent)
