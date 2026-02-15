## test_layout_topology.gd
## Integration topology checks for ProceduralLayoutV2.
## Run via: godot --headless res://tests/test_layout_topology.tscn
extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")

const SEED_COUNT := 30
const TEST_MISSION := 3
const ARENA := Rect2(-1100, -1100, 2200, 2200)

const MIN_AVG_EXTRA_LOOPS := 0.05
const MIN_CENTER_DEG3PLUS_PCT := 30.0
const MAX_AVG_NON_CLOSET_DEAD_ENDS := 3.80


func _count_non_closet_dead_ends(layout) -> int:
	var count := 0
	for i in range(layout.rooms.size()):
		if i in layout._void_ids:
			continue
		if layout._is_closet_room(i):
			continue
		var deg := (layout._door_adj[i] as Array).size() if layout._door_adj.has(i) else 0
		if deg <= 1:
			count += 1
	return count


func _count_closet_contract_violations(layout) -> int:
	var bad := 0
	for i in range(layout.rooms.size()):
		if i in layout._void_ids:
			continue
		if not layout._is_closet_room(i):
			continue
		var deg := (layout._door_adj[i] as Array).size() if layout._door_adj.has(i) else 0
		if deg != 1:
			bad += 1
	return bad


func _ready() -> void:
	print("=".repeat(68))
	print("LAYOUT TOPOLOGY TEST: %d seeds, arena %s" % [SEED_COUNT, str(ARENA)])
	print("=".repeat(68))

	var invalid_count := 0
	var disconnected_count := 0
	var total_half_doors := 0
	var total_door_overlaps := 0
	var total_closet_contract_violations := 0
	var total_missing_adjacent_doors := 0
	var total_non_closet_dead_ends := 0
	var total_center_rooms := 0
	var total_center_deg3plus := 0
	var total_extra_loops := 0
	var multi_contact_failures := 0
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
			if not TestHelpers.is_door_graph_connected(layout):
				disconnected_count += 1
			total_half_doors += TestHelpers.count_half_doors(layout)
			total_door_overlaps += TestHelpers.count_overlapping_doors(layout)
			total_missing_adjacent_doors += TestHelpers.count_missing_adjacent_doors(layout)
			total_closet_contract_violations += _count_closet_contract_violations(layout)
			total_non_closet_dead_ends += _count_non_closet_dead_ends(layout)
			total_extra_loops += int(layout.extra_loops)

			var core_ids: Array = layout._core_non_closet_ids()
			total_center_rooms += core_ids.size()
			for rid_variant in core_ids:
				var rid := int(rid_variant)
				var deg := (layout._door_adj[rid] as Array).size() if layout._door_adj.has(rid) else 0
				if deg >= 3:
					total_center_deg3plus += 1

			var edges: Array = layout._build_room_adjacency_edges()
			var multi_contact: int = layout._count_non_closet_rooms_with_min_adjacency(edges, 2)
			if multi_contact < layout._required_multi_contact_rooms():
				multi_contact_failures += 1

		player_node.queue_free()
		walls_node.queue_free()
		debug_node.queue_free()
		await get_tree().process_frame

	var denom := maxf(float(valid_count), 1.0)
	var avg_extra_loops := float(total_extra_loops) / denom
	var avg_non_closet_dead_ends := float(total_non_closet_dead_ends) / denom
	var center_deg3plus_pct := float(total_center_deg3plus) * 100.0 / maxf(float(total_center_rooms), 1.0)

	print("\n" + "-".repeat(68))
	print("Topology metrics")
	print("  valid layouts:                %d / %d" % [valid_count, SEED_COUNT])
	print("  invalid layouts:              %d" % invalid_count)
	print("  disconnected layouts:         %d" % disconnected_count)
	print("  total half-doors:             %d" % total_half_doors)
	print("  total door overlaps:          %d" % total_door_overlaps)
	print("  total closet contract breaks: %d" % total_closet_contract_violations)
	print("  total missing adjacent doors: %d" % total_missing_adjacent_doors)
	print("  avg non-closet dead-ends:     %.2f" % avg_non_closet_dead_ends)
	print("  center deg3+ pct:             %.2f" % center_deg3plus_pct)
	print("  avg extra loops:              %.2f" % avg_extra_loops)
	print("  multi-contact failures:       %d" % multi_contact_failures)

	var has_errors := (
		invalid_count > 0
		or disconnected_count > 0
		or total_half_doors > 0
		or total_door_overlaps > 0
		or total_closet_contract_violations > 0
		or total_missing_adjacent_doors > 0
		or multi_contact_failures > 0
		or avg_non_closet_dead_ends > MAX_AVG_NON_CLOSET_DEAD_ENDS
		or center_deg3plus_pct < MIN_CENTER_DEG3PLUS_PCT
		or avg_extra_loops < MIN_AVG_EXTRA_LOOPS
	)
	print("\nRESULT: %s" % ("PASS" if not has_errors else "FAIL"))
	print("=".repeat(68))
	get_tree().quit(1 if has_errors else 0)
