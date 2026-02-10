## test_hotline_similarity.gd
## Hotline Miami similarity regression test for procedural layouts.
## Run via: godot --headless res://tests/test_hotline_similarity.tscn
extends Node

const SEED_COUNT := 80
const ARENA := Rect2(-1100, -1100, 2200, 2200)
const TARGET_SCORE := 95.0

# Profile targets for "HM 95% similarity" archetypes.
# These are gameplay-geometry archetypes, not exact level copies.
const HOTLINE_95_ARCHETYPES := [
	{"name": "Apartment Spine", "mode": "SPINE", "t_u": true, "notches": true},
	{"name": "Office Loop", "mode": "RING", "t_u": true, "notches": true},
	{"name": "Club Dual Hub", "mode": "DUAL_HUB", "t_u": false, "notches": true},
	{"name": "Compound Hall", "mode": "HALL", "t_u": true, "notches": true},
]

const TARGET_MODE_DISTRIBUTION := {
	"HALL": 0.30,
	"SPINE": 0.20,
	"RING": 0.25,
	"DUAL_HUB": 0.25,
}

const TARGET_TU_MIN_AVG := 0.25
const TARGET_TU_MAX_AVG := 0.90


func _ready() -> void:
	print("=".repeat(68))
	print("HOTLINE SIMILARITY TEST: %d seeds, arena %s" % [SEED_COUNT, str(ARENA)])
	print("Target score: %.1f" % TARGET_SCORE)
	print("=".repeat(68))
	print("Reference archetypes (HM 95% profile):")
	for archetype in HOTLINE_95_ARCHETYPES:
		print("  - %s (%s)" % [String(archetype["name"]), String(archetype["mode"])])

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

	var raw_mode_counts: Dictionary = {}
	var final_mode_counts: Dictionary = {}
	var valid_count := 0
	var invalid_count := 0
	var total_t_u_rooms := 0
	var total_notched_rooms := 0
	var total_gut_rects := 0
	var total_bad_edge_corridors := 0

	for s in range(1, SEED_COUNT + 1):
		# Raw, single-attempt generation (before retry bias).
		var raw_layout := ProceduralLayout.new()
		raw_layout._arena = ARENA
		seed(s)
		raw_layout.layout_seed = s
		raw_layout._generate()
		var raw_mode := raw_layout.layout_mode_name if raw_layout.layout_mode_name != "" else "UNKNOWN"
		_inc_count(raw_mode_counts, raw_mode)

		# Final generation path used by game (with retries).
		for child in walls_node.get_children():
			child.queue_free()
		await get_tree().process_frame
		var final_layout := ProceduralLayout.generate_and_build(ARENA, s, walls_node, debug_node, player_node)
		var final_mode := final_layout.layout_mode_name if final_layout.layout_mode_name != "" else "UNKNOWN"
		_inc_count(final_mode_counts, final_mode)

		if not final_layout.valid:
			invalid_count += 1
			continue

		valid_count += 1
		total_t_u_rooms += final_layout._t_u_room_ids.size()

		var notched_count := 0
		for i in range(final_layout.rooms.size()):
			if i in final_layout._void_ids:
				continue
			var room: Dictionary = final_layout.rooms[i]
			if room.get("is_perimeter_notched", false) == true:
				notched_count += 1
			for rect in (room["rects"] as Array):
				if final_layout._is_gut_rect(rect as Rect2):
					total_gut_rects += 1
			if room["is_corridor"] == true and final_layout._is_bad_edge_corridor(i):
				total_bad_edge_corridors += 1
		total_notched_rooms += notched_count

	var avg_t_u := float(total_t_u_rooms) / maxf(float(SEED_COUNT), 1.0)
	var avg_notched := float(total_notched_rooms) / maxf(float(SEED_COUNT), 1.0)
	var hard_score := _hard_score(invalid_count, total_gut_rects, total_bad_edge_corridors)
	var mode_score := _mode_score(final_mode_counts)
	var t_u_score := _t_u_score(avg_t_u)
	var similarity_score := hard_score + mode_score + t_u_score

	print("\n" + "-".repeat(68))
	print("RAW composition_mode_stats (single-pass, pre-retry)")
	_print_mode_distribution(raw_mode_counts, SEED_COUNT)

	print("\n" + "-".repeat(68))
	print("FINAL composition_mode_stats (generate_and_build, post-retry)")
	_print_mode_distribution(final_mode_counts, SEED_COUNT)

	print("\n" + "-".repeat(68))
	print("Similarity metrics")
	print("  valid layouts:              %d / %d" % [valid_count, SEED_COUNT])
	print("  invalid layouts:            %d" % invalid_count)
	print("  total gut rects:            %d" % total_gut_rects)
	print("  total bad edge corridors:   %d" % total_bad_edge_corridors)
	print("  avg t_u_rooms_count:        %.2f" % avg_t_u)
	print("  avg notched_rooms_count:    %.2f" % avg_notched)
	print("\nScoring")
	print("  hard_score:                 %.2f / 60" % hard_score)
	print("  mode_score:                 %.2f / 20" % mode_score)
	print("  t_u_score:                  %.2f / 20" % t_u_score)
	print("  HotlineSimilarityScore:     %.2f / 100" % similarity_score)
	print("  TARGET:                     %.2f" % TARGET_SCORE)

	var is_pass := similarity_score >= TARGET_SCORE
	print("\nRESULT: %s" % ("PASS" if is_pass else "FAIL"))
	print("=".repeat(68))
	get_tree().quit(0 if is_pass else 1)


func _inc_count(dict: Dictionary, key: String) -> void:
	if not dict.has(key):
		dict[key] = 0
	dict[key] = int(dict[key]) + 1


func _print_mode_distribution(counts: Dictionary, total: int) -> void:
	var modes := ["HALL", "SPINE", "RING", "DUAL_HUB", "UNKNOWN"]
	for mode in modes:
		var cnt := int(counts.get(mode, 0))
		if cnt == 0 and mode == "UNKNOWN":
			continue
		print("  %-10s %3d (%.1f%%)" % [mode, cnt, 100.0 * float(cnt) / maxf(float(total), 1.0)])


func _hard_score(invalid_count: int, gut_count: int, bad_edge_count: int) -> float:
	if invalid_count > 0:
		return 0.0
	if gut_count > 0:
		return 0.0
	if bad_edge_count > 0:
		return 0.0
	return 60.0


func _mode_score(counts: Dictionary) -> float:
	var l1_dist := 0.0
	for mode_name in TARGET_MODE_DISTRIBUTION.keys():
		var target_ratio := float(TARGET_MODE_DISTRIBUTION[mode_name])
		var got_ratio := float(counts.get(mode_name, 0)) / maxf(float(SEED_COUNT), 1.0)
		l1_dist += absf(got_ratio - target_ratio)
	# Max L1 for a 4-class distribution is 2.0
	return clampf(20.0 * (1.0 - l1_dist / 2.0), 0.0, 20.0)


func _t_u_score(avg_t_u: float) -> float:
	if avg_t_u < TARGET_TU_MIN_AVG:
		return clampf(20.0 * (avg_t_u / TARGET_TU_MIN_AVG), 0.0, 20.0)
	if avg_t_u > TARGET_TU_MAX_AVG:
		# Overuse also hurts similarity.
		var overflow := avg_t_u - TARGET_TU_MAX_AVG
		return clampf(20.0 * (1.0 - overflow / TARGET_TU_MAX_AVG), 0.0, 20.0)
	return 20.0
