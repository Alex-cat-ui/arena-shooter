## test_layout_visual_regression.gd
## Visual geometry guard for Hotline-like layouts.
## Run via: godot --headless res://tests/test_layout_visual_regression.tscn
extends Node

const SEED_COUNT := 50
const ARENA := Rect2(-1100, -1100, 2200, 2200)
const MAX_AVG_OPEN_OVERSIZED := 2.20
const MIN_AVG_BLOCKERS := 0.35


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

	for s in range(1, SEED_COUNT + 1):
		for child in walls_node.get_children():
			child.queue_free()
		await get_tree().process_frame

		var layout := ProceduralLayout.generate_and_build(ARENA, s, walls_node, debug_node, player_node)
		if not layout.valid:
			invalid_count += 1
			continue

		total_blockers += layout._interior_blocker_segs.size()

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

	print("\n" + "-".repeat(68))
	print("Visual metrics")
	print("  invalid layouts:            %d" % invalid_count)
	print("  total bad corridors:        %d" % total_bad_corridors)
	print("  total bad edge corridors:   %d" % total_bad_edge_corridors)
	print("  avg open oversized rooms:   %.2f (target <= %.2f)" % [avg_open_oversized, MAX_AVG_OPEN_OVERSIZED])
	print("  avg blockers per layout:    %.2f (target >= %.2f)" % [avg_blockers, MIN_AVG_BLOCKERS])
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

	print("RESULT: %s" % ("PASS" if is_pass else "FAIL"))
	print("=".repeat(68))
	get_tree().quit(0 if is_pass else 1)
