extends SceneTree

const NAV_SERVICE_SCRIPT := preload("res://src/systems/navigation_service.gd")

const ROOM_C := Rect2(900.0, 568.0, 800.0, 600.0)
const SHADOW_C1 := Rect2(950.0, 650.0, 100.0, 100.0)
const CHOKE_BC := Rect2(800.0, 680.0, 100.0, 128.0)
const CHOKE_DC := Rect2(1692.0, 630.0, 16.0, 128.0)
const OBSTACLE_CLEARANCE_PX := 16.0
const CENTER := Vector2(1000.0, 700.0)

func _initialize() -> void:
	var service := NAV_SERVICE_SCRIPT.new()
	var obstacle := SHADOW_C1.grow(OBSTACLE_CLEARANCE_PX)
	var carved := service.call("_subtract_obstacles_from_rects", [ROOM_C], [obstacle]) as Array
	print("MODEL|carved_count=%d" % carved.size())
	for i in range(carved.size()):
		var r := carved[i] as Rect2
		print("CARVED|%d|%s" % [i, str(r)])

	var overlaps := [CHOKE_BC.grow(16.0), CHOKE_DC.grow(16.0)]
	var overlaps_carved := service.call("_subtract_obstacles_from_rects", overlaps, [obstacle]) as Array
	print("MODEL|overlap_count=%d" % overlaps_carved.size())
	for i in range(overlaps_carved.size()):
		var r := overlaps_carved[i] as Rect2
		print("OVERLAP|%d|%s" % [i, str(r)])

	var room_outlines: Array = []
	for rect_var in carved:
		room_outlines.append(service.call("_rect_to_outline", rect_var as Rect2))

	var all_outlines: Array = room_outlines.duplicate()
	for ov_var in overlaps_carved:
		all_outlines = service.call("_merge_overlapping_outlines", all_outlines, service.call("_rect_to_outline", ov_var as Rect2)) as Array

	print("MODEL|outline_count=%d" % all_outlines.size())
	for i in range(all_outlines.size()):
		var outline := all_outlines[i] as PackedVector2Array
		print("OUTLINE|%d|pts=%d|contains_center=%s|area=%.2f" % [
			i,
			outline.size(),
			str(Geometry2D.is_point_in_polygon(CENTER, outline)),
			_area(outline)
		])
		for j in range(outline.size()):
			print("OUTPT|%d|%d|%s" % [i, j, str(outline[j])])
	quit(0)

func _area(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	var sum := 0.0
	for i in range(poly.size()):
		var p0 := poly[i]
		var p1 := poly[(i + 1) % poly.size()]
		sum += p0.x * p1.y - p1.x * p0.y
	return sum * 0.5
