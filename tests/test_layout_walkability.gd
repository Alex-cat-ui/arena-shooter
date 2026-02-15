## test_layout_walkability.gd
## Integration walkability/spawn checks for ProceduralLayoutV2.
## Run via: godot --headless res://tests/test_layout_walkability.tscn
extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")

const SEED_COUNT := 30
const TEST_MISSION := 3
const ARENA := Rect2(-1100, -1100, 2200, 2200)

const WALL_SAMPLE_STEP := 32.0
const WALL_POINT_EPS := 2.5
const MIN_NORTH_GATE_WIDTH := 84.0
const PLAYER_SPAWN_NORTH_OFFSET := 100.0
const PLAYER_SPAWN_NORTH_TOLERANCE := 40.0


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
			var ra := TestHelpers.room_id_at_point(layout, pa)
			var rb := TestHelpers.room_id_at_point(layout, pb)
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

			var tx := r.position.x + WALL_SAMPLE_STEP * 0.5
			while tx < r.end.x:
				var inside_t := Vector2(tx, r.position.y + eps)
				var outside_t := Vector2(tx, r.position.y - eps)
				var inside_id_t := TestHelpers.room_id_at_point(layout, inside_t)
				var outside_id_t := TestHelpers.room_id_at_point(layout, outside_t)
				if inside_id_t == i and outside_id_t != i:
					if not _is_point_near_wall_segment(wall_segs, Vector2(tx, r.position.y), eps * 2.0) and not _is_point_in_opening(layout, Vector2(tx, r.position.y), eps * 2.0):
						leaks += 1
						break
				tx += WALL_SAMPLE_STEP

			var bx := r.position.x + WALL_SAMPLE_STEP * 0.5
			while bx < r.end.x:
				var inside_b := Vector2(bx, r.end.y - eps)
				var outside_b := Vector2(bx, r.end.y + eps)
				var inside_id_b := TestHelpers.room_id_at_point(layout, inside_b)
				var outside_id_b := TestHelpers.room_id_at_point(layout, outside_b)
				if inside_id_b == i and outside_id_b != i:
					if not _is_point_near_wall_segment(wall_segs, Vector2(bx, r.end.y), eps * 2.0) and not _is_point_in_opening(layout, Vector2(bx, r.end.y), eps * 2.0):
						leaks += 1
						break
				bx += WALL_SAMPLE_STEP

			var ly := r.position.y + WALL_SAMPLE_STEP * 0.5
			while ly < r.end.y:
				var inside_l := Vector2(r.position.x + eps, ly)
				var outside_l := Vector2(r.position.x - eps, ly)
				var inside_id_l := TestHelpers.room_id_at_point(layout, inside_l)
				var outside_id_l := TestHelpers.room_id_at_point(layout, outside_l)
				if inside_id_l == i and outside_id_l != i:
					if not _is_point_near_wall_segment(wall_segs, Vector2(r.position.x, ly), eps * 2.0) and not _is_point_in_opening(layout, Vector2(r.position.x, ly), eps * 2.0):
						leaks += 1
						break
				ly += WALL_SAMPLE_STEP

			var ry := r.position.y + WALL_SAMPLE_STEP * 0.5
			while ry < r.end.y:
				var inside_r := Vector2(r.end.x - eps, ry)
				var outside_r := Vector2(r.end.x + eps, ry)
				var inside_id_r := TestHelpers.room_id_at_point(layout, inside_r)
				var outside_id_r := TestHelpers.room_id_at_point(layout, outside_r)
				if inside_id_r == i and outside_id_r != i:
					if not _is_point_near_wall_segment(wall_segs, Vector2(r.end.x, ry), eps * 2.0) and not _is_point_in_opening(layout, Vector2(r.end.x, ry), eps * 2.0):
						leaks += 1
						break
				ry += WALL_SAMPLE_STEP

	return leaks


func _north_gate_is_walkable(layout) -> bool:
	if layout._entry_gate == Rect2():
		return false
	var gate := layout._entry_gate as Rect2
	var gate_len := maxf(gate.size.x, gate.size.y)
	if gate_len < MIN_NORTH_GATE_WIDTH:
		return false
	var center := gate.get_center()
	for dx in PackedFloat32Array([-18.0, 0.0, 18.0]):
		var inside_id := TestHelpers.room_id_at_point(layout, center + Vector2(dx, 18.0))
		if inside_id < 0:
			return false
	return true


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
	print("=".repeat(68))
	print("LAYOUT WALKABILITY TEST: %d seeds, arena %s" % [SEED_COUNT, str(ARENA)])
	print("=".repeat(68))

	var invalid_count := 0
	var total_bad_north_gates := 0
	var total_bad_spawn_rooms := 0
	var total_stuck_spawns := 0
	var total_room_wall_leaks := 0
	var total_extra_walls := 0
	var total_pseudo_gaps := 0
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
			var wall_segs: Array = layout._compute_cut_wall_segments_for_validation()
			total_pseudo_gaps += int(layout.pseudo_gap_count_stat)
			total_extra_walls += _count_extra_wall_segments(layout, wall_segs)
			total_room_wall_leaks += _count_room_wall_leaks(layout, wall_segs)
			if not _north_gate_is_walkable(layout):
				total_bad_north_gates += 1

			var spawn_room_id := TestHelpers.room_id_at_point(layout, player_node.global_position)
			var spawn_near_north := _is_spawn_near_north_entry(layout, player_node.global_position)
			if not spawn_near_north:
				total_bad_spawn_rooms += 1
			elif spawn_room_id >= 0 and layout._is_closet_room(spawn_room_id):
				total_bad_spawn_rooms += 1
			if _is_spawn_stuck(player_node):
				total_stuck_spawns += 1

		player_node.queue_free()
		walls_node.queue_free()
		debug_node.queue_free()
		await get_tree().process_frame

	print("\n" + "-".repeat(68))
	print("Walkability metrics")
	print("  valid layouts:         %d / %d" % [valid_count, SEED_COUNT])
	print("  invalid layouts:       %d" % invalid_count)
	print("  bad north gates:       %d" % total_bad_north_gates)
	print("  bad spawn rooms:       %d" % total_bad_spawn_rooms)
	print("  stuck spawns:          %d" % total_stuck_spawns)
	print("  room wall leaks:       %d" % total_room_wall_leaks)
	print("  extra wall segments:   %d" % total_extra_walls)
	print("  pseudo-gaps:           %d" % total_pseudo_gaps)

	var has_errors := (
		invalid_count > 0
		or total_bad_north_gates > 0
		or total_bad_spawn_rooms > 0
		or total_stuck_spawns > 0
		or total_room_wall_leaks > 0
		or total_extra_walls > 0
		or total_pseudo_gaps > 0
	)
	print("\nRESULT: %s" % ("PASS" if not has_errors else "FAIL"))
	print("=".repeat(68))
	get_tree().quit(1 if has_errors else 0)
