extends RefCounted
class_name LevelLayoutController

const PROCEDURAL_LAYOUT_V2_SCRIPT = preload("res://src/systems/procedural_layout_v2.gd")
const V2_FLOOR_FILL_COLOR = Color(0.58, 0.58, 0.58, 1.0)
const PLAYER_NORTH_SPAWN_OFFSET = 100.0

var transition_controller = null
var camera_controller = null
var enemy_runtime_controller = null
var runtime_guard = null


func set_dependencies(
	transition,
	camera,
	enemy_runtime,
	guard
) -> void:
	transition_controller = transition
	camera_controller = camera
	enemy_runtime_controller = enemy_runtime
	runtime_guard = guard


func random_arena_rect() -> Rect2:
	var cx = 0.0
	var cy = 0.0
	var w = 2200.0
	var h = 1500.0
	return Rect2(cx - w * 0.5, cy - h * 0.5, w, h)


func initialize_layout(ctx, mission_index: int) -> void:
	ensure_walkable_floor_node(ctx)
	if GameConfig and GameConfig.procedural_layout_enabled:
		var arena_rect = Rect2(ctx.arena_min, ctx.arena_max - ctx.arena_min)
		var s: int = GameConfig.layout_seed
		if s == 0:
			s = int(Time.get_ticks_msec()) % 999999
		ctx.layout = generate_layout(ctx, arena_rect, s, mission_index)
		ensure_layout_recovered(ctx, arena_rect, s, mission_index)
	if ctx.layout_door_system and ctx.layout_door_system.has_method("rebuild_for_layout"):
		ctx.layout_door_system.rebuild_for_layout(ctx.layout)
	rebuild_walkable_floor(ctx)
	update_layout_room_stats(ctx)
	sync_layout_runtime_memory(ctx, mission_index)


func regenerate_layout(ctx, new_seed: int = 0) -> void:
	if not ctx.layout_walls:
		return

	clear_node_children_detached(ctx.layout_walls)
	clear_node_children_detached(ctx.layout_doors)
	clear_node_children_detached(ctx.layout_debug)

	var arena_rect = random_arena_rect()
	ctx.arena_min = arena_rect.position
	ctx.arena_max = arena_rect.end
	if ctx.arena_boundary:
		ctx.arena_boundary.initialize(ctx.arena_min, ctx.arena_max)

	var mission = transition_controller.current_mission_index(ctx) if transition_controller else 3
	var s = new_seed
	if s == 0:
		s = int(Time.get_ticks_msec()) % 999999
	ctx.layout = generate_layout(ctx, arena_rect, s, mission)
	ensure_layout_recovered(ctx, arena_rect, s, mission)

	if ctx.layout_door_system and ctx.layout_door_system.has_method("rebuild_for_layout"):
		ctx.layout_door_system.rebuild_for_layout(ctx.layout)

	rebuild_walkable_floor(ctx)
	update_layout_room_stats(ctx)
	sync_layout_runtime_memory(ctx, mission)

	if ctx.room_enemy_spawner:
		ctx.room_enemy_spawner.rebuild_for_layout(ctx.layout)
	if ctx.navigation_service and ctx.navigation_service.has_method("rebuild_for_layout"):
		ctx.navigation_service.rebuild_for_layout(ctx.layout)
	if ctx.navigation_service and ctx.navigation_service.has_method("build_from_layout"):
		ctx.navigation_service.build_from_layout(ctx.layout, ctx.level)
	if ctx.navigation_service and ctx.navigation_service.has_method("bind_tactical_systems"):
		ctx.navigation_service.bind_tactical_systems(ctx.enemy_alert_system, ctx.enemy_squad_system)
	if enemy_runtime_controller:
		enemy_runtime_controller.rebind_enemy_aggro_context(ctx)

	if transition_controller:
		transition_controller.setup_north_transition_trigger(ctx)
	if camera_controller:
		camera_controller.reset_follow(ctx)
	ensure_player_runtime_ready(ctx)
	if runtime_guard:
		runtime_guard.enforce_on_layout_reset(ctx)


func generate_layout(ctx, arena_rect: Rect2, seed_value: int, mission_index: int):
	var attempts = 8
	var base_seed = seed_value
	var layout = null
	for i in range(attempts):
		var s = base_seed + i * 9973
		layout = PROCEDURAL_LAYOUT_V2_SCRIPT.generate_and_build(arena_rect, s, ctx.layout_walls, ctx.layout_debug, ctx.player, mission_index)
		if layout and layout.valid:
			if i > 0:
				print("[LevelMVP] Layout recovered on retry %d (seed=%d -> %d)" % [i + 1, seed_value, s])
			return layout
		clear_node_children_detached(ctx.layout_walls)
		clear_node_children_detached(ctx.layout_debug)
	print("[LevelMVP][WARN] Layout failed after %d retries (seed=%d, mission=%d)" % [attempts, seed_value, mission_index])
	return layout


func ensure_layout_recovered(ctx, arena_rect: Rect2, seed_value: int, mission_index: int) -> void:
	if ctx.layout and ctx.layout.valid and layout_has_wall_visuals(ctx):
		return

	var recovery_seeds = [1337, 7331, 424242, seed_value + 131071]
	for recovery_seed_variant in recovery_seeds:
		var recovery_seed = int(recovery_seed_variant)
		clear_node_children_detached(ctx.layout_walls)
		clear_node_children_detached(ctx.layout_debug)
		var recovered: Variant = generate_layout(ctx, arena_rect, recovery_seed, mission_index)
		if recovered and recovered.valid and layout_has_wall_visuals(ctx):
			ctx.layout = recovered
			print("[LevelMVP] Layout recovery OK (seed=%d)" % recovery_seed)
			return

	print("[LevelMVP][WARN] Layout visuals missing after recovery; fallback floor will be shown.")


func sync_layout_runtime_memory(ctx, mission_index: int) -> void:
	ctx.layout_room_memory.clear()
	if is_layout_v2(ctx.layout):
		var room_memory_variant = ctx.layout.get("room_generation_memory")
		if room_memory_variant is Array:
			ctx.layout_room_memory = (room_memory_variant as Array).duplicate(true)
	if RuntimeState:
		RuntimeState.layout_room_memory = ctx.layout_room_memory.duplicate(true)
		RuntimeState.mission_index = mission_index


func is_layout_v2(layout_obj) -> bool:
	if not layout_obj:
		return false
	var script_obj: Script = layout_obj.get_script() as Script
	if not script_obj:
		return false
	return script_obj.resource_path == "res://src/systems/procedural_layout_v2.gd"


func ensure_walkable_floor_node(ctx) -> void:
	if not ctx.floor_root:
		return
	if ctx.walkable_floor:
		return
	ctx.walkable_floor = Node2D.new()
	ctx.walkable_floor.name = "WalkableFloor"
	ctx.floor_root.add_child(ctx.walkable_floor)


func clear_walkable_floor(ctx) -> void:
	if not ctx.walkable_floor:
		return
	ctx.non_walkable_floor_bg = null
	clear_node_children_detached(ctx.walkable_floor)


func ensure_non_walkable_background(ctx) -> void:
	if not ctx.walkable_floor:
		return
	var bg_bounds = compute_layout_render_bounds(ctx)
	if ctx.non_walkable_floor_bg and is_instance_valid(ctx.non_walkable_floor_bg):
		ctx.non_walkable_floor_bg.position = bg_bounds.get_center()
		ctx.non_walkable_floor_bg.scale = bg_bounds.size
		return

	var bg = Sprite2D.new()
	bg.name = "NonWalkableBlack"
	bg.texture = solid_black_texture(ctx)
	bg.centered = true
	bg.position = bg_bounds.get_center()
	bg.scale = bg_bounds.size
	bg.z_index = -50
	ctx.walkable_floor.add_child(bg)
	ctx.non_walkable_floor_bg = bg


func compute_layout_render_bounds(ctx) -> Rect2:
	var bounds = Rect2(ctx.arena_min, ctx.arena_max - ctx.arena_min)
	if not ctx.layout or not ctx.layout.valid:
		return bounds

	var has_rect = false
	var merged = Rect2()
	for i in range(ctx.layout.rooms.size()):
		if i in ctx.layout._void_ids:
			continue
		var room: Dictionary = ctx.layout.rooms[i]
		for rect_variant in (room["rects"] as Array):
			var r = rect_variant as Rect2
			if not has_rect:
				merged = r
				has_rect = true
			else:
				merged = merged.merge(r)

	if not has_rect:
		return bounds
	return bounds.merge(merged).grow(220.0)


func rebuild_walkable_floor(ctx) -> void:
	if not ctx.floor_sprite:
		return
	ensure_walkable_floor_node(ctx)
	clear_walkable_floor(ctx)

	if not ctx.layout or not ctx.layout.valid:
		ctx.floor_sprite.visible = true
		return

	var v2_fill_mode = is_layout_v2(ctx.layout)
	if not v2_fill_mode and not ctx.floor_sprite.texture:
		ctx.floor_sprite.visible = true
		return

	ctx.floor_sprite.visible = false
	ensure_non_walkable_background(ctx)
	var sx = ctx.floor_sprite.scale.x
	var sy = ctx.floor_sprite.scale.y
	if absf(sx) < 0.0001:
		sx = 1.0
	if absf(sy) < 0.0001:
		sy = 1.0

	for i in range(ctx.layout.rooms.size()):
		if i in ctx.layout._void_ids:
			continue
		var room: Dictionary = ctx.layout.rooms[i]
		for rect_variant in (room["rects"] as Array):
			var r = rect_variant as Rect2
			if r.size.x < 2.0 or r.size.y < 2.0:
				continue
			var patch = Sprite2D.new()
			patch.centered = true
			patch.position = r.get_center()
			if v2_fill_mode:
				patch.texture = solid_white_texture(ctx)
				patch.modulate = V2_FLOOR_FILL_COLOR
				patch.scale = r.size
			else:
				patch.texture = ctx.floor_sprite.texture
				patch.texture_filter = ctx.floor_sprite.texture_filter
				patch.texture_repeat = ctx.floor_sprite.texture_repeat
				patch.scale = ctx.floor_sprite.scale
				patch.region_enabled = true
				patch.region_rect = Rect2(
					r.position.x / sx,
					r.position.y / sy,
					r.size.x / sx,
					r.size.y / sy
				)
			patch.z_index = -40
			ctx.walkable_floor.add_child(patch)


func solid_white_texture(ctx) -> ImageTexture:
	if ctx.cached_white_pixel_tex and is_instance_valid(ctx.cached_white_pixel_tex):
		return ctx.cached_white_pixel_tex
	var img = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.WHITE)
	ctx.cached_white_pixel_tex = ImageTexture.create_from_image(img)
	return ctx.cached_white_pixel_tex


func solid_black_texture(ctx) -> ImageTexture:
	if ctx.cached_black_pixel_tex and is_instance_valid(ctx.cached_black_pixel_tex):
		return ctx.cached_black_pixel_tex
	var img = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.BLACK)
	ctx.cached_black_pixel_tex = ImageTexture.create_from_image(img)
	return ctx.cached_black_pixel_tex


func clear_node_children_detached(parent: Node) -> void:
	if not parent:
		return
	var children = parent.get_children()
	for child in children:
		parent.remove_child(child)
		child.queue_free()


func ensure_player_runtime_ready(ctx) -> void:
	if not ctx.player:
		return

	ctx.player.visible = true
	var sprite = ctx.player.get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		sprite.visible = true
		if sprite.modulate.a < 0.99:
			sprite.modulate = Color.WHITE

	var cb = ctx.player as CharacterBody2D
	if not cb:
		return

	if (cb.collision_mask & 1) == 0:
		cb.collision_mask |= 1

	if is_layout_v2(ctx.layout):
		var room_id: int = int(ctx.layout._room_id_at_point(cb.global_position))
		var near_north_spawn = is_near_layout_north_spawn(ctx, cb.global_position)
		var outside_bad = room_id < 0 and not near_north_spawn
		var bad_spawn: bool = outside_bad or bool(ctx.layout._is_closet_room(room_id)) or is_player_stuck(cb)
		if bad_spawn:
			cb.global_position = ctx.layout.player_spawn_pos
			if cb.test_move(cb.global_transform, Vector2.ZERO) or is_player_stuck(cb):
				var spawn_room_id = int(ctx.layout.player_room_id)
				if spawn_room_id >= 0 and spawn_room_id < ctx.layout.rooms.size():
					var room = ctx.layout.rooms[spawn_room_id] as Dictionary
					var rects = room.get("rects", []) as Array
					if not rects.is_empty():
						rects.sort_custom(func(a, b): return (a as Rect2).get_area() > (b as Rect2).get_area())
						cb.global_position = (rects[0] as Rect2).get_center()

	if RuntimeState:
		RuntimeState.player_pos = Vector3(cb.global_position.x, cb.global_position.y, 0)


func is_player_stuck(cb: CharacterBody2D) -> bool:
	var probes = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	for dir_variant in probes:
		var dir = dir_variant as Vector2
		if not cb.test_move(cb.global_transform, dir * 4.0):
			return false
	return true


func is_near_layout_north_spawn(ctx, pos: Vector2) -> bool:
	if not is_layout_v2(ctx.layout):
		return false
	if ctx.layout._entry_gate == Rect2():
		return false
	var north_target = (ctx.layout._entry_gate as Rect2).get_center() + Vector2(0.0, -PLAYER_NORTH_SPAWN_OFFSET)
	return pos.distance_to(north_target) <= 40.0


func update_layout_room_stats(ctx) -> void:
	ctx.layout_room_stats["corridors"] = 0
	ctx.layout_room_stats["interior_rooms"] = 0
	ctx.layout_room_stats["exterior_rooms"] = 0
	ctx.layout_room_stats["closets"] = 0

	if not ctx.layout or not ctx.layout.valid:
		print("[LevelMVP] Room stats: layout invalid or disabled")
		return

	for i in range(ctx.layout.rooms.size()):
		if i in ctx.layout._void_ids:
			continue
		var room: Dictionary = ctx.layout.rooms[i]
		if room["is_corridor"] == true:
			ctx.layout_room_stats["corridors"] = int(ctx.layout_room_stats["corridors"]) + 1
			continue
		if ctx.layout._is_closet_room(i):
			ctx.layout_room_stats["closets"] = int(ctx.layout_room_stats["closets"]) + 1
			continue
		if ctx.layout._room_touch_perimeter(i):
			ctx.layout_room_stats["exterior_rooms"] = int(ctx.layout_room_stats["exterior_rooms"]) + 1
		else:
			ctx.layout_room_stats["interior_rooms"] = int(ctx.layout_room_stats["interior_rooms"]) + 1

	print("[LevelMVP] Room stats: corr=%d inner=%d outer=%d closet=%d" % [
		int(ctx.layout_room_stats["corridors"]),
		int(ctx.layout_room_stats["interior_rooms"]),
		int(ctx.layout_room_stats["exterior_rooms"]),
		int(ctx.layout_room_stats["closets"]),
	])


func layout_has_wall_visuals(ctx) -> bool:
	if not ctx.layout_walls:
		return false
	var walls_visual = ctx.layout_walls.get_node_or_null("WallsVisual") as Node
	return walls_visual != null and walls_visual.get_child_count() > 0
