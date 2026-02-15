## test_layout_room_shapes.gd
## Unit tests for LayoutRoomShapes: shape generation, room planning, core quota.
## Run via: godot --headless res://tests/test_layout_room_shapes.tscn
extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LayoutRoomShapes = preload("res://src/systems/layout_room_shapes.gd")

var _t := TestHelpers.new()
var _shapes := LayoutRoomShapes.new()


func _ready() -> void:
	print("=".repeat(60))
	print("LAYOUT ROOM SHAPES TEST")
	print("=".repeat(60))

	_test_mission_room_range()
	_test_pick_room_type_weighted_distribution()
	_test_pick_closet_target()
	_test_configure_core_quota()
	_test_build_rect_shape()
	_test_build_square_shape()
	_test_build_closet_shape()
	_test_build_l_shape()
	_test_build_u_shape()
	_test_build_room_shape_dispatches()

	_t.summary("LAYOUT ROOM SHAPES RESULTS")
	get_tree().quit(_t.quit_code())


# ---------------------------------------------------------------------------
# Mission / planning
# ---------------------------------------------------------------------------

func _test_mission_room_range() -> void:
	print("\n--- mission_room_range ---")
	var r1 := _shapes.mission_room_range(1)
	_t.check("Mission 1 min=3", r1.x == 3)
	_t.check("Mission 1 max=4", r1.y == 4)

	var r2 := _shapes.mission_room_range(2)
	_t.check("Mission 2 min=5", r2.x == 5)
	_t.check("Mission 2 max=8", r2.y == 8)

	var r3 := _shapes.mission_room_range(3)
	_t.check("Mission 3+ min=9", r3.x == 9)
	_t.check("Mission 3+ max=14", r3.y == 14)


func _test_pick_room_type_weighted_distribution() -> void:
	print("\n--- pick_room_type_weighted ---")
	seed(42)
	var counts := {"RECT": 0, "SQUARE": 0, "L": 0, "U": 0}
	for i in range(1000):
		var t := _shapes.pick_room_type_weighted(LayoutRoomShapes.ROOM_TYPE_WEIGHTS)
		counts[t] = int(counts[t]) + 1
	_t.check("RECT appears (>200)", int(counts["RECT"]) > 200)
	_t.check("SQUARE appears (>50)", int(counts["SQUARE"]) > 50)
	_t.check("L appears (>50)", int(counts["L"]) > 50)
	_t.check("U appears (>50)", int(counts["U"]) > 50)
	_t.check("Total is 1000", int(counts["RECT"]) + int(counts["SQUARE"]) + int(counts["L"]) + int(counts["U"]) == 1000)


func _test_pick_closet_target() -> void:
	print("\n--- pick_closet_target ---")
	seed(123)
	var min_seen := 999
	var max_seen := 0
	for i in range(100):
		var target := _shapes.pick_closet_target(10)
		min_seen = mini(min_seen, target)
		max_seen = maxi(max_seen, target)
	_t.check("Closet target >= 1", min_seen >= 1)
	_t.check("Closet target <= 4", max_seen <= 4)


func _test_configure_core_quota() -> void:
	print("\n--- configure_core_quota ---")
	var r := _shapes.configure_core_quota(10, 2)
	_t.check("core_radius > 0", float(r["core_radius"]) > 0.0)
	_t.check("core_target_non_closet >= 2", int(r["core_target_non_closet"]) >= 2)
	_t.check("core_target_non_closet <= 6", int(r["core_target_non_closet"]) <= 6)

	var r_small := _shapes.configure_core_quota(3, 2)
	_t.check("Small layout: target = 1", int(r_small["core_target_non_closet"]) == 1)


# ---------------------------------------------------------------------------
# Shape builders
# ---------------------------------------------------------------------------

func _test_build_rect_shape() -> void:
	print("\n--- build_rect_shape ---")
	seed(10)
	var shape := _shapes.build_rect_shape(false)
	_t.check("RECT type", shape["type"] == "RECT")
	_t.check("RECT has 1 rect", (shape["rects"] as Array).size() == 1)
	var r := shape["rects"][0] as Rect2
	_t.check("RECT width > 0", r.size.x > 0.0)
	_t.check("RECT height > 0", r.size.y > 0.0)


func _test_build_square_shape() -> void:
	print("\n--- build_square_shape ---")
	seed(20)
	var shape := _shapes.build_square_shape(false)
	_t.check("SQUARE type", shape["type"] == "SQUARE")
	var r := shape["rects"][0] as Rect2
	_t.check("SQUARE is square", absf(r.size.x - r.size.y) < 0.01)
	_t.check("SQUARE size >= medium", r.size.x >= LayoutRoomShapes.ROOM_MEDIUM_MIN_SIDE)


func _test_build_closet_shape() -> void:
	print("\n--- build_closet_shape ---")
	seed(30)
	var shape := _shapes.build_closet_shape()
	_t.check("CLOSET type", shape["type"] == "CLOSET")
	var r := shape["rects"][0] as Rect2
	var short := minf(r.size.x, r.size.y)
	var long := maxf(r.size.x, r.size.y)
	_t.check("CLOSET short side >= 60", short >= 60.0 - 0.01)
	_t.check("CLOSET short side <= 70", short <= 70.0 + 0.01)
	_t.check("CLOSET elongated (ratio ~2)", absf(long / short - 2.0) < 0.1)


func _test_build_l_shape() -> void:
	print("\n--- build_l_shape ---")
	seed(40)
	var valid_count := 0
	for i in range(20):
		var shape := _shapes.build_l_shape(false)
		if shape.is_empty():
			continue
		valid_count += 1
		_t.check("L type", shape["type"] == "L")
		_t.check("L has 2 rects", (shape["rects"] as Array).size() == 2)
	_t.check("L shape generates at least some valid shapes", valid_count > 5)


func _test_build_u_shape() -> void:
	print("\n--- build_u_shape ---")
	seed(50)
	var valid_count := 0
	for i in range(20):
		var shape := _shapes.build_u_shape(false)
		if shape.is_empty():
			continue
		valid_count += 1
		_t.check("U type", shape["type"] == "U")
		_t.check("U has 3 rects", (shape["rects"] as Array).size() == 3)
	_t.check("U shape generates at least some valid shapes", valid_count > 5)


func _test_build_room_shape_dispatches() -> void:
	print("\n--- build_room_shape dispatches ---")
	seed(60)
	for room_type in ["RECT", "SQUARE", "CLOSET"]:
		var shape := _shapes.build_room_shape(room_type, false)
		_t.check("%s dispatches correctly" % room_type, shape["type"] == room_type)

	# L and U may return empty on rare RNG, try multiple times
	var l_ok := false
	var u_ok := false
	for i in range(10):
		var l := _shapes.build_room_shape("L", false)
		if not l.is_empty() and l["type"] == "L":
			l_ok = true
			break
	for i in range(10):
		var u := _shapes.build_room_shape("U", false)
		if not u.is_empty() and u["type"] == "U":
			u_ok = true
			break
	_t.check("L dispatch works", l_ok)
	_t.check("U dispatch works", u_ok)

	var unknown := _shapes.build_room_shape("UNKNOWN", false)
	_t.check("Unknown type returns empty", unknown.is_empty())
