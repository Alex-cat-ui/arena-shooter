## test_layout_wall_builder.gd
## Unit tests for LayoutWallBuilder: segment math, door cutting, gap sealing, pruning.
## Uses synthetic room data (2-3 rooms) — no full layout generation.
## Run via: godot --headless res://tests/test_layout_wall_builder.tscn
extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LayoutWallBuilder = preload("res://src/systems/layout_wall_builder.gd")

var _t := TestHelpers.new()
var _wb := LayoutWallBuilder.new()


func _ready() -> void:
	print("=".repeat(60))
	print("LAYOUT WALL BUILDER TEST")
	print("=".repeat(60))

	_test_merge_collinear_empty()
	_test_merge_collinear_two_adjacent()
	_test_merge_collinear_non_adjacent()
	_test_cut_doors_horizontal()
	_test_cut_doors_vertical()
	_test_cut_doors_no_match()
	_test_seal_non_door_gaps_small_gap()
	_test_seal_non_door_gaps_large_gap()
	_test_seal_preserves_intentional_gap()
	_test_count_non_door_gaps()
	_test_is_perimeter_segment()
	_test_collect_base_single_room()
	_test_collect_base_two_rooms()
	_test_finalize_pipeline()
	_test_prune_redundant_interior()

	_t.summary("LAYOUT WALL BUILDER RESULTS")
	get_tree().quit(_t.quit_code())


# ---------------------------------------------------------------------------
# merge_collinear_segments
# ---------------------------------------------------------------------------

func _test_merge_collinear_empty() -> void:
	print("\n--- merge_collinear: empty ---")
	var result := _wb.merge_collinear_segments([])
	_t.check("Empty in → empty out", result.is_empty())


func _test_merge_collinear_two_adjacent() -> void:
	print("\n--- merge_collinear: two adjacent ---")
	var segs: Array = [
		{"type": "H", "pos": 100.0, "t0": 0.0, "t1": 50.0},
		{"type": "H", "pos": 100.0, "t0": 50.0, "t1": 120.0},
	]
	var result := _wb.merge_collinear_segments(segs)
	_t.check("Adjacent H merged to 1", result.size() == 1)
	if result.size() == 1:
		_t.check("Merged t0=0", absf(float(result[0]["t0"])) < 0.01)
		_t.check("Merged t1=120", absf(float(result[0]["t1"]) - 120.0) < 0.01)


func _test_merge_collinear_non_adjacent() -> void:
	print("\n--- merge_collinear: non-adjacent ---")
	var segs: Array = [
		{"type": "V", "pos": 50.0, "t0": 0.0, "t1": 40.0},
		{"type": "V", "pos": 50.0, "t0": 80.0, "t1": 120.0},
	]
	var result := _wb.merge_collinear_segments(segs)
	_t.check("Non-adjacent V stays 2", result.size() == 2)


# ---------------------------------------------------------------------------
# cut_doors_from_segments
# ---------------------------------------------------------------------------

func _test_cut_doors_horizontal() -> void:
	print("\n--- cut_doors: horizontal ---")
	# H segment at y=100, from x=0 to x=200
	var segs: Array = [{"type": "H", "pos": 100.0, "t0": 0.0, "t1": 200.0}]
	# Horizontal door at (80, 96, 40, 8) — center y=100
	var door_rects: Array = [Rect2(80.0, 96.0, 40.0, 8.0)]
	var result := _wb.cut_doors_from_segments(segs, door_rects, 16.0)
	_t.check("H door cut: 2 segments", result.size() == 2)
	if result.size() == 2:
		_t.check("First seg t1 ~ 80", absf(float(result[0]["t1"]) - 80.0) < 1.0)
		_t.check("Second seg t0 ~ 120", absf(float(result[1]["t0"]) - 120.0) < 1.0)


func _test_cut_doors_vertical() -> void:
	print("\n--- cut_doors: vertical ---")
	# V segment at x=200, from y=0 to y=300
	var segs: Array = [{"type": "V", "pos": 200.0, "t0": 0.0, "t1": 300.0}]
	# Vertical door at (196, 100, 8, 40) — center x=200
	var door_rects: Array = [Rect2(196.0, 100.0, 8.0, 40.0)]
	var result := _wb.cut_doors_from_segments(segs, door_rects, 16.0)
	_t.check("V door cut: 2 segments", result.size() == 2)
	if result.size() == 2:
		_t.check("First seg t1 ~ 100", absf(float(result[0]["t1"]) - 100.0) < 1.0)
		_t.check("Second seg t0 ~ 140", absf(float(result[1]["t0"]) - 140.0) < 1.0)


func _test_cut_doors_no_match() -> void:
	print("\n--- cut_doors: no match ---")
	var segs: Array = [{"type": "H", "pos": 100.0, "t0": 0.0, "t1": 200.0}]
	# Door far from this segment
	var door_rects: Array = [Rect2(80.0, 500.0, 40.0, 8.0)]
	var result := _wb.cut_doors_from_segments(segs, door_rects, 16.0)
	_t.check("No match: 1 segment unchanged", result.size() == 1)


# ---------------------------------------------------------------------------
# seal_non_door_gaps
# ---------------------------------------------------------------------------

func _test_seal_non_door_gaps_small_gap() -> void:
	print("\n--- seal_non_door_gaps: small gap ---")
	# Two H segments with a 20px gap, no door nearby → should seal
	var segs: Array = [
		{"type": "H", "pos": 100.0, "t0": 0.0, "t1": 80.0},
		{"type": "H", "pos": 100.0, "t0": 100.0, "t1": 200.0},
	]
	var result := _wb.seal_non_door_gaps(segs, [], 16.0, 75.0)
	_t.check("Small gap sealed to 1", result.size() == 1)
	if result.size() == 1:
		_t.check("Sealed t0=0", absf(float(result[0]["t0"])) < 0.01)
		_t.check("Sealed t1=200", absf(float(result[0]["t1"]) - 200.0) < 0.01)


func _test_seal_non_door_gaps_large_gap() -> void:
	print("\n--- seal_non_door_gaps: large gap ---")
	# Two H segments with a 200px gap → too big, not sealed
	var segs: Array = [
		{"type": "H", "pos": 100.0, "t0": 0.0, "t1": 80.0},
		{"type": "H", "pos": 100.0, "t0": 280.0, "t1": 400.0},
	]
	var result := _wb.seal_non_door_gaps(segs, [], 16.0, 75.0)
	_t.check("Large gap: stays 2", result.size() == 2)


func _test_seal_preserves_intentional_gap() -> void:
	print("\n--- seal: intentional gap preserved ---")
	# Gap exactly where a door is → should NOT seal
	var segs: Array = [
		{"type": "H", "pos": 100.0, "t0": 0.0, "t1": 80.0},
		{"type": "H", "pos": 100.0, "t0": 120.0, "t1": 200.0},
	]
	# Horizontal door overlapping the gap
	var door_rects: Array = [Rect2(75.0, 96.0, 50.0, 8.0)]
	var result := _wb.seal_non_door_gaps(segs, door_rects, 16.0, 75.0)
	_t.check("Intentional gap: stays 2", result.size() == 2)


# ---------------------------------------------------------------------------
# count_non_door_gaps
# ---------------------------------------------------------------------------

func _test_count_non_door_gaps() -> void:
	print("\n--- count_non_door_gaps ---")
	var segs: Array = [
		{"type": "H", "pos": 100.0, "t0": 0.0, "t1": 80.0},
		{"type": "H", "pos": 100.0, "t0": 100.0, "t1": 200.0},
	]
	# Gap of 20px, within pseudo_gap_limit(75) = 74
	var count_no_doors := _wb.count_non_door_gaps(segs, [], 16.0, 75.0)
	_t.check("20px gap with no door = 1 pseudo-gap", count_no_doors == 1)

	# Same gap but with a door covering it
	var door_rects: Array = [Rect2(75.0, 96.0, 50.0, 8.0)]
	var count_with_door := _wb.count_non_door_gaps(segs, door_rects, 16.0, 75.0)
	_t.check("Gap with door = 0 pseudo-gaps", count_with_door == 0)


# ---------------------------------------------------------------------------
# is_perimeter_segment
# ---------------------------------------------------------------------------

func _test_is_perimeter_segment() -> void:
	print("\n--- is_perimeter_segment ---")
	var arena := Rect2(0.0, 0.0, 1000.0, 1000.0)
	_t.check("H at top is perimeter", _wb.is_perimeter_segment({"type": "H", "pos": 0.0, "t0": 0.0, "t1": 100.0}, arena))
	_t.check("H at bottom is perimeter", _wb.is_perimeter_segment({"type": "H", "pos": 1000.0, "t0": 0.0, "t1": 100.0}, arena))
	_t.check("V at left is perimeter", _wb.is_perimeter_segment({"type": "V", "pos": 0.0, "t0": 0.0, "t1": 100.0}, arena))
	_t.check("V at right is perimeter", _wb.is_perimeter_segment({"type": "V", "pos": 1000.0, "t0": 0.0, "t1": 100.0}, arena))
	_t.check("H at y=500 not perimeter", not _wb.is_perimeter_segment({"type": "H", "pos": 500.0, "t0": 0.0, "t1": 100.0}, arena))


# ---------------------------------------------------------------------------
# collect_base_wall_segments (synthetic rooms)
# ---------------------------------------------------------------------------

func _test_collect_base_single_room() -> void:
	print("\n--- collect_base: single room ---")
	var rooms: Array = [{"id": 0, "rects": [Rect2(100.0, 100.0, 200.0, 200.0)]}]
	var segs := _wb.collect_base_wall_segments(rooms, [])
	# Single room should produce 4 boundary segments (top, bottom, left, right)
	_t.check("Single room: 4 segments", segs.size() == 4)
	var h_count := 0
	var v_count := 0
	for s in segs:
		if s["type"] == "H":
			h_count += 1
		else:
			v_count += 1
	_t.check("2 horizontal + 2 vertical", h_count == 2 and v_count == 2)


func _test_collect_base_two_rooms() -> void:
	print("\n--- collect_base: two rooms sharing edge ---")
	# Room 0: (0,0)-(200,200), Room 1: (200,0)-(400,200) — share x=200 edge
	var rooms: Array = [
		{"id": 0, "rects": [Rect2(0.0, 0.0, 200.0, 200.0)]},
		{"id": 1, "rects": [Rect2(200.0, 0.0, 200.0, 200.0)]},
	]
	var segs := _wb.collect_base_wall_segments(rooms, [])
	# Shared boundary at x=200 should exist because rooms differ on each side
	var shared_v := 0
	for s in segs:
		if s["type"] == "V" and absf(float(s["pos"]) - 200.0) < 1.0:
			shared_v += 1
	_t.check("Shared V wall at x=200 exists", shared_v >= 1)
	# Total: top H + bottom H (might be 2 each or merged into 1 spanning 0-400) + left V + right V + shared V
	_t.check("At least 5 segments", segs.size() >= 5)


# ---------------------------------------------------------------------------
# finalize_pipeline end-to-end
# ---------------------------------------------------------------------------

func _test_finalize_pipeline() -> void:
	print("\n--- finalize_pipeline ---")
	# Two adjacent rooms, one door between them
	var rooms: Array = [
		{"id": 0, "rects": [Rect2(0.0, 0.0, 200.0, 200.0)]},
		{"id": 1, "rects": [Rect2(200.0, 0.0, 200.0, 200.0)]},
	]
	var arena := Rect2(-50.0, -50.0, 500.0, 300.0)
	var base_segs := _wb.collect_base_wall_segments(rooms, [])
	# Vertical door at shared boundary x=200, y=80..120
	var door_rects: Array = [Rect2(196.0, 80.0, 8.0, 40.0)]
	var result := _wb.finalize_wall_segments(base_segs, door_rects, 16.0, 75.0, rooms, [], arena)
	var wall_segs := result["wall_segs"] as Array
	var pseudo_gaps := int(result["pseudo_gap_count"])
	_t.check("Finalized has segments", wall_segs.size() > 0)
	_t.check("Pseudo-gap count >= 0", pseudo_gaps >= 0)
	# The shared V wall should be cut by the door
	var shared_v_segs: Array = []
	for s in wall_segs:
		if s["type"] == "V" and absf(float(s["pos"]) - 200.0) < 1.0:
			shared_v_segs.append(s)
	_t.check("Shared V wall cut into >= 2 parts", shared_v_segs.size() >= 2)


# ---------------------------------------------------------------------------
# prune_redundant (interior wall between same room)
# ---------------------------------------------------------------------------

func _test_prune_redundant_interior() -> void:
	print("\n--- prune_redundant: interior ---")
	# L-shaped room: two rects that share an internal edge at y=200
	var rooms: Array = [
		{"id": 0, "rects": [Rect2(0.0, 0.0, 300.0, 200.0), Rect2(0.0, 200.0, 150.0, 200.0)]},
	]
	var arena := Rect2(-50.0, -50.0, 500.0, 500.0)
	var base_segs := _wb.collect_base_wall_segments(rooms, [])
	# The internal H edge at y=200 from x=0 to x=150 should be pruned (both sides are room 0)
	# But x=150 to x=300 is room/outside boundary → kept
	var result := _wb.finalize_wall_segments(base_segs, [], 16.0, 75.0, rooms, [], arena)
	var wall_segs := result["wall_segs"] as Array
	# Check that internal segment at y=200, x=[0,150] was pruned
	var internal_found := false
	for s in wall_segs:
		if s["type"] == "H" and absf(float(s["pos"]) - 200.0) < 1.0:
			if float(s["t0"]) < 10.0 and float(s["t1"]) > 140.0 and float(s["t1"]) < 160.0:
				internal_found = true
	_t.check("Interior L-shape wall pruned", not internal_found)
	# But the boundary segment from x=150 to x=300 at y=200 should remain
	var boundary_found := false
	for s in wall_segs:
		if s["type"] == "H" and absf(float(s["pos"]) - 200.0) < 1.0:
			if float(s["t0"]) >= 140.0:
				boundary_found = true
	_t.check("Boundary at y=200, x>150 kept", boundary_found)
