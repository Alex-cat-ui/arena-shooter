## layout_room_shapes.gd
## Room shape generation extracted from ProceduralLayoutV2.
## Instance (RefCounted) — uses global RNG functions.
class_name LayoutRoomShapes
extends RefCounted

const LayoutGeometryUtils = preload("res://src/systems/layout_geometry_utils.gd")

# Room size constants
const ROOM_SMALL_MAX_SIDE := 200.0
const ROOM_MEDIUM_MIN_SIDE := 200.0
const ROOM_MEDIUM_MAX_SIDE := 400.0
const ROOM_LARGE_MIN_SIDE := 400.0
const ROOM_LARGE_MAX_SIDE := 600.0
const ROOM_NON_CENTER_LARGE_MAX_SIDE := 540.0

const ROOM_TYPE_WEIGHTS := {"RECT": 0.40, "SQUARE": 0.20, "L": 0.20, "U": 0.20}

# Closet constants (also in LayoutGeometryUtils for classification)
const CLOSET_COUNT_MIN := 1
const CLOSET_COUNT_MAX := 4
const CLOSET_SIZE_MIN := 60.0
const CLOSET_SIZE_MAX := 70.0
const CLOSET_LONG_SIDE_FACTOR := 2.0

# Core quota constants
const CORE_ROOM_TARGET_RATIO := 0.42
const CORE_RADIUS_MIN := 520.0
const CORE_RADIUS_MAX := 700.0
const CORE_RADIUS_PER_ROOM := 16.0


# ---------------------------------------------------------------------------
# Mission / room count planning
# ---------------------------------------------------------------------------

func mission_room_range(mission_id: int) -> Vector2i:
	match mission_id:
		1:
			return Vector2i(3, 4)
		2:
			return Vector2i(5, 8)
		_:
			return Vector2i(9, 14)


func pick_center_room_type_equal() -> String:
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


func pick_room_type_weighted(weights: Dictionary) -> String:
	var roll := randf()
	var acc := 0.0
	for key in ["RECT", "SQUARE", "L", "U"]:
		acc += float(weights.get(key, 0.0))
		if roll <= acc:
			return key
	return "RECT"


func pick_closet_target(total_rooms: int) -> int:
	var max_allowed := mini(CLOSET_COUNT_MAX, maxi(1, total_rooms - 1))
	var min_allowed := mini(CLOSET_COUNT_MIN, max_allowed)
	return randi_range(min_allowed, max_allowed)


## Returns {"core_radius": float, "core_target_non_closet": int}
func configure_core_quota(total_rooms: int, closets_target: int) -> Dictionary:
	var non_closet_target := maxi(total_rooms - closets_target, 1)
	var core_radius := clampf(420.0 + float(total_rooms) * CORE_RADIUS_PER_ROOM, CORE_RADIUS_MIN, CORE_RADIUS_MAX)
	var core_target: int
	if non_closet_target <= 2:
		core_target = non_closet_target
	else:
		var scaled := int(round(float(non_closet_target) * CORE_ROOM_TARGET_RATIO))
		core_target = clampi(scaled, 2, mini(non_closet_target, 6))
	return {"core_radius": core_radius, "core_target_non_closet": core_target}


# ---------------------------------------------------------------------------
# Shape builders
# ---------------------------------------------------------------------------

func build_room_shape(room_type: String, is_center: bool) -> Dictionary:
	match room_type:
		"RECT":
			return build_rect_shape(is_center)
		"SQUARE":
			return build_square_shape(is_center)
		"L":
			return build_l_shape(is_center)
		"U":
			return build_u_shape(is_center)
		"CLOSET":
			return build_closet_shape()
	return {}


func build_rect_shape(is_center: bool) -> Dictionary:
	var w := pick_span_for_room_class(is_center)
	var h := pick_span_for_room_class(is_center)
	if maxf(w, h) / maxf(minf(w, h), 1.0) > 2.2:
		h = clampf(w * randf_range(0.6, 1.4), ROOM_MEDIUM_MIN_SIDE * 0.85, ROOM_LARGE_MAX_SIDE)
	if randf() < 0.5:
		var t := w
		w = h
		h = t
	return {"type": "RECT", "rects": [Rect2(0.0, 0.0, w, h)]}


func build_square_shape(is_center: bool) -> Dictionary:
	var s := pick_span_for_room_class(is_center)
	s = clampf(s, ROOM_MEDIUM_MIN_SIDE, ROOM_LARGE_MAX_SIDE)
	return {"type": "SQUARE", "rects": [Rect2(0.0, 0.0, s, s)]}


func pick_span_for_room_class(is_center: bool) -> float:
	var roll := randf()
	if is_center:
		if roll < 0.55:
			return randf_range(ROOM_MEDIUM_MIN_SIDE + 20.0, ROOM_MEDIUM_MAX_SIDE - 10.0)
		return randf_range(ROOM_LARGE_MIN_SIDE, ROOM_LARGE_MAX_SIDE - 20.0)
	if roll < 0.15:
		return randf_range(160.0, ROOM_SMALL_MAX_SIDE)
	if roll < 0.70:
		return randf_range(ROOM_MEDIUM_MIN_SIDE, ROOM_MEDIUM_MAX_SIDE)
	return randf_range(ROOM_LARGE_MIN_SIDE, ROOM_NON_CENTER_LARGE_MAX_SIDE)


func build_closet_shape() -> Dictionary:
	var short_side := randf_range(CLOSET_SIZE_MIN, CLOSET_SIZE_MAX)
	var long_side := short_side * CLOSET_LONG_SIDE_FACTOR
	var horizontal := randf() < 0.5
	var w := long_side if horizontal else short_side
	var h := short_side if horizontal else long_side
	return {"type": "CLOSET", "rects": [Rect2(0.0, 0.0, w, h)]}


func build_l_shape(is_center: bool) -> Dictionary:
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


func build_u_shape(is_center: bool) -> Dictionary:
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
	var bbox := LayoutGeometryUtils.bbox_from_rects(rects)
	if bbox == Rect2():
		return {}
	var min_side := 340.0 if is_center else 300.0
	var max_side := 640.0 if is_center else ROOM_NON_CENTER_LARGE_MAX_SIDE
	if bbox.size.x < min_side or bbox.size.y < min_side:
		var sx := maxf(min_side / maxf(bbox.size.x, 1.0), 1.0)
		var sy := maxf(min_side / maxf(bbox.size.y, 1.0), 1.0)
		var s := minf(maxf(sx, sy), max_side / maxf(maxf(bbox.size.x, bbox.size.y), 1.0))
		var scaled: Array = []
		for rect_variant in rects:
			var r := rect_variant as Rect2
			scaled.append(Rect2(r.position * s, r.size * s))
		rects = scaled
		bbox = LayoutGeometryUtils.bbox_from_rects(rects)
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
