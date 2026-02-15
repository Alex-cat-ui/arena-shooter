## test_layout_perf.gd
## Measures generation latency and retry counts.
## Run via: godot --headless res://tests/test_layout_perf.tscn
extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")

const SEED_COUNT := 30
const ARENA := Rect2(-1100, -1100, 2200, 2200)
const MAX_AVG_MS := 1200.0
const MAX_P95_MS := 2200.0
const MAX_AVG_ATTEMPTS := 28.0
const PROCEDURAL_LAYOUT_V2_SCRIPT := preload("res://src/systems/procedural_layout_v2.gd")
const TEST_MISSION := 3


func _ready() -> void:
	var _nodes := TestHelpers.create_layout_nodes(self)
	var walls_node: Node2D = _nodes["walls"]
	var debug_node: Node2D = _nodes["debug"]
	var player_node: CharacterBody2D = _nodes["player"]

	var ms_samples: Array = []
	var attempts_samples: Array = []
	var invalid_count := 0

	print("=".repeat(60))
	print("LAYOUT PERF TEST: %d seeds" % SEED_COUNT)
	print("=".repeat(60))

	for s in range(1, SEED_COUNT + 1):
		for child in walls_node.get_children():
			child.queue_free()
		await get_tree().process_frame

		var t0 := Time.get_ticks_usec()
		var layout := PROCEDURAL_LAYOUT_V2_SCRIPT.generate_and_build(ARENA, s, walls_node, debug_node, player_node, TEST_MISSION)
		var dt_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		ms_samples.append(dt_ms)
		attempts_samples.append(layout.generation_attempts_stat)
		if not layout.valid:
			invalid_count += 1

		print("seed=%d valid=%s ms=%.1f attempts=%d mode=%s" % [
			s,
			str(layout.valid),
			dt_ms,
			layout.generation_attempts_stat,
			layout.layout_mode_name if layout.layout_mode_name != "" else "UNKNOWN",
		])

	ms_samples.sort()
	attempts_samples.sort()

	var sum_ms := 0.0
	for v in ms_samples:
		sum_ms += float(v)
	var avg_ms := sum_ms / maxf(float(ms_samples.size()), 1.0)

	var sum_attempts := 0.0
	for v in attempts_samples:
		sum_attempts += float(v)
	var avg_attempts := sum_attempts / maxf(float(attempts_samples.size()), 1.0)

	var p95_idx := int(floor(float(ms_samples.size() - 1) * 0.95))
	var p95_ms := float(ms_samples[p95_idx]) if not ms_samples.is_empty() else 0.0

	print("")
	print("AVG_MS=%.1f P95_MS=%.1f AVG_ATTEMPTS=%.1f INVALID=%d" % [avg_ms, p95_ms, avg_attempts, invalid_count])
	print("=".repeat(60))

	var has_errors := (
		invalid_count > 0
		or avg_ms > MAX_AVG_MS
		or p95_ms > MAX_P95_MS
		or avg_attempts > MAX_AVG_ATTEMPTS
	)
	get_tree().quit(1 if has_errors else 0)
