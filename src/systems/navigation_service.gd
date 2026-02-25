## navigation_service.gd
## Room-level navigation helper for enemies on ProceduralLayoutV2.
class_name NavigationService
extends Node

const NAV_RUNTIME_QUERIES_SCRIPT := preload("res://src/systems/navigation_runtime_queries.gd")
const NAV_ENEMY_WIRING_SCRIPT := preload("res://src/systems/navigation_enemy_wiring.gd")
const NAV_SHADOW_POLICY_SCRIPT := preload("res://src/systems/navigation_shadow_policy.gd")

var layout = null
var entities_container: Node2D = null
var player_node: Node2D = null
var alert_system: Node = null
var squad_system: Node = null
var _zone_director_cache: Node = null
var _zone_director_checked: bool = false

var _room_graph: Dictionary = {}      # room_id -> Array[int]
var _pair_doors: Dictionary = {}      # "a|b" -> Array[Vector2]
var _rng := RandomNumberGenerator.new()
const DOOR_NAV_OVERLAP_PX := 16.0
const NAV_CARVE_EPSILON := 0.5
const OBSTACLE_CLEARANCE_PX := 16.0
const OBSTACLE_INTERSECTION_SAMPLE_STEP_PX := 8.0
const NAV_OBSTACLE_GROUP := "nav_obstacles"
const POLICY_SAMPLE_STEP_PX := 12.0
var _nav_regions: Array[NavigationRegion2D] = []
var _room_to_region: Dictionary = {} # room_id -> NavigationRegion2D
var _runtime_queries = null
var _enemy_wiring = null
var _shadow_policy = null
var _last_nav_obstacle_source: String = "none"
var _last_nav_obstacles: Array[Rect2] = []
var _legacy_traverse_api_warned: bool = false
var _geometry_map_unavailable_warned: bool = false
var _nav_build_invalid: bool = false


func _ensure_runtime_components() -> void:
	if _runtime_queries == null:
		_runtime_queries = NAV_RUNTIME_QUERIES_SCRIPT.new(self)
	if _enemy_wiring == null:
		_enemy_wiring = NAV_ENEMY_WIRING_SCRIPT.new(self)
	if _shadow_policy == null:
		_shadow_policy = NAV_SHADOW_POLICY_SCRIPT.new(self)


func initialize(p_layout, p_entities_container: Node2D, p_player_node: Node2D) -> void:
	_ensure_runtime_components()
	layout = p_layout
	entities_container = p_entities_container
	player_node = p_player_node
	_rng.randomize()
	if EventBus and not EventBus.player_shot.is_connected(_on_player_shot):
		EventBus.player_shot.connect(_on_player_shot)
	if entities_container and not entities_container.child_entered_tree.is_connected(_on_entity_child_entered):
		entities_container.child_entered_tree.connect(_on_entity_child_entered)
	rebuild_for_layout(layout)


func bind_tactical_systems(p_alert_system: Node = null, p_squad_system: Node = null) -> void:
	alert_system = p_alert_system
	squad_system = p_squad_system
	_configure_existing_enemies()


func set_zone_director(director: Node) -> void:
	_zone_director_cache = director
	_zone_director_checked = true
	_configure_existing_enemies()


func build_zone_config_from_layout() -> Array:
	var zone_config: Array[Dictionary] = []
	var zone_edges: Array[Array] = []
	if layout == null:
		return [zone_config, zone_edges]

	if _room_graph.is_empty():
		rebuild_for_layout(layout)

	var void_ids := _extract_void_room_ids(layout)
	var void_lookup: Dictionary = {}
	for rid_variant in void_ids:
		void_lookup[int(rid_variant)] = true

	var configured_zone_ids: Dictionary = {}
	var rooms: Array = []
	if layout is Dictionary:
		rooms = ((layout as Dictionary).get("rooms", []) as Array)
	elif "rooms" in layout:
		rooms = layout.rooms as Array

	for i in range(rooms.size()):
		if void_lookup.has(i):
			continue
		var room_id := i
		var room_dict := rooms[i] as Dictionary
		if room_dict and room_dict.has("id"):
			room_id = int(room_dict.get("id", i))
		if room_id < 0 or void_lookup.has(room_id):
			continue
		if configured_zone_ids.has(room_id):
			continue
		configured_zone_ids[room_id] = true
		zone_config.append({
			"id": room_id,
			"rooms": [room_id],
			"zone_id": room_id,
			"room_ids": [room_id],
		})

	for room_key_variant in _room_graph.keys():
		var room_id := int(room_key_variant)
		if room_id < 0 or void_lookup.has(room_id):
			continue
		if configured_zone_ids.has(room_id):
			continue
		configured_zone_ids[room_id] = true
		zone_config.append({
			"id": room_id,
			"rooms": [room_id],
			"zone_id": room_id,
			"room_ids": [room_id],
		})

	var edge_seen: Dictionary = {}
	for room_key_variant in _room_graph.keys():
		var a := int(room_key_variant)
		if a < 0 or void_lookup.has(a):
			continue
		for neighbor_variant in (_room_graph.get(room_key_variant, []) as Array):
			var b := int(neighbor_variant)
			if b < 0 or a == b or void_lookup.has(b):
				continue
			var key := _pair_key(a, b)
			if edge_seen.has(key):
				continue
			edge_seen[key] = true
			zone_edges.append([mini(a, b), maxi(a, b)])
	return [zone_config, zone_edges]


func rebuild_for_layout(p_layout) -> void:
	layout = p_layout
	_room_graph.clear()
	_pair_doors.clear()

	if not layout or not bool(layout.valid):
		return

	# Base room adjacency from generator door graph.
	if "_door_adj" in layout and (layout._door_adj is Dictionary):
		for rid_variant in layout._door_adj.keys():
			var rid := int(rid_variant)
			var arr: Array = []
			for n_variant in (layout._door_adj[rid_variant] as Array):
				arr.append(int(n_variant))
			_room_graph[rid] = arr

	# Door centers per room-pair for waypoint routing.
	for door_variant in (layout.doors as Array):
		var door := door_variant as Rect2
		var adjacent := _adjacent_room_ids_for_door(door)
		if adjacent.size() != 2:
			continue
		var a := int(adjacent[0])
		var b := int(adjacent[1])
		if a == b:
			continue
		var key := _pair_key(a, b)
		if not _pair_doors.has(key):
			_pair_doors[key] = []
		(_pair_doors[key] as Array).append(door.get_center())

		if not _room_graph.has(a):
			_room_graph[a] = []
		if not _room_graph.has(b):
			_room_graph[b] = []
		if not ((_room_graph[a] as Array).has(b)):
			(_room_graph[a] as Array).append(b)
		if not ((_room_graph[b] as Array).has(a)):
			(_room_graph[b] as Array).append(a)

	if alert_system and alert_system.has_method("reset_all"):
		alert_system.reset_all()
	_configure_existing_enemies()


func clear() -> void:
	for region in _nav_regions:
		if is_instance_valid(region):
			region.queue_free()
	_nav_regions.clear()
	_room_to_region.clear()
	_room_graph.clear()
	_pair_doors.clear()
	_last_nav_obstacle_source = "none"
	_last_nav_obstacles.clear()
	_geometry_map_unavailable_warned = false
	_nav_build_invalid = false


func build_from_layout(p_layout, parent: Node2D) -> void:
	clear()
	if parent == null:
		return
	if not p_layout or not bool(p_layout.valid):
		return

	layout = p_layout
	rebuild_for_layout(layout)
	_nav_build_invalid = false

	var void_ids: Array = []
	for rid_variant in _extract_void_room_ids(layout):
		void_ids.append(int(rid_variant))

	# Collect all door overlap rects per room first so each room bakes once.
	var door_overlaps_per_room: Dictionary = {}
	if layout.has_method("_door_adjacent_room_ids"):
		for door_variant in (layout.doors as Array):
			var door_rect := door_variant as Rect2
			if door_rect == Rect2():
				continue
			var adjacent: Array = layout._door_adjacent_room_ids(door_rect)
			if adjacent.size() != 2:
				continue
			var overlap_rect := door_rect.grow(DOOR_NAV_OVERLAP_PX)
			for room_id_variant in adjacent:
				var room_id := int(room_id_variant)
				if not door_overlaps_per_room.has(room_id):
					door_overlaps_per_room[room_id] = []
				door_overlaps_per_room[room_id].append(overlap_rect)

	var nav_obstacles := _resolve_nav_obstacles_for_build(layout)
	_last_nav_obstacles = nav_obstacles.duplicate()
	var cleared_obstacles: Array[Rect2] = []
	for obs in nav_obstacles:
		cleared_obstacles.append((obs as Rect2).grow(OBSTACLE_CLEARANCE_PX))

	for i in range(layout.rooms.size()):
		if i in void_ids:
			continue
		var room := layout.rooms[i] as Dictionary
		var rects := room.get("rects", []) as Array
		var carved_rects := _subtract_obstacles_from_rects(rects, cleared_obstacles)
		var door_overlaps: Array = door_overlaps_per_room.get(i, [])
		var door_overlaps_carved := _subtract_obstacles_from_rects(door_overlaps, cleared_obstacles)
		_create_region_for_room(i, carved_rects, door_overlaps_carved, parent)

	_validate_nav_build_integrity(nav_obstacles)


func get_navigation_map_rid() -> RID:
	if _nav_build_invalid:
		return RID()
	for region in _nav_regions:
		if is_instance_valid(region):
			return region.get_navigation_map()
	var viewport := get_viewport()
	if viewport and viewport.world_2d:
		return viewport.world_2d.navigation_map
	return RID()


func debug_get_nav_obstacle_source() -> String:
	return _last_nav_obstacle_source


func is_navigation_build_valid() -> bool:
	return not _nav_build_invalid


func path_intersects_navigation_obstacles(
	from_pos: Vector2,
	path_points: Array,
	sample_step_px: float = OBSTACLE_INTERSECTION_SAMPLE_STEP_PX
) -> bool:
	if _last_nav_obstacles.is_empty() or path_points.is_empty():
		return false
	var sample_step := maxf(sample_step_px, 1.0)
	var prev := from_pos
	for point_variant in path_points:
		var point := point_variant as Vector2
		var seg_len := prev.distance_to(point)
		var steps := maxi(int(ceil(seg_len / sample_step)), 1)
		for step in range(1, steps + 1):
			var t := float(step) / float(steps)
			var sample := prev.lerp(point, t)
			for obstacle_variant in _last_nav_obstacles:
				var obstacle := obstacle_variant as Rect2
				if obstacle.size.x <= NAV_CARVE_EPSILON or obstacle.size.y <= NAV_CARVE_EPSILON:
					continue
				if obstacle.has_point(sample):
					return true
		prev = point
	return false


func room_id_at_point(p: Vector2) -> int:
	_ensure_runtime_components()
	return int(_runtime_queries.room_id_at_point(p))


func can_enemy_traverse_shadow_policy_point(enemy: Node, point: Vector2) -> bool:
	_ensure_runtime_components()
	if _shadow_policy and _shadow_policy.has_method("can_enemy_traverse_shadow_policy_point"):
		return bool(_shadow_policy.call("can_enemy_traverse_shadow_policy_point", enemy, point))
	return bool(_shadow_policy.can_enemy_traverse_point(enemy, point))


func can_enemy_traverse_geometry_point(_enemy: Node, point: Vector2) -> bool:
	return is_point_on_navigation_map(point)


func is_point_on_navigation_map(point: Vector2, tolerance_px: float = 4.0) -> bool:
	if not _has_bound_navigation_regions():
		if not _geometry_map_unavailable_warned:
			_geometry_map_unavailable_warned = true
			push_warning("geometry_map_unavailable")
		return false
	var map_rid := get_navigation_map_rid()
	if not map_rid.is_valid():
		if not _geometry_map_unavailable_warned:
			_geometry_map_unavailable_warned = true
			push_warning("geometry_map_unavailable")
		return false
	var iteration_id := NavigationServer2D.map_get_iteration_id(map_rid)
	if iteration_id <= 0:
		if not _geometry_map_unavailable_warned:
			_geometry_map_unavailable_warned = true
			push_warning("geometry_map_unavailable")
		return false
	_geometry_map_unavailable_warned = false
	var closest_point := NavigationServer2D.map_get_closest_point(map_rid, point)
	if not _is_finite_vector2(closest_point):
		return false
	var max_dist := maxf(tolerance_px, 0.0)
	var on_nav_map := closest_point.distance_to(point) <= max_dist + 0.001
	if _is_point_inside_navigation_obstacle(point):
		if on_nav_map and AIWatchdog and AIWatchdog.has_method("record_geometry_walkable_false_positive_event"):
			AIWatchdog.call("record_geometry_walkable_false_positive_event")
		return false
	return on_nav_map


func _has_bound_navigation_regions() -> bool:
	for region in _nav_regions:
		if is_instance_valid(region):
			return true
	return false


func can_enemy_traverse_point(enemy: Node, point: Vector2) -> bool:
	if not _legacy_traverse_api_warned:
		_legacy_traverse_api_warned = true
		push_warning("can_enemy_traverse_point is deprecated; use can_enemy_traverse_shadow_policy_point/can_enemy_traverse_geometry_point")
	return can_enemy_traverse_shadow_policy_point(enemy, point)


func validate_enemy_path_policy(
	enemy: Node,
	from_pos: Vector2,
	path_points: Array,
	sample_step_px: float = POLICY_SAMPLE_STEP_PX
) -> Dictionary:
	_ensure_runtime_components()
	return _shadow_policy.validate_enemy_path_policy(enemy, from_pos, path_points, sample_step_px)


func is_point_in_shadow(point: Vector2) -> bool:
	_ensure_runtime_components()
	return bool(_shadow_policy.is_point_in_shadow(point))


func get_nearest_non_shadow_point(from_pos: Vector2, search_radius: float) -> Vector2:
	var max_radius := maxf(search_radius, 0.0)
	if max_radius <= 0.0:
		return Vector2.ZERO
	if not is_point_in_shadow(from_pos):
		return from_pos
	var sample_count := 12
	var ring_radii := [32.0, 64.0, 96.0]
	var best_point := Vector2.ZERO
	var best_dist := INF
	for radius_variant in ring_radii:
		var radius := float(radius_variant)
		if radius > max_radius + 0.001:
			continue
		for i in range(sample_count):
			var angle := TAU * (float(i) / float(sample_count))
			var candidate := from_pos + Vector2.RIGHT.rotated(angle) * radius
			if is_point_in_shadow(candidate):
				continue
			var dist := from_pos.distance_to(candidate)
			if dist < best_dist:
				best_dist = dist
				best_point = candidate
	if not is_finite(best_dist):
		return Vector2.ZERO
	return best_point


func get_nearest_shadow_zone_direction(pos: Vector2, range_px: float) -> Dictionary:
	var tree := get_tree()
	if tree == null:
		return {"found": false}
	var best_dist := range_px
	var best_dir := Vector2.ZERO
	for zone_variant in tree.get_nodes_in_group("shadow_zones"):
		var zone := zone_variant as Node2D
		if zone == null or not zone.has_method("contains_point"):
			continue
		var zone_center := zone.global_position
		var dist := pos.distance_to(zone_center)
		if dist < best_dist:
			best_dist = dist
			best_dir = (zone_center - pos).normalized()
	if best_dir == Vector2.ZERO:
		return {"found": false}
	return {"found": true, "direction": best_dir}


func is_adjacent(a: int, b: int) -> bool:
	_ensure_runtime_components()
	return bool(_runtime_queries.is_adjacent(a, b))


func is_same_or_adjacent_room(room_a: int, room_b: int) -> bool:
	_ensure_runtime_components()
	return bool(_runtime_queries.is_same_or_adjacent_room(room_a, room_b))


func get_enemy_room_id(enemy: Node) -> int:
	_ensure_runtime_components()
	return int(_runtime_queries.get_enemy_room_id(enemy))


func get_neighbors(room_id: int) -> Array[int]:
	_ensure_runtime_components()
	return _runtime_queries.get_neighbors(room_id)


func get_enemy_room_id_by_id(enemy_id: int) -> int:
	_ensure_runtime_components()
	return int(_runtime_queries.get_enemy_room_id_by_id(enemy_id))


func get_alert_level(room_id: int) -> int:
	_ensure_runtime_components()
	return int(_runtime_queries.get_alert_level(room_id))


func get_alert_level_at_point(p: Vector2) -> int:
	_ensure_runtime_components()
	return int(_runtime_queries.get_alert_level_at_point(p))


func get_adjacent_room_ids(room_id: int) -> Array[int]:
	_ensure_runtime_components()
	return _runtime_queries.get_adjacent_room_ids(room_id)


func get_room_center(room_id: int) -> Vector2:
	_ensure_runtime_components()
	return _runtime_queries.get_room_center(room_id)


func get_room_rect(room_id: int) -> Rect2:
	_ensure_runtime_components()
	return _runtime_queries.get_room_rect(room_id)


func get_door_center_between(room_a: int, room_b: int, anchor: Vector2) -> Vector2:
	_ensure_runtime_components()
	return _runtime_queries.get_door_center_between(room_a, room_b, anchor)


func get_player_position() -> Vector2:
	_ensure_runtime_components()
	return _runtime_queries.get_player_position()


func get_enemies_in_room(room_id: int) -> Array[Node]:
	_ensure_runtime_components()
	return _runtime_queries.get_enemies_in_room(room_id)


func pick_top2_neighbor_rooms_for_reinforcement(source_room: int, player_pos: Vector2) -> Array[int]:
	_ensure_runtime_components()
	return _runtime_queries.pick_top2_neighbor_rooms_for_reinforcement(source_room, player_pos)


func random_point_in_room(room_id: int, margin: float = 20.0) -> Vector2:
	_ensure_runtime_components()
	return _runtime_queries.random_point_in_room(room_id, margin)


func build_path_points(from_pos: Vector2, to_pos: Vector2) -> Array[Vector2]:
	_ensure_runtime_components()
	return _runtime_queries.build_path_points(from_pos, to_pos)


func build_policy_valid_path(
	from_pos: Vector2,
	to_pos: Vector2,
	enemy: Node = null,
	cost_profile: Dictionary = {}
) -> Dictionary:
	_ensure_runtime_components()
	return _runtime_queries.build_policy_valid_path(from_pos, to_pos, enemy, cost_profile)


func build_reachable_path_points(from_pos: Vector2, to_pos: Vector2, enemy: Node = null) -> Array[Vector2]:
	_ensure_runtime_components()
	return _runtime_queries.build_reachable_path_points(from_pos, to_pos, enemy)


func nav_path_length(from_pos: Vector2, to_pos: Vector2, enemy: Node = null) -> float:
	_ensure_runtime_components()
	return float(_runtime_queries.nav_path_length(from_pos, to_pos, enemy))


func _build_room_graph_path_points_reachable(from_pos: Vector2, to_pos: Vector2) -> Array[Vector2]:
	var from_room := room_id_at_point(from_pos)
	var to_room := room_id_at_point(to_pos)
	if from_room < 0 or to_room < 0:
		return []
	if from_room == to_room:
		return [to_pos]

	var room_path := _bfs_room_path(from_room, to_room)
	if room_path.size() < 2:
		return []

	var waypoints: Array[Vector2] = []
	var anchor := from_pos
	for i in range(room_path.size() - 1):
		var a := int(room_path[i])
		var b := int(room_path[i + 1])
		var door_center := _select_door_center(a, b, anchor)
		waypoints.append(door_center)
		anchor = door_center
	waypoints.append(to_pos)
	return waypoints


func _path_crosses_policy_block(enemy: Node, from_pos: Vector2, path_points: Array[Vector2]) -> bool:
	if enemy == null:
		return false
	if path_points.is_empty():
		return false
	var validation := validate_enemy_path_policy(enemy, from_pos, path_points, POLICY_SAMPLE_STEP_PX)
	return not bool(validation.get("valid", false))


func _on_player_shot(_weapon: String, position: Vector3, _direction: Vector3) -> void:
	if not entities_container:
		return
	var shot_pos := Vector2(position.x, position.y)
	var shot_room := room_id_at_point(shot_pos)
	if shot_room < 0:
		return
	for enemy_variant in entities_container.get_children():
		var enemy := enemy_variant as Node
		if not enemy:
			continue
		if not enemy.has_method("on_heard_shot"):
			continue
		var own_room := get_enemy_room_id(enemy)
		if is_same_or_adjacent_room(own_room, shot_room):
			enemy.on_heard_shot(shot_room, shot_pos)


func _configure_existing_enemies() -> void:
	_ensure_runtime_components()
	_enemy_wiring.configure_existing_enemies()


func _on_entity_child_entered(node: Node) -> void:
	_ensure_runtime_components()
	_enemy_wiring.on_entity_child_entered(node)


func _configure_enemy(node: Node) -> void:
	_ensure_runtime_components()
	_enemy_wiring.configure_enemy(node)


func _adjacent_room_ids_for_door(door: Rect2) -> Array:
	if layout and layout.has_method("_door_adjacent_room_ids"):
		return layout._door_adjacent_room_ids(door)
	return []


func _pair_key(a: int, b: int) -> String:
	if a <= b:
		return "%d|%d" % [a, b]
	return "%d|%d" % [b, a]


func _select_door_center(a: int, b: int, anchor: Vector2) -> Vector2:
	var key := _pair_key(a, b)
	if _pair_doors.has(key):
		var centers := _pair_doors[key] as Array
		if not centers.is_empty():
			var best := centers[0] as Vector2
			var best_d := best.distance_to(anchor)
			for c_variant in centers:
				var c := c_variant as Vector2
				var d := c.distance_to(anchor)
				if d < best_d:
					best = c
					best_d = d
			return best
	if layout and a >= 0 and b >= 0 and a < layout.rooms.size() and b < layout.rooms.size():
		var ca := layout.rooms[a].get("center", Vector2.ZERO) as Vector2
		var cb := layout.rooms[b].get("center", Vector2.ZERO) as Vector2
		return (ca + cb) * 0.5
	return anchor


func _bfs_room_path(start_room: int, goal_room: int) -> Array[int]:
	if start_room == goal_room:
		return [start_room]
	if not _room_graph.has(start_room) or not _room_graph.has(goal_room):
		return []

	var visited := {}
	var parent := {}
	var queue: Array[int] = [start_room]
	visited[start_room] = true
	var qi := 0
	while qi < queue.size():
		var cur := int(queue[qi])
		qi += 1
		if cur == goal_room:
			break
		for n_variant in (_room_graph.get(cur, []) as Array):
			var n := int(n_variant)
			if visited.has(n):
				continue
			visited[n] = true
			parent[n] = cur
			queue.append(n)

	if not visited.has(goal_room):
		return []
	var path: Array[int] = [goal_room]
	var curp := goal_room
	while curp != start_room:
		curp = int(parent[curp])
		path.push_front(curp)
	return path


func _create_region_for_room(room_id: int, rects: Array, door_overlaps: Array, parent: Node2D) -> void:
	if rects.is_empty() or parent == null:
		return

	var region := NavigationRegion2D.new()
	var nav_poly := NavigationPolygon.new()

	# Build room outline(s) from rects
	var room_outlines: Array = []
	for rect_variant in rects:
		var rect := rect_variant as Rect2
		if rect.size.x <= NAV_CARVE_EPSILON or rect.size.y <= NAV_CARVE_EPSILON:
			continue
		room_outlines.append(_rect_to_outline(rect))

	# Merge all door overlaps in one pass (avoids repeated nav polygon rebakes)
	var all_outlines: Array = room_outlines.duplicate()
	for overlap_variant in door_overlaps:
		all_outlines = _merge_overlapping_outlines(all_outlines, _rect_to_outline(overlap_variant as Rect2))

	for outline_variant in all_outlines:
		nav_poly.add_outline(outline_variant as PackedVector2Array)

	_bake_navigation_polygon(nav_poly)
	region.navigation_polygon = nav_poly
	region.name = "NavRegion_%d" % room_id
	parent.add_child(region)
	_nav_regions.append(region)
	_room_to_region[room_id] = region


func _resolve_nav_obstacles_for_build(p_layout) -> Array[Rect2]:
	var layout_obstacles := _extract_navigation_obstacles(p_layout)
	if not layout_obstacles.is_empty():
		_last_nav_obstacle_source = "layout_api"
		return layout_obstacles
	_last_nav_obstacle_source = "scene_fallback"
	return _extract_scene_obstacles()


func _extract_navigation_obstacles(p_layout) -> Array[Rect2]:
	var obstacles: Array[Rect2] = []
	if p_layout == null:
		return obstacles
	if not (p_layout is Object):
		return obstacles
	if not p_layout.has_method("_navigation_obstacles"):
		return obstacles

	var raw_variant: Variant = p_layout.call("_navigation_obstacles")
	if not (raw_variant is Array):
		return obstacles

	for obstacle_variant in (raw_variant as Array):
		var obstacle := obstacle_variant as Rect2
		if obstacle.size.x <= NAV_CARVE_EPSILON or obstacle.size.y <= NAV_CARVE_EPSILON:
			continue
		obstacles.append(obstacle)
	return obstacles


func _extract_scene_obstacles() -> Array[Rect2]:
	# Fallback obstacle contract:
	# - Node is in group `nav_obstacles`.
	# - Node type is `StaticBody2D`.
	# - One or more `CollisionShape2D` children with `RectangleShape2D`.
	# - Obstacle rect is resolved in world space via `body.global_position + shape.position`.
	var result: Array[Rect2] = []
	if not is_inside_tree():
		return result
	var nodes := get_tree().get_nodes_in_group(NAV_OBSTACLE_GROUP)
	for node in nodes:
		var body := node as StaticBody2D
		if body == null:
			continue
		for child in body.get_children():
			var col := child as CollisionShape2D
			if col == null:
				continue
			if not (col.shape is RectangleShape2D):
				continue
			var rect_shape := col.shape as RectangleShape2D
			if rect_shape == null:
				continue
			var half := rect_shape.size * 0.5
			var obs_rect := Rect2(body.global_position + col.position - half, rect_shape.size)
			if obs_rect.size.x <= NAV_CARVE_EPSILON or obs_rect.size.y <= NAV_CARVE_EPSILON:
				continue
			result.append(obs_rect)
	return result


func _subtract_obstacles_from_rects(rects: Array, obstacles: Array[Rect2]) -> Array:
	if rects.is_empty() or obstacles.is_empty():
		return rects.duplicate()

	var carved: Array[Rect2] = []
	for rect_variant in rects:
		var source := rect_variant as Rect2
		if source.size.x <= NAV_CARVE_EPSILON or source.size.y <= NAV_CARVE_EPSILON:
			continue
		var fragments: Array[Rect2] = [source]
		for obstacle in obstacles:
			var next_fragments: Array[Rect2] = []
			for fragment_variant in fragments:
				var fragment := fragment_variant as Rect2
				next_fragments.append_array(_subtract_rect(fragment, obstacle))
			fragments = next_fragments
			if fragments.is_empty():
				break
		for fragment in fragments:
			if fragment.size.x <= NAV_CARVE_EPSILON or fragment.size.y <= NAV_CARVE_EPSILON:
				continue
			carved.append(fragment)
	return carved


func _subtract_rect(source: Rect2, obstacle: Rect2) -> Array[Rect2]:
	var intersection := source.intersection(obstacle)
	if intersection.size.x <= NAV_CARVE_EPSILON or intersection.size.y <= NAV_CARVE_EPSILON:
		return [source]

	var out: Array[Rect2] = []
	var top_h := intersection.position.y - source.position.y
	if top_h > NAV_CARVE_EPSILON:
		out.append(Rect2(
			source.position.x,
			source.position.y,
			source.size.x,
			top_h
		))

	var bottom_h := source.end.y - intersection.end.y
	if bottom_h > NAV_CARVE_EPSILON:
		out.append(Rect2(
			source.position.x,
			intersection.end.y,
			source.size.x,
			bottom_h
		))

	var left_w := intersection.position.x - source.position.x
	if left_w > NAV_CARVE_EPSILON:
		out.append(Rect2(
			source.position.x,
			intersection.position.y,
			left_w,
			intersection.size.y
		))

	var right_w := source.end.x - intersection.end.x
	if right_w > NAV_CARVE_EPSILON:
		out.append(Rect2(
			intersection.end.x,
			intersection.position.y,
			right_w,
			intersection.size.y
		))
	return out


static func _bake_navigation_polygon(nav_poly: NavigationPolygon) -> void:
	if nav_poly == null:
		return
	var source_data := NavigationMeshSourceGeometryData2D.new()
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, source_data)


static func _rect_to_outline(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		r.position,
		Vector2(r.end.x, r.position.y),
		r.end,
		Vector2(r.position.x, r.end.y),
	])


static func _rect_to_packed_vector2(r: Rect2) -> PackedVector2Array:
	return _rect_to_outline(r)


static func _merge_overlapping_outlines(existing_outlines: Array, addition: PackedVector2Array) -> Array:
	var pending: Array = []
	for outline_variant in existing_outlines:
		var outline := outline_variant as PackedVector2Array
		if not outline.is_empty():
			pending.append(outline)
	if not addition.is_empty():
		pending.append(addition)
	var merged_any := true
	while merged_any:
		merged_any = false
		var i := 0
		while i < pending.size():
			var j := i + 1
			while j < pending.size():
				var a := pending[i] as PackedVector2Array
				var b := pending[j] as PackedVector2Array
				if not _polygons_have_area_overlap(a, b):
					j += 1
					continue
				var merged := Geometry2D.merge_polygons(a, b)
				if merged.is_empty():
					j += 1
					continue
				pending[i] = merged[0]
				pending.remove_at(j)
				for hole_idx in range(1, merged.size()):
					pending.append(merged[hole_idx])
				merged_any = true
				j = i + 1
			i += 1
	return pending


static func _polygons_have_area_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	var intersections := Geometry2D.intersect_polygons(a, b)
	if intersections.is_empty():
		return false
	for poly_variant in intersections:
		var poly := poly_variant as PackedVector2Array
		if absf(_polygon_area(poly)) > NAV_CARVE_EPSILON:
			return true
	return false


static func _polygon_area(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	var sum := 0.0
	for i in range(poly.size()):
		var p0 := poly[i]
		var p1 := poly[(i + 1) % poly.size()]
		sum += p0.x * p1.y - p1.x * p0.y
	return sum * 0.5


func _extract_void_room_ids(source_layout) -> Array[int]:
	var void_ids: Array[int] = []
	if source_layout == null:
		return void_ids
	if source_layout is Dictionary:
		for rid_variant in ((source_layout as Dictionary).get("_void_ids", []) as Array):
			void_ids.append(int(rid_variant))
		return void_ids
	if source_layout is Object:
		for prop_variant in source_layout.get_property_list():
			var prop := prop_variant as Dictionary
			if String(prop.get("name", "")) != "_void_ids":
				continue
			for rid_variant in (source_layout.get("_void_ids") as Array):
				void_ids.append(int(rid_variant))
			break
	return void_ids


static func _is_finite_vector2(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)


func _is_point_inside_navigation_obstacle(point: Vector2) -> bool:
	for obstacle_variant in _last_nav_obstacles:
		var obstacle := obstacle_variant as Rect2
		if obstacle.size.x <= NAV_CARVE_EPSILON or obstacle.size.y <= NAV_CARVE_EPSILON:
			continue
		if obstacle.has_point(point):
			return true
	return false


func _validate_nav_build_integrity(nav_obstacles: Array[Rect2], attempt: int = 0) -> void:
	if nav_obstacles.is_empty():
		return
	var map_rid := get_navigation_map_rid()
	if not map_rid.is_valid():
		_nav_build_invalid = true
		push_error("invalid_nav_build:geometry_map_unavailable")
		return
	var iteration_id := NavigationServer2D.map_get_iteration_id(map_rid)
	if iteration_id <= 0:
		if attempt < 3:
			call_deferred("_validate_nav_build_integrity_deferred", nav_obstacles.duplicate(), attempt + 1)
		return
	for obstacle_variant in nav_obstacles:
		var obstacle := obstacle_variant as Rect2
		if obstacle.size.x <= NAV_CARVE_EPSILON or obstacle.size.y <= NAV_CARVE_EPSILON:
			continue
		var center := obstacle.get_center()
		var closest := NavigationServer2D.map_get_closest_point(map_rid, center)
		if not _is_finite_vector2(closest):
			_nav_build_invalid = true
			push_error("invalid_nav_build:geometry_closest_point_invalid")
			return
		if center.distance_to(closest) <= 4.0:
			push_warning(
				"invalid_nav_build:obstacle_center_walkable center=%s closest=%s distance=%.3f obstacle=%s"
				% [str(center), str(closest), center.distance_to(closest), str(obstacle)]
			)


func _validate_nav_build_integrity_deferred(nav_obstacles_variant: Variant, attempt: int) -> void:
	await get_tree().process_frame
	if _nav_build_invalid:
		return
	var nav_obstacles: Array[Rect2] = []
	if nav_obstacles_variant is Array:
		for obstacle_variant in (nav_obstacles_variant as Array):
			nav_obstacles.append(obstacle_variant as Rect2)
	_validate_nav_build_integrity(nav_obstacles, attempt)
