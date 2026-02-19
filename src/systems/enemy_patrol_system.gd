## enemy_patrol_system.gd
## Lightweight patrol module for more organic enemy idle behavior.
class_name EnemyPatrolSystem
extends RefCounted

enum PatrolState {
	MOVE,
	PAUSE,
	LOOK,
}

const POINT_REACHED_PX := 14.0
const PATROL_SPEED_SCALE := 0.82
const ROUTE_POINTS_MIN := 3
const ROUTE_POINTS_MAX := 6
const ROUTE_REBUILD_MIN_SEC := 7.0
const ROUTE_REBUILD_MAX_SEC := 12.0
const PAUSE_MIN_SEC := 0.25
const PAUSE_MAX_SEC := 0.90
const LOOK_CHANCE := 0.45
const LOOK_MIN_SEC := 0.35
const LOOK_MAX_SEC := 0.85
const LOOK_SWEEP_RAD := 0.62
const LOOK_SWEEP_SPEED := 2.6

var owner: CharacterBody2D = null
var nav_system: Node = null
var home_room_id: int = -1

var _state: PatrolState = PatrolState.MOVE
var _route: Array[Vector2] = []
var _route_index: int = 0
var _state_timer: float = 0.0
var _route_rebuild_timer: float = 0.0
var _look_phase: float = 0.0
var _look_base_dir: Vector2 = Vector2.RIGHT
var _rng := RandomNumberGenerator.new()


func _init(p_owner: CharacterBody2D) -> void:
	owner = p_owner
	_rng.seed = 1


func configure(p_nav_system: Node, p_home_room_id: int) -> void:
	nav_system = p_nav_system
	home_room_id = p_home_room_id
	_rng.seed = _resolve_deterministic_seed()
	_state = PatrolState.MOVE
	_state_timer = 0.0
	_route_rebuild_timer = _rng.randf_range(
		_patrol_cfg_float("route_rebuild_min_sec", ROUTE_REBUILD_MIN_SEC),
		_patrol_cfg_float("route_rebuild_max_sec", ROUTE_REBUILD_MAX_SEC)
	)
	_look_phase = 0.0
	_look_base_dir = Vector2.RIGHT
	_rebuild_route()


func notify_alert() -> void:
	_state = PatrolState.MOVE
	_state_timer = 0.0


func notify_calm() -> void:
	if _route.is_empty():
		_rebuild_route()
	_state = PatrolState.PAUSE
	_state_timer = _rng.randf_range(
		_patrol_cfg_float("pause_min_sec", PAUSE_MIN_SEC),
		_patrol_cfg_float("pause_max_sec", PAUSE_MAX_SEC)
	)


func update(delta: float, facing_dir: Vector2) -> Dictionary:
	if not owner:
		return {"waiting": true}
	_route_rebuild_timer -= delta
	if _route_rebuild_timer <= 0.0:
		_route_rebuild_timer = _rng.randf_range(
			_patrol_cfg_float("route_rebuild_min_sec", ROUTE_REBUILD_MIN_SEC),
			_patrol_cfg_float("route_rebuild_max_sec", ROUTE_REBUILD_MAX_SEC)
		)
		_rebuild_route()

	if _route.is_empty():
		return {"waiting": true}

	match _state:
		PatrolState.PAUSE:
			_state_timer -= delta
			if _state_timer <= 0.0:
				if _rng.randf() < _patrol_cfg_float("look_chance", LOOK_CHANCE):
					_state = PatrolState.LOOK
					_state_timer = _rng.randf_range(
						_patrol_cfg_float("look_min_sec", LOOK_MIN_SEC),
						_patrol_cfg_float("look_max_sec", LOOK_MAX_SEC)
					)
					_look_phase = 0.0
					_look_base_dir = facing_dir.normalized() if facing_dir.length_squared() > 0.0001 else Vector2.RIGHT
				else:
					_state = PatrolState.MOVE
			return {"waiting": true}
		PatrolState.LOOK:
			_state_timer -= delta
			_look_phase += delta * _patrol_cfg_float("look_sweep_speed", LOOK_SWEEP_SPEED)
			var angle := sin(_look_phase) * _patrol_cfg_float("look_sweep_rad", LOOK_SWEEP_RAD)
			var look_dir := _look_base_dir.rotated(angle)
			if _state_timer <= 0.0:
				_state = PatrolState.MOVE
			return {"waiting": true, "look_dir": look_dir}
		_:
			pass

	var target := _route[_route_index] as Vector2
	if owner.global_position.distance_to(target) <= _patrol_cfg_float("point_reached_px", POINT_REACHED_PX):
		_route_index = (_route_index + 1) % _route.size()
		_state = PatrolState.PAUSE
		_state_timer = _rng.randf_range(
			_patrol_cfg_float("pause_min_sec", PAUSE_MIN_SEC),
			_patrol_cfg_float("pause_max_sec", PAUSE_MAX_SEC)
		)
		return {"waiting": true}

	return {
		"waiting": false,
		"target": target,
		"speed_scale": _patrol_cfg_float("speed_scale", PATROL_SPEED_SCALE),
	}


func _rebuild_route() -> void:
	_route.clear()
	_route_index = 0
	if not owner:
		return

	var fallback := owner.global_position
	var candidates: Array[Vector2] = []

	if nav_system and home_room_id >= 0:
		# --- typed point: center ---
		var center := Vector2.ZERO
		if nav_system.has_method("get_room_center"):
			center = nav_system.get_room_center(home_room_id) as Vector2
		candidates.append(center if center != Vector2.ZERO else fallback)

		# --- typed points: corner-inset (pick 1-2 from 4 inset corners) ---
		var room_rect := Rect2()
		if nav_system.has_method("get_room_rect"):
			room_rect = nav_system.get_room_rect(home_room_id) as Rect2
		if room_rect.size.x > 0.0 and room_rect.size.y > 0.0:
			var ci := _patrol_cfg_float("corner_inset_px", 48.0)
			var all_corners: Array[Vector2] = [
				room_rect.position + Vector2(ci, ci),
				room_rect.position + Vector2(room_rect.size.x - ci, ci),
				room_rect.position + Vector2(ci, room_rect.size.y - ci),
				room_rect.end - Vector2(ci, ci),
			]
			# Deterministic pick of 1-2 corners via seeded RNG.
			var corner_count := _rng.randi_range(1, 2)
			var picked: Array[int] = []
			while picked.size() < corner_count:
				var idx := _rng.randi_range(0, 3)
				if idx not in picked:
					picked.append(idx)
					candidates.append(all_corners[idx])

		# --- typed points: door-adjacent (0-1 per neighbor, up to 2 neighbors) ---
		if nav_system.has_method("get_neighbors") and nav_system.has_method("get_door_center_between"):
			var neighbors := nav_system.get_neighbors(home_room_id) as Array
			var max_door_pts := mini(2, neighbors.size())
			for j in range(max_door_pts):
				if _rng.randf() < 0.6:
					var nb_id := int(neighbors[j])
					var door_pos := nav_system.get_door_center_between(home_room_id, nb_id, center) as Vector2
					if door_pos != Vector2.ZERO and door_pos.distance_to(center) > 24.0:
						var to_center := (center - door_pos).normalized()
						var di := _patrol_cfg_float("door_inset_px", 32.0)
						candidates.append(door_pos + to_center * di)

		# --- typed point: mid-wall (0-1, midpoint of a random rect edge, inset inward) ---
		if room_rect.size.x > 0.0 and _rng.randf() < 0.5:
			var half := room_rect.size * 0.5
			var wi := _patrol_cfg_float("wall_inset_px", 36.0)
			var mid_walls: Array[Vector2] = [
				room_rect.position + Vector2(half.x, wi),
				room_rect.position + Vector2(half.x, room_rect.size.y - wi),
				room_rect.position + Vector2(wi, half.y),
				room_rect.position + Vector2(room_rect.size.x - wi, half.y),
			]
			candidates.append(mid_walls[_rng.randi_range(0, 3)])

		# --- fill remaining slots with random-in-room to reach route_points_min ---
		var min_pts := _patrol_cfg_int("route_points_min", ROUTE_POINTS_MIN)
		if nav_system.has_method("random_point_in_room"):
			while candidates.size() < min_pts:
				var margin := _rng.randf_range(18.0, 34.0)
				candidates.append(nav_system.random_point_in_room(home_room_id, margin))
	else:
		candidates.append(fallback)

	# Deduplicate near points to avoid jitter loops.
	var dedup_dist := _patrol_cfg_float("route_dedup_min_dist_px", 42.0)
	var compact: Array[Vector2] = []
	for p in candidates:
		var keep := true
		for q in compact:
			if p.distance_to(q) < dedup_dist:
				keep = false
				break
		if keep:
			compact.append(p)
	_route = compact
	if _route.size() < 2:
		_route = [fallback, fallback + Vector2(_patrol_cfg_float("fallback_step_px", 24.0), 0.0)]


func _patrol_cfg_float(key: String, fallback: float) -> float:
	if GameConfig and GameConfig.ai_balance.has("patrol"):
		var section := GameConfig.ai_balance["patrol"] as Dictionary
		return float(section.get(key, fallback))
	return fallback


func _patrol_cfg_int(key: String, fallback: int) -> int:
	if GameConfig and GameConfig.ai_balance.has("patrol"):
		var section := GameConfig.ai_balance["patrol"] as Dictionary
		return int(section.get(key, fallback))
	return fallback


func _resolve_deterministic_seed() -> int:
	var owner_id := 0
	if owner and "entity_id" in owner:
		owner_id = int(owner.entity_id)
	var base := owner_id
	if base <= 0 and owner:
		base = int(round(owner.global_position.x * 31.0 + owner.global_position.y * 17.0))
	base = abs(base)
	return int(abs(base * 1103515245 + home_room_id * 12345 + 2654435761))
