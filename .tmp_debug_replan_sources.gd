extends Node

const LEVEL_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")

func _ready() -> void:
	await _run_case("no_force_collision", false)
	await _run_case("force_collision", true)
	get_tree().quit(0)

func _run_case(label: String, force_collision: bool) -> void:
	if AIWatchdog and AIWatchdog.has_method("debug_reset_metrics_for_tests"):
		AIWatchdog.call("debug_reset_metrics_for_tests")
	var level := LEVEL_SCENE.instantiate() as Node
	if level == null:
		print("CASE_" + label + "=ERR_LEVEL")
		return
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := level.get_node_or_null("Stealth3ZoneTestController")
	if controller == null:
		print("CASE_" + label + "=ERR_CONTROLLER")
		level.queue_free()
		await get_tree().process_frame
		return
	var spawned := int(controller.call("debug_spawn_enemy_duplicates_for_tests", 12))
	if force_collision:
		_apply_force_collision_layout(level)

	var counts := {
		"path_plan_status": {},
		"path_failed_reason": {},
		"collision_kind": {},
		"collision_reason": {},
		"policy_blocked_true_samples": 0,
		"hard_stall_true_samples": 0,
		"samples": 0,
		"enemy_count": spawned,
	}

	for i in range(600):
		await get_tree().physics_frame
		await get_tree().process_frame
		for enemy_variant in get_tree().get_nodes_in_group("enemies"):
			var enemy := enemy_variant as Node
			if enemy == null:
				continue
			if enemy != level and not level.is_ancestor_of(enemy):
				continue
			if not enemy.has_method("debug_get_pursuit_navigation_policy_snapshot_for_test"):
				continue
			var snap := enemy.call("debug_get_pursuit_navigation_policy_snapshot_for_test") as Dictionary
			_acc_count(counts["path_plan_status"] as Dictionary, String(snap.get("path_plan_status", "")))
			_acc_count(counts["path_failed_reason"] as Dictionary, String(snap.get("path_failed_reason", "")))
			_acc_count(counts["collision_kind"] as Dictionary, String(snap.get("collision_kind", "")))
			_acc_count(counts["collision_reason"] as Dictionary, String(snap.get("collision_reason", "")))
			if bool(snap.get("policy_blocked", false)):
				counts["policy_blocked_true_samples"] = int(counts.get("policy_blocked_true_samples", 0)) + 1
			if bool(snap.get("hard_stall", false)):
				counts["hard_stall_true_samples"] = int(counts.get("hard_stall_true_samples", 0)) + 1
			counts["samples"] = int(counts.get("samples", 0)) + 1

	var wd := AIWatchdog.get_snapshot() as Dictionary if AIWatchdog and AIWatchdog.has_method("get_snapshot") else {}
	print("CASE_" + label + "_COUNTS_JSON=" + JSON.stringify(counts))
	print("CASE_" + label + "_WATCHDOG_JSON=" + JSON.stringify(wd))

	level.queue_free()
	await get_tree().process_frame

func _acc_count(d: Dictionary, key: String) -> void:
	if key == "":
		key = "<empty>"
	d[key] = int(d.get(key, 0)) + 1

func _apply_force_collision_layout(level: Node) -> void:
	var player := level.get_node_or_null("Entities/Player") as CharacterBody2D
	if player == null:
		return
	player.global_position = Vector2(638.0, 240.0)
	player.velocity = Vector2.ZERO
	var enemies: Array = []
	for enemy_variant in get_tree().get_nodes_in_group("enemies"):
		var enemy := enemy_variant as Node2D
		if enemy == null:
			continue
		if enemy != level and not level.is_ancestor_of(enemy):
			continue
		enemies.append(enemy)
	if enemies.is_empty():
		return
	var probe_anchor := player.global_position + Vector2(-220.0, 0.0)
	var ring_radius := 300.0
	for i in range(enemies.size()):
		var enemy := enemies[i] as Node2D
		var angle := (TAU * float(i)) / float(maxi(enemies.size(), 1))
		enemy.global_position = player.global_position + Vector2.RIGHT.rotated(angle) * ring_radius
		if enemy is CharacterBody2D:
			(enemy as CharacterBody2D).velocity = Vector2.ZERO
		enemy.set_meta("room_id", i % 5)
		if enemy.has_method("debug_force_awareness_state"):
			enemy.call("debug_force_awareness_state", "COMBAT" if i < 2 else "CALM")
	if enemies.size() >= 1:
		enemies[0].global_position = probe_anchor + Vector2(0.0, -6.0)
	if enemies.size() >= 2:
		enemies[1].global_position = probe_anchor + Vector2(0.0, 6.0)
