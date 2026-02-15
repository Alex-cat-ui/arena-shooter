## room_nav_system.gd
## Room-level navigation helper for enemies on ProceduralLayoutV2.
class_name RoomNavSystem
extends Node

var layout = null
var entities_container: Node2D = null
var player_node: Node2D = null

var _room_graph: Dictionary = {}      # room_id -> Array[int]
var _pair_doors: Dictionary = {}      # "a|b" -> Array[Vector2]
var _rng := RandomNumberGenerator.new()


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

	_configure_existing_enemies()


func room_id_at_point(p: Vector2) -> int:
	if not layout or not bool(layout.valid):
		return -1
	if not layout.has_method("_room_id_at_point"):
		return -1
	return int(layout._room_id_at_point(p))


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


func get_adjacent_room_ids(room_id: int) -> Array[int]:
	return get_neighbors(room_id)


func get_room_center(room_id: int) -> Vector2:
	if not layout or not bool(layout.valid):
		return Vector2.ZERO
	if room_id < 0 or room_id >= layout.rooms.size():
		return Vector2.ZERO
	var room := layout.rooms[room_id] as Dictionary
	return room.get("center", Vector2.ZERO) as Vector2


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
	var from_room := room_id_at_point(from_pos)
	var to_room := room_id_at_point(to_pos)
	if from_room < 0 or to_room < 0:
		return [to_pos]
	if from_room == to_room:
		return [to_pos]

	var room_path := _bfs_room_path(from_room, to_room)
	if room_path.size() < 2:
		return [to_pos]

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
