extends SceneTree

const LEVEL_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")
const SIM_SECONDS := 60.0
const PHYSICS_FPS := 60.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if RuntimeState:
		RuntimeState.is_frozen = false
		RuntimeState.player_visibility_mul = 0.0
		RuntimeState.player_hp = maxi(int(RuntimeState.player_hp), 100)

	var level := LEVEL_SCENE.instantiate()
	if level == null:
		push_error("Failed to instantiate stealth_3zone_test scene")
		quit(1)
		return
	root.add_child(level)

	await process_frame
	await physics_frame

	var enemies: Array = []
	for member_variant in root.get_tree().get_nodes_in_group("enemies"):
		var enemy := member_variant as Node
		if enemy == null:
			continue
		if enemy == level or level.is_ancestor_of(enemy):
			enemies.append(enemy)

	if enemies.is_empty():
		push_error("No enemies discovered in stealth_3zone_test scene")
		quit(1)
		return

	var trackers: Dictionary = {}
	for enemy_variant in enemies:
		var enemy := enemy_variant as Node
		if enemy == null or not enemy.has_method("debug_get_pursuit_system_for_test"):
			continue
		var pursuit: Variant = enemy.call("debug_get_pursuit_system_for_test")
		if pursuit == null:
			continue
		var patrol: Variant = pursuit.get("_patrol")
		if patrol == null:
			continue
		trackers[enemy.get_instance_id()] = {
			"enemy": enemy,
			"patrol": patrol,
			"prev_timer": float(patrol.get("_route_rebuild_timer")),
			"rebuilds": 0,
		}

	if trackers.is_empty():
		push_error("Failed to resolve patrol systems for enemies")
		quit(1)
		return

	var total_frames := int(round(SIM_SECONDS * PHYSICS_FPS))
	for _frame in range(total_frames):
		await physics_frame
		for key_variant in trackers.keys():
			var key := int(key_variant)
			var tracker := trackers.get(key, {}) as Dictionary
			var patrol := tracker.get("patrol", null)
			if patrol == null:
				continue
			var prev_timer := float(tracker.get("prev_timer", 0.0))
			var next_timer := float(patrol.get("_route_rebuild_timer"))
			if next_timer > prev_timer + 0.5:
				tracker["rebuilds"] = int(tracker.get("rebuilds", 0)) + 1
			tracker["prev_timer"] = next_timer
			trackers[key] = tracker

	var total_rebuilds := 0
	for tracker_variant in trackers.values():
		var tracker := tracker_variant as Dictionary
		total_rebuilds += int(tracker.get("rebuilds", 0))

	var per_min := float(total_rebuilds) / maxf(SIM_SECONDS / 60.0, 0.001)
	print("BASELINE_PATROL_ROUTE_REBUILDS_TOTAL=%d" % total_rebuilds)
	print("BASELINE_PATROL_ROUTE_REBUILDS_PER_MIN=%.3f" % per_min)

	quit(0)
