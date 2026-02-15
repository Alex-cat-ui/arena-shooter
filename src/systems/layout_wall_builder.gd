## layout_wall_builder.gd
## Wall segment collection, merging, door-cutting, gap-sealing, pruning,
## and scene-node construction extracted from ProceduralLayoutV2.
## Instance (RefCounted) — caches a 1×1 white texture for wall sprites.
class_name LayoutWallBuilder
extends RefCounted

const LayoutGeometryUtils = preload("res://src/systems/layout_geometry_utils.gd")

static var _cached_white_tex: ImageTexture = null


# ---------------------------------------------------------------------------
# Public entry points
# ---------------------------------------------------------------------------

## Collect raw boundary segments from room rects, classify edges, merge collinear.
## Returns Array of {type:"H"/"V", pos:float, t0:float, t1:float}.
func collect_base_wall_segments(rooms: Array, void_ids: Array) -> Array:
	var h_groups: Dictionary = {}
	var v_groups: Dictionary = {}
	var global_x_breaks: Array = []
	var global_y_breaks: Array = []
	for i in range(rooms.size()):
		if i in void_ids:
			continue
		for rect_variant in (rooms[i]["rects"] as Array):
			var r := rect_variant as Rect2
			if r.size.x <= 1.0 or r.size.y <= 1.0:
				continue
			global_x_breaks.append(LayoutGeometryUtils.quantize_coord(r.position.x))
			global_x_breaks.append(LayoutGeometryUtils.quantize_coord(r.end.x))
			global_y_breaks.append(LayoutGeometryUtils.quantize_coord(r.position.y))
			global_y_breaks.append(LayoutGeometryUtils.quantize_coord(r.end.y))
			_append_line_interval(h_groups, r.position.y, r.position.x, r.end.x)
			_append_line_interval(h_groups, r.end.y, r.position.x, r.end.x)
			_append_line_interval(v_groups, r.position.x, r.position.y, r.end.y)
			_append_line_interval(v_groups, r.end.x, r.position.y, r.end.y)

	var segs: Array = []
	segs.append_array(_line_groups_to_segments(h_groups, true, global_x_breaks, rooms, void_ids))
	segs.append_array(_line_groups_to_segments(v_groups, false, global_y_breaks, rooms, void_ids))
	return merge_collinear_segments(segs)


## Full finalize pipeline: merge → cut doors → seal gaps → merge → prune.
## Returns {wall_segs: Array, pseudo_gap_count: int}.
func finalize_wall_segments(base_segs: Array, all_door_rects: Array, wall_t: float,
		door_opening_len: float, rooms: Array, void_ids: Array, arena: Rect2,
		notch_config: Dictionary = {}) -> Dictionary:
	var merged := merge_collinear_segments(base_segs)
	var cutouts: Array = all_door_rects.duplicate()
	cutouts.append_array(_collect_hinge_notch_rects(all_door_rects, wall_t, arena, notch_config))
	var cut := cut_doors_from_segments(merged, cutouts, wall_t)
	var sealed := seal_non_door_gaps(cut, cutouts, wall_t, door_opening_len)
	var final := merge_collinear_segments(sealed)
	var redundant_pruned := prune_redundant_wall_segments(final, wall_t, rooms, void_ids, arena)
	var pruned := prune_redundant_parallel_duplicates(redundant_pruned, wall_t, rooms, void_ids, arena)
	var gap_count := count_non_door_gaps(pruned, cutouts, wall_t, door_opening_len)
	return {"wall_segs": pruned, "pseudo_gap_count": gap_count}


## Build wall collision + visual nodes under walls_node.
## Returns {wall_segs: Array, pseudo_gap_count: int}.
func build_walls(walls_node: Node2D, rooms: Array, void_ids: Array,
		door_rects: Array, entry_gate: Rect2, arena: Rect2,
		wall_t: float, door_opening_len: float, notch_config: Dictionary = {}) -> Dictionary:
	if not walls_node:
		return {"wall_segs": [], "pseudo_gap_count": 0}

	var base_segs := collect_base_wall_segments(rooms, void_ids)
	var all_door_rects: Array = door_rects.duplicate()
	if entry_gate != Rect2():
		all_door_rects.append(entry_gate)
	var result := finalize_wall_segments(base_segs, all_door_rects, wall_t, door_opening_len, rooms, void_ids, arena, notch_config)
	var wall_segs := result["wall_segs"] as Array

	var white_tex := _wall_white_texture()
	var walls_body := StaticBody2D.new()
	walls_body.name = "WallsBody"
	walls_body.collision_layer = 1
	walls_body.collision_mask = 1
	walls_node.add_child(walls_body)

	var walls_visual := Node2D.new()
	walls_visual.name = "WallsVisual"
	walls_node.add_child(walls_visual)

	for seg_variant in wall_segs:
		var seg := seg_variant as Dictionary
		var seg_type := seg["type"] as String
		var seg_pos := float(seg["pos"])
		var seg_t0 := float(seg["t0"])
		var seg_t1 := float(seg["t1"])
		var seg_len := seg_t1 - seg_t0
		if seg_len < 2.0:
			continue

		var shape := RectangleShape2D.new()
		var pos: Vector2
		var sz: Vector2
		if seg_type == "H":
			sz = Vector2(seg_len + 4.0, wall_t)
			pos = Vector2(seg_t0 + seg_len * 0.5 - 2.0, seg_pos)
		else:
			sz = Vector2(wall_t, seg_len + 4.0)
			pos = Vector2(seg_pos, seg_t0 + seg_len * 0.5 - 2.0)
		pos.x = roundf(pos.x * 0.5) * 2.0
		pos.y = roundf(pos.y * 0.5) * 2.0
		sz.x = maxf(roundf(sz.x * 0.5) * 2.0, 2.0)
		sz.y = maxf(roundf(sz.y * 0.5) * 2.0, 2.0)
		shape.size = sz
		var col := CollisionShape2D.new()
		col.shape = shape
		col.position = pos
		walls_body.add_child(col)
		var spr := Sprite2D.new()
		spr.texture = white_tex
		spr.scale = sz
		spr.modulate = Color.WHITE
		spr.position = pos
		walls_visual.add_child(spr)

	return result


## Build debug overlay: room outlines + door rects + entry gate.
func build_debug(debug_node: Node2D, rooms: Array, void_ids: Array,
		hub_ids: Array, door_rects: Array, entry_gate: Rect2) -> void:
	if not debug_node:
		return
	clear_node_children_detached(debug_node)
	for room_variant in rooms:
		var room := room_variant as Dictionary
		var rid := int(room["id"])
		var is_void := rid in void_ids
		var color := Color(0.2, 0.8, 0.2, 0.6)
		if is_void:
			color = Color(0.4, 0.4, 0.4, 0.3)
		elif rid in hub_ids:
			color = Color(1.0, 0.3, 0.3, 0.7)
		for rect_variant in (room["rects"] as Array):
			draw_rect_outline(debug_node, rect_variant as Rect2, color, 2.0)
	for door_variant in door_rects:
		draw_rect_outline(debug_node, door_variant as Rect2, Color(0.2, 0.5, 1.0, 0.7), 2.0)
	if entry_gate != Rect2():
		draw_rect_outline(debug_node, entry_gate, Color(0.0, 1.0, 1.0, 0.8), 3.0)


# ---------------------------------------------------------------------------
# Segment math (public for unit testing)
# ---------------------------------------------------------------------------

func merge_collinear_segments(segs: Array) -> Array:
	if segs.is_empty():
		return segs
	var h_segs: Array = []
	var v_segs: Array = []
	for s in segs:
		if s["type"] == "H":
			h_segs.append(s)
		else:
			v_segs.append(s)
	var result: Array = []
	result.append_array(_merge_segs_by_pos(h_segs))
	result.append_array(_merge_segs_by_pos(v_segs))
	return result


func cut_doors_from_segments(base_segs: Array, door_rects: Array, wall_t: float) -> Array:
	var result: Array = base_segs.duplicate(true)
	var axis_eps := maxf(1.5, wall_t * 0.2)
	for door_variant in door_rects:
		var door := door_variant as Rect2
		var door_is_vertical := door.size.y > door.size.x
		var new_result: Array = []
		for seg_variant in result:
			var seg := seg_variant as Dictionary
			var seg_type := seg["type"] as String
			var seg_pos := float(seg["pos"])
			var seg_t0 := float(seg["t0"])
			var seg_t1 := float(seg["t1"])
			var cut := false
			if seg_type == "V":
				if not door_is_vertical:
					new_result.append(seg)
					continue
				var door_x := door.position.x + door.size.x * 0.5
				if absf(door_x - seg_pos) <= axis_eps:
					var d_t0 := door.position.y
					var d_t1 := door.end.y
					if d_t0 < seg_t1 and d_t1 > seg_t0:
						cut = true
						if d_t0 > seg_t0 + 2.0:
							new_result.append({"type": "V", "pos": seg_pos, "t0": seg_t0, "t1": d_t0})
						if d_t1 < seg_t1 - 2.0:
							new_result.append({"type": "V", "pos": seg_pos, "t0": d_t1, "t1": seg_t1})
			else:
				if door_is_vertical:
					new_result.append(seg)
					continue
				var door_y := door.position.y + door.size.y * 0.5
				if absf(door_y - seg_pos) <= axis_eps:
					var d_t0h := door.position.x
					var d_t1h := door.end.x
					if d_t0h < seg_t1 and d_t1h > seg_t0:
						cut = true
						if d_t0h > seg_t0 + 2.0:
							new_result.append({"type": "H", "pos": seg_pos, "t0": seg_t0, "t1": d_t0h})
						if d_t1h < seg_t1 - 2.0:
							new_result.append({"type": "H", "pos": seg_pos, "t0": d_t1h, "t1": seg_t1})
			if not cut:
				new_result.append(seg)
		result = new_result
	return result


func seal_non_door_gaps(segs: Array, door_rects: Array, wall_t: float,
		door_opening_len: float) -> Array:
	if segs.is_empty():
		return segs
	var grouped: Dictionary = {}
	for seg_variant in segs:
		var seg := seg_variant as Dictionary
		var seg_type := seg["type"] as String
		var seg_pos := float(seg["pos"])
		var key := "%s:%.1f" % [seg_type, roundf(seg_pos * 2.0) / 2.0]
		if not grouped.has(key):
			grouped[key] = []
		(grouped[key] as Array).append(seg)

	var result: Array = []
	var max_gap := _pseudo_gap_limit(door_opening_len)
	for key_variant in grouped.keys():
		var group := grouped[key_variant] as Array
		group.sort_custom(func(a, b): return float(a["t0"]) < float(b["t0"]))
		if group.is_empty():
			continue
		var merged_group: Array = [group[0].duplicate()]
		for i in range(1, group.size()):
			var curr := (group[i] as Dictionary).duplicate()
			var last := merged_group[merged_group.size() - 1] as Dictionary
			var last_t1 := float(last["t1"])
			var curr_t0 := float(curr["t0"])
			var curr_t1 := float(curr["t1"])
			var seg_type := last["type"] as String
			var seg_pos := float(last["pos"])
			var gap := curr_t0 - last_t1
			if gap <= 0.5:
				last["t1"] = maxf(last_t1, curr_t1)
				merged_group[merged_group.size() - 1] = last
				continue
			var should_seal := gap <= max_gap and not _is_intentional_gap(seg_type, seg_pos, last_t1, curr_t0, door_rects, wall_t, door_opening_len)
			if should_seal:
				last["t1"] = curr_t1
				merged_group[merged_group.size() - 1] = last
				continue
			merged_group.append(curr)
		result.append_array(merged_group)
	return result


func count_non_door_gaps(segs: Array, door_rects: Array, wall_t: float,
		door_opening_len: float) -> int:
	if segs.is_empty():
		return 0
	var grouped: Dictionary = {}
	for seg_variant in segs:
		var seg := seg_variant as Dictionary
		var seg_type := seg["type"] as String
		var seg_pos := float(seg["pos"])
		var key := "%s:%.1f" % [seg_type, roundf(seg_pos * 2.0) / 2.0]
		if not grouped.has(key):
			grouped[key] = []
		(grouped[key] as Array).append(seg)
	var count := 0
	var max_gap := _pseudo_gap_limit(door_opening_len)
	for key_variant in grouped.keys():
		var group := grouped[key_variant] as Array
		group.sort_custom(func(a, b): return float(a["t0"]) < float(b["t0"]))
		for i in range(1, group.size()):
			var prev := group[i - 1] as Dictionary
			var curr := group[i] as Dictionary
			var gap_t0 := float(prev["t1"])
			var gap_t1 := float(curr["t0"])
			var gap := gap_t1 - gap_t0
			if gap <= 0.5 or gap > max_gap:
				continue
			var seg_type := prev["type"] as String
			var seg_pos := float(prev["pos"])
			if not _is_intentional_gap(seg_type, seg_pos, gap_t0, gap_t1, door_rects, wall_t, door_opening_len):
				count += 1
	return count


func prune_redundant_wall_segments(segs: Array, wall_t: float,
		rooms: Array, void_ids: Array, arena: Rect2) -> Array:
	if segs.is_empty():
		return segs
	var pruned: Array = []
	for seg_variant in segs:
		var seg := seg_variant as Dictionary
		if not _is_redundant_wall_segment(seg, wall_t, rooms, void_ids, arena):
			pruned.append(seg)
	return pruned


func prune_redundant_parallel_duplicates(segs: Array, wall_t: float,
		rooms: Array, void_ids: Array, arena: Rect2) -> Array:
	if segs.size() < 2:
		return segs
	var keep: Array = []
	for seg_variant in segs:
		keep.append(true)
	var near_dist := maxf(2.0, wall_t * 0.55)
	for i in range(segs.size()):
		if not keep[i]:
			continue
		var a := segs[i] as Dictionary
		for j in range(i + 1, segs.size()):
			if not keep[j]:
				continue
			var b := segs[j] as Dictionary
			if a["type"] != b["type"]:
				continue
			if absf(float(a["pos"]) - float(b["pos"])) > near_dist:
				continue
			if absf(float(a["t0"]) - float(b["t0"])) > 1.5:
				continue
			if absf(float(a["t1"]) - float(b["t1"])) > 1.5:
				continue
			if not _is_redundant_wall_segment(a, wall_t, rooms, void_ids, arena):
				continue
			if not _is_redundant_wall_segment(b, wall_t, rooms, void_ids, arena):
				continue
			keep[i] = false
			keep[j] = false
	var out: Array = []
	for idx in range(segs.size()):
		if keep[idx]:
			out.append(segs[idx])
	return out


func is_perimeter_segment(seg: Dictionary, arena: Rect2) -> bool:
	var seg_type := seg["type"] as String
	var seg_pos := float(seg["pos"])
	if seg_type == "H":
		return absf(seg_pos - arena.position.y) < 1.0 or absf(seg_pos - arena.end.y) < 1.0
	return absf(seg_pos - arena.position.x) < 1.0 or absf(seg_pos - arena.end.x) < 1.0


# ---------------------------------------------------------------------------
# Visual helpers
# ---------------------------------------------------------------------------

static func draw_rect_outline(parent: Node2D, r: Rect2, color: Color, width: float) -> void:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.add_point(r.position)
	line.add_point(Vector2(r.end.x, r.position.y))
	line.add_point(r.end)
	line.add_point(Vector2(r.position.x, r.end.y))
	line.add_point(r.position)
	parent.add_child(line)


static func clear_node_children_detached(parent: Node) -> void:
	if not parent:
		return
	var children := parent.get_children()
	for child in children:
		parent.remove_child(child)
		child.queue_free()


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _append_line_interval(groups: Dictionary, pos: float, t0: float, t1: float) -> void:
	var p := LayoutGeometryUtils.quantize_coord(pos)
	var a := LayoutGeometryUtils.quantize_coord(minf(t0, t1))
	var b := LayoutGeometryUtils.quantize_coord(maxf(t0, t1))
	if b <= a + 0.5:
		return
	if not groups.has(p):
		groups[p] = []
	(groups[p] as Array).append({"t0": a, "t1": b})


func _line_groups_to_segments(groups: Dictionary, horizontal: bool, global_breaks: Array,
		rooms: Array, void_ids: Array) -> Array:
	var segs: Array = []
	for key_variant in groups.keys():
		var pos := float(key_variant)
		var intervals := groups[key_variant] as Array
		var points := _collect_sorted_points(intervals)
		if points.size() < 2:
			continue
		var min_t := float(points[0])
		var max_t := float(points[points.size() - 1])
		for bp_variant in global_breaks:
			var bp := float(bp_variant)
			if bp <= min_t + 0.25 or bp >= max_t - 0.25:
				continue
			points.append(bp)
		points.sort()
		points = _dedupe_sorted_points(points)
		if points.size() < 2:
			continue
		for i in range(points.size() - 1):
			var a := float(points[i])
			var b := float(points[i + 1])
			if b <= a + 0.5:
				continue
			var mid := (a + b) * 0.5
			var side_a := -1
			var side_b := -1
			if horizontal:
				side_a = LayoutGeometryUtils.room_id_at_point(rooms, void_ids, Vector2(mid, pos - 2.0))
				side_b = LayoutGeometryUtils.room_id_at_point(rooms, void_ids, Vector2(mid, pos + 2.0))
				if side_a == side_b:
					continue
				segs.append({"type": "H", "pos": pos, "t0": a, "t1": b})
			else:
				side_a = LayoutGeometryUtils.room_id_at_point(rooms, void_ids, Vector2(pos - 2.0, mid))
				side_b = LayoutGeometryUtils.room_id_at_point(rooms, void_ids, Vector2(pos + 2.0, mid))
				if side_a == side_b:
					continue
				segs.append({"type": "V", "pos": pos, "t0": a, "t1": b})
	return segs


func _collect_sorted_points(intervals: Array) -> Array:
	var points: Array = []
	for interval_variant in intervals:
		var interval := interval_variant as Dictionary
		points.append(float(interval["t0"]))
		points.append(float(interval["t1"]))
	points.sort()
	return _dedupe_sorted_points(points)


func _dedupe_sorted_points(points: Array) -> Array:
	var unique_points: Array = []
	for p_variant in points:
		var p := float(p_variant)
		if unique_points.is_empty() or absf(float(unique_points[unique_points.size() - 1]) - p) > 0.25:
			unique_points.append(p)
	return unique_points


func _merge_segs_by_pos(segs: Array) -> Array:
	if segs.is_empty():
		return []
	var groups: Dictionary = {}
	for s in segs:
		var pos := float(s["pos"])
		var key := roundf(pos * 2.0) / 2.0
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(s)
	var result: Array = []
	for key_variant in groups.keys():
		var group := groups[key_variant] as Array
		group.sort_custom(func(a, b): return float(a["t0"]) < float(b["t0"]))
		var merged: Array = [group[0].duplicate()]
		for i in range(1, group.size()):
			var last := merged.back() as Dictionary
			var curr := group[i] as Dictionary
			if float(curr["t0"]) <= float(last["t1"]) + 1.0:
				last["t1"] = maxf(float(last["t1"]), float(curr["t1"]))
			else:
				merged.append(curr.duplicate())
		result.append_array(merged)
	return result


func _tiny_opening_limit(door_opening_len: float) -> float:
	return clampf(door_opening_len - 1.0, 24.0, 96.0)


func _pseudo_gap_limit(door_opening_len: float) -> float:
	return _tiny_opening_limit(door_opening_len)


func _is_intentional_gap(seg_type: String, seg_pos: float, gap_t0: float, gap_t1: float,
		door_rects: Array, wall_t: float, door_opening_len: float) -> bool:
	var gap_len := gap_t1 - gap_t0
	if gap_len <= 0.5:
		return true
	for door_variant in door_rects:
		var door := door_variant as Rect2
		var door_is_vertical := door.size.y > door.size.x
		if seg_type == "H":
			if door_is_vertical:
				continue
			var door_y := door.position.y + door.size.y * 0.5
			if absf(door_y - seg_pos) > wall_t:
				continue
			var ov0 := maxf(gap_t0, door.position.x)
			var ov1 := minf(gap_t1, door.end.x)
			if ov1 - ov0 >= minf(gap_len * 0.6, door_opening_len * 0.5):
				return true
		else:
			if not door_is_vertical:
				continue
			var door_x := door.position.x + door.size.x * 0.5
			if absf(door_x - seg_pos) > wall_t:
				continue
			var ov0v := maxf(gap_t0, door.position.y)
			var ov1v := minf(gap_t1, door.end.y)
			if ov1v - ov0v >= minf(gap_len * 0.6, door_opening_len * 0.5):
				return true
	return false


func _collect_hinge_notch_rects(door_rects: Array, wall_t: float, arena: Rect2,
		notch_config: Dictionary) -> Array:
	if not bool(notch_config.get("enabled", false)):
		return []

	var ratio := clampf(float(notch_config.get("span_ratio", 0.7)), 0.2, 1.5)
	var depth := clampf(float(notch_config.get("depth_px", wall_t)), 2.0, maxf(wall_t, 2.0))
	var notches: Array = []
	var perimeter_margin := maxf(wall_t, 2.0)

	for door_variant in door_rects:
		var door := door_variant as Rect2
		if door == Rect2():
			continue
		if _door_touches_perimeter(door, arena, perimeter_margin):
			continue
		var is_vertical := door.size.y > door.size.x
		var span := maxf(door.size.x, door.size.y)
		if span <= 2.0:
			continue
		var notch_span := maxf(4.0, span * ratio)
		if is_vertical:
			var hinge_y := door.position.y
			notches.append(Rect2(
				door.position.x - notch_span,
				hinge_y - depth * 0.5,
				notch_span,
				depth
			))
			notches.append(Rect2(
				door.end.x,
				hinge_y - depth * 0.5,
				notch_span,
				depth
			))
		else:
			var hinge_x := door.position.x
			notches.append(Rect2(
				hinge_x - depth * 0.5,
				door.position.y - notch_span,
				depth,
				notch_span
			))
			notches.append(Rect2(
				hinge_x - depth * 0.5,
				door.end.y,
				depth,
				notch_span
			))

	return notches


func _door_touches_perimeter(door: Rect2, arena: Rect2, margin: float) -> bool:
	if arena == Rect2():
		return false
	return (
		absf(door.position.x - arena.position.x) <= margin
		or absf(door.end.x - arena.end.x) <= margin
		or absf(door.position.y - arena.position.y) <= margin
		or absf(door.end.y - arena.end.y) <= margin
	)


func _is_redundant_wall_segment(seg: Dictionary, wall_t: float,
		rooms: Array, void_ids: Array, arena: Rect2) -> bool:
	if is_perimeter_segment(seg, arena):
		return false
	var seg_type := seg["type"] as String
	var seg_pos := float(seg["pos"])
	var t0 := float(seg["t0"])
	var t1 := float(seg["t1"])
	var length := t1 - t0
	if length <= 4.0:
		return false
	var side_offset := maxf(wall_t * 0.8, 10.0)
	var checks := PackedFloat32Array([0.15, 0.35, 0.50, 0.65, 0.85])
	var valid_samples := 0
	var same_room_samples := 0
	for ratio in checks:
		var t := lerpf(t0, t1, ratio)
		var p_a: Vector2
		var p_b: Vector2
		if seg_type == "H":
			p_a = Vector2(t, seg_pos - side_offset)
			p_b = Vector2(t, seg_pos + side_offset)
		else:
			p_a = Vector2(seg_pos - side_offset, t)
			p_b = Vector2(seg_pos + side_offset, t)
		var room_a := LayoutGeometryUtils.room_id_at_point(rooms, void_ids, p_a)
		var room_b := LayoutGeometryUtils.room_id_at_point(rooms, void_ids, p_b)
		if room_a < 0 or room_b < 0:
			continue
		valid_samples += 1
		if room_a != room_b:
			return false
		same_room_samples += 1
	return valid_samples >= 3 and same_room_samples >= 3


func _wall_white_texture() -> ImageTexture:
	if _cached_white_tex and is_instance_valid(_cached_white_tex):
		return _cached_white_tex
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.WHITE)
	_cached_white_tex = ImageTexture.create_from_image(img)
	return _cached_white_tex
