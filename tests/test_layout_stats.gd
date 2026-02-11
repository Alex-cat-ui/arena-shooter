## test_layout_stats.gd
## Generates ProceduralLayout instances and prints geometry/topology statistics.
## Run via: godot --headless res://tests/test_layout_stats.tscn
extends Node

const SEED_COUNT := 50
const ARENA := Rect2(-1100, -1100, 2200, 2200)


func _ready() -> void:
	print("=".repeat(60))
	print("LAYOUT STATS TEST: %d seeds, arena %s" % [SEED_COUNT, str(ARENA)])
	print("=".repeat(60))

	# Dummy nodes required by generate_and_build
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
	var composition_mode_stats: Dictionary = {}

	var total_count_rooms := 0
	var total_count_corridors := 0
	var total_closets := 0
	var total_closet_bad_entries := 0
	var total_gut_rects := 0
	var total_bad_edge_corridors := 0
	var total_dead_ends := 0
	var total_notched_rooms := 0
	var total_t_u_rooms := 0
	var total_central_missing := 0
	var total_non_uniform_door_layouts := 0

	for s in range(1, SEED_COUNT + 1):
		for child in walls_node.get_children():
			child.queue_free()
		await get_tree().process_frame

		var layout := ProceduralLayout.generate_and_build(ARENA, s, walls_node, debug_node, player_node)

		var mode_name: String = layout.layout_mode_name if layout.layout_mode_name != "" else "UNKNOWN"
		if not composition_mode_stats.has(mode_name):
			composition_mode_stats[mode_name] = 0
		composition_mode_stats[mode_name] = int(composition_mode_stats[mode_name]) + 1

		var count_rooms := 0
		var count_corridors := 0
		var closets_count := 0
		var closet_bad_entries_found := 0
		var gut_rects_found := 0
		var bad_edge_corridors_found := 0
		var dead_end_count := 0
		var notched_rooms_count := 0
		var t_u_rooms_count := layout._t_u_room_ids.size()
		var central_missing := 0
		var door_size_variants: Dictionary = {}

		for door_variant in layout.doors:
			var door_rect := door_variant as Rect2
			var opening_len := maxf(door_rect.size.x, door_rect.size.y)
			var opening_key := str(int(roundf(opening_len)))
			door_size_variants[opening_key] = true

		var unique_hubs: Array = []
		for hub_variant in layout._hub_ids:
			var hub_id := int(hub_variant)
			if hub_id not in unique_hubs:
				unique_hubs.append(hub_id)
		for hub_id in unique_hubs:
			if hub_id in layout._void_ids:
				continue
			if not layout._leaf_adj.has(hub_id):
				continue
			for n_variant in (layout._leaf_adj[hub_id] as Array):
				var ni := int(n_variant)
				if ni in layout._void_ids or ni == hub_id:
					continue
				var seg := layout._find_shared_split_seg(hub_id, ni)
				if seg.is_empty():
					continue
				if not layout._door_adj.has(hub_id):
					continue
				if ni in (layout._door_adj[hub_id] as Array):
					continue
				if layout._can_add_door_between(hub_id, ni) and layout._can_place_door_on_split(hub_id, ni, seg):
					central_missing += 1

		for i in range(layout.rooms.size()):
			if i in layout._void_ids:
				continue
			count_rooms += 1

			var room: Dictionary = layout.rooms[i]
			var is_corridor: bool = room["is_corridor"] == true
			var rects: Array = room["rects"] as Array

			if room.get("is_perimeter_notched", false) == true:
				notched_rooms_count += 1

			if is_corridor:
				count_corridors += 1
				if layout._is_bad_edge_corridor(i):
					bad_edge_corridors_found += 1

			var deg := 0
			if layout._door_adj.has(i):
				deg = (layout._door_adj[i] as Array).size()
			if not is_corridor and deg == 1:
				dead_end_count += 1

			for rect in rects:
				var r := rect as Rect2
				if layout._is_gut_rect(r):
					gut_rects_found += 1

			if layout._is_closet_room(i):
				closets_count += 1
				if deg != 1:
					closet_bad_entries_found += 1

		print("\n  seed=%d valid=%s mode=%s count_rooms=%d count_corridors=%d closets=%d closet_bad_entries=%d gut_rects=%d bad_edge_corridors=%d dead_end=%d notched=%d t_u=%d central_missing=%d door_variants=%d" % [
			s,
			str(layout.valid),
			mode_name,
			count_rooms,
			count_corridors,
			closets_count,
			closet_bad_entries_found,
			gut_rects_found,
			bad_edge_corridors_found,
			dead_end_count,
			notched_rooms_count,
			t_u_rooms_count,
			central_missing,
			door_size_variants.size(),
		])

		if layout.valid:
			valid_count += 1
		else:
			invalid_count += 1

		total_count_rooms += count_rooms
		total_count_corridors += count_corridors
		total_closets += closets_count
		total_closet_bad_entries += closet_bad_entries_found
		total_gut_rects += gut_rects_found
		total_bad_edge_corridors += bad_edge_corridors_found
		total_dead_ends += dead_end_count
		total_notched_rooms += notched_rooms_count
		total_t_u_rooms += t_u_rooms_count
		total_central_missing += central_missing
		if door_size_variants.size() > 1:
			total_non_uniform_door_layouts += 1

	print("\n")
	print("=".repeat(60))
	print("LAYOUT STATS SUMMARY (%d seeds)" % SEED_COUNT)
	print("=".repeat(60))
	print("  Valid:                    %d / %d (%.0f%%)" % [valid_count, SEED_COUNT, float(valid_count) / float(SEED_COUNT) * 100.0])
	print("  Invalid:                  %d" % invalid_count)
	print("  Avg count_rooms:          %.2f" % (float(total_count_rooms) / float(SEED_COUNT)))
	print("  Avg count_corridors:      %.2f" % (float(total_count_corridors) / float(SEED_COUNT)))
	print("  Avg closets_count:        %.2f" % (float(total_closets) / float(SEED_COUNT)))
	print("  Total closet bad entries: %d" % total_closet_bad_entries)
	print("  Total gut_rects_found:    %d" % total_gut_rects)
	print("  Total bad_edge_corridors: %d" % total_bad_edge_corridors)
	print("  Avg dead_end_count:       %.2f" % (float(total_dead_ends) / float(SEED_COUNT)))
	print("  Avg notched_rooms_count:  %.2f" % (float(total_notched_rooms) / float(SEED_COUNT)))
	print("  Avg t_u_rooms_count:      %.2f" % (float(total_t_u_rooms) / float(SEED_COUNT)))
	print("  Total central_missing:    %d" % total_central_missing)
	print("  Non-uniform door layouts: %d" % total_non_uniform_door_layouts)
	print("")
	print("  composition_mode_stats:")
	var sorted_modes: Array = composition_mode_stats.keys()
	sorted_modes.sort()
	for m in sorted_modes:
		var cnt := int(composition_mode_stats[m])
		print("    %-20s %d (%.0f%%)" % [m, cnt, float(cnt) / float(SEED_COUNT) * 100.0])

	print("")
	print("=".repeat(60))
	print("LAYOUT STATS TEST COMPLETE")
	print("=".repeat(60))

	var has_errors := (
		invalid_count > 0
		or total_gut_rects > 0
		or total_bad_edge_corridors > 0
		or total_closet_bad_entries > 0
		or total_central_missing > 0
		or total_non_uniform_door_layouts > 0
	)
	get_tree().quit(1 if has_errors else 0)
