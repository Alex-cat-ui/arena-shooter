## navigation_service.gd
## Room-level navigation helper for enemies on ProceduralLayoutV2.
class_name NavigationService
extends Node

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
const POLICY_SAMPLE_STEP_PX := 12.0
var _nav_regions: Array[NavigationRegion2D] = []
var _room_to_region: Dictionary = {} # room_id -> NavigationRegion2D


func initialize(p_layout, p_entities_container: Node2D, p_player_node: Node2D) -> void:
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


func build_from_layout(p_layout, parent: Node2D) -> void:
	clear()
	if parent == null:
		return
	if not p_layout or not bool(p_layout.valid):
		return

	layout = p_layout
	rebuild_for_layout(layout)

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

	var nav_obstacles := _extract_navigation_obstacles(layout)

	for i in range(layout.rooms.size()):
		if i in void_ids:
			continue
		var room := layout.rooms[i] as Dictionary
		var rects := room.get("rects", []) as Array
		var carved_rects := _subtract_obstacles_from_rects(rects, nav_obstacles)
		if carved_rects.is_empty():
			carved_rects = rects
		var door_overlaps: Array = door_overlaps_per_room.get(i, [])
		_create_region_for_room(i, carved_rects, door_overlaps, parent)


func get_navigation_map_rid() -> RID:
	for region in _nav_regions:
		if is_instance_valid(region):
			return region.get_navigation_map()
	var viewport := get_viewport()
	if viewport and viewport.world_2d:
		return viewport.world_2d.navigation_map
	return RID()


func room_id_at_point(p: Vector2) -> int:
	if not layout or not bool(layout.valid):
		return -1
	if not layout.has_method("_room_id_at_point"):
		return -1
	return int(layout._room_id_at_point(p))


func can_enemy_traverse_point(enemy: Node, point: Vector2) -> bool:
	if enemy == null:
		return true
	if _is_enemy_flashlight_active(enemy):
		return true
	return not is_point_in_shadow(point)


func is_point_in_shadow(point: Vector2) -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for zone_variant in tree.get_nodes_in_group("shadow_zones"):
		var zone := zone_variant as ShadowZone
		if zone == null:
			continue
		if zone.contains_point(point):
			return true
	return false


func is_adjacent(a: int, b: int) -> bool:
	if a < 0 or b < 0:
		return false
	if not _room_graph.has(a):
		return false
	return (_room_graph[a] as Array).has(b)


func get_enemy_room_id(enemy: Node) -> int:
	if not enemy:
		return -1
	var enemy_node := enemy as Node2D
	if enemy_node and layout and bool(layout.valid):
		var detected_room := room_id_at_point(enemy_node.global_position)
		if detected_room >= 0:
			enemy.set_meta("room_id", detected_room)
			return detected_room
	var room_id := int(enemy.get_meta("room_id", -1))
	if room_id >= 0:
		return room_id
	if not enemy_node:
		return -1
	room_id = room_id_at_point(enemy_node.global_position)
	enemy.set_meta("room_id", room_id)
	return room_id


func get_neighbors(room_id: int) -> Array[int]:
	var result: Array[int] = []
	if room_id < 0 or not _room_graph.has(room_id):
		return result
	for rid_variant in (_room_graph[room_id] as Array):
		var rid := int(rid_variant)
		if rid >= 0 and rid != room_id:
			result.append(rid)
	result.sort()
	return result


func get_enemy_room_id_by_id(enemy_id: int) -> int:
	if enemy_id <= 0 or not entities_container:
		return -1
	for child_variant in entities_container.get_children():
		var enemy := child_variant as Node
		if not enemy:
			continue
		if not enemy.is_in_group("enemies"):
			continue
		if not ("entity_id" in enemy):
			continue
		if int(enemy.entity_id) != enemy_id:
			continue
		return get_enemy_room_id(enemy)
	return -1


func get_alert_level(room_id: int) -> int:
	if alert_system and alert_system.has_method("get_room_alert_level"):
		return int(alert_system.get_room_alert_level(room_id))
	return 0


func get_alert_level_at_point(p: Vector2) -> int:
	return get_alert_level(room_id_at_point(p))


func get_adjacent_room_ids(room_id: int) -> Array[int]:
	return get_neighbors(room_id)


func get_room_center(room_id: int) -> Vector2:
	if not layout or not bool(layout.valid):
		return Vector2.ZERO
	if room_id < 0 or room_id >= layout.rooms.size():
		return Vector2.ZERO
	var room := layout.rooms[room_id] as Dictionary
	return room.get("center", Vector2.ZERO) as Vector2


func get_room_rect(room_id: int) -> Rect2:
	if not layout or not bool(layout.valid):
		return Rect2()
	if room_id < 0 or room_id >= layout.rooms.size():
		return Rect2()
	var room := layout.rooms[room_id] as Dictionary
	var rects := room.get("rects", []) as Array
	if rects.is_empty():
		return Rect2()
	var best := rects[0] as Rect2
	for rect_variant in rects:
		var r := rect_variant as Rect2
		if r.get_area() > best.get_area():
			best = r
	return best


func get_door_center_between(room_a: int, room_b: int, anchor: Vector2) -> Vector2:
	return _select_door_center(room_a, room_b, anchor)


func _is_enemy_flashlight_active(enemy: Node) -> bool:
	if enemy == null:
		return false
	if enemy.has_method("is_flashlight_active_for_navigation"):
		var active_variant: Variant = enemy.call("is_flashlight_active_for_navigation")
		return bool(active_variant)
	if enemy.has_meta("flashlight_active"):
		return bool(enemy.get_meta("flashlight_active"))
	if enemy.has_method("get_debug_detection_snapshot"):
		var snapshot_variant: Variant = enemy.call("get_debug_detection_snapshot")
		if snapshot_variant is Dictionary:
			var snapshot := snapshot_variant as Dictionary
			return bool(snapshot.get("flashlight_active", false))
	return false


func get_player_position() -> Vector2:
	if player_node and is_instance_valid(player_node):
		return player_node.global_position
	if RuntimeState:
		return Vector2(RuntimeState.player_pos.x, RuntimeState.player_pos.y)
	return Vector2.ZERO


func get_enemies_in_room(room_id: int) -> Array[Node]:
	var result: Array[Node] = []
	if room_id < 0 or not entities_container:
		return result
	for child_variant in entities_container.get_children():
		var enemy := child_variant as Node2D
		if not enemy:
			continue
		if not enemy.is_in_group("enemies"):
			continue
		if "is_dead" in enemy and bool(enemy.is_dead):
			continue
		var own_room := get_enemy_room_id(enemy)
		if own_room == room_id:
			result.append(enemy)
	return result


func pick_top2_neighbor_rooms_for_reinforcement(source_room: int, player_pos: Vector2) -> Array[int]:
	var neighbors := get_neighbors(source_room)
	if neighbors.size() <= 2:
		return neighbors
	var scored: Array[Dictionary] = []
	for room_id in neighbors:
		scored.append({
			"room_id": room_id,
			"dist": get_room_center(room_id).distance_to(player_pos),
		})
	scored.sort_custom(func(a, b):
		var da := float(a.get("dist", INF))
		var db := float(b.get("dist", INF))
		if is_equal_approx(da, db):
			return int(a.get("room_id", -1)) < int(b.get("room_id", -1))
		return da < db
	)
	return [
		int(scored[0].get("room_id", -1)),
		int(scored[1].get("room_id", -1)),
	]


func random_point_in_room(room_id: int, margin: float = 20.0) -> Vector2:
	if not layout or not bool(layout.valid):
		return Vector2.ZERO
	if room_id < 0 or room_id >= layout.rooms.size():
		return Vector2.ZERO
	var room := layout.rooms[room_id] as Dictionary
	var rects := room.get("rects", []) as Array
	if rects.is_empty():
		return room.get("center", Vector2.ZERO) as Vector2

	var pick_rect := rects[0] as Rect2
	for rect_variant in rects:
		var r := rect_variant as Rect2
		if r.get_area() > pick_rect.get_area():
			pick_rect = r
	var safe := pick_rect.grow(-margin)
	if safe.size.x < 4.0 or safe.size.y < 4.0:
		safe = pick_rect.grow(-4.0)
	if safe.size.x < 2.0 or safe.size.y < 2.0:
		return pick_rect.get_center()
	return Vector2(
		_rng.randf_range(safe.position.x, safe.end.x),
		_rng.randf_range(safe.position.y, safe.end.y)
	)


func build_path_points(from_pos: Vector2, to_pos: Vector2) -> Array[Vector2]:
	var reachable_path := build_reachable_path_points(from_pos, to_pos)
	if not reachable_path.is_empty():
		return reachable_path
	return [to_pos]


func build_reachable_path_points(from_pos: Vector2, to_pos: Vector2, enemy: Node = null) -> Array[Vector2]:
	var map_rid := get_navigation_map_rid()
	if map_rid.is_valid():
		var raw_path: PackedVector2Array = NavigationServer2D.map_get_path(map_rid, from_pos, to_pos, true)
		if raw_path.is_empty():
			return []
		var out: Array[Vector2] = []
		for p in raw_path:
			out.append(p)
		if out.is_empty() or out[out.size() - 1].distance_to(to_pos) > 0.5:
			out.append(to_pos)
		if enemy != null and _path_crosses_policy_block(enemy, from_pos, out):
			return []
		return out
	var room_graph_path := _build_room_graph_path_points_reachable(from_pos, to_pos)
	if room_graph_path.is_empty():
		return []
	if enemy != null and _path_crosses_policy_block(enemy, from_pos, room_graph_path):
		return []
	return room_graph_path


func nav_path_length(from_pos: Vector2, to_pos: Vector2, enemy: Node = null) -> float:
	var path := build_reachable_path_points(from_pos, to_pos, enemy)
	if path.is_empty():
		return INF
	var total := 0.0
	var prev := from_pos
	for point in path:
		total += prev.distance_to(point)
		prev = point
	return total


func _build_room_graph_path_points(from_pos: Vector2, to_pos: Vector2) -> Array[Vector2]:
	var path := _build_room_graph_path_points_reachable(from_pos, to_pos)
	if not path.is_empty():
		return path
	return [to_pos]


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
	var prev := from_pos
	for point in path_points:
		var segment_len := prev.distance_to(point)
		var steps := maxi(int(ceil(segment_len / POLICY_SAMPLE_STEP_PX)), 1)
		for step in range(1, steps + 1):
			var t := float(step) / float(steps)
			var sample := prev.lerp(point, t)
			if not can_enemy_traverse_point(enemy, sample):
				return true
		prev = point
	return false


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
		if own_room == shot_room or is_adjacent(own_room, shot_room):
			enemy.on_heard_shot(shot_room, shot_pos)


func _configure_existing_enemies() -> void:
	if not entities_container:
		return
	for child in entities_container.get_children():
		_configure_enemy(child)


func _on_entity_child_entered(node: Node) -> void:
	call_deferred("_configure_enemy", node)


func _configure_enemy(node: Node) -> void:
	var enemy := node as Node2D
	if not enemy:
		return
	if not enemy.is_in_group("enemies"):
		return
	var room_id := room_id_at_point(enemy.global_position)
	enemy.set_meta("room_id", room_id)
	if enemy.has_method("set_room_navigation"):
		enemy.set_room_navigation(self, room_id)
	if enemy.has_method("set_tactical_systems"):
		enemy.set_tactical_systems(alert_system, squad_system)
	if enemy.has_method("set_zone_director"):
		var zone_director := _get_zone_director()
		if zone_director:
			enemy.set_zone_director(zone_director)
	var door_system := _resolve_door_system_for_enemy()
	if door_system:
		enemy.set_meta("door_system", door_system)


func _get_zone_director() -> Node:
	if _zone_director_checked:
		return _zone_director_cache
	_zone_director_checked = true
	if not get_tree():
		return null
	if not get_tree().root:
		return null
	if get_tree().root.has_node("ZoneDirector"):
		_zone_director_cache = get_tree().root.get_node("ZoneDirector")
	return _zone_director_cache


func _resolve_door_system_for_enemy() -> Node:
	if layout is Dictionary:
		var layout_dict := layout as Dictionary
		if "door_system" in layout_dict:
			return layout_dict.get("door_system", null) as Node
	if layout and not (layout is Dictionary) and layout.has_meta("door_system"):
		return layout.get_meta("door_system") as Node
	if entities_container:
		var level_root := entities_container.get_parent()
		if level_root:
			return level_root.get_node_or_null("LayoutDoorSystem")
	return null


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
	if rects.size() == 1:
		room_outlines.append(_rect_to_outline(rects[0] as Rect2))
	else:
		var merged := _rect_to_packed_vector2(rects[0] as Rect2)
		for i in range(1, rects.size()):
			var next := _rect_to_packed_vector2(rects[i] as Rect2)
			var result: Array = Geometry2D.merge_polygons(merged, next)
			if result.is_empty():
				room_outlines.append(merged)
				merged = next
			else:
				merged = result[0] as PackedVector2Array
				for hole_idx in range(1, result.size()):
					room_outlines.append(result[hole_idx] as PackedVector2Array)
		room_outlines.append(merged)

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


func _connect_regions_at_door(door_rect: Rect2, p_layout) -> void:
	if door_rect == Rect2():
		return
	if not (p_layout is Object):
		return
	if not p_layout.has_method("_door_adjacent_room_ids"):
		return
	var adjacent := p_layout._door_adjacent_room_ids(door_rect) as Array
	if adjacent.size() != 2:
		return

	var a := int(adjacent[0])
	var b := int(adjacent[1])
	var overlap_rect := door_rect.grow(DOOR_NAV_OVERLAP_PX)

	for room_id in [a, b]:
		if not _room_to_region.has(room_id):
			continue
		var region := _room_to_region[room_id] as NavigationRegion2D
		if region == null:
			continue
		var nav_poly := region.navigation_polygon
		if nav_poly == null:
			continue
		var existing_outlines: Array = []
		for idx in range(nav_poly.get_outline_count()):
			existing_outlines.append(nav_poly.get_outline(idx))
		var merged_outlines := _merge_overlapping_outlines(existing_outlines, _rect_to_outline(overlap_rect))
		var rebuilt := NavigationPolygon.new()
		for outline_variant in merged_outlines:
			rebuilt.add_outline(outline_variant as PackedVector2Array)
		_bake_navigation_polygon(rebuilt)
		region.navigation_polygon = rebuilt


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
