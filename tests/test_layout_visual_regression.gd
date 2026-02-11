## test_layout_visual_regression.gd
## Visual geometry guard for Hotline-like layouts.
## Run via: godot --headless res://tests/test_layout_visual_regression.tscn
extends Node

const SEED_COUNT := 50
const ARENA := Rect2(-1100, -1100, 2200, 2200)
const MAX_AVG_OPEN_OVERSIZED := 2.20
const MIN_AVG_BLOCKERS := 0.0
const MAX_LINEAR_PATH_FAILS := 0
const MAX_WALKABILITY_FAILS := 0
const MAX_UNREACHABLE_CELLS_PER_LAYOUT := 1
const MAX_TOTAL_PSEUDO_GAPS := 0
const MAX_TOTAL_NORTH_EXIT_FAILS := 0
const MAX_AVG_OUTER_RUN_PCT := 86.0


func _ready() -> void:
	print("=".repeat(68))
	print("VISUAL REGRESSION TEST: %d seeds, arena %s" % [SEED_COUNT, str(ARENA)])
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
	var total_bad_corridors := 0
	var total_bad_edge_corridors := 0
	var total_open_oversized := 0
	var total_blockers := 0
	var linear_path_failures := 0
	var walkability_failures := 0
	var total_unreachable_cells := 0
	var total_main_path_turns := 0
	var total_main_path_edges := 0
	var total_main_path_straight := 0
	var total_pseudo_gaps := 0
	var total_north_exit_fails := 0
	var total_outer_run_pct := 0.0

	for s in range(1, SEED_COUNT + 1):
		for child in walls_node.get_children():
			child.queue_free()
		await get_tree().process_frame

		var layout := ProceduralLayout.generate_and_build(ARENA, s, walls_node, debug_node, player_node)
		if not layout.valid:
			invalid_count += 1
			continue

		total_blockers += layout._interior_blocker_segs.size()
		total_unreachable_cells += layout.walk_unreachable_cells_stat
		total_main_path_turns += layout.main_path_turns_stat
		total_main_path_edges += layout.main_path_edges_stat
		total_main_path_straight += layout.main_path_straight_run_stat
		total_pseudo_gaps += layout.pseudo_gap_count_stat
		total_north_exit_fails += layout.north_core_exit_fail_stat
		total_outer_run_pct += layout.outer_longest_run_pct_stat
		if layout.walk_unreachable_cells_stat > MAX_UNREACHABLE_CELLS_PER_LAYOUT:
			walkability_failures += 1
		if layout.main_path_edges_stat >= 4 and layout.main_path_turns_stat < 1:
			linear_path_failures += 1
		if layout.main_path_straight_run_stat > 4:
			linear_path_failures += 1

		for i in range(layout.rooms.size()):
			if i in layout._void_ids:
				continue
			var room: Dictionary = layout.rooms[i]
			if room["is_corridor"] == true:
				if layout._is_bad_corridor_geometry(i):
					total_bad_corridors += 1
				if layout._is_bad_edge_corridor(i):
					total_bad_edge_corridors += 1
				continue

			var rects: Array = room["rects"] as Array
			if rects.size() != 1:
				continue
			if i in layout._hub_ids:
				continue
			if i in layout._ring_ids:
				continue
			var r := rects[0] as Rect2
			var is_open_oversized: bool = (
				r.get_area() >= 420000.0
				and minf(r.size.x, r.size.y) >= 520.0
				and room.get("is_perimeter_notched", false) != true
				and room.get("complex_shape", "") == ""
			)
			if is_open_oversized:
				total_open_oversized += 1

	var avg_open_oversized := float(total_open_oversized) / maxf(float(SEED_COUNT), 1.0)
	var avg_blockers := float(total_blockers) / maxf(float(SEED_COUNT), 1.0)
	var avg_unreachable := float(total_unreachable_cells) / maxf(float(SEED_COUNT), 1.0)
	var avg_turns := float(total_main_path_turns) / maxf(float(SEED_COUNT), 1.0)
	var avg_straight_run := float(total_main_path_straight) / maxf(float(SEED_COUNT), 1.0)
	var avg_outer_run_pct := total_outer_run_pct / maxf(float(SEED_COUNT), 1.0)

	print("\n" + "-".repeat(68))
	print("Visual metrics")
	print("  invalid layouts:            %d" % invalid_count)
	print("  total bad corridors:        %d" % total_bad_corridors)
	print("  total bad edge corridors:   %d" % total_bad_edge_corridors)
	print("  avg open oversized rooms:   %.2f (target <= %.2f)" % [avg_open_oversized, MAX_AVG_OPEN_OVERSIZED])
	print("  avg blockers per layout:    %.2f (target >= %.2f, currently optional)" % [avg_blockers, MIN_AVG_BLOCKERS])
	print("  linear path failures:       %d (target <= %d)" % [linear_path_failures, MAX_LINEAR_PATH_FAILS])
	print("  walkability failures:       %d (target <= %d)" % [walkability_failures, MAX_WALKABILITY_FAILS])
	print("  avg unreachable cells:      %.2f" % avg_unreachable)
	print("  avg main path turns:        %.2f" % avg_turns)
	print("  avg main straight run:      %.2f" % avg_straight_run)
	print("  total pseudo gaps:          %d (target <= %d)" % [total_pseudo_gaps, MAX_TOTAL_PSEUDO_GAPS])
	print("  total north exit fails:     %d (target <= %d)" % [total_north_exit_fails, MAX_TOTAL_NORTH_EXIT_FAILS])
	print("  avg outer longest run %%:    %.2f (target <= %.2f)" % [avg_outer_run_pct, MAX_AVG_OUTER_RUN_PCT])
	print("-".repeat(68))

	var is_pass := true
	if invalid_count > 0:
		is_pass = false
	if total_bad_corridors > 0:
		is_pass = false
	if total_bad_edge_corridors > 0:
		is_pass = false
	if avg_open_oversized > MAX_AVG_OPEN_OVERSIZED:
		is_pass = false
	if avg_blockers < MIN_AVG_BLOCKERS:
		is_pass = false
	if linear_path_failures > MAX_LINEAR_PATH_FAILS:
		is_pass = false
	if walkability_failures > MAX_WALKABILITY_FAILS:
		is_pass = false
	if total_pseudo_gaps > MAX_TOTAL_PSEUDO_GAPS:
		is_pass = false
	if total_north_exit_fails > MAX_TOTAL_NORTH_EXIT_FAILS:
		is_pass = false
	if avg_outer_run_pct > MAX_AVG_OUTER_RUN_PCT:
		is_pass = false

	print("RESULT: %s" % ("PASS" if is_pass else "FAIL"))
	print("=".repeat(68))
	get_tree().quit(0 if is_pass else 1)
