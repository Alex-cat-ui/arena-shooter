extends Node

const LEVEL_SCENE: PackedScene = preload("res://src/levels/stealth_3zone_test.tscn")
const SIM_SECONDS: float = 60.0
const PHYSICS_FPS: float = 60.0


func _ready() -> void:
	var ok := await _run_measurement()
	get_tree().quit(0 if ok else 1)


func _run_measurement() -> bool:
	if RuntimeState:
		RuntimeState.is_frozen = false
		RuntimeState.player_visibility_mul = 0.0
		RuntimeState.player_hp = maxi(int(RuntimeState.player_hp), 100)

	var level: Node = LEVEL_SCENE.instantiate() as Node
	if level == null:
		push_error("Failed to instantiate stealth_3zone_test scene")
		return false
	add_child(level)

	await get_tree().process_frame
	await get_tree().physics_frame

	var enemies: Array[Node] = []
	for member_variant in get_tree().get_nodes_in_group("enemies"):
		var enemy := member_variant as Node
		if enemy == null:
			continue
		if enemy == level or level.is_ancestor_of(enemy):
			enemies.append(enemy)

	if enemies.is_empty():
		push_error("No enemies discovered in stealth_3zone_test scene")
		level.queue_free()
		await get_tree().process_frame
		return false

	var trackers: Dictionary = {}
	for enemy in enemies:
		if enemy == null or not enemy.has_method("debug_get_pursuit_system_for_test"):
			continue
		var pursuit_variant: Variant = enemy.call("debug_get_pursuit_system_for_test")
		if pursuit_variant == null:
			continue
		var pursuit_obj := pursuit_variant as Object
		if pursuit_obj == null:
			continue
		var patrol_variant: Variant = pursuit_obj.get("_patrol")
		var patrol_obj := patrol_variant as Object
		if patrol_obj == null:
			continue
		trackers[int(enemy.get_instance_id())] = {
			"patrol": patrol_obj,
			"prev_timer": float(patrol_obj.get("_route_rebuild_timer")),
			"rebuilds": 0,
		}

	if trackers.is_empty():
		push_error("Failed to resolve patrol systems for enemies")
		level.queue_free()
		await get_tree().process_frame
		return false

	var total_frames: int = int(round(SIM_SECONDS * PHYSICS_FPS))
	for _frame in range(total_frames):
		await get_tree().physics_frame
		for key_variant in trackers.keys():
			var key: int = int(key_variant)
			var tracker: Dictionary = trackers.get(key, {}) as Dictionary
			var patrol_obj := tracker.get("patrol", null) as Object
			if patrol_obj == null:
				continue
			var prev_timer: float = float(tracker.get("prev_timer", 0.0))
			var next_timer: float = float(patrol_obj.get("_route_rebuild_timer"))
			if next_timer > prev_timer + 0.5:
				tracker["rebuilds"] = int(tracker.get("rebuilds", 0)) + 1
			tracker["prev_timer"] = next_timer
			trackers[key] = tracker

	var total_rebuilds: int = 0
	for tracker_variant in trackers.values():
		var tracker: Dictionary = tracker_variant as Dictionary
		total_rebuilds += int(tracker.get("rebuilds", 0))

	var per_min: float = float(total_rebuilds) / maxf(SIM_SECONDS / 60.0, 0.001)
	print("BASELINE_PATROL_ROUTE_REBUILDS_TOTAL=%d" % total_rebuilds)
	print("BASELINE_PATROL_ROUTE_REBUILDS_PER_MIN=%.3f" % per_min)

	level.queue_free()
	await get_tree().process_frame
	return true
