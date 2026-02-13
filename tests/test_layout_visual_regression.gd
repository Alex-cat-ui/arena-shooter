## test_layout_visual_regression.gd
## Visual geometry guard for ProceduralLayoutV2.
## Run via: godot --headless res://tests/test_layout_visual_regression.tscn
extends Node

const SEED_COUNT := 50
const TEST_MISSION := 3
const ARENA := Rect2(-1100, -1100, 2200, 2200)
const MAX_WALKABILITY_FAILS := 0
const MAX_UNREACHABLE_CELLS_PER_LAYOUT := 1
const MAX_TOTAL_PSEUDO_GAPS := 0
const MAX_TOTAL_NORTH_EXIT_FAILS := 0
const MAX_AVG_OUTER_RUN_PCT := 31.0
const MAX_SINGLE_OUTER_RUN_PCT := 40.0
const MIN_AVG_OUTCROPS := 1.0
const MIN_AVG_TU_ROOMS := 1.5
const PROCEDURAL_LAYOUT_V2_SCRIPT := preload("res://src/systems/procedural_layout_v2.gd")


func _ready() -> void:
	print("=".repeat(68))
	print("VISUAL REGRESSION TEST (V2): %d seeds, arena %s" % [SEED_COUNT, str(ARENA)])
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

	var invalid_count := 0
	var walkability_failures := 0
	var total_unreachable_cells := 0
	var total_pseudo_gaps := 0
	var total_north_exit_fails := 0
	var total_outer_run_pct := 0.0
	var max_outer_run_pct := 0.0
	var total_outcrops := 0
	var total_t_u_rooms := 0
	var total_closets := 0
	var total_closet_bad_entries := 0
	var total_closet_range_violations := 0

	for s in range(1, SEED_COUNT + 1):
		for child in walls_node.get_children():
			child.queue_free()
		await get_tree().process_frame

		var layout := PROCEDURAL_LAYOUT_V2_SCRIPT.generate_and_build(ARENA, s, walls_node, debug_node, player_node, TEST_MISSION)
		if not layout.valid:
			invalid_count += 1
			continue

		total_unreachable_cells += layout.walk_unreachable_cells_stat
		if layout.walk_unreachable_cells_stat > MAX_UNREACHABLE_CELLS_PER_LAYOUT:
			walkability_failures += 1

		total_pseudo_gaps += layout.pseudo_gap_count_stat
		total_north_exit_fails += layout.north_core_exit_fail_stat
		total_outcrops += layout.outcrop_count_stat
		total_outer_run_pct += layout.outer_longest_run_pct_stat
		max_outer_run_pct = maxf(max_outer_run_pct, layout.outer_longest_run_pct_stat)

		var t_u_count := _count_t_u_rooms(layout)
		total_t_u_rooms += t_u_count

		var closets_count := _count_closets(layout)
		total_closets += closets_count
		if closets_count < 1 or closets_count > 4:
			total_closet_range_violations += 1
		total_closet_bad_entries += _count_closet_bad_entries(layout)

	var avg_unreachable := float(total_unreachable_cells) / maxf(float(SEED_COUNT), 1.0)
	var avg_t_u_rooms := float(total_t_u_rooms) / maxf(float(SEED_COUNT), 1.0)
	var avg_outcrops := float(total_outcrops) / maxf(float(SEED_COUNT), 1.0)
	var avg_outer_run_pct := total_outer_run_pct / maxf(float(SEED_COUNT), 1.0)
	var avg_closets := float(total_closets) / maxf(float(SEED_COUNT), 1.0)

	print("\n" + "-".repeat(68))
	print("Visual metrics (V2)")
	print("  invalid layouts:            %d" % invalid_count)
	print("  walkability failures:       %d (target <= %d)" % [walkability_failures, MAX_WALKABILITY_FAILS])
	print("  avg unreachable cells:      %.2f" % avg_unreachable)
	print("  total pseudo gaps:          %d (target <= %d)" % [total_pseudo_gaps, MAX_TOTAL_PSEUDO_GAPS])
	print("  total north exit fails:     %d (target <= %d)" % [total_north_exit_fails, MAX_TOTAL_NORTH_EXIT_FAILS])
	print("  avg outer longest run %%:    %.2f (target <= %.2f)" % [avg_outer_run_pct, MAX_AVG_OUTER_RUN_PCT])
	print("  max outer longest run %%:    %.2f (target <= %.2f)" % [max_outer_run_pct, MAX_SINGLE_OUTER_RUN_PCT])
	print("  avg outcrops per layout:    %.2f (target >= %.2f)" % [avg_outcrops, MIN_AVG_OUTCROPS])
	print("  avg t_u rooms per layout:   %.2f (target >= %.2f)" % [avg_t_u_rooms, MIN_AVG_TU_ROOMS])
	print("  avg closets per layout:     %.2f (target 1..4)" % avg_closets)
	print("  closet range violations:    %d" % total_closet_range_violations)
	print("  closet bad entries total:   %d" % total_closet_bad_entries)
	print("-".repeat(68))

	var is_pass := true
	if invalid_count > 0:
		is_pass = false
	if walkability_failures > MAX_WALKABILITY_FAILS:
		is_pass = false
	if total_pseudo_gaps > MAX_TOTAL_PSEUDO_GAPS:
		is_pass = false
	if total_north_exit_fails > MAX_TOTAL_NORTH_EXIT_FAILS:
		is_pass = false
	if avg_outer_run_pct > MAX_AVG_OUTER_RUN_PCT:
		is_pass = false
	if max_outer_run_pct > MAX_SINGLE_OUTER_RUN_PCT:
		is_pass = false
	if avg_outcrops < MIN_AVG_OUTCROPS:
		is_pass = false
	if avg_t_u_rooms < MIN_AVG_TU_ROOMS:
		is_pass = false
	if total_closet_range_violations > 0:
		is_pass = false
	if total_closet_bad_entries > 0:
		is_pass = false

	print("RESULT: %s" % ("PASS" if is_pass else "FAIL"))
	print("=".repeat(68))
	get_tree().quit(0 if is_pass else 1)


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


func _count_closet_bad_entries(layout) -> int:
	var bad := 0
	for i in range(layout.rooms.size()):
		if i in layout._void_ids:
			continue
		if not layout._is_closet_room(i):
			continue
		var deg := 0
		if layout._door_adj.has(i):
			deg = (layout._door_adj[i] as Array).size()
		if deg != 1:
			bad += 1
	return bad

