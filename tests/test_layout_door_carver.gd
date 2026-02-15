## test_layout_door_carver.gd
## Unit tests for LayoutDoorCarver.
## Run via: godot --headless res://tests/test_layout_door_carver.tscn
extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LayoutDoorCarver = preload("res://src/systems/layout_door_carver.gd")
const LayoutGeometryUtils = preload("res://src/systems/layout_geometry_utils.gd")

var _t := TestHelpers.new()


func _ready() -> void:
	print("=".repeat(60))
	print("LAYOUT DOOR CARVER TEST")
	print("=".repeat(60))

	_test_adjacency_two_touching_rooms()
	_test_adjacency_two_separated_rooms()
	_test_adjacency_three_rooms_chain()
	_test_adjacency_respects_min_span()
	_test_carve_two_rooms_one_door()
	_test_carve_preserves_connectivity()
	_test_closet_gets_exactly_one_door()
	_test_door_placement_valid_position()
	_test_door_no_overlap()
	_test_dead_end_relief()
	_test_room_size_class()
	_test_max_doors_caps()

	_t.summary("LAYOUT DOOR CARVER RESULTS")
	get_tree().quit(_t.quit_code())


func _make_room(id: int, rect: Rect2, room_type: String = "RECT") -> Dictionary:
	return {
		"id": id,
		"rects": [rect],
		"center": rect.get_center(),
		"is_corridor": false,
		"room_type": room_type,
	}


func _base_config(rooms: Array, void_ids: Array = [], core_ids: Array = []) -> Dictionary:
	return {
		"rooms": rooms,
		"void_ids": void_ids,
		"core_ids": core_ids,
		"hub_ids": [0],
		"arena": Rect2(-200.0, -200.0, 2400.0, 2400.0),
		"door_opening_len": 75.0,
		"wall_thickness": 16.0,
		"total_non_closet": rooms.size(),
		"required_multi_contact": [],
	}


func _count_dead_ends(result: Dictionary, rooms: Array, void_ids: Array = []) -> int:
	var door_adj := result["door_adj"] as Dictionary
	var dead_ends := 0
	for i in range(rooms.size()):
		if i in void_ids:
			continue
		var room := rooms[i] as Dictionary
		if LayoutGeometryUtils.is_closet_room(room, void_ids, i):
			continue
		var deg := (door_adj[i] as Array).size() if door_adj.has(i) else 0
		if deg <= 1:
			dead_ends += 1
	return dead_ends


func _test_adjacency_two_touching_rooms() -> void:
	var rooms: Array = [
		_make_room(0, Rect2(0.0, 0.0, 300.0, 300.0)),
		_make_room(1, Rect2(300.0, 0.0, 300.0, 300.0)),
	]
	var dc := LayoutDoorCarver.new()
	var edges := dc.build_room_adjacency_edges(rooms, [], 75.0, 16.0)
	_t.check("2 touching rooms -> 1 edge", edges.size() == 1)
	if edges.size() == 1:
		var edge := edges[0] as Dictionary
		_t.check("Edge type=V", str(edge["type"]) == "V")
		_t.check("Edge span=300", absf(float(edge["t1"]) - float(edge["t0"]) - 300.0) < 0.5)


func _test_adjacency_two_separated_rooms() -> void:
	var rooms: Array = [
		_make_room(0, Rect2(0.0, 0.0, 220.0, 220.0)),
		_make_room(1, Rect2(500.0, 0.0, 220.0, 220.0)),
	]
	var dc := LayoutDoorCarver.new()
	var edges := dc.build_room_adjacency_edges(rooms, [], 75.0, 16.0)
	_t.check("2 separated rooms -> 0 edges", edges.size() == 0)


func _test_adjacency_three_rooms_chain() -> void:
	var rooms: Array = [
		_make_room(0, Rect2(0.0, 0.0, 240.0, 240.0)),
		_make_room(1, Rect2(240.0, 0.0, 240.0, 240.0)),
		_make_room(2, Rect2(480.0, 0.0, 240.0, 240.0)),
	]
	var dc := LayoutDoorCarver.new()
	var edges := dc.build_room_adjacency_edges(rooms, [], 75.0, 16.0)
	_t.check("A-B-C chain -> 2 edges", edges.size() == 2)


func _test_adjacency_respects_min_span() -> void:
	var rooms: Array = [
		_make_room(0, Rect2(0.0, 0.0, 300.0, 300.0)),
		_make_room(1, Rect2(300.0, 250.0, 300.0, 300.0)),
	]
	var dc := LayoutDoorCarver.new()
	var edges := dc.build_room_adjacency_edges(rooms, [], 75.0, 16.0)
	_t.check("Contact span 50 < min -> no edge", edges.size() == 0)


func _test_carve_two_rooms_one_door() -> void:
	var rooms: Array = [
		_make_room(0, Rect2(0.0, 0.0, 300.0, 300.0)),
		_make_room(1, Rect2(300.0, 0.0, 300.0, 300.0)),
	]
	var dc := LayoutDoorCarver.new()
	var edges := dc.build_room_adjacency_edges(rooms, [], 75.0, 16.0)
	var result := dc.carve_doors_from_edges(edges, _base_config(rooms))
	_t.check("carve(2 rooms) error=empty", str(result["error"]) == "")
	_t.check("carve(2 rooms) doors=1", (result["doors"] as Array).size() == 1)


func _test_carve_preserves_connectivity() -> void:
	var rooms: Array = [
		_make_room(0, Rect2(0.0, 0.0, 220.0, 220.0)),
		_make_room(1, Rect2(220.0, 0.0, 220.0, 220.0)),
		_make_room(2, Rect2(440.0, 0.0, 220.0, 220.0)),
		_make_room(3, Rect2(0.0, 220.0, 220.0, 220.0)),
		_make_room(4, Rect2(220.0, 220.0, 220.0, 220.0)),
		_make_room(5, Rect2(440.0, 220.0, 220.0, 220.0)),
	]
	var dc := LayoutDoorCarver.new()
	var edges := dc.build_room_adjacency_edges(rooms, [], 75.0, 16.0)
	var result := dc.carve_doors_from_edges(edges, _base_config(rooms))
	_t.check("carve(grid) error=empty", str(result["error"]) == "")
	var connected := TestHelpers.is_door_graph_connected(rooms, result["doors"] as Array, [])
	_t.check("Door graph connected (BFS)", connected)


func _test_closet_gets_exactly_one_door() -> void:
	var rooms: Array = [
		_make_room(0, Rect2(0.0, 0.0, 300.0, 300.0)),
		_make_room(1, Rect2(300.0, 85.0, 65.0, 130.0), "CLOSET"),
	]
	var dc := LayoutDoorCarver.new()
	var edges := dc.build_room_adjacency_edges(rooms, [], 75.0, 16.0)
	var result := dc.carve_doors_from_edges(edges, _base_config(rooms))
	_t.check("closet carve error=empty", str(result["error"]) == "")
	var adj := result["door_adj"] as Dictionary
	_t.check("Closet degree == 1", (adj[1] as Array).size() == 1)


func _test_door_placement_valid_position() -> void:
	var rooms: Array = [
		_make_room(0, Rect2(0.0, 0.0, 300.0, 300.0)),
		_make_room(1, Rect2(300.0, 0.0, 300.0, 300.0)),
	]
	var dc := LayoutDoorCarver.new()
	var edges := dc.build_room_adjacency_edges(rooms, [], 75.0, 16.0)
	var result := dc.carve_doors_from_edges(edges, _base_config(rooms))
	var carved_doors := result["doors"] as Array
	if carved_doors.is_empty():
		_t.check("Door placed on boundary", false)
		return
	var door := carved_doors[0] as Rect2
	var cx := door.get_center().x
	var ids := dc.door_adjacent_room_ids(door)
	_t.check("Door center near shared x=300", absf(cx - 300.0) <= 20.0)
	_t.check("Door touches exactly two rooms", ids.size() == 2)


func _test_door_no_overlap() -> void:
	var rooms: Array = [
		_make_room(0, Rect2(0.0, 0.0, 220.0, 220.0)),
		_make_room(1, Rect2(220.0, 0.0, 220.0, 220.0)),
		_make_room(2, Rect2(440.0, 0.0, 220.0, 220.0)),
		_make_room(3, Rect2(0.0, 220.0, 220.0, 220.0)),
		_make_room(4, Rect2(220.0, 220.0, 220.0, 220.0)),
		_make_room(5, Rect2(440.0, 220.0, 220.0, 220.0)),
	]
	var dc := LayoutDoorCarver.new()
	var edges := dc.build_room_adjacency_edges(rooms, [], 75.0, 16.0)
	var result := dc.carve_doors_from_edges(edges, _base_config(rooms))
	var carved_doors := result["doors"] as Array
	var overlaps := 0
	for i in range(carved_doors.size()):
		var a := carved_doors[i] as Rect2
		for j in range(i + 1, carved_doors.size()):
			var b := carved_doors[j] as Rect2
			if a.grow(1.5).intersects(b.grow(1.5)):
				overlaps += 1
	_t.check("N doors have no overlap", overlaps == 0)


func _test_dead_end_relief() -> void:
	var rooms: Array = [
		_make_room(0, Rect2(0.0, 0.0, 220.0, 220.0)),
		_make_room(1, Rect2(220.0, 0.0, 220.0, 220.0)),
		_make_room(2, Rect2(440.0, 0.0, 220.0, 220.0)),
		_make_room(3, Rect2(0.0, 220.0, 220.0, 220.0)),
		_make_room(4, Rect2(220.0, 220.0, 220.0, 220.0)),
		_make_room(5, Rect2(440.0, 220.0, 220.0, 220.0)),
	]
	var dc := LayoutDoorCarver.new()
	var edges := dc.build_room_adjacency_edges(rooms, [], 75.0, 16.0)
	var result := dc.carve_doors_from_edges(edges, _base_config(rooms))
	var dead_ends := _count_dead_ends(result, rooms)
	var target := dc.target_non_closet_dead_ends()
	_t.check("Dead-end relief keeps dead_ends <= target", dead_ends <= target)


func _test_room_size_class() -> void:
	var rooms: Array = [
		_make_room(0, Rect2(0.0, 0.0, 150.0, 150.0)),
		_make_room(1, Rect2(200.0, 0.0, 300.0, 300.0)),
		_make_room(2, Rect2(600.0, 0.0, 500.0, 500.0)),
		_make_room(3, Rect2(0.0, 400.0, 65.0, 130.0), "CLOSET"),
	]
	var dc := LayoutDoorCarver.new()
	dc.build_room_adjacency_edges(rooms, [], 75.0, 16.0)
	_t.check("size_class SMALL", dc.room_size_class(0) == "SMALL")
	_t.check("size_class MEDIUM", dc.room_size_class(1) == "MEDIUM")
	_t.check("size_class LARGE", dc.room_size_class(2) == "LARGE")
	_t.check("size_class CLOSET", dc.room_size_class(3) == "CLOSET")


func _test_max_doors_caps() -> void:
	var rooms: Array = [
		_make_room(0, Rect2(0.0, 0.0, 65.0, 130.0), "CLOSET"),
		_make_room(1, Rect2(200.0, 0.0, 150.0, 150.0)),
		_make_room(2, Rect2(400.0, 0.0, 300.0, 300.0)),
		_make_room(3, Rect2(800.0, 0.0, 500.0, 500.0)),
	]
	var dc := LayoutDoorCarver.new()
	dc.build_room_adjacency_edges(rooms, [], 75.0, 16.0)
	_t.check("max_doors closet = 1", dc.max_doors_for_room(0) == 1)
	_t.check("max_doors small <= 4", dc.max_doors_for_room(1) <= 4)
	_t.check("max_doors medium <= 5", dc.max_doors_for_room(2) <= 5)
	_t.check("max_doors large <= 6", dc.max_doors_for_room(3) <= 6)
