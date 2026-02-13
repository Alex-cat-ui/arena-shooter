## test_hotline_similarity.gd
## V2 similarity/profile regression score.
## Run via: godot --headless res://tests/test_hotline_similarity.tscn
extends Node

const SEED_COUNT := 50
const TEST_MISSION := 3
const ARENA := Rect2(-1100, -1100, 2200, 2200)
const TARGET_SCORE := 95.0
const PROCEDURAL_LAYOUT_V2_SCRIPT := preload("res://src/systems/procedural_layout_v2.gd")


func _ready() -> void:
	print("=".repeat(68))
	print("V2 SIMILARITY TEST: %d seeds, arena %s" % [SEED_COUNT, str(ARENA)])
	print("Target score: %.1f" % TARGET_SCORE)
	print("=".repeat(68))

	var walls_node := Node2D.new()
	add_child(walls_node)
	var debug_node := Node2D.new()
	add_child(debug_node)
	var player_node := CharacterBody2D.new()
	var col_shape := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	col_shape.shape = shape
	player_node.add_child(col_shape)
	add_child(player_node)

	var valid_count := 0
	var invalid_count := 0
	var total_t_u_rooms := 0
	var total_closets := 0
	var total_outcrops := 0
	var total_outer_run_pct := 0.0
	var total_gut_rects := 0
	var total_missing_adj_doors := 0
	var total_half_doors := 0
	var total_door_overlaps := 0

	for s in range(1, SEED_COUNT + 1):
		for child in walls_node.get_children():
			child.queue_free()
		await get_tree().process_frame

		var layout := PROCEDURAL_LAYOUT_V2_SCRIPT.generate_and_build(ARENA, s, walls_node, debug_node, player_node, TEST_MISSION)
		if not layout.valid:
			invalid_count += 1
			continue

		valid_count += 1
		total_outcrops += layout.outcrop_count_stat
		total_outer_run_pct += layout.outer_longest_run_pct_stat
		total_t_u_rooms += _count_t_u_rooms(layout)
		total_closets += _count_closets(layout)
		total_gut_rects += _count_gut_rects(layout)
		total_missing_adj_doors += _count_missing_adjacent_doors(layout)
		total_half_doors += _count_half_doors(layout)
		total_door_overlaps += _count_overlapping_doors(layout)

	var avg_t_u := float(total_t_u_rooms) / maxf(float(SEED_COUNT), 1.0)
	var avg_closets := float(total_closets) / maxf(float(SEED_COUNT), 1.0)
	var avg_outcrops := float(total_outcrops) / maxf(float(SEED_COUNT), 1.0)
	var avg_outer_run_pct := float(total_outer_run_pct) / maxf(float(SEED_COUNT), 1.0)

	var hard_score := _hard_score(
		invalid_count,
		total_gut_rects,
		total_missing_adj_doors,
		total_half_doors,
		total_door_overlaps
	)
	var silhouette_score := _silhouette_score(avg_outer_run_pct, avg_outcrops)
	var shape_score := _shape_score(avg_t_u, avg_closets)
	var similarity_score := hard_score + silhouette_score + shape_score

	print("\n" + "-".repeat(68))
	print("Similarity metrics (V2 profile)")
	print("  valid layouts:              %d / %d" % [valid_count, SEED_COUNT])
	print("  invalid layouts:            %d" % invalid_count)
	print("  total gut rects:            %d" % total_gut_rects)
	print("  total missing_adj_doors:    %d" % total_missing_adj_doors)
	print("  total half_doors:           %d" % total_half_doors)
	print("  total door_overlaps:        %d" % total_door_overlaps)
	print("  avg t_u_rooms_count:        %.2f" % avg_t_u)
	print("  avg closets_count:          %.2f" % avg_closets)
	print("  avg outcrop_count:          %.2f" % avg_outcrops)
	print("  avg outer_run_pct:          %.2f" % avg_outer_run_pct)
	print("\nScoring")
	print("  hard_score:                 %.2f / 60" % hard_score)
	print("  silhouette_score:           %.2f / 20" % silhouette_score)
	print("  shape_score:                %.2f / 20" % shape_score)
	print("  V2SimilarityScore:          %.2f / 100" % similarity_score)
	print("  TARGET:                     %.2f" % TARGET_SCORE)

	var is_pass := similarity_score >= TARGET_SCORE
	print("\nRESULT: %s" % ("PASS" if is_pass else "FAIL"))
	print("=".repeat(68))
	get_tree().quit(0 if is_pass else 1)


func _hard_score(invalid_count: int, gut_count: int, missing_adj: int, half_doors: int, overlaps: int) -> float:
	if invalid_count > 0:
		return 0.0
	if gut_count > 0:
		return 0.0
	if missing_adj > 0:
		return 0.0
	if half_doors > 0:
		return 0.0
	if overlaps > 0:
		return 0.0
	return 60.0


func _silhouette_score(avg_outer_run_pct: float, avg_outcrops: float) -> float:
	var outer_term := clampf(1.0 - maxf(avg_outer_run_pct - 24.0, 0.0) / 20.0, 0.0, 1.0)
	var outcrop_term := 1.0 - minf(absf(avg_outcrops - 2.0), 2.0) / 2.0
	return clampf(20.0 * (outer_term * 0.7 + outcrop_term * 0.3), 0.0, 20.0)


func _shape_score(avg_t_u: float, avg_closets: float) -> float:
	var t_u_term := clampf(avg_t_u / 3.0, 0.0, 1.0)
	var closet_term := 1.0 - minf(absf(avg_closets - 2.0), 2.0) / 2.0
	return clampf(20.0 * (t_u_term * 0.7 + closet_term * 0.3), 0.0, 20.0)


func _count_t_u_rooms(layout) -> int:
	var count := 0
	var memory_variant = layout.get("room_generation_memory")
	if not (memory_variant is Array):
		return count
	for item_variant in (memory_variant as Array):
		var item := item_variant as Dictionary
		var room_type := str(item.get("type", ""))
		if room_type == "L" or room_type == "U" or room_type == "T":
			count += 1
	return count


func _count_closets(layout) -> int:
	var closets := 0
	for i in range(layout.rooms.size()):
		if i in layout._void_ids:
			continue
		if layout._is_closet_room(i):
			closets += 1
	return closets


func _is_gut_rect_v2(r: Rect2) -> bool:
	return minf(r.size.x, r.size.y) < 128.0 and maxf(r.size.x, r.size.y) > 256.0


func _count_gut_rects(layout) -> int:
	var count := 0
	for i in range(layout.rooms.size()):
		if i in layout._void_ids:
			continue
		var room: Dictionary = layout.rooms[i]
		for rect_variant in (room["rects"] as Array):
			var r := rect_variant as Rect2
			if _is_gut_rect_v2(r):
				count += 1
	return count


func _door_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


func _room_id_at_point(layout, p: Vector2) -> int:
	for i in range(layout.rooms.size()):
		if i in layout._void_ids:
			continue
		var room: Dictionary = layout.rooms[i]
		for rect_variant in (room["rects"] as Array):
			var r := rect_variant as Rect2
			if r.grow(0.25).has_point(p):
				return i
	return -1


func _door_adjacent_room_ids(layout, door: Rect2) -> Array:
	var ids: Dictionary = {}
	var center := door.get_center()
	var probe := maxf(layout._door_wall_thickness() * 0.8, 8.0)
	if door.size.y > door.size.x:
		var left_id := _room_id_at_point(layout, Vector2(center.x - probe, center.y))
		var right_id := _room_id_at_point(layout, Vector2(center.x + probe, center.y))
		if left_id >= 0:
			ids[left_id] = true
		if right_id >= 0:
			ids[right_id] = true
	else:
		var top_id := _room_id_at_point(layout, Vector2(center.x, center.y - probe))
		var bottom_id := _room_id_at_point(layout, Vector2(center.x, center.y + probe))
		if top_id >= 0:
			ids[top_id] = true
		if bottom_id >= 0:
			ids[bottom_id] = true
	return ids.keys()


func _count_half_doors(layout) -> int:
	var bad := 0
	for door_variant in layout.doors:
		var door := door_variant as Rect2
		var ids := _door_adjacent_room_ids(layout, door)
		if ids.size() != 2:
			bad += 1
	return bad


func _count_overlapping_doors(layout) -> int:
	var overlaps := 0
	for i in range(layout.doors.size()):
		var a := layout.doors[i] as Rect2
		for j in range(i + 1, layout.doors.size()):
			var b := layout.doors[j] as Rect2
			if a.grow(2.0).intersects(b.grow(2.0)):
				overlaps += 1
	return overlaps


func _count_missing_adjacent_doors(layout) -> int:
	var edge_keys_with_doors: Dictionary = {}
	for item_variant in layout._door_map:
		var item := item_variant as Dictionary
		var a := int(item["a"])
		var b := int(item["b"])
		edge_keys_with_doors[_door_key(a, b)] = true

	var missing := 0
	var edges: Array = layout._build_room_adjacency_edges()
	for edge_variant in edges:
		var edge := edge_variant as Dictionary
		var a := int(edge["a"])
		var b := int(edge["b"])
		if layout._is_closet_room(a) or layout._is_closet_room(b):
			continue
		if not layout._edge_is_geometrically_doorable(edge):
			continue
		if not (layout._room_requires_full_adjacency(a) or layout._room_requires_full_adjacency(b)):
			continue
		var key := _door_key(a, b)
		if not edge_keys_with_doors.has(key):
			missing += 1
	return missing

