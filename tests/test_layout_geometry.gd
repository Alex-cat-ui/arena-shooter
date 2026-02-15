## test_layout_geometry.gd
## Integration geometry checks for ProceduralLayoutV2.
## Run via: godot --headless res://tests/test_layout_geometry.tscn
extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")

const SEED_COUNT := 30
const TEST_MISSION := 3
const ARENA := Rect2(-1100, -1100, 2200, 2200)

const MAX_AVG_OUTER_RUN_PCT := 31.0
const MAX_SINGLE_OUTER_RUN_PCT := 40.0
const MIN_AVG_OUTCROPS := 1.0

const MICRO_GAP_BRIDGE_MAX := 5.0


func _is_gut_rect_v2(r: Rect2) -> bool:
	return minf(r.size.x, r.size.y) < 128.0 and maxf(r.size.x, r.size.y) > 256.0


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


func _count_notched_rooms(layout) -> int:
	var count := 0
	for i in range(layout.rooms.size()):
		if i in layout._void_ids:
			continue
		if bool((layout.rooms[i] as Dictionary).get("is_perimeter_notched", false)):
			count += 1
	return count


func _count_unbridged_micro_gaps(layout) -> int:
	var door_edges: Dictionary = {}
	for item_variant in layout._door_map:
		var item := item_variant as Dictionary
		var a := int(item["a"])
		var b := int(item["b"])
		door_edges[TestHelpers.door_key(a, b)] = true

	var missing := 0
	for a in range(layout.rooms.size()):
		if a in layout._void_ids:
			continue
		for b in range(a + 1, layout.rooms.size()):
			if b in layout._void_ids:
				continue
			var min_span := float(layout._min_adjacency_span_for_pair(a, b)) - 0.75
			var gap_match := false
			for ra_variant in (layout.rooms[a]["rects"] as Array):
				var ra := ra_variant as Rect2
				for rb_variant in (layout.rooms[b]["rects"] as Array):
					var rb := rb_variant as Rect2
					var y0 := maxf(ra.position.y, rb.position.y)
					var y1 := minf(ra.end.y, rb.end.y)
					var y_span := y1 - y0
					var x0 := maxf(ra.position.x, rb.position.x)
					var x1 := minf(ra.end.x, rb.end.x)
					var x_span := x1 - x0
					var gap_lr := rb.position.x - ra.end.x
					var gap_rl := ra.position.x - rb.end.x
					var gap_tb := rb.position.y - ra.end.y
					var gap_bt := ra.position.y - rb.end.y
					if (gap_lr > 0.75 and gap_lr <= MICRO_GAP_BRIDGE_MAX and y_span >= min_span) \
						or (gap_rl > 0.75 and gap_rl <= MICRO_GAP_BRIDGE_MAX and y_span >= min_span) \
						or (gap_tb > 0.75 and gap_tb <= MICRO_GAP_BRIDGE_MAX and x_span >= min_span) \
						or (gap_bt > 0.75 and gap_bt <= MICRO_GAP_BRIDGE_MAX and x_span >= min_span):
						gap_match = true
						break
				if gap_match:
					break
			if gap_match and not door_edges.has(TestHelpers.door_key(a, b)):
				missing += 1
	return missing


func _ready() -> void:
	print("=".repeat(68))
	print("LAYOUT GEOMETRY TEST: %d seeds, arena %s" % [SEED_COUNT, str(ARENA)])
	print("=".repeat(68))

	var invalid_count := 0
	var room_count_violations := 0
	var corridor_count_violations := 0
	var total_gut_rects := 0
	var total_unbridged_micro_gaps := 0
	var total_outer_longest_run_pct := 0.0
	var max_outer_longest_run_pct := 0.0
	var total_outcrops := 0
	var total_t_u_rooms := 0
	var total_notched_rooms := 0
	var valid_count := 0

	for s in range(1, SEED_COUNT + 1):
		var built := TestHelpers.create_layout(self, s, ARENA, TEST_MISSION)
		var layout = built["layout"]
		var player_node := built["player"] as CharacterBody2D
		var walls_node := built["walls"] as Node2D
		var debug_node := built["debug"] as Node2D

		if not layout.valid:
			invalid_count += 1
		else:
			valid_count += 1
			var count_rooms := 0
			var count_corridors := 0
			for i in range(layout.rooms.size()):
				if i in layout._void_ids:
					continue
				count_rooms += 1
				var room := layout.rooms[i] as Dictionary
				if bool(room.get("is_corridor", false)):
					count_corridors += 1
				for rect_variant in (room["rects"] as Array):
					var r := rect_variant as Rect2
					if _is_gut_rect_v2(r):
						total_gut_rects += 1

			if count_rooms < 9 or count_rooms > 14:
				room_count_violations += 1
			if count_corridors > count_rooms:
				corridor_count_violations += 1

			total_outcrops += int(layout.outcrop_count_stat)
			total_outer_longest_run_pct += float(layout.outer_longest_run_pct_stat)
			max_outer_longest_run_pct = maxf(max_outer_longest_run_pct, float(layout.outer_longest_run_pct_stat))
			total_t_u_rooms += _count_t_u_rooms(layout)
			total_notched_rooms += _count_notched_rooms(layout)
			total_unbridged_micro_gaps += _count_unbridged_micro_gaps(layout)

		player_node.queue_free()
		walls_node.queue_free()
		debug_node.queue_free()
		await get_tree().process_frame

	var denom := maxf(float(valid_count), 1.0)
	var avg_outcrops := float(total_outcrops) / denom
	var avg_outer_run_pct := total_outer_longest_run_pct / denom
	var avg_t_u_rooms := float(total_t_u_rooms) / denom
	var avg_notched_rooms := float(total_notched_rooms) / denom

	print("\n" + "-".repeat(68))
	print("Geometry metrics")
	print("  valid layouts:              %d / %d" % [valid_count, SEED_COUNT])
	print("  invalid layouts:            %d" % invalid_count)
	print("  room count violations:      %d" % room_count_violations)
	print("  corridor count violations:  %d" % corridor_count_violations)
	print("  total gut rects:            %d" % total_gut_rects)
	print("  avg outcrops:               %.2f" % avg_outcrops)
	print("  avg outer run pct:          %.2f" % avg_outer_run_pct)
	print("  max outer run pct:          %.2f" % max_outer_longest_run_pct)
	print("  avg T/U rooms:              %.2f" % avg_t_u_rooms)
	print("  avg notched rooms:          %.2f" % avg_notched_rooms)
	print("  total unbridged micro-gaps: %d" % total_unbridged_micro_gaps)

	var has_errors := (
		invalid_count > 0
		or room_count_violations > 0
		or corridor_count_violations > 0
		or total_gut_rects > 0
		or total_unbridged_micro_gaps > 0
		or avg_outcrops < MIN_AVG_OUTCROPS
		or avg_outer_run_pct > MAX_AVG_OUTER_RUN_PCT
		or max_outer_longest_run_pct > MAX_SINGLE_OUTER_RUN_PCT
		or avg_t_u_rooms <= 0.0
		or avg_notched_rooms <= 0.0
	)
	print("\nRESULT: %s" % ("PASS" if not has_errors else "FAIL"))
	print("=".repeat(68))
	get_tree().quit(1 if has_errors else 0)
