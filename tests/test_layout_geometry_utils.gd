## test_layout_geometry_utils.gd
## Unit tests for LayoutGeometryUtils static helpers.
## Run via: godot --headless res://tests/test_layout_geometry_utils.tscn
extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LayoutGeometryUtils = preload("res://src/systems/layout_geometry_utils.gd")

var _t := TestHelpers.new()


func _ready() -> void:
	print("=".repeat(60))
	print("LAYOUT GEOMETRY UTILS TEST")
	print("=".repeat(60))

	_test_bbox_from_rects()
	_test_area_weighted_center()
	_test_quantize_coord()
	_test_translate_shape_to_center()
	_test_normalize_rects_to_origin()
	_test_rect_aspect()
	_test_is_closet_rect()
	_test_is_closet_room()
	_test_room_id_at_point()
	_test_room_bounding_box()
	_test_room_total_area()
	_test_subtract_1d_intervals()
	_test_collect_same_room_edge_cuts()

	_t.summary("LAYOUT GEOMETRY UTILS RESULTS")
	get_tree().quit(_t.quit_code())


# ---------------------------------------------------------------------------
# bbox_from_rects
# ---------------------------------------------------------------------------

func _test_bbox_from_rects() -> void:
	print("\n--- bbox_from_rects ---")
	_t.check("Empty array returns zero rect",
		LayoutGeometryUtils.bbox_from_rects([]) == Rect2())

	var single := [Rect2(10, 20, 30, 40)]
	_t.check("Single rect returns itself",
		LayoutGeometryUtils.bbox_from_rects(single) == Rect2(10, 20, 30, 40))

	var two := [Rect2(0, 0, 10, 10), Rect2(20, 20, 10, 10)]
	var bbox := LayoutGeometryUtils.bbox_from_rects(two)
	_t.check("Two rects merged: position", bbox.position == Vector2(0, 0))
	_t.check("Two rects merged: end", bbox.end == Vector2(30, 30))


# ---------------------------------------------------------------------------
# area_weighted_center
# ---------------------------------------------------------------------------

func _test_area_weighted_center() -> void:
	print("\n--- area_weighted_center ---")
	var rects := [Rect2(0, 0, 100, 100)]
	var c := LayoutGeometryUtils.area_weighted_center(rects)
	_t.check("Single rect center", c.distance_to(Vector2(50, 50)) < 0.01)

	# Two equal rects: center should be midpoint of their centers
	var two := [Rect2(0, 0, 100, 100), Rect2(200, 0, 100, 100)]
	var c2 := LayoutGeometryUtils.area_weighted_center(two)
	_t.check("Two equal rects center x", absf(c2.x - 150.0) < 0.01)
	_t.check("Two equal rects center y", absf(c2.y - 50.0) < 0.01)


# ---------------------------------------------------------------------------
# quantize_coord
# ---------------------------------------------------------------------------

func _test_quantize_coord() -> void:
	print("\n--- quantize_coord ---")
	_t.check("Integer stays", LayoutGeometryUtils.quantize_coord(10.0) == 10.0)
	_t.check("Half stays", LayoutGeometryUtils.quantize_coord(10.5) == 10.5)
	_t.check("Quarter rounds to half", LayoutGeometryUtils.quantize_coord(10.25) == 10.5)
	_t.check("0.1 rounds to 0", LayoutGeometryUtils.quantize_coord(0.1) == 0.0)
	_t.check("0.3 rounds to 0.5", LayoutGeometryUtils.quantize_coord(0.3) == 0.5)


# ---------------------------------------------------------------------------
# translate_shape_to_center
# ---------------------------------------------------------------------------

func _test_translate_shape_to_center() -> void:
	print("\n--- translate_shape_to_center ---")
	var rects := [Rect2(0, 0, 100, 100)]
	var result := LayoutGeometryUtils.translate_shape_to_center(rects, Vector2(200, 200))
	var r := result[0] as Rect2
	_t.check("Translated center matches target",
		r.get_center().distance_to(Vector2(200, 200)) < 0.01)
	_t.check("Size preserved", r.size == Vector2(100, 100))


# ---------------------------------------------------------------------------
# normalize_rects_to_origin
# ---------------------------------------------------------------------------

func _test_normalize_rects_to_origin() -> void:
	print("\n--- normalize_rects_to_origin ---")
	var rects := [Rect2(50, 50, 100, 100), Rect2(150, 50, 80, 80)]
	var result := LayoutGeometryUtils.normalize_rects_to_origin(rects)
	var r0 := result[0] as Rect2
	_t.check("First rect at origin", r0.position == Vector2(0, 0))
	_t.check("First rect size preserved", r0.size == Vector2(100, 100))
	var r1 := result[1] as Rect2
	_t.check("Second rect offset correct", r1.position == Vector2(100, 0))


# ---------------------------------------------------------------------------
# rect_aspect
# ---------------------------------------------------------------------------

func _test_rect_aspect() -> void:
	print("\n--- rect_aspect ---")
	_t.check("Square aspect = 1", LayoutGeometryUtils.rect_aspect(Rect2(0, 0, 100, 100)) == 1.0)
	_t.check("2:1 aspect = 2", LayoutGeometryUtils.rect_aspect(Rect2(0, 0, 200, 100)) == 2.0)
	_t.check("1:3 aspect = 3", LayoutGeometryUtils.rect_aspect(Rect2(0, 0, 50, 150)) == 3.0)


# ---------------------------------------------------------------------------
# is_closet_rect
# ---------------------------------------------------------------------------

func _test_is_closet_rect() -> void:
	print("\n--- is_closet_rect ---")
	# Closet: short side 60-70, long side 120-140
	_t.check("Typical closet 65x130", LayoutGeometryUtils.is_closet_rect(Rect2(0, 0, 65, 130)))
	_t.check("Rotated closet 130x65", LayoutGeometryUtils.is_closet_rect(Rect2(0, 0, 130, 65)))
	_t.check("Too big is not closet", not LayoutGeometryUtils.is_closet_rect(Rect2(0, 0, 200, 200)))
	_t.check("Too small is not closet", not LayoutGeometryUtils.is_closet_rect(Rect2(0, 0, 30, 30)))
	_t.check("Square 65x65 is not closet", not LayoutGeometryUtils.is_closet_rect(Rect2(0, 0, 65, 65)))


# ---------------------------------------------------------------------------
# is_closet_room
# ---------------------------------------------------------------------------

func _test_is_closet_room() -> void:
	print("\n--- is_closet_room ---")
	var void_ids: Array = [2]

	# Room with CLOSET type
	var room_closet := {"rects": [Rect2(0, 0, 200, 200)], "is_corridor": false, "room_type": "CLOSET"}
	_t.check("room_type CLOSET", LayoutGeometryUtils.is_closet_room(room_closet, void_ids, 0))

	# Room with closet-sized rect
	var room_rect := {"rects": [Rect2(0, 0, 65, 130)], "is_corridor": false}
	_t.check("Closet-sized rect", LayoutGeometryUtils.is_closet_room(room_rect, void_ids, 1))

	# Corridor is never closet
	var room_corridor := {"rects": [Rect2(0, 0, 65, 130)], "is_corridor": true}
	_t.check("Corridor not closet", not LayoutGeometryUtils.is_closet_room(room_corridor, void_ids, 3))

	# Void room
	var room_void := {"rects": [Rect2(0, 0, 65, 130)], "is_corridor": false}
	_t.check("Void id not closet", not LayoutGeometryUtils.is_closet_room(room_void, void_ids, 2))

	# Multi-rect room
	var room_multi := {"rects": [Rect2(0, 0, 65, 130), Rect2(65, 0, 65, 130)], "is_corridor": false}
	_t.check("Multi-rect not closet", not LayoutGeometryUtils.is_closet_room(room_multi, void_ids, 4))

	# Negative id
	_t.check("Negative id not closet", not LayoutGeometryUtils.is_closet_room(room_closet, void_ids, -1))


# ---------------------------------------------------------------------------
# room_id_at_point
# ---------------------------------------------------------------------------

func _test_room_id_at_point() -> void:
	print("\n--- room_id_at_point ---")
	var rooms := [
		{"rects": [Rect2(0, 0, 100, 100)]},
		{"rects": [Rect2(200, 0, 100, 100)]},
	]
	var void_ids: Array = []

	_t.check("Point in room 0", LayoutGeometryUtils.room_id_at_point(rooms, void_ids, Vector2(50, 50)) == 0)
	_t.check("Point in room 1", LayoutGeometryUtils.room_id_at_point(rooms, void_ids, Vector2(250, 50)) == 1)
	_t.check("Point outside", LayoutGeometryUtils.room_id_at_point(rooms, void_ids, Vector2(150, 50)) == -1)

	# Void room
	var void_ids2: Array = [0]
	_t.check("Void room skipped", LayoutGeometryUtils.room_id_at_point(rooms, void_ids2, Vector2(50, 50)) == -1)


# ---------------------------------------------------------------------------
# room_bounding_box
# ---------------------------------------------------------------------------

func _test_room_bounding_box() -> void:
	print("\n--- room_bounding_box ---")
	var room := {"rects": [Rect2(10, 20, 100, 50), Rect2(50, 70, 80, 60)]}
	var bbox := LayoutGeometryUtils.room_bounding_box(room)
	_t.check("bbox position", bbox.position == Vector2(10, 20))
	_t.check("bbox end", bbox.end == Vector2(130, 130))

	var empty_room := {"rects": []}
	_t.check("Empty rects returns zero", LayoutGeometryUtils.room_bounding_box(empty_room) == Rect2())


# ---------------------------------------------------------------------------
# room_total_area
# ---------------------------------------------------------------------------

func _test_room_total_area() -> void:
	print("\n--- room_total_area ---")
	var room := {"rects": [Rect2(0, 0, 100, 100), Rect2(0, 0, 50, 50)]}
	_t.check("Total area = 12500", LayoutGeometryUtils.room_total_area(room) == 12500.0)

	var empty_room := {"rects": []}
	_t.check("Empty rects = 0", LayoutGeometryUtils.room_total_area(empty_room) == 0.0)


# ---------------------------------------------------------------------------
# subtract_1d_intervals
# ---------------------------------------------------------------------------

func _test_subtract_1d_intervals() -> void:
	print("\n--- subtract_1d_intervals ---")
	# No cuts -> full interval
	var r0 := LayoutGeometryUtils.subtract_1d_intervals(0.0, 100.0, [])
	_t.check("No cuts: one segment", r0.size() == 1)
	_t.check("No cuts: full range", absf(float(r0[0]["t0"])) < 0.01 and absf(float(r0[0]["t1"]) - 100.0) < 0.01)

	# One cut in middle
	var r1 := LayoutGeometryUtils.subtract_1d_intervals(0.0, 100.0, [{"t0": 40.0, "t1": 60.0}])
	_t.check("Middle cut: two segments", r1.size() == 2)
	_t.check("Middle cut: first segment end", absf(float(r1[0]["t1"]) - 40.0) < 0.01)
	_t.check("Middle cut: second segment start", absf(float(r1[1]["t0"]) - 60.0) < 0.01)

	# Cut covers entire range
	var r2 := LayoutGeometryUtils.subtract_1d_intervals(0.0, 100.0, [{"t0": -10.0, "t1": 110.0}])
	_t.check("Full cover: no segments", r2.size() == 0)

	# Degenerate base (too small)
	var r3 := LayoutGeometryUtils.subtract_1d_intervals(0.0, 0.3, [])
	_t.check("Degenerate base: no segments", r3.size() == 0)

	# Two adjacent cuts
	var r4 := LayoutGeometryUtils.subtract_1d_intervals(0.0, 100.0, [
		{"t0": 10.0, "t1": 30.0},
		{"t0": 60.0, "t1": 80.0},
	])
	_t.check("Two cuts: three segments", r4.size() == 3)


# ---------------------------------------------------------------------------
# collect_same_room_edge_cuts
# ---------------------------------------------------------------------------

func _test_collect_same_room_edge_cuts() -> void:
	print("\n--- collect_same_room_edge_cuts ---")
	# L-shaped room: two rects sharing a TOP/BOTTOM edge
	var base := Rect2(0, 0, 100, 100)
	var neighbor := Rect2(20, 100, 60, 80)  # neighbor.end.y = 100? No: neighbor at y=100, below base
	# neighbor's top (y=100) == base's bottom (y=100)
	# For BOTTOM edge of base: check if other.position.y == base.end.y
	var room_rects := [base, neighbor]

	var cuts_bottom := LayoutGeometryUtils.collect_same_room_edge_cuts(room_rects, base, "BOTTOM")
	_t.check("L-shape bottom: one cut", cuts_bottom.size() == 1)
	if cuts_bottom.size() == 1:
		_t.check("L-shape bottom: t0=20", absf(float(cuts_bottom[0]["t0"]) - 20.0) < 0.01)
		_t.check("L-shape bottom: t1=80", absf(float(cuts_bottom[0]["t1"]) - 80.0) < 0.01)

	# No overlap on TOP
	var cuts_top := LayoutGeometryUtils.collect_same_room_edge_cuts(room_rects, base, "TOP")
	_t.check("L-shape top: no cuts", cuts_top.size() == 0)

	# No overlap on LEFT/RIGHT
	var cuts_left := LayoutGeometryUtils.collect_same_room_edge_cuts(room_rects, base, "LEFT")
	_t.check("L-shape left: no cuts", cuts_left.size() == 0)
