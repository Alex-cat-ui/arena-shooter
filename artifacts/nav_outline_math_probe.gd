extends SceneTree

const NAV_CARVE_EPSILON := 0.5
const ROOM_C := Rect2(900.0, 568.0, 800.0, 600.0)
const SHADOW_C1 := Rect2(950.0, 650.0, 100.0, 100.0)
const SHADOW_C2 := Rect2(1450.0, 850.0, 100.0, 100.0)
const CHOKE_BC := Rect2(800.0, 680.0, 100.0, 128.0)
const CHOKE_DC := Rect2(1692.0, 630.0, 16.0, 128.0)
const OBSTACLE_CLEARANCE_PX := 16.0
const CENTER := Vector2(1000.0, 700.0)

func _initialize() -> void:
	var obstacles: Array[Rect2] = [SHADOW_C1.grow(OBSTACLE_CLEARANCE_PX), SHADOW_C2.grow(OBSTACLE_CLEARANCE_PX)]
	var carved := _subtract_obstacles_from_rects([ROOM_C], obstacles)
	print("MODEL2|carved_count=%d" % carved.size())
	for i in range(carved.size()):
		print("CARVED|%d|%s" % [i, str(carved[i])])

	var room_outlines: Array = []
	for rect_var in carved:
		room_outlines.append(_rect_to_outline(rect_var as Rect2))

	var overlaps := [CHOKE_BC.grow(16.0), CHOKE_DC.grow(16.0)]
	var overlaps_carved := _subtract_obstacles_from_rects(overlaps, obstacles)
	print("MODEL2|overlap_count=%d" % overlaps_carved.size())
	for i in range(overlaps_carved.size()):
		print("OVERLAP|%d|%s" % [i, str(overlaps_carved[i])])

	var all_outlines: Array = room_outlines.duplicate()
	for ov_var in overlaps_carved:
		all_outlines = _merge_overlapping_outlines(all_outlines, _rect_to_outline(ov_var as Rect2))
	print("MODEL2|outline_count=%d" % all_outlines.size())
	for i in range(all_outlines.size()):
		var outline := all_outlines[i] as PackedVector2Array
		print("OUTLINE|%d|pts=%d|contains_center=%s|area=%.2f" % [
			i,
			outline.size(),
			str(Geometry2D.is_point_in_polygon(CENTER, outline)),
			_polygon_area(outline)
		])
		for j in range(outline.size()):
			print("OUTPT|%d|%d|%s" % [i, j, str(outline[j])])
	quit(0)

func _subtract_obstacles_from_rects(rects: Array, obstacles: Array[Rect2]) -> Array:
	if rects.is_empty() or obstacles.is_empty():
		return rects.duplicate()
	var carved: Array[Rect2] = []
	for rect_variant in rects:
		var source := rect_variant as Rect2
		if source.size.x <= NAV_CARVE_EPSILON or source.size.y <= NAV_CARVE_EPSILON:
			continue
		var fragments: Array[Rect2] = [source]
		for obstacle in obstacles:
			var next_fragments: Array[Rect2] = []
			for fragment_variant in fragments:
				var fragment := fragment_variant as Rect2
				next_fragments.append_array(_subtract_rect(fragment, obstacle))
			fragments = next_fragments
			if fragments.is_empty():
				break
		for fragment in fragments:
			if fragment.size.x <= NAV_CARVE_EPSILON or fragment.size.y <= NAV_CARVE_EPSILON:
				continue
			carved.append(fragment)
	return carved

func _subtract_rect(source: Rect2, obstacle: Rect2) -> Array[Rect2]:
	var intersection := source.intersection(obstacle)
	if intersection.size.x <= NAV_CARVE_EPSILON or intersection.size.y <= NAV_CARVE_EPSILON:
		return [source]
	var out: Array[Rect2] = []
	var top_h := intersection.position.y - source.position.y
	if top_h > NAV_CARVE_EPSILON:
		out.append(Rect2(source.position.x, source.position.y, source.size.x, top_h))
	var bottom_h := source.end.y - intersection.end.y
	if bottom_h > NAV_CARVE_EPSILON:
		out.append(Rect2(source.position.x, intersection.end.y, source.size.x, bottom_h))
	var left_w := intersection.position.x - source.position.x
	if left_w > NAV_CARVE_EPSILON:
		out.append(Rect2(source.position.x, intersection.position.y, left_w, intersection.size.y))
	var right_w := source.end.x - intersection.end.x
	if right_w > NAV_CARVE_EPSILON:
		out.append(Rect2(intersection.end.x, intersection.position.y, right_w, intersection.size.y))
	return out

func _rect_to_outline(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		r.position,
		Vector2(r.end.x, r.position.y),
		r.end,
		Vector2(r.position.x, r.end.y),
	])

func _merge_overlapping_outlines(existing_outlines: Array, addition: PackedVector2Array) -> Array:
	var pending: Array = []
	for outline_variant in existing_outlines:
		var outline := outline_variant as PackedVector2Array
		if not outline.is_empty():
			pending.append(outline)
	if not addition.is_empty():
		pending.append(addition)
	var merged_any := true
	while merged_any:
		merged_any = false
		var i := 0
		while i < pending.size():
			var j := i + 1
			while j < pending.size():
				var a := pending[i] as PackedVector2Array
				var b := pending[j] as PackedVector2Array
				if not _polygons_have_area_overlap(a, b):
					j += 1
					continue
				var merged := Geometry2D.merge_polygons(a, b)
				if merged.is_empty():
					j += 1
					continue
				pending[i] = merged[0]
				pending.remove_at(j)
				for hole_idx in range(1, merged.size()):
					pending.append(merged[hole_idx])
				merged_any = true
				j = i + 1
			i += 1
	return pending

func _polygons_have_area_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	var intersections := Geometry2D.intersect_polygons(a, b)
	if intersections.is_empty():
		return false
	for poly_variant in intersections:
		var poly := poly_variant as PackedVector2Array
		if absf(_polygon_area(poly)) > NAV_CARVE_EPSILON:
			return true
	return false

func _polygon_area(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	var sum := 0.0
	for i in range(poly.size()):
		var p0 := poly[i]
		var p1 := poly[(i + 1) % poly.size()]
		sum += p0.x * p1.y - p1.x * p0.y
	return sum * 0.5
