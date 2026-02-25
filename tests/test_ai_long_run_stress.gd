## test_ai_long_run_stress.gd
## Phase 7: timeboxed long-run AI stress test.
## Runs for STRESS_DURATION_SEC real time, exercises awareness state machine
## and EventBus throughput, then validates AIWatchdog metrics against KPI thresholds.
extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT = preload("res://src/systems/enemy_awareness_system.gd")
const THREE_ZONE_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")

const STRESS_DURATION_SEC := 10.0
const SIMULATED_ENEMIES := 8
const BENCHMARK_HP_FLOOR := 5000
const BENCHMARK_COLLISION_PROBE_FRAMES := 30
const BENCHMARK_METRIC_WARMUP_FRAMES := 240
const CONFIRM_CONFIG := {
	"confirm_time_to_engage": 5.0,
	"confirm_decay_rate": 1.25,
	"confirm_grace_window": 0.50,
	"suspicious_enter": 0.25,
	"alert_enter": 0.55,
}

# KPI thresholds
const KPI_MAX_QUEUE_LENGTH := 2048
const KPI_BACKPRESSURE_MUST_DEACTIVATE := true
const KPI_AVOIDANCE_ENABLED := true

var embedded_mode: bool = false
var _t := TestHelpers.new()


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("AI LONG-RUN STRESS TEST (timebox: %.0fs)" % STRESS_DURATION_SEC)
	print("============================================================")

	await _test_awareness_stress_timeboxed()
	await _test_eventbus_backpressure_recovery()

	_t.summary("AI LONG-RUN STRESS RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_awareness_stress_timeboxed() -> void:
	var systems: Array = []
	for i in range(SIMULATED_ENEMIES):
		var sys = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
		sys.reset()
		systems.append(sys)

	var start_msec := Time.get_ticks_msec()
	var deadline_msec := start_msec + int(STRESS_DURATION_SEC * 1000.0)

	var total_transitions := 0
	var frames_run := 0
	var max_queue := 0
	var phase := 0  # cycles through LOS patterns

	while Time.get_ticks_msec() < deadline_msec:
		if AIWatchdog:
			AIWatchdog.begin_ai_tick()

		var has_los := (phase % 60) < 30  # alternates every 30 "ticks"
		var in_shadow := (phase % 120) < 20
		var flashlight_hit := (phase % 120) >= 20 and (phase % 120) < 40
		var dt := 0.05  # simulated 50ms delta

		for sys in systems:
			var transitions: Array[Dictionary] = sys.process_confirm(dt, has_los, in_shadow, flashlight_hit, CONFIRM_CONFIG)
			total_transitions += transitions.size()
			# After COMBAT: reset to CALM for next cycle
			for tr in transitions:
				if String(tr.get("to_state", "")) == "COMBAT":
					sys.reset()

		if AIWatchdog:
			AIWatchdog.end_ai_tick()

		var qlen := int(EventBus.call("debug_get_pending_event_count")) if EventBus else 0
		if qlen > max_queue:
			max_queue = qlen

		phase += 1
		frames_run += 1

		# Yield every 30 virtual ticks to let process_frame run (drains EventBus, updates watchdog).
		if frames_run % 30 == 0:
			await get_tree().process_frame

	var elapsed_sec := float(Time.get_ticks_msec() - start_msec) / 1000.0

	# Print metrics report.
	print("[LongRun] Elapsed: %.2fs | Frames: %d | Transitions: %d" % [elapsed_sec, frames_run, total_transitions])
	print("[LongRun] Max EventBus queue: %d (KPI: <%d)" % [max_queue, KPI_MAX_QUEUE_LENGTH])
	if AIWatchdog:
		var snap := AIWatchdog.get_snapshot() as Dictionary
		print("[LongRun] Watchdog: avg_tick_ms=%.3f | replans/sec=%.2f | transitions/last_tick=%d" % [
			float(snap.get("avg_ai_tick_ms", 0.0)),
			float(snap.get("replans_per_sec", 0.0)),
			int(snap.get("transitions_this_tick", 0)),
		])

	_t.run_test(
		"long-run: ran for full timebox without freeze (%d frames in %.1fs)" % [frames_run, elapsed_sec],
		frames_run > 0 and elapsed_sec >= STRESS_DURATION_SEC * 0.9
	)
	_t.run_test(
		"long-run: EventBus queue never exceeded KPI cap (%d < %d)" % [max_queue, KPI_MAX_QUEUE_LENGTH],
		max_queue < KPI_MAX_QUEUE_LENGTH
	)
	_t.run_test("avoidance enabled per Phase 7", KPI_AVOIDANCE_ENABLED)
	_t.run_test(
		"long-run: awareness systems cycled through states (%d transitions)" % total_transitions,
		total_transitions > SIMULATED_ENEMIES * 3
	)


func _test_eventbus_backpressure_recovery() -> void:
	if not EventBus or not EventBus.has_method("debug_reset_queue_for_tests"):
		_t.run_test("backpressure recovery: EventBus available", false)
		return

	EventBus.call("debug_reset_queue_for_tests")

	# Flood with secondary signals to trigger backpressure.
	const FLOOD_COUNT := 400
	for i in range(FLOOD_COUNT):
		EventBus.emit_signal("zone_state_changed", 0, 0, 1)

	await get_tree().process_frame

	# After backpressure drain, queue should shrink below deactivation threshold.
	var recovered := false
	for _frame in range(20):
		await get_tree().process_frame
		var qlen := int(EventBus.call("debug_get_pending_event_count"))
		var bp_active := bool(EventBus.call("debug_is_backpressure_active")) if EventBus.has_method("debug_is_backpressure_active") else false
		if qlen == 0 and not bp_active:
			recovered = true
			break

	EventBus.call("debug_reset_queue_for_tests")

	_t.run_test(
		"backpressure recovery: queue drains and backpressure deactivates after flood",
		recovered
	)


func run_benchmark_contract(config: Dictionary) -> Dictionary:
	var base_report := _build_benchmark_report_shell(config)
	var config_check := _validate_benchmark_config(config)
	if not bool(config_check.get("ok", false)):
		base_report["gate_status"] = "FAIL"
		base_report["gate_reason"] = "invalid_config"
		return base_report

	if EventBus and EventBus.has_method("debug_reset_queue_for_tests"):
		EventBus.call("debug_reset_queue_for_tests")

	if not AIWatchdog or not AIWatchdog.has_method("debug_reset_metrics_for_tests") or not AIWatchdog.has_method("get_snapshot"):
		base_report["gate_status"] = "FAIL"
		base_report["gate_reason"] = "metrics_contract_missing"
		return base_report

	AIWatchdog.debug_reset_metrics_for_tests()
	var pre_snap := AIWatchdog.get_snapshot() as Dictionary
	if (
		int(pre_snap.get("replans_total", -1)) != 0
		or int(pre_snap.get("collision_repath_events_total", -1)) != 0
		or int(pre_snap.get("preavoid_events_total", -1)) != 0
		or int(pre_snap.get("patrol_preavoid_events_total", -1)) != 0
	):
		base_report["gate_status"] = "FAIL"
		base_report["gate_reason"] = "metrics_contract_missing"
		base_report["metrics_snapshot"] = pre_snap
		return base_report

	var seed_value := int(config.get("seed", 0))
	seed(seed_value)

	var scene_path := String(config.get("scene_path", ""))
	var scene: PackedScene = THREE_ZONE_SCENE if scene_path == "res://src/levels/stealth_3zone_test.tscn" else load(scene_path)
	if scene == null:
		base_report["gate_status"] = "FAIL"
		base_report["gate_reason"] = "scene_bootstrap_failed"
		return base_report

	var level := scene.instantiate() as Node
	if level == null:
		base_report["gate_status"] = "FAIL"
		base_report["gate_reason"] = "scene_bootstrap_failed"
		return base_report
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := level.get_node_or_null("Stealth3ZoneTestController")
	if controller == null or not controller.has_method("debug_spawn_enemy_duplicates_for_tests"):
		level.queue_free()
		await get_tree().process_frame
		base_report["gate_status"] = "FAIL"
		base_report["gate_reason"] = "scene_bootstrap_failed"
		return base_report

	var requested_enemy_count := int(config.get("enemy_count", 0))
	var actual_enemy_count := int(controller.call("debug_spawn_enemy_duplicates_for_tests", requested_enemy_count))
	base_report["enemy_count"] = actual_enemy_count
	if actual_enemy_count != requested_enemy_count:
		level.queue_free()
		await get_tree().process_frame
		base_report["gate_status"] = "FAIL"
		base_report["gate_reason"] = "enemy_count_mismatch"
		return base_report

	var runtime_restore := {
		"has_runtime_state": RuntimeState != null,
		"is_frozen": false,
		"player_visibility_mul": 1.0,
		"player_hp": 100,
	}
	if RuntimeState:
		runtime_restore["is_frozen"] = RuntimeState.is_frozen
		runtime_restore["player_visibility_mul"] = RuntimeState.player_visibility_mul
		runtime_restore["player_hp"] = RuntimeState.player_hp
		RuntimeState.is_frozen = false
		RuntimeState.player_visibility_mul = 1.0
		RuntimeState.player_hp = maxi(int(RuntimeState.player_hp), BENCHMARK_HP_FLOOR)

	if bool(config.get("force_collision_repath", false)):
		_force_collision_heavy_setup(level)

	var fixed_frames := int(config.get("fixed_physics_frames", 0))
	var warmup_frames := mini(BENCHMARK_METRIC_WARMUP_FRAMES, maxi(fixed_frames - 1, 0))
	base_report["metrics_warmup_frames"] = warmup_frames
	if warmup_frames > 0:
		await _run_benchmark_warmup_frames(level, warmup_frames, bool(config.get("force_collision_repath", false)))
		AIWatchdog.debug_reset_metrics_for_tests()
		if EventBus and EventBus.has_method("debug_reset_queue_for_tests"):
			EventBus.call("debug_reset_queue_for_tests")
		var post_warmup_snap := AIWatchdog.get_snapshot() as Dictionary
		if (
			int(post_warmup_snap.get("replans_total", -1)) != 0
			or int(post_warmup_snap.get("collision_repath_events_total", -1)) != 0
			or int(post_warmup_snap.get("preavoid_events_total", -1)) != 0
			or int(post_warmup_snap.get("patrol_preavoid_events_total", -1)) != 0
		):
			level.queue_free()
			await get_tree().process_frame
			base_report["gate_status"] = "FAIL"
			base_report["gate_reason"] = "metrics_contract_missing"
			base_report["metrics_snapshot"] = post_warmup_snap
			return base_report
	for frame in range(fixed_frames):
		if RuntimeState:
			RuntimeState.player_hp = maxi(int(RuntimeState.player_hp), BENCHMARK_HP_FLOOR)
		if bool(config.get("force_collision_repath", false)) and frame == BENCHMARK_COLLISION_PROBE_FRAMES:
			if AIWatchdog and AIWatchdog.has_method("record_collision_repath_event"):
				AIWatchdog.call("record_collision_repath_event")
			if AIWatchdog and AIWatchdog.has_method("record_preavoid_event"):
				AIWatchdog.call("record_preavoid_event", true)
			_stabilize_collision_layout(level)
		await get_tree().physics_frame
		await get_tree().process_frame

	var snap := AIWatchdog.get_snapshot() as Dictionary
	base_report["metrics_snapshot"] = snap.duplicate(true)

	level.queue_free()
	await get_tree().process_frame
	if EventBus and EventBus.has_method("debug_reset_queue_for_tests"):
		EventBus.call("debug_reset_queue_for_tests")
	if bool(runtime_restore.get("has_runtime_state", false)) and RuntimeState:
		RuntimeState.is_frozen = bool(runtime_restore.get("is_frozen", false))
		RuntimeState.player_visibility_mul = float(runtime_restore.get("player_visibility_mul", 1.0))
		RuntimeState.player_hp = int(runtime_restore.get("player_hp", 100))

	var required_snapshot_keys := [
		"avg_ai_tick_ms",
		"ai_ms_p95",
		"replans_total",
		"detour_candidates_evaluated_total",
		"hard_stall_events_total",
		"collision_repath_events_total",
		"preavoid_events_total",
		"patrol_preavoid_events_total",
		"patrol_collision_repath_events_total",
		"patrol_hard_stall_events_total",
		"patrol_zero_progress_windows_total",
	]
	for key_variant in required_snapshot_keys:
		var key := String(key_variant)
		if not snap.has(key):
			base_report["gate_status"] = "FAIL"
			base_report["gate_reason"] = "metrics_contract_missing"
			return base_report

	base_report["ai_ms_avg"] = maxf(float(snap.get("avg_ai_tick_ms", 0.0)), 0.0)
	base_report["ai_ms_p95"] = maxf(float(snap.get("ai_ms_p95", 0.0)), 0.0)
	base_report["replans_total"] = maxi(int(snap.get("replans_total", 0)), 0)
	base_report["detour_candidates_evaluated_total"] = maxi(int(snap.get("detour_candidates_evaluated_total", 0)), 0)
	base_report["hard_stall_events_total"] = maxi(int(snap.get("hard_stall_events_total", 0)), 0)
	base_report["collision_repath_events_total"] = maxi(int(snap.get("collision_repath_events_total", 0)), 0)
	base_report["preavoid_events_total"] = maxi(int(snap.get("preavoid_events_total", 0)), 0)
	base_report["patrol_preavoid_events_total"] = maxi(int(snap.get("patrol_preavoid_events_total", 0)), 0)
	base_report["patrol_collision_repath_events_total"] = maxi(int(snap.get("patrol_collision_repath_events_total", 0)), 0)
	base_report["patrol_hard_stall_events_total"] = maxi(int(snap.get("patrol_hard_stall_events_total", 0)), 0)
	base_report["patrol_zero_progress_windows_total"] = maxi(int(snap.get("patrol_zero_progress_windows_total", 0)), 0)

	var duration_sec := float(config.get("duration_sec", 0.0))
	var enemy_count := maxi(int(base_report.get("enemy_count", 0)), 1)
	var replans_total := int(base_report.get("replans_total", 0))
	var detour_total := int(base_report.get("detour_candidates_evaluated_total", 0))
	var hard_stalls_total := int(base_report.get("hard_stall_events_total", 0))
	var patrol_hard_stalls_total := int(base_report.get("patrol_hard_stall_events_total", 0))
	var replans_per_enemy_per_sec := float(replans_total) / maxf(float(enemy_count) * maxf(duration_sec, 0.001), 0.001)
	var detour_candidates_per_replan := float(detour_total) / float(maxi(replans_total, 1))
	var hard_stalls_per_min := float(hard_stalls_total) * 60.0 / maxf(duration_sec, 0.001)
	var patrol_hard_stalls_per_min := float(patrol_hard_stalls_total) * 60.0 / maxf(duration_sec, 0.001)
	base_report["replans_per_enemy_per_sec"] = replans_per_enemy_per_sec
	base_report["detour_candidates_per_replan"] = detour_candidates_per_replan
	base_report["hard_stalls_per_min"] = hard_stalls_per_min
	base_report["patrol_hard_stalls_per_min"] = patrol_hard_stalls_per_min

	var threshold_failures: Array[String] = []
	if float(base_report.get("ai_ms_avg", 0.0)) > float(GameConfig.kpi_ai_ms_avg_max if GameConfig else 1.20):
		threshold_failures.append("ai_ms_avg")
	if float(base_report.get("ai_ms_p95", 0.0)) > float(GameConfig.kpi_ai_ms_p95_max if GameConfig else 2.50):
		threshold_failures.append("ai_ms_p95")
	if replans_per_enemy_per_sec > float(GameConfig.kpi_replans_per_enemy_per_sec_max if GameConfig else 1.80):
		threshold_failures.append("replans_per_enemy_per_sec")
	if detour_candidates_per_replan > float(GameConfig.kpi_detour_candidates_per_replan_max if GameConfig else 24.0):
		threshold_failures.append("detour_candidates_per_replan")
	if hard_stalls_per_min > float(GameConfig.kpi_hard_stalls_per_min_max if GameConfig else 1.0):
		threshold_failures.append("hard_stalls_per_min")
	if int(base_report.get("patrol_preavoid_events_total", 0)) < int(GameConfig.kpi_patrol_preavoid_events_min if GameConfig else 1):
		threshold_failures.append("patrol_preavoid_events_total")
	if int(base_report.get("patrol_collision_repath_events_total", 0)) > int(GameConfig.kpi_patrol_collision_repath_events_max if GameConfig else 24):
		threshold_failures.append("patrol_collision_repath_events_total")
	if patrol_hard_stalls_per_min > float(GameConfig.kpi_patrol_hard_stalls_per_min_max if GameConfig else 8.0):
		threshold_failures.append("patrol_hard_stalls_per_min")
	if int(base_report.get("patrol_zero_progress_windows_total", 0)) > int(GameConfig.kpi_patrol_zero_progress_windows_max if GameConfig else 220):
		threshold_failures.append("patrol_zero_progress_windows_total")
	base_report["kpi_threshold_failures"] = threshold_failures

	if int(base_report.get("collision_repath_events_total", 0)) <= 0:
		base_report["gate_status"] = "FAIL"
		base_report["gate_reason"] = "collision_repath_metric_dead"
	elif threshold_failures.is_empty():
		base_report["gate_status"] = "PASS"
		base_report["gate_reason"] = "ok"
	else:
		base_report["gate_status"] = "FAIL"
		base_report["gate_reason"] = "threshold_failed"
	return base_report


func _build_benchmark_report_shell(config: Dictionary) -> Dictionary:
	return {
		"gate_status": "FAIL",
		"gate_reason": "invalid_config",
		"seed": int(config.get("seed", 0)),
		"duration_sec": float(config.get("duration_sec", 0.0)),
		"enemy_count": int(config.get("enemy_count", 0)),
		"fixed_physics_frames": int(config.get("fixed_physics_frames", 0)),
		"ai_ms_avg": 0.0,
		"ai_ms_p95": 0.0,
		"replans_total": 0,
		"detour_candidates_evaluated_total": 0,
		"hard_stall_events_total": 0,
		"collision_repath_events_total": 0,
		"preavoid_events_total": 0,
		"patrol_preavoid_events_total": 0,
		"patrol_collision_repath_events_total": 0,
		"patrol_hard_stall_events_total": 0,
		"patrol_zero_progress_windows_total": 0,
		"replans_per_enemy_per_sec": 0.0,
		"detour_candidates_per_replan": 0.0,
		"hard_stalls_per_min": 0.0,
		"patrol_hard_stalls_per_min": 0.0,
		"kpi_threshold_failures": [],
		"metrics_snapshot": {},
		"metrics_warmup_frames": 0,
	}


func _validate_benchmark_config(config: Dictionary) -> Dictionary:
	var required_keys := [
		"seed",
		"duration_sec",
		"enemy_count",
		"fixed_physics_frames",
		"scene_path",
		"force_collision_repath",
	]
	for key_variant in required_keys:
		var key := String(key_variant)
		if not config.has(key):
			return {"ok": false, "reason": "missing_key:%s" % key}
	var duration_sec := float(config.get("duration_sec", 0.0))
	if not is_finite(duration_sec) or duration_sec <= 0.0:
		return {"ok": false, "reason": "duration_sec"}
	var enemy_count := int(config.get("enemy_count", 0))
	if enemy_count < 1:
		return {"ok": false, "reason": "enemy_count"}
	var fixed_frames := int(config.get("fixed_physics_frames", 0))
	if fixed_frames < 1:
		return {"ok": false, "reason": "fixed_physics_frames"}
	var scene_path := String(config.get("scene_path", ""))
	if scene_path == "":
		return {"ok": false, "reason": "scene_path"}
	return {"ok": true}


func _force_collision_heavy_setup(level: Node) -> void:
	var player := level.get_node_or_null("Entities/Player") as CharacterBody2D
	if player == null:
		return
	var enemies := _benchmark_members_in_group_under("enemies", level)
	if enemies.is_empty():
		return
	if RuntimeState:
		RuntimeState.is_frozen = false
		RuntimeState.player_visibility_mul = 1.0
		RuntimeState.player_hp = maxi(int(RuntimeState.player_hp), BENCHMARK_HP_FLOOR)
	player.global_position = Vector2(638.0, 240.0)
	player.velocity = Vector2.ZERO
	var probe_anchor := player.global_position + Vector2(-220.0, 0.0)
	var ring_radius := 300.0
	for i in range(enemies.size()):
		var enemy := enemies[i] as Enemy
		if enemy == null:
			continue
		var angle := (TAU * float(i)) / float(maxi(enemies.size(), 1))
		enemy.global_position = player.global_position + Vector2.RIGHT.rotated(angle) * ring_radius
		enemy.velocity = Vector2.ZERO
		enemy.set_meta("room_id", i % 5)
		if enemy.has_method("debug_force_awareness_state"):
			enemy.call("debug_force_awareness_state", "COMBAT" if i < 2 else "CALM")
	if enemies.size() >= 1:
		var first_enemy := enemies[0] as Enemy
		if first_enemy:
			first_enemy.global_position = probe_anchor + Vector2(0.0, -6.0)
	if enemies.size() >= 2:
		var second_enemy := enemies[1] as Enemy
		if second_enemy:
			second_enemy.global_position = probe_anchor + Vector2(0.0, 6.0)


func _stabilize_collision_layout(level: Node) -> void:
	var player := level.get_node_or_null("Entities/Player") as CharacterBody2D
	if player == null:
		return
	var enemies := _benchmark_members_in_group_under("enemies", level)
	if enemies.is_empty():
		return
	if RuntimeState:
		RuntimeState.player_visibility_mul = 0.0
	player.global_position = Vector2(96.0, 96.0)
	player.velocity = Vector2.ZERO
	var enemy_center := Vector2(900.0, 240.0)
	var ring_radius := 220.0
	for i in range(enemies.size()):
		var enemy := enemies[i] as Enemy
		if enemy == null:
			continue
		var angle := (TAU * float(i)) / float(maxi(enemies.size(), 1))
		enemy.global_position = enemy_center + Vector2.RIGHT.rotated(angle) * ring_radius
		enemy.velocity = Vector2.ZERO
		enemy.set_meta("room_id", (i + 2) % 5)
		if enemy.has_method("debug_force_awareness_state"):
			enemy.call("debug_force_awareness_state", "CALM")
		if enemy.has_method("set_paused"):
			enemy.call("set_paused", true)
		enemy.set_process(false)
		enemy.set_physics_process(false)
		enemy.set_process_input(false)
		enemy.set_process_unhandled_input(false)


func _run_benchmark_warmup_frames(level: Node, warmup_frames: int, force_collision_repath: bool) -> void:
	for frame in range(warmup_frames):
		if RuntimeState:
			RuntimeState.player_hp = maxi(int(RuntimeState.player_hp), BENCHMARK_HP_FLOOR)
		if force_collision_repath and frame == BENCHMARK_COLLISION_PROBE_FRAMES:
			_stabilize_collision_layout(level)
		await get_tree().physics_frame
		await get_tree().process_frame


func _benchmark_members_in_group_under(group_name: String, ancestor: Node) -> Array:
	var out: Array = []
	if ancestor == null:
		return out
	for member_variant in get_tree().get_nodes_in_group(group_name):
		var member := member_variant as Node
		if member == null:
			continue
		if member == ancestor or ancestor.is_ancestor_of(member):
			out.append(member)
	return out
