extends RefCounted
class_name LevelTransitionController


func setup_north_transition_trigger(ctx) -> void:
	ctx.north_transition_enabled = false
	ctx.north_transition_rect = Rect2()
	if not ctx.layout or not ctx.layout.valid:
		return
	var bbox = compute_layout_rooms_bbox(ctx)
	if bbox == Rect2():
		return
	var trigger_h = 100.0
	var trigger_y = bbox.position.y - 200.0 - trigger_h
	ctx.north_transition_rect = Rect2(bbox.position.x, trigger_y, bbox.size.x, trigger_h)
	ctx.north_transition_enabled = true
	print("[LevelMVP] Mission=%d transition trigger=%s" % [current_mission_index(ctx), str(ctx.north_transition_rect)])


func compute_layout_rooms_bbox(ctx) -> Rect2:
	if not ctx.layout or not ctx.layout.valid:
		return Rect2()
	var has_rect = false
	var bbox = Rect2()
	for i in range(ctx.layout.rooms.size()):
		if i in ctx.layout._void_ids:
			continue
		for rect_variant in (ctx.layout.rooms[i]["rects"] as Array):
			var r = rect_variant as Rect2
			if not has_rect:
				bbox = r
				has_rect = true
			else:
				bbox = bbox.merge(r)
	return bbox if has_rect else Rect2()


func check_north_transition(ctx, on_regenerate_layout: Callable) -> void:
	if not ctx.north_transition_enabled:
		return
	if ctx.north_transition_cooldown > 0.0:
		return
	if not ctx.player:
		return
	if not is_north_transition_unlocked(ctx):
		return
	if ctx.north_transition_rect.has_point(ctx.player.position):
		ctx.north_transition_cooldown = 0.4
		advance_mission_cycle(ctx, on_regenerate_layout)


func is_north_transition_unlocked(ctx) -> bool:
	return alive_scene_enemies_count(ctx) == 0


func alive_scene_enemies_count(ctx) -> int:
	if not ctx.level or not ctx.level.get_tree():
		return 0
	var alive = 0
	for node_variant in ctx.level.get_tree().get_nodes_in_group("enemies"):
		var node = node_variant as Node
		if not node:
			continue
		if "is_dead" in node and bool(node.is_dead):
			continue
		alive += 1
	return alive


func advance_mission_cycle(ctx, on_regenerate_layout: Callable) -> void:
	if ctx.mission_cycle.is_empty():
		return
	ctx.mission_cycle_pos = (ctx.mission_cycle_pos + 1) % ctx.mission_cycle.size()
	var next_mission = current_mission_index(ctx)
	print("[LevelMVP] Transition -> mission %d" % next_mission)
	if on_regenerate_layout.is_valid():
		on_regenerate_layout.call()
	if EventBus:
		EventBus.emit_mission_transitioned(next_mission)


func current_mission_index(ctx) -> int:
	if ctx.mission_cycle.is_empty():
		return 3
	return int(ctx.mission_cycle[clampi(ctx.mission_cycle_pos, 0, ctx.mission_cycle.size() - 1)])
