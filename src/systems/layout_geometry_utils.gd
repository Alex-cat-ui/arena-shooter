## layout_geometry_utils.gd
## Pure geometry helpers extracted from ProceduralLayoutV2.
## All functions are static — no instance needed.
class_name LayoutGeometryUtils
extends RefCounted

# Shared constants used by placement (orchestrator) and door carver
const CONTACT_MIN := 122.0
const CONTACT_EPS := 0.75
const CLOSET_CONTACT_MIN := 58.0

const CLOSET_SIZE_MIN := 60.0
const CLOSET_SIZE_MAX := 70.0
const CLOSET_LONG_SIDE_FACTOR := 2.0
const CLOSET_LONG_SIZE_MIN := CLOSET_SIZE_MIN * CLOSET_LONG_SIDE_FACTOR
const CLOSET_LONG_SIZE_MAX := CLOSET_SIZE_MAX * CLOSET_LONG_SIDE_FACTOR

# ---------------------------------------------------------------------------
# Bounding box / center of mass
# ---------------------------------------------------------------------------

static func bbox_from_rects(rects: Array) -> Rect2:
	if rects.is_empty():
		return Rect2()
	var out := rects[0] as Rect2
	for i in range(1, rects.size()):
		out = out.merge(rects[i] as Rect2)
	return out


static func area_weighted_center(rects: Array) -> Vector2:
	var sum := Vector2.ZERO
	var total_area := 0.0
	for rect_variant in rects:
		var r := rect_variant as Rect2
		var a := r.get_area()
		sum += r.get_center() * a
		total_area += a
	return sum / maxf(total_area, 1.0)


# ---------------------------------------------------------------------------
# Room-level geometry (take rooms array, not instance state)
# ---------------------------------------------------------------------------

static func room_bounding_box(room: Dictionary) -> Rect2:
	var rects: Array = room.get("rects", []) as Array
	if rects.is_empty():
		return Rect2()
	var bbox := rects[0] as Rect2
	for i in range(1, rects.size()):
		bbox = bbox.merge(rects[i] as Rect2)
	return bbox


static func room_total_area(room: Dictionary) -> float:
	var total := 0.0
	for rect_variant in (room.get("rects", []) as Array):
		total += (rect_variant as Rect2).get_area()
	return total


static func room_id_at_point(rooms: Array, void_ids: Array, p: Vector2) -> int:
	for i in range(rooms.size()):
		if i in void_ids:
			continue
		for rect_variant in (rooms[i]["rects"] as Array):
			if (rect_variant as Rect2).grow(0.25).has_point(p):
				return i
	return -1


static func is_closet_room(room: Dictionary, void_ids: Array, room_id: int) -> bool:
	if room_id < 0:
		return false
	if room_id in void_ids:
		return false
	if room.get("is_corridor", false):
		return false
	if str(room.get("room_type", "")) == "CLOSET":
		return true
	var rects := room.get("rects", []) as Array
	if rects.size() != 1:
		return false
	return is_closet_rect(rects[0] as Rect2)


# ---------------------------------------------------------------------------
# Shape transforms
# ---------------------------------------------------------------------------

static func quantize_coord(v: float) -> float:
	return roundf(v * 2.0) / 2.0


static func translate_shape_to_center(rects: Array, center: Vector2) -> Array:
	var bbox := bbox_from_rects(rects)
	var delta := center - bbox.get_center()
	var out: Array = []
	for rect_variant in rects:
		var r := rect_variant as Rect2
		out.append(Rect2(r.position + delta, r.size))
	return out


static func normalize_rects_to_origin(rects: Array) -> Array:
	var bbox := bbox_from_rects(rects)
	var out: Array = []
	for rect_variant in rects:
		var r := rect_variant as Rect2
		out.append(Rect2(r.position - bbox.position, r.size))
	return out


# ---------------------------------------------------------------------------
# Rect classification
# ---------------------------------------------------------------------------

static func rect_aspect(r: Rect2) -> float:
	return maxf(r.size.x, r.size.y) / maxf(minf(r.size.x, r.size.y), 1.0)


static func is_closet_rect(r: Rect2) -> bool:
	var short_min := CLOSET_SIZE_MIN - 1.0
	var short_max := CLOSET_SIZE_MAX + 1.0
	var long_min := CLOSET_LONG_SIZE_MIN - 2.0
	var long_max := CLOSET_LONG_SIZE_MAX + 2.0
	var x_short := r.size.x >= short_min and r.size.x <= short_max
	var y_short := r.size.y >= short_min and r.size.y <= short_max
	var x_long := r.size.x >= long_min and r.size.x <= long_max
	var y_long := r.size.y >= long_min and r.size.y <= long_max
	return (x_short and y_long) or (x_long and y_short)


# ---------------------------------------------------------------------------
# 1D interval subtraction (wall segment math)
# ---------------------------------------------------------------------------

static func subtract_1d_intervals(base_t0: float, base_t1: float, cuts: Array) -> Array:
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


# ---------------------------------------------------------------------------
# Same-room edge cuts (for wall builder)
# ---------------------------------------------------------------------------

static func collect_same_room_edge_cuts(room_rects: Array, base_rect: Rect2, edge: String) -> Array:
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
