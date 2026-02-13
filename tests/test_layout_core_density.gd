## test_layout_core_density.gd
## Core-center topology regression test for ProceduralLayoutV2.
## Run via: godot --headless res://tests/test_layout_core_density.tscn
extends Node

const SEED_COUNT := 50
const TEST_MISSION := 3
const ARENA := Rect2(-1100, -1100, 2200, 2200)

const MIN_AVG_CENTER_ROOMS := 4.0
const MIN_CENTER_DEG3PLUS_PCT := 30.0
const MIN_AVG_CENTER_DEGREE := 2.20
const MAX_AVG_CORE_DOMINANCE := 0.62
const MAX_AVG_NON_CLOSET_DEAD_ENDS := 3.60

const PROCEDURAL_LAYOUT_V2_SCRIPT := preload("res://src/systems/procedural_layout_v2.gd")


func _door_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


func _room_id_at_point(layout, p: Vector2) -> int:
	for i in range(layout.rooms.size()):
		if i in layout._void_ids:
			continue
		var room := layout.rooms[i] as Dictionary
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


func _count_non_closet_dead_ends(layout) -> int:
	var count := 0
	for i in range(layout.rooms.size()):
		if i in layout._void_ids:
			continue
		if layout._is_closet_room(i):
			continue
		if not layout._door_adj.has(i):
			continue
		var deg := (layout._door_adj[i] as Array).size()
		if deg <= 1:
			count += 1
	return count


func _core_degree_stats(layout, core_ids: Array) -> Dictionary:
	var deg3plus := 0
	var deg_sum := 0.0
	for rid_variant in core_ids:
		var rid := int(rid_variant)
		if rid < 0 or rid >= layout.rooms.size():
			continue
		if not layout._door_adj.has(rid):
			continue
		var deg := (layout._door_adj[rid] as Array).size()
		deg_sum += float(deg)
		if deg >= 3:
			deg3plus += 1
	return {
		"deg3plus": deg3plus,
		"deg_sum": deg_sum,
	}


func _core_dominance(layout, core_ids: Array) -> float:
	var total_area := 0.0
	var max_area := 0.0
	for rid_variant in core_ids:
		var rid := int(rid_variant)
		var area := float(layout._room_total_area(rid))
		total_area += area
		max_area = maxf(max_area, area)
	if total_area <= 1.0:
		return 1.0
	return max_area / total_area


func _ready() -> void:
	print("=".repeat(68))
	print("CORE DENSITY TEST (V2): %d seeds, arena %s" % [SEED_COUNT, str(ARENA)])
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
	var total_center_rooms := 0
	var total_center_deg3plus := 0
	var total_center_degree_sum := 0.0
	var total_core_dominance := 0.0
	var total_non_closet_dead_ends := 0
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
			print("  seed=%d valid=false fail_reason=%s" % [s, layout.validate_fail_reason])
			continue

		valid_count += 1
		var core_ids: Array = layout._core_non_closet_ids()
		var core_count := core_ids.size()
		var core_stats := _core_degree_stats(layout, core_ids)
		var core_deg3plus := int(core_stats["deg3plus"])
		var core_deg_sum := float(core_stats["deg_sum"])
		var core_dominance := _core_dominance(layout, core_ids)
		var non_closet_dead_ends := _count_non_closet_dead_ends(layout)

		var missing_adj := _count_missing_adjacent_doors(layout)
		var half_doors := _count_half_doors(layout)
		var overlaps := _count_overlapping_doors(layout)

		total_center_rooms += core_count
		total_center_deg3plus += core_deg3plus
		total_center_degree_sum += core_deg_sum
		total_core_dominance += core_dominance
		total_non_closet_dead_ends += non_closet_dead_ends
		total_missing_adj_doors += missing_adj
		total_half_doors += half_doors
		total_door_overlaps += overlaps

		var center_deg3plus_pct := float(core_deg3plus) * 100.0 / maxf(float(core_count), 1.0)
		var center_avg_deg := core_deg_sum / maxf(float(core_count), 1.0)
		print("  seed=%d core_rooms=%d core_deg3plus=%.1f%% core_avg_deg=%.2f core_dominance=%.2f non_closet_dead_ends=%d missing_adj=%d half=%d overlaps=%d" % [
			s,
			core_count,
			center_deg3plus_pct,
			center_avg_deg,
			core_dominance,
			non_closet_dead_ends,
			missing_adj,
			half_doors,
			overlaps,
		])

	var valid_denom := maxf(float(valid_count), 1.0)
	var avg_center_rooms := float(total_center_rooms) / valid_denom
	var center_deg3plus_pct_total := float(total_center_deg3plus) * 100.0 / maxf(float(total_center_rooms), 1.0)
	var avg_center_degree := total_center_degree_sum / maxf(float(total_center_rooms), 1.0)
	var avg_core_dominance := total_core_dominance / valid_denom
	var avg_non_closet_dead_ends := float(total_non_closet_dead_ends) / valid_denom

	print("\n" + "-".repeat(68))
	print("Core topology metrics")
	print("  valid layouts:              %d / %d" % [valid_count, SEED_COUNT])
	print("  invalid layouts:            %d" % invalid_count)
	print("  avg center_room_count:      %.2f" % avg_center_rooms)
	print("  center deg3+ pct:           %.2f" % center_deg3plus_pct_total)
	print("  avg center degree:          %.2f" % avg_center_degree)
	print("  avg core dominance:         %.3f" % avg_core_dominance)
	print("  avg non_closet_dead_ends:   %.2f" % avg_non_closet_dead_ends)
	print("  total missing_adj_doors:    %d" % total_missing_adj_doors)
	print("  total half_doors:           %d" % total_half_doors)
	print("  total door_overlaps:        %d" % total_door_overlaps)

	var has_errors := (
		invalid_count > 0
		or total_missing_adj_doors > 0
		or total_half_doors > 0
		or total_door_overlaps > 0
		or avg_center_rooms < MIN_AVG_CENTER_ROOMS
		or center_deg3plus_pct_total < MIN_CENTER_DEG3PLUS_PCT
		or avg_center_degree < MIN_AVG_CENTER_DEGREE
		or avg_core_dominance > MAX_AVG_CORE_DOMINANCE
		or avg_non_closet_dead_ends > MAX_AVG_NON_CLOSET_DEAD_ENDS
	)

	print("\nRESULT: %s" % ("PASS" if not has_errors else "FAIL"))
	print("=".repeat(68))
	get_tree().quit(1 if has_errors else 0)
