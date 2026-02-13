## room_enemy_spawner.gd
## Static enemy placement by room size class for ProceduralLayoutV2 layouts.
class_name RoomEnemySpawner
extends Node

const ENEMY_TYPE := "zombie"
const STATIC_WAVE_ID := 0
const EDGE_PADDING_PX := 24.0
const MIN_ENEMY_SPACING_PX := 100.0
const SAMPLE_ATTEMPTS_PER_ENEMY := 140
const GRID_SEARCH_STEP_PX := 22.0

var enemy_scene: PackedScene = null
var entities_container: Node2D = null
var _rng := RandomNumberGenerator.new()
var _next_enemy_id: int = 1_000_000


func initialize(p_enemy_scene: PackedScene, p_entities_container: Node2D) -> void:
	enemy_scene = p_enemy_scene
	entities_container = p_entities_container


func rebuild_for_layout(layout) -> void:
	clear_spawned()
	if not layout or not layout.valid:
		return
	if not enemy_scene or not entities_container:
		return

	var seed_base := int(layout.layout_seed) if "layout_seed" in layout else int(Time.get_ticks_msec())
	_rng.seed = int(absi(seed_base * 1103515245 + 12345))
	var start_room_id := -1
	if "player_room_id" in layout:
		start_room_id = int(layout.player_room_id)

	for room_id in range(layout.rooms.size()):
		if room_id in layout._void_ids:
			continue
		if room_id == start_room_id:
			continue
		if layout._is_closet_room(room_id):
			continue
		var room := layout.rooms[room_id] as Dictionary
		if bool(room.get("is_corridor", false)):
			continue

		var quota := _quota_for_room(layout, room_id)
		if quota <= 0:
			continue

		var points := _pick_spawn_points(room.get("rects", []) as Array, quota)
		for p_variant in points:
			var spawn_pos := p_variant as Vector2
			_spawn_enemy(spawn_pos, room_id)


func clear_spawned() -> void:
	if not entities_container:
		return
	for child in entities_container.get_children():
		if child and child.is_in_group("room_static_enemy"):
			child.queue_free()


func _quota_for_room(layout, room_id: int) -> int:
	var size_class := str(layout._room_size_class(room_id))
	match size_class:
		"LARGE":
			return 3
		"MEDIUM":
			return 2
		"SMALL":
			return 1
		_:
			return 1


func _pick_spawn_points(room_rects: Array, target_count: int) -> Array:
	var safe_rects := _safe_rects(room_rects)
	if safe_rects.is_empty():
		return []

	var points: Array = []
	for _i in range(target_count):
		var best := Vector2.ZERO
		var best_dist := -1.0
		for _attempt in range(SAMPLE_ATTEMPTS_PER_ENEMY):
			var candidate := _sample_point(safe_rects)
			var nearest := _nearest_distance(candidate, points)
			if nearest > best_dist:
				best_dist = nearest
				best = candidate
		if points.is_empty():
			points.append(best)
			continue
		if best_dist >= MIN_ENEMY_SPACING_PX - 0.5:
			points.append(best)
			continue
		var grid_pick := _best_grid_candidate(safe_rects, points)
		if grid_pick["ok"]:
			points.append(grid_pick["pos"] as Vector2)
	return points


func _safe_rects(room_rects: Array) -> Array:
	var out: Array = []
	for rect_variant in room_rects:
		var r := rect_variant as Rect2
		var safe := r.grow(-EDGE_PADDING_PX)
		if safe.size.x >= 6.0 and safe.size.y >= 6.0:
			out.append(safe)
			continue
		var soft := r.grow(-8.0)
		if soft.size.x >= 6.0 and soft.size.y >= 6.0:
			out.append(soft)
	return out


func _sample_point(rects: Array) -> Vector2:
	if rects.is_empty():
		return Vector2.ZERO
	var total_area := 0.0
	for rect_variant in rects:
		var r := rect_variant as Rect2
		total_area += maxf(r.get_area(), 1.0)
	if total_area <= 0.0:
		var fallback := rects[0] as Rect2
		return fallback.get_center()

	var pick := _rng.randf_range(0.0, total_area)
	var acc := 0.0
	for rect_variant in rects:
		var r := rect_variant as Rect2
		var area := maxf(r.get_area(), 1.0)
		acc += area
		if pick <= acc:
			return Vector2(
				_rng.randf_range(r.position.x, r.end.x),
				_rng.randf_range(r.position.y, r.end.y)
			)
	var tail := rects[rects.size() - 1] as Rect2
	return tail.get_center()


func _nearest_distance(candidate: Vector2, points: Array) -> float:
	if points.is_empty():
		return INF
	var nearest := INF
	for p_variant in points:
		var p := p_variant as Vector2
		nearest = minf(nearest, p.distance_to(candidate))
	return nearest


func _best_grid_candidate(rects: Array, points: Array) -> Dictionary:
	var best := Vector2.ZERO
	var best_dist := -1.0
	for rect_variant in rects:
		var r := rect_variant as Rect2
		if r.size.x < 4.0 or r.size.y < 4.0:
			continue
		var x := r.position.x
		while x <= r.end.x:
			var y := r.position.y
			while y <= r.end.y:
				var candidate := Vector2(x, y)
				var nearest := _nearest_distance(candidate, points)
				if nearest > best_dist:
					best_dist = nearest
					best = candidate
				y += GRID_SEARCH_STEP_PX
			x += GRID_SEARCH_STEP_PX
	if best_dist >= MIN_ENEMY_SPACING_PX - 0.5:
		return {"ok": true, "pos": best}
	return {"ok": false}


func _spawn_enemy(spawn_pos: Vector2, room_id: int) -> void:
	var enemy := enemy_scene.instantiate()
	if not enemy:
		return

	if enemy.has_method("initialize"):
		enemy.initialize(_next_enemy_id, ENEMY_TYPE, STATIC_WAVE_ID)

	if "speed_tiles" in enemy:
		enemy.speed_tiles = float(enemy.speed_tiles)
	if "velocity" in enemy:
		enemy.velocity = Vector2.ZERO
	enemy.set_meta("room_id", room_id)
	enemy.add_to_group("room_static_enemy")
	enemy.position = spawn_pos
	entities_container.add_child(enemy)
	if enemy.has_method("set_physics_process"):
		enemy.set_physics_process(true)

	_next_enemy_id += 1
