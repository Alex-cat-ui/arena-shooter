## layout_door_carver.gd
## Adjacency graph, door placement, density enforcement and dead-end relief,
## extracted from ProceduralLayoutV2.
## Instance (RefCounted) — builds internal door_adj/door_map during a single carve pass.
class_name LayoutDoorCarver
extends RefCounted

const LayoutGeometryUtils = preload("res://src/systems/layout_geometry_utils.gd")
const LayoutRoomShapes = preload("res://src/systems/layout_room_shapes.gd")

# Constants shared with orchestrator (same values)
const CONTACT_MIN := LayoutGeometryUtils.CONTACT_MIN
const CONTACT_EPS := LayoutGeometryUtils.CONTACT_EPS
const CLOSET_CONTACT_MIN := LayoutGeometryUtils.CLOSET_CONTACT_MIN
const DOOR_ROOM_MIN_SPACING := 120.0
const TARGET_MIN_EXTRA_LOOPS := 1
const CORE_DOOR_DENSITY_TARGET_PCT := 58.0
const ROOM_SMALL_MAX_SIDE := LayoutRoomShapes.ROOM_SMALL_MAX_SIDE
const ROOM_MEDIUM_MAX_SIDE := LayoutRoomShapes.ROOM_MEDIUM_MAX_SIDE

# Internal state built during carve pass
var _doors: Array = []
var _door_adj: Dictionary = {}
var _door_map: Array = []

# Config passed in from orchestrator
var _rooms: Array = []
var _void_ids: Array = []
var _core_ids: Array = []
var _hub_ids: Array = []
var _arena: Rect2 = Rect2()
var _door_opening_len: float = 75.0
var _wall_thickness: float = 16.0
var _total_non_closet: int = -1
var _required_multi_contact: Array = []


# ---------------------------------------------------------------------------
# Public entry: build adjacency edges
# ---------------------------------------------------------------------------

## Configure module context before calling analytical helpers.
func configure_context(rooms: Array, void_ids: Array, core_ids: Array, arena: Rect2,
		door_opening_len: float, wall_thickness: float, hub_ids: Array = [],
		total_non_closet: int = -1, required_multi_contact: Array = []) -> void:
	_rooms = rooms
	_void_ids = void_ids
	_core_ids = core_ids
	_hub_ids = hub_ids
	_arena = arena
	_door_opening_len = door_opening_len
	_wall_thickness = wall_thickness
	_total_non_closet = total_non_closet
	_required_multi_contact = required_multi_contact

## Build all room-room adjacency edges. Returns Array of edge dicts.
func build_room_adjacency_edges(rooms: Array, void_ids: Array,
		door_opening_len: float, wall_thickness: float) -> Array:
	configure_context(rooms, void_ids, [], Rect2(), door_opening_len, wall_thickness)
	var edges: Array = []
	var best_by_key: Dictionary = {}
	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			var edge := best_shared_edge_between(i, j, _min_adjacency_span_for_pair(i, j))
			if edge.is_empty():
				continue
			var key := "%d:%d" % [i, j]
			best_by_key[key] = edge
	for key in best_by_key.keys():
		edges.append(best_by_key[key])
	return edges


# ---------------------------------------------------------------------------
# Public entry: carve doors from edges
# ---------------------------------------------------------------------------

## Carve doors from adjacency edges.
## Config keys: rooms, void_ids, core_ids, arena, door_opening_len,
##              wall_thickness, total_non_closet (unused for now)
## Returns: {doors, door_adj, door_map, edges, extra_loops, error}
func carve_doors_from_edges(edges: Array, config: Dictionary) -> Dictionary:
	var rooms := config.get("rooms", []) as Array
	var void_ids := config.get("void_ids", []) as Array
	var core_ids := config.get("core_ids", []) as Array
	var arena := config.get("arena", Rect2()) as Rect2
	var door_len := float(config.get("door_opening_len", 75.0))
	var wall_t := float(config.get("wall_thickness", 16.0))
	var hub_ids := config.get("hub_ids", []) as Array
	var total_non_closet := int(config.get("total_non_closet", -1))
	var required_multi_contact := config.get("required_multi_contact", []) as Array
	configure_context(
		rooms,
		void_ids,
		core_ids,
		arena,
		door_len,
		wall_t,
		hub_ids,
		total_non_closet,
		required_multi_contact
	)

	_doors.clear()
	_door_adj.clear()
	_door_map.clear()

	for i in range(_rooms.size()):
		_door_adj[i] = []

	var door_centers: Dictionary = {}
	for i in range(_rooms.size()):
		door_centers[i] = []

	var edge_by_key: Dictionary = {}
	for edge_variant in edges:
		var edge := edge_variant as Dictionary
		edge_by_key[edge_key(edge)] = edge

	var used_edge_keys: Dictionary = {}

	# Phase 1: Spanning tree (Prim-style)
	var visited: Dictionary = {0: true}
	while visited.size() < _rooms.size():
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
			return _make_result("tree_disconnected", 0, edges)
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
			_doors.append(door)
			_register_door_connection(a, b, door)
			used_edge_keys[edge_key(edge)] = true
			visited[a] = true
			visited[b] = true
			linked = true
			break
		if not linked:
			return _make_result("tree_door_geom", 0, edges)

	# Phase 2: Full-adjacency rooms (core + large)
	var extra_added := 0
	var prioritized_rooms: Array = []
	for rid in range(_rooms.size()):
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
			var key := edge_key(edge)
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
			_doors.append(door)
			_register_door_connection(a, b, door)
			used_edge_keys[edge_key(edge)] = true
			extra_added += 1

	# Phase 3: Extra loops for connectivity
	var target_loops := _target_min_extra_loops()
	if extra_added < target_loops:
		var optional_edges: Array = []
		for edge_variant in edges:
			var edge := edge_variant as Dictionary
			var a := int(edge["a"])
			var b := int(edge["b"])
			var key := edge_key(edge)
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
			_doors.append(door)
			_register_door_connection(a, b, door)
			used_edge_keys[edge_key(edge)] = true
			extra_added += 1

	# Phase 4: Dead-end relief + core density.
	# Relief runs first so low-degree rooms are not blocked by later core densification.
	extra_added += _apply_dead_end_relief_doors(edges, used_edge_keys, door_centers)
	extra_added += _apply_core_door_density(edges, used_edge_keys, door_centers)

	# Validation
	var missing := _count_missing_required_adjacency_edges(edge_by_key, used_edge_keys)
	if missing > 0:
		return _make_result("missing_adjacent_doors", extra_added, edges, missing)

	if not _validate_closet_door_contract():
		return _make_result("closet_door_contract", extra_added, edges)

	return _make_result("", extra_added, edges)


# ---------------------------------------------------------------------------
# Adjacency helpers (public for testing)
# ---------------------------------------------------------------------------

func best_shared_edge_between(a: int, b: int, min_span: float) -> Dictionary:
	var best := {}
	var best_span := 0.0
	for ra_variant in (_rooms[a]["rects"] as Array):
		var ra := ra_variant as Rect2
		for rb_variant in (_rooms[b]["rects"] as Array):
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


func contact_span_with_room(room_id: int, rects: Array) -> float:
	var best := 0.0
	for ex_variant in (_rooms[room_id]["rects"] as Array):
		var a := ex_variant as Rect2
		for cand_variant in rects:
			var b := cand_variant as Rect2
			if absf(a.end.x - b.position.x) < 1.0 or absf(b.end.x - a.position.x) < 1.0:
				best = maxf(best, minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y))
			if absf(a.end.y - b.position.y) < 1.0 or absf(b.end.y - a.position.y) < 1.0:
				best = maxf(best, minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x))
	return best


static func edge_key(edge: Dictionary) -> String:
	var a := mini(int(edge["a"]), int(edge["b"]))
	var b := maxi(int(edge["a"]), int(edge["b"]))
	return "%d:%d" % [a, b]


func door_opening_len() -> float:
	return _door_opening_len


func door_wall_thickness() -> float:
	return _wall_thickness


# ---------------------------------------------------------------------------
# Door degree / room classification
# ---------------------------------------------------------------------------

func door_degree(room_id: int) -> int:
	if not _door_adj.has(room_id):
		return 0
	return (_door_adj[room_id] as Array).size()


func room_size_class(room_id: int) -> String:
	if _is_closet_room(room_id):
		return "CLOSET"
	var bbox := LayoutGeometryUtils.room_bounding_box(_rooms[room_id])
	var min_side := minf(bbox.size.x, bbox.size.y)
	var max_side := maxf(bbox.size.x, bbox.size.y)
	if min_side <= ROOM_SMALL_MAX_SIDE:
		return "SMALL"
	if max_side <= ROOM_MEDIUM_MAX_SIDE:
		return "MEDIUM"
	return "LARGE"


func max_doors_for_room(room_id: int) -> int:
	if _is_closet_room(room_id):
		return 1
	var perimeter := _room_touch_perimeter(room_id)
	var sc := room_size_class(room_id)
	match sc:
		"SMALL":
			return 4 if perimeter else 4
		"MEDIUM":
			return 5 if perimeter else 5
		_:
			return 6 if perimeter else 6


func door_adjacent_room_ids(door: Rect2) -> Array:
	var ids: Dictionary = {}
	var center := door.get_center()
	var probe := maxf(_wall_thickness * 0.8, 8.0)
	if door.size.y > door.size.x:
		var left_id := LayoutGeometryUtils.room_id_at_point(_rooms, _void_ids, Vector2(center.x - probe, center.y))
		var right_id := LayoutGeometryUtils.room_id_at_point(_rooms, _void_ids, Vector2(center.x + probe, center.y))
		if left_id >= 0:
			ids[left_id] = true
		if right_id >= 0:
			ids[right_id] = true
	else:
		var top_id := LayoutGeometryUtils.room_id_at_point(_rooms, _void_ids, Vector2(center.x, center.y - probe))
		var bottom_id := LayoutGeometryUtils.room_id_at_point(_rooms, _void_ids, Vector2(center.x, center.y + probe))
		if top_id >= 0:
			ids[top_id] = true
		if bottom_id >= 0:
			ids[bottom_id] = true
	return ids.keys()


func contact_min_for_pair(a: int, b: int) -> float:
	return _contact_min_for_pair(a, b)


func min_adjacency_span_for_pair(a: int, b: int) -> float:
	return _min_adjacency_span_for_pair(a, b)


func door_margin_for_pair(a: int, b: int) -> float:
	return _door_margin_for_pair(a, b)


func target_min_extra_loops() -> int:
	return _target_min_extra_loops()


func edge_is_geometrically_doorable(edge: Dictionary) -> bool:
	return _edge_is_geometrically_doorable(edge)


func room_requires_full_adjacency(room_id: int) -> bool:
	return _room_requires_full_adjacency(room_id)


func validate_closet_door_contract() -> bool:
	return _validate_closet_door_contract()


func count_non_closet_dead_ends_from_doors() -> int:
	return _count_non_closet_dead_ends_from_doors()


func target_non_closet_dead_ends() -> int:
	return _target_non_closet_dead_ends()


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _is_closet_room(room_id: int) -> bool:
	if room_id < 0 or room_id >= _rooms.size():
		return false
	return LayoutGeometryUtils.is_closet_room(_rooms[room_id], _void_ids, room_id)


func _room_total_area(room_id: int) -> float:
	if room_id < 0 or room_id >= _rooms.size():
		return 0.0
	return LayoutGeometryUtils.room_total_area(_rooms[room_id])


func _room_touch_perimeter(room_id: int) -> bool:
	if room_id < 0 or room_id >= _rooms.size():
		return false
	for rect_variant in (_rooms[room_id]["rects"] as Array):
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


func _is_room_in_core_radius(room_id: int) -> bool:
	return room_id in _core_ids


func _core_non_closet_ids() -> Array:
	var ids: Array = []
	for rid_variant in _core_ids:
		var rid := int(rid_variant)
		if rid < 0 or rid >= _rooms.size():
			continue
		if _is_closet_room(rid):
			continue
		ids.append(rid)
	return ids


func _count_closet_rooms() -> int:
	var count := 0
	for i in range(_rooms.size()):
		if _is_closet_room(i):
			count += 1
	return count


func _door_degree(room_id: int) -> int:
	return door_degree(room_id)


func _contact_min_for_pair(a: int, b: int) -> float:
	return CLOSET_CONTACT_MIN if _is_closet_room(a) or _is_closet_room(b) else CONTACT_MIN


func _min_adjacency_span_for_pair(a: int, b: int) -> float:
	var base := _contact_min_for_pair(a, b)
	var required_for_door := _door_opening_len + _door_margin_for_pair(a, b) * 2.0
	return maxf(base, required_for_door)


func _door_margin_for_pair(a: int, b: int) -> float:
	if _is_closet_room(a) or _is_closet_room(b):
		return 4.0
	return 24.0


func _can_add_door_between(a: int, b: int) -> bool:
	return door_degree(a) < max_doors_for_room(a) and door_degree(b) < max_doors_for_room(b)


func _edge_is_geometrically_doorable(edge: Dictionary) -> bool:
	var a := int(edge["a"])
	var b := int(edge["b"])
	var span := float(edge["t1"]) - float(edge["t0"])
	var margin := _door_margin_for_pair(a, b)
	return span >= _door_opening_len + margin * 2.0


func _room_requires_full_adjacency(room_id: int) -> bool:
	if room_id < 0 or room_id >= _rooms.size():
		return false
	if room_id in _void_ids:
		return false
	if _is_closet_room(room_id):
		return false
	if _is_room_in_core_radius(room_id):
		return true
	if _room_touch_perimeter(room_id):
		return false
	var sc := room_size_class(room_id)
	return sc == "MEDIUM" or sc == "LARGE"


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


func _door_for_edge(edge: Dictionary, door_centers: Dictionary) -> Rect2:
	var edge_type := edge["type"] as String
	var pos := float(edge["pos"])
	var a := int(edge["a"])
	var b := int(edge["b"])
	var side_margin := _door_margin_for_pair(a, b)
	var door_len := _door_opening_len
	var t0 := float(edge["t0"]) + side_margin
	var t1 := float(edge["t1"]) - side_margin
	if t1 - t0 < door_len:
		return Rect2()
	var wall_t := _wall_thickness
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
		if _door_center_is_valid(a, center, door_centers) and _door_center_is_valid(b, center, door_centers) and _validate_door_placement(rect, a, b):
			(door_centers[a] as Array).append(center)
			(door_centers[b] as Array).append(center)
			return rect
	return Rect2()


func _door_center_is_valid(room_id: int, center: Vector2, door_centers: Dictionary) -> bool:
	var centers := door_centers[room_id] as Array
	for c_variant in centers:
		var c := c_variant as Vector2
		if c.distance_to(center) < DOOR_ROOM_MIN_SPACING:
			return false
	return true


func _validate_door_placement(door_rect: Rect2, expected_a: int, expected_b: int) -> bool:
	var adj := door_adjacent_room_ids(door_rect)
	if adj.size() < 2:
		return false
	for id_variant in adj:
		var id := int(id_variant)
		if id in _void_ids:
			return false
	var center_room := LayoutGeometryUtils.room_id_at_point(_rooms, _void_ids, door_rect.get_center())
	if center_room >= 0 and center_room in _void_ids:
		return false
	return true


func _validate_closet_door_contract() -> bool:
	for i in range(_rooms.size()):
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
		var adjacent_ids := door_adjacent_room_ids(door_rect)
		if adjacent_ids.size() != 2:
			return false
		if not adjacent_ids.has(i):
			return false
	return true


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


func _target_min_extra_loops() -> int:
	var non_closet_count := _total_non_closet if _total_non_closet >= 0 else maxi(_rooms.size() - _count_closet_rooms(), 0)
	if non_closet_count < 6:
		return 0
	if non_closet_count >= 10:
		return 2
	return TARGET_MIN_EXTRA_LOOPS


func _count_deg3plus_for_room_ids(room_ids: Array) -> int:
	var count := 0
	for rid_variant in room_ids:
		var rid := int(rid_variant)
		if rid < 0 or rid >= _rooms.size():
			continue
		if _is_closet_room(rid):
			continue
		if door_degree(rid) >= 3:
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
		var key := edge_key(edge)
		if used_edge_keys.has(key):
			continue
		if _is_closet_room(a) or _is_closet_room(b):
			continue
		if not _edge_is_geometrically_doorable(edge):
			continue
		var core_touch := (1 if core_set.has(a) else 0) + (1 if core_set.has(b) else 0)
		if core_touch <= 0:
			continue
		var pressure := maxi(0, 3 - door_degree(a)) + maxi(0, 3 - door_degree(b))
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
		_doors.append(door)
		_register_door_connection(a, b, door)
		used_edge_keys[edge_key(edge)] = true
		added += 1
	return added


func _count_non_closet_dead_ends_from_doors() -> int:
	var count := 0
	for rid in range(_rooms.size()):
		if rid in _void_ids:
			continue
		if _is_closet_room(rid):
			continue
		if door_degree(rid) <= 1:
			count += 1
	return count


func _target_non_closet_dead_ends() -> int:
	var non_closet := maxi(_rooms.size() - _count_closet_rooms(), 0)
	if non_closet <= 4:
		return 1
	var scaled := int(floor(float(non_closet) * 0.24))
	return clampi(scaled, 1, 3)


func _apply_dead_end_relief_doors(edges: Array, used_edge_keys: Dictionary, door_centers: Dictionary) -> int:
	if _count_non_closet_dead_ends_from_doors() <= _target_non_closet_dead_ends():
		return 0
	var candidates: Array = []
	for edge_variant in edges:
		var edge := edge_variant as Dictionary
		var a := int(edge["a"])
		var b := int(edge["b"])
		var key := edge_key(edge)
		if used_edge_keys.has(key):
			continue
		if _is_closet_room(a) or _is_closet_room(b):
			continue
		if not _edge_is_geometrically_doorable(edge):
			continue
		var dead_touch := (1 if door_degree(a) <= 1 else 0) + (1 if door_degree(b) <= 1 else 0)
		if dead_touch <= 0:
			continue
		candidates.append({
			"edge": edge,
			"dead_touch": dead_touch,
			"deg_sum": door_degree(a) + door_degree(b),
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
		_doors.append(door)
		_register_door_connection(a, b, door)
		used_edge_keys[edge_key(edge)] = true
		added += 1
	return added


# ---------------------------------------------------------------------------
# Result builder
# ---------------------------------------------------------------------------

func _make_result(error: String, extra_loops_count: int, edges: Array, missing_adj: int = 0) -> Dictionary:
	return {
		"doors": _doors.duplicate(),
		"door_adj": _door_adj.duplicate(true),
		"door_map": _door_map.duplicate(true),
		"edges": edges.duplicate(true),
		"extra_loops": extra_loops_count,
		"missing_adjacent_doors": missing_adj,
		"error": error,
	}
