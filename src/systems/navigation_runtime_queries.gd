## navigation_runtime_queries.gd
## Runtime query helpers for NavigationService.
class_name NavigationRuntimeQueries
extends RefCounted

var _service: Node = null


func _init(service: Node) -> void:
	_service = service


func room_id_at_point(p: Vector2) -> int:
	var layout = _service.layout
	if not layout or not bool(layout.valid):
		return -1
	if not layout.has_method("_room_id_at_point"):
		return -1
	return int(layout._room_id_at_point(p))


func is_adjacent(a: int, b: int) -> bool:
	if a < 0 or b < 0:
		return false
	if not _service._room_graph.has(a):
		return false
	return (_service._room_graph[a] as Array).has(b)


func get_enemy_room_id(enemy: Node) -> int:
	if not enemy:
		return -1
	var enemy_node := enemy as Node2D
	if enemy_node and _service.layout and bool(_service.layout.valid):
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
	if room_id < 0 or not _service._room_graph.has(room_id):
		return result
	for rid_variant in (_service._room_graph[room_id] as Array):
		var rid := int(rid_variant)
		if rid >= 0 and rid != room_id:
			result.append(rid)
	result.sort()
	return result


func get_enemy_room_id_by_id(enemy_id: int) -> int:
	if enemy_id <= 0 or not _service.entities_container:
		return -1
	for child_variant in _service.entities_container.get_children():
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
	if _service.alert_system and _service.alert_system.has_method("get_room_alert_level"):
		return int(_service.alert_system.get_room_alert_level(room_id))
	return 0


func get_alert_level_at_point(p: Vector2) -> int:
	return get_alert_level(room_id_at_point(p))


func get_adjacent_room_ids(room_id: int) -> Array[int]:
	return get_neighbors(room_id)


func get_room_center(room_id: int) -> Vector2:
	if not _service.layout or not bool(_service.layout.valid):
		return Vector2.ZERO
	if room_id < 0 or room_id >= _service.layout.rooms.size():
		return Vector2.ZERO
	var room := _service.layout.rooms[room_id] as Dictionary
	return room.get("center", Vector2.ZERO) as Vector2


func get_room_rect(room_id: int) -> Rect2:
	if not _service.layout or not bool(_service.layout.valid):
		return Rect2()
	if room_id < 0 or room_id >= _service.layout.rooms.size():
		return Rect2()
	var room := _service.layout.rooms[room_id] as Dictionary
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
	return _service._select_door_center(room_a, room_b, anchor)


func get_player_position() -> Vector2:
	if _service.player_node and is_instance_valid(_service.player_node):
		return _service.player_node.global_position
	if RuntimeState:
		return Vector2(RuntimeState.player_pos.x, RuntimeState.player_pos.y)
	return Vector2.ZERO


func get_enemies_in_room(room_id: int) -> Array[Node]:
	var result: Array[Node] = []
	if room_id < 0 or not _service.entities_container:
		return result
	for child_variant in _service.entities_container.get_children():
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
	if not _service.layout or not bool(_service.layout.valid):
		return Vector2.ZERO
	if room_id < 0 or room_id >= _service.layout.rooms.size():
		return Vector2.ZERO
	var room := _service.layout.rooms[room_id] as Dictionary
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
		_service._rng.randf_range(safe.position.x, safe.end.x),
		_service._rng.randf_range(safe.position.y, safe.end.y)
	)


func build_path_points(from_pos: Vector2, to_pos: Vector2) -> Array[Vector2]:
	var reachable_path := build_reachable_path_points(from_pos, to_pos)
	if not reachable_path.is_empty():
		return reachable_path
	return [to_pos]


func build_reachable_path_points(from_pos: Vector2, to_pos: Vector2, enemy: Node = null) -> Array[Vector2]:
	var map_rid: RID = _service.get_navigation_map_rid()
	if map_rid.is_valid():
		var raw_path: PackedVector2Array = NavigationServer2D.map_get_path(map_rid, from_pos, to_pos, true)
		if raw_path.is_empty():
			return []
		var out: Array[Vector2] = []
		for p in raw_path:
			out.append(p)
		if out.is_empty() or out[out.size() - 1].distance_to(to_pos) > 0.5:
			out.append(to_pos)
		if enemy != null and bool(_service.call("_path_crosses_policy_block", enemy, from_pos, out)):
			return []
		return out

	var room_graph_variant: Variant = _service.call("_build_room_graph_path_points_reachable", from_pos, to_pos)
	var room_graph_path: Array[Vector2] = []
	if room_graph_variant is Array:
		for point_variant in (room_graph_variant as Array):
			room_graph_path.append(point_variant as Vector2)
	if room_graph_path.is_empty():
		return []
	if enemy != null and bool(_service.call("_path_crosses_policy_block", enemy, from_pos, room_graph_path)):
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
