## test_layout_stats.gd
## Generates ProceduralLayoutV2 instances and prints geometry/topology statistics.
## Run via: godot --headless res://tests/test_layout_stats.tscn
extends Node

const SEED_COUNT := 30
const ARENA := Rect2(-1100, -1100, 2200, 2200)
const WALL_SAMPLE_STEP := 32.0
const WALL_POINT_EPS := 2.5
const MAX_AVG_OUTER_RUN_PCT := 31.0
const MAX_SINGLE_OUTER_RUN_PCT := 40.0
const MIN_AVG_EXTRA_LOOPS := 0.05
const MIN_NON_CLOSET_DEG3PLUS_PCT := 23.0
const MAX_AVG_NON_CLOSET_DEAD_ENDS := 3.00
const PLAYER_SPAWN_NORTH_OFFSET := 100.0
const PLAYER_SPAWN_NORTH_TOLERANCE := 40.0
const TEST_MISSION := 3
const PROCEDURAL_LAYOUT_V2_SCRIPT := preload("res://src/systems/procedural_layout_v2.gd")


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


func _is_point_in_opening(layout, p: Vector2, eps: float) -> bool:
	for door_variant in layout.doors:
		var d := door_variant as Rect2
		if d.grow(eps).has_point(p):
			return true
	if layout._entry_gate != Rect2() and layout._entry_gate.grow(eps).has_point(p):
		return true
	return false


func _is_point_near_wall_segment(wall_segs: Array, p: Vector2, eps: float) -> bool:
	for seg_variant in wall_segs:
		var seg := seg_variant as Dictionary
		var seg_type := seg["type"] as String
		var pos := float(seg["pos"])
		var t0 := float(seg["t0"])
		var t1 := float(seg["t1"])
		if seg_type == "H":
			if absf(p.y - pos) <= eps and p.x >= t0 - eps and p.x <= t1 + eps:
				return true
		else:
			if absf(p.x - pos) <= eps and p.y >= t0 - eps and p.y <= t1 + eps:
				return true
	return false


func _count_extra_wall_segments(layout, wall_segs: Array) -> int:
	var wall_t: float = GameConfig.wall_thickness if GameConfig else 16.0
	var side_offset := maxf(wall_t * 0.8, 10.0)
	var checks := PackedFloat32Array([0.15, 0.35, 0.50, 0.65, 0.85])
	var extra_count := 0

	for seg_variant in wall_segs:
		var seg := seg_variant as Dictionary
		var seg_type := seg["type"] as String
		var pos := float(seg["pos"])
		var t0 := float(seg["t0"])
		var t1 := float(seg["t1"])
		var seg_len := t1 - t0
		if seg_len < 24.0:
			continue

		var same_room_hits := 0
		var valid_hits := 0
		for ratio in checks:
			var t := lerpf(t0, t1, ratio)
			var pa: Vector2
			var pb: Vector2
			if seg_type == "H":
				pa = Vector2(t, pos - side_offset)
				pb = Vector2(t, pos + side_offset)
			else:
				pa = Vector2(pos - side_offset, t)
				pb = Vector2(pos + side_offset, t)
			var ra := _room_id_at_point(layout, pa)
			var rb := _room_id_at_point(layout, pb)
			if ra < 0 or rb < 0:
				continue
			valid_hits += 1
			if ra == rb:
				same_room_hits += 1

		if valid_hits >= 3 and same_room_hits >= 3:
			extra_count += 1

	return extra_count


func _count_room_wall_leaks(layout, wall_segs: Array) -> int:
	var leaks := 0
	var eps := WALL_POINT_EPS

	for i in range(layout.rooms.size()):
		if i in layout._void_ids:
			continue
		var room := layout.rooms[i] as Dictionary
		for rect_variant in (room["rects"] as Array):
			var r := rect_variant as Rect2
			if r.size.x < 8.0 or r.size.y < 8.0:
				continue

			# top edge
			var tx := r.position.x + WALL_SAMPLE_STEP * 0.5
			while tx < r.end.x:
				var inside_t := Vector2(tx, r.position.y + eps)
				var outside_t := Vector2(tx, r.position.y - eps)
				var inside_id_t := _room_id_at_point(layout, inside_t)
				var outside_id_t := _room_id_at_point(layout, outside_t)
				if inside_id_t == i and outside_id_t != i:
					if not _is_point_near_wall_segment(wall_segs, Vector2(tx, r.position.y), eps * 2.0) and not _is_point_in_opening(layout, Vector2(tx, r.position.y), eps * 2.0):
						leaks += 1
						break
				tx += WALL_SAMPLE_STEP

			# bottom edge
			var bx := r.position.x + WALL_SAMPLE_STEP * 0.5
			while bx < r.end.x:
				var inside_b := Vector2(bx, r.end.y - eps)
				var outside_b := Vector2(bx, r.end.y + eps)
				var inside_id_b := _room_id_at_point(layout, inside_b)
				var outside_id_b := _room_id_at_point(layout, outside_b)
				if inside_id_b == i and outside_id_b != i:
					if not _is_point_near_wall_segment(wall_segs, Vector2(bx, r.end.y), eps * 2.0) and not _is_point_in_opening(layout, Vector2(bx, r.end.y), eps * 2.0):
						leaks += 1
						break
				bx += WALL_SAMPLE_STEP

			# left edge
			var ly := r.position.y + WALL_SAMPLE_STEP * 0.5
			while ly < r.end.y:
				var inside_l := Vector2(r.position.x + eps, ly)
				var outside_l := Vector2(r.position.x - eps, ly)
				var inside_id_l := _room_id_at_point(layout, inside_l)
				var outside_id_l := _room_id_at_point(layout, outside_l)
				if inside_id_l == i and outside_id_l != i:
					if not _is_point_near_wall_segment(wall_segs, Vector2(r.position.x, ly), eps * 2.0) and not _is_point_in_opening(layout, Vector2(r.position.x, ly), eps * 2.0):
						leaks += 1
						break
				ly += WALL_SAMPLE_STEP

			# right edge
			var ry := r.position.y + WALL_SAMPLE_STEP * 0.5
			while ry < r.end.y:
				var inside_r := Vector2(r.end.x - eps, ry)
				var outside_r := Vector2(r.end.x + eps, ry)
				var inside_id_r := _room_id_at_point(layout, inside_r)
				var outside_id_r := _room_id_at_point(layout, outside_r)
				if inside_id_r == i and outside_id_r != i:
					if not _is_point_near_wall_segment(wall_segs, Vector2(r.end.x, ry), eps * 2.0) and not _is_point_in_opening(layout, Vector2(r.end.x, ry), eps * 2.0):
						leaks += 1
						break
				ry += WALL_SAMPLE_STEP

	return leaks


func _is_gut_rect_v2(r: Rect2) -> bool:
	return minf(r.size.x, r.size.y) < 128.0 and maxf(r.size.x, r.size.y) > 256.0


func _is_door_graph_connected(layout) -> bool:
	var solid_ids: Array[int] = []
	for i in range(layout.rooms.size()):
		if i in layout._void_ids:
			continue
		solid_ids.append(i)
	if solid_ids.is_empty():
		return false

	var start_id := solid_ids[0]
	var visited: Dictionary = {start_id: true}
	var queue: Array = [start_id]
	while not queue.is_empty():
		var curr := int(queue.pop_front())
		if not layout._door_adj.has(curr):
			continue
		for n_variant in (layout._door_adj[curr] as Array):
			var ni := int(n_variant)
			if ni in layout._void_ids:
				continue
			if visited.has(ni):
				continue
			visited[ni] = true
			queue.append(ni)
	return visited.size() == solid_ids.size()


func _door_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


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


func _is_spawn_stuck(player_node: CharacterBody2D) -> bool:
	var probes := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	for dir_variant in probes:
		var dir := dir_variant as Vector2
		if not player_node.test_move(player_node.global_transform, dir * 4.0):
			return false
	return true


func _is_spawn_near_north_entry(layout, player_pos: Vector2) -> bool:
	if layout._entry_gate == Rect2():
		return false
	var gate := layout._entry_gate as Rect2
	var target: Vector2 = gate.get_center() + Vector2(0.0, -PLAYER_SPAWN_NORTH_OFFSET)
	return player_pos.distance_to(target) <= PLAYER_SPAWN_NORTH_TOLERANCE


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
	var fail_reason_stats: Dictionary = {}

	var total_count_rooms := 0
	var total_count_corridors := 0
	var total_closets := 0
	var total_closet_range_violations := 0
	var total_closet_bad_entries := 0
	var total_gut_rects := 0
	var total_bad_edge_corridors := 0
	var total_dead_ends := 0
	var total_notched_rooms := 0
	var total_t_u_rooms := 0
	var total_central_missing := 0
	var total_non_uniform_door_layouts := 0
	var total_pseudo_gaps := 0
	var total_tiny_gaps := 0
	var total_north_core_exit_fails := 0
	var total_outcrops := 0
	var total_outer_longest_run_pct := 0.0
	var max_outer_longest_run_pct := 0.0
	var total_attempts := 0
	var total_extra_loops := 0
	var total_extra_walls := 0
	var total_walkability_issues := 0
	var total_room_wall_leaks := 0
	var total_missing_adjacent_doors := 0
	var total_half_doors := 0
	var total_door_overlaps := 0
	var total_closet_no_door := 0
	var total_closet_multi_door := 0
	var total_non_closet_rooms := 0
	var total_non_closet_deg3plus := 0
	var total_non_closet_dead_ends := 0
	var total_bad_spawn_rooms := 0
	var total_stuck_spawns := 0

	for s in range(1, SEED_COUNT + 1):
		for child in walls_node.get_children():
			child.queue_free()
		await get_tree().process_frame

		var layout := PROCEDURAL_LAYOUT_V2_SCRIPT.generate_and_build(ARENA, s, walls_node, debug_node, player_node, TEST_MISSION)

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
		var t_u_rooms_count := 0
		var central_missing := 0
		var door_size_variants: Dictionary = {}
		var pseudo_gap_count := layout.pseudo_gap_count_stat
		var north_core_exit_fail := layout.north_core_exit_fail_stat
		var outcrop_count := layout.outcrop_count_stat
		var outer_longest_run_pct := layout.outer_longest_run_pct_stat
		var attempts_count := layout.generation_attempts_stat
		var extra_loops_count := layout.extra_loops
		var wall_segs := layout._compute_cut_wall_segments_for_validation()
		var all_door_rects: Array = layout.doors.duplicate()
		if layout._entry_gate != Rect2():
			all_door_rects.append(layout._entry_gate)
		var tiny_gaps_found := layout._count_non_door_gaps(wall_segs, all_door_rects, layout._door_wall_thickness())
		var extra_walls_found := _count_extra_wall_segments(layout, wall_segs)
		var room_wall_leaks_found := _count_room_wall_leaks(layout, wall_segs)
		var missing_adjacent_doors := _count_missing_adjacent_doors(layout)
		var half_doors := _count_half_doors(layout)
		var door_overlaps := _count_overlapping_doors(layout)
		var closet_no_door_found := 0
		var closet_multi_door_found := 0
		var non_closet_rooms_count := 0
		var non_closet_deg3plus_count := 0
		var non_closet_dead_ends_count := 0
		var bad_spawn_room_found := 0
		var stuck_spawn_found := 0
		var walk_unreach := 0
		var walkability_issue := not _is_door_graph_connected(layout)
		var fail_reason: String = layout.validate_fail_reason if not layout.valid else ""

		var spawn_room_id := _room_id_at_point(layout, player_node.global_position)
		var spawn_near_north := _is_spawn_near_north_entry(layout, player_node.global_position)
		if not spawn_near_north:
			bad_spawn_room_found = 1
		elif spawn_room_id >= 0 and layout._is_closet_room(spawn_room_id):
			bad_spawn_room_found = 1
		if _is_spawn_stuck(player_node):
			stuck_spawn_found = 1

		var memory_variant = layout.get("room_generation_memory")
		if memory_variant is Array:
			for item_variant in (memory_variant as Array):
				var item := item_variant as Dictionary
				var room_type := str(item.get("type", ""))
				if room_type == "L" or room_type == "U" or room_type == "T":
					t_u_rooms_count += 1

		for door_variant in layout.doors:
			var door_rect := door_variant as Rect2
			var opening_len := maxf(door_rect.size.x, door_rect.size.y)
			var opening_key := str(int(roundf(opening_len)))
			door_size_variants[opening_key] = true

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

			var deg := 0
			if layout._door_adj.has(i):
				deg = (layout._door_adj[i] as Array).size()
			if not is_corridor and deg == 1:
				dead_end_count += 1

			for rect in rects:
				var r := rect as Rect2
				if _is_gut_rect_v2(r):
					gut_rects_found += 1

			if layout._is_closet_room(i):
				closets_count += 1
				if deg < 1:
					closet_no_door_found += 1
				elif deg > 1:
					closet_multi_door_found += 1
				if deg != 1:
					closet_bad_entries_found += 1
			else:
				non_closet_rooms_count += 1
				if deg >= 3:
					non_closet_deg3plus_count += 1
				if deg == 1:
					non_closet_dead_ends_count += 1

		var closet_range_violation := closets_count < 1 or closets_count > 4

		print("\n  seed=%d valid=%s mode=%s count_rooms=%d count_corridors=%d closets=%d closet_bad_entries=%d closet_no_door=%d closet_multi_door=%d closet_range_bad=%s spawn_bad_room=%d spawn_stuck=%d gut_rects=%d bad_edge_corridors=%d dead_end=%d non_closet_dead_end=%d non_closet_deg3plus=%d/%d notched=%d t_u=%d central_missing=%d pseudo_gaps=%d tiny_gaps=%d north_exit_fail=%d outcrops=%d outer_run%%=%.1f attempts=%d loops=%d extra_walls=%d room_wall_leaks=%d missing_adj_doors=%d half_doors=%d door_overlaps=%d walk_unreach=%d door_variants=%d fail_reason=%s" % [
			s,
			str(layout.valid),
			mode_name,
			count_rooms,
			count_corridors,
			closets_count,
			closet_bad_entries_found,
			closet_no_door_found,
			closet_multi_door_found,
			str(closet_range_violation),
			bad_spawn_room_found,
			stuck_spawn_found,
			gut_rects_found,
			bad_edge_corridors_found,
			dead_end_count,
			non_closet_dead_ends_count,
			non_closet_deg3plus_count,
			non_closet_rooms_count,
			notched_rooms_count,
			t_u_rooms_count,
			central_missing,
			pseudo_gap_count,
			tiny_gaps_found,
			north_core_exit_fail,
			outcrop_count,
			outer_longest_run_pct,
			attempts_count,
			extra_loops_count,
			extra_walls_found,
			room_wall_leaks_found,
			missing_adjacent_doors,
			half_doors,
			door_overlaps,
			walk_unreach,
			door_size_variants.size(),
			fail_reason,
		])

		if layout.valid:
			valid_count += 1
		else:
			invalid_count += 1
			if not fail_reason_stats.has(fail_reason):
				fail_reason_stats[fail_reason] = 0
			fail_reason_stats[fail_reason] = int(fail_reason_stats[fail_reason]) + 1

		total_count_rooms += count_rooms
		total_count_corridors += count_corridors
		total_closets += closets_count
		if closet_range_violation:
			total_closet_range_violations += 1
		total_closet_bad_entries += closet_bad_entries_found
		total_gut_rects += gut_rects_found
		total_bad_edge_corridors += bad_edge_corridors_found
		total_dead_ends += dead_end_count
		total_notched_rooms += notched_rooms_count
		total_t_u_rooms += t_u_rooms_count
		total_central_missing += central_missing
		total_pseudo_gaps += pseudo_gap_count
		total_tiny_gaps += tiny_gaps_found
		total_north_core_exit_fails += north_core_exit_fail
		total_outcrops += outcrop_count
		total_outer_longest_run_pct += outer_longest_run_pct
		max_outer_longest_run_pct = maxf(max_outer_longest_run_pct, outer_longest_run_pct)
		total_attempts += attempts_count
		total_extra_loops += extra_loops_count
		total_extra_walls += extra_walls_found
		total_room_wall_leaks += room_wall_leaks_found
		total_missing_adjacent_doors += missing_adjacent_doors
		total_half_doors += half_doors
		total_door_overlaps += door_overlaps
		total_closet_no_door += closet_no_door_found
		total_closet_multi_door += closet_multi_door_found
		total_non_closet_rooms += non_closet_rooms_count
		total_non_closet_deg3plus += non_closet_deg3plus_count
		total_non_closet_dead_ends += non_closet_dead_ends_count
		total_bad_spawn_rooms += bad_spawn_room_found
		total_stuck_spawns += stuck_spawn_found
		if walkability_issue:
			total_walkability_issues += 1
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
	print("  Closet range violations:  %d" % total_closet_range_violations)
	print("  Total closet bad entries: %d" % total_closet_bad_entries)
	print("  Total gut_rects_found:    %d" % total_gut_rects)
	print("  Total bad_edge_corridors: %d" % total_bad_edge_corridors)
	print("  Avg dead_end_count:       %.2f" % (float(total_dead_ends) / float(SEED_COUNT)))
	print("  Avg notched_rooms_count:  %.2f" % (float(total_notched_rooms) / float(SEED_COUNT)))
	print("  Avg t_u_rooms_count:      %.2f" % (float(total_t_u_rooms) / float(SEED_COUNT)))
	print("  Total central_missing:    %d" % total_central_missing)
	print("  Total pseudo_gaps:        %d" % total_pseudo_gaps)
	print("  Total tiny_gaps:          %d" % total_tiny_gaps)
	print("  Total north_exit_fails:   %d" % total_north_core_exit_fails)
	print("  Avg outcrop_count:        %.2f" % (float(total_outcrops) / float(SEED_COUNT)))
	print("  Avg outer_run_pct:        %.2f" % (total_outer_longest_run_pct / float(SEED_COUNT)))
	print("  Max outer_run_pct:        %.2f" % max_outer_longest_run_pct)
	print("  Avg attempts:             %.2f" % (float(total_attempts) / float(SEED_COUNT)))
	print("  Avg extra_loops:          %.2f" % (float(total_extra_loops) / float(SEED_COUNT)))
	print("  Total extra_walls:        %d" % total_extra_walls)
	print("  Total room_wall_leaks:    %d" % total_room_wall_leaks)
	print("  Total missing_adj_doors:  %d" % total_missing_adjacent_doors)
	print("  Total half_doors:         %d" % total_half_doors)
	print("  Total door_overlaps:      %d" % total_door_overlaps)
	print("  Total closet_no_door:     %d" % total_closet_no_door)
	print("  Total closet_multi_door:  %d" % total_closet_multi_door)
	print("  Total bad_spawn_rooms:    %d" % total_bad_spawn_rooms)
	print("  Total stuck_spawns:       %d" % total_stuck_spawns)
	print("  Avg non_closet_dead_end:  %.2f" % (float(total_non_closet_dead_ends) / float(SEED_COUNT)))
	print("  Non-closet deg3+ pct:     %.2f" % (float(total_non_closet_deg3plus) * 100.0 / maxf(float(total_non_closet_rooms), 1.0)))
	print("  Walkability issue seeds:  %d" % total_walkability_issues)
	print("  Non-uniform door layouts: %d" % total_non_uniform_door_layouts)
	print("")
	print("  composition_mode_stats:")
	var sorted_modes: Array = composition_mode_stats.keys()
	sorted_modes.sort()
	for m in sorted_modes:
		var cnt := int(composition_mode_stats[m])
		print("    %-20s %d (%.0f%%)" % [m, cnt, float(cnt) / float(SEED_COUNT) * 100.0])
	if not fail_reason_stats.is_empty():
		print("")
		print("  validate_fail_reason_stats:")
		var sorted_reasons: Array = fail_reason_stats.keys()
		sorted_reasons.sort()
		for reason in sorted_reasons:
			var rcnt := int(fail_reason_stats[reason])
			print("    %-24s %d (%.0f%% invalid)" % [reason, rcnt, float(rcnt) / maxf(float(invalid_count), 1.0) * 100.0])

	print("")
	print("=".repeat(60))
	print("LAYOUT STATS TEST COMPLETE")
	print("=".repeat(60))

	var avg_outer_run_pct := total_outer_longest_run_pct / float(SEED_COUNT)
	var avg_extra_loops := float(total_extra_loops) / float(SEED_COUNT)
	var non_closet_deg3plus_pct := float(total_non_closet_deg3plus) * 100.0 / maxf(float(total_non_closet_rooms), 1.0)
	var avg_non_closet_dead_ends := float(total_non_closet_dead_ends) / float(SEED_COUNT)
	var has_errors := (
		invalid_count > 0
		or total_gut_rects > 0
		or total_bad_edge_corridors > 0
		or total_closet_bad_entries > 0
			or total_closet_no_door > 0
			or total_closet_multi_door > 0
			or total_bad_spawn_rooms > 0
			or total_stuck_spawns > 0
			or total_closet_range_violations > 0
		or total_central_missing > 0
		or total_pseudo_gaps > 0
		or total_tiny_gaps > 0
		or total_north_core_exit_fails > 0
		or total_extra_walls > 0
		or total_room_wall_leaks > 0
		or total_missing_adjacent_doors > 0
		or total_half_doors > 0
		or total_door_overlaps > 0
		or total_walkability_issues > 0
		or total_non_uniform_door_layouts > 0
		or avg_outer_run_pct > MAX_AVG_OUTER_RUN_PCT
		or max_outer_longest_run_pct > MAX_SINGLE_OUTER_RUN_PCT
		or avg_extra_loops < MIN_AVG_EXTRA_LOOPS
		or non_closet_deg3plus_pct < MIN_NON_CLOSET_DEG3PLUS_PCT
		or avg_non_closet_dead_ends > MAX_AVG_NON_CLOSET_DEAD_ENDS
	)
	get_tree().quit(1 if has_errors else 0)
