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
const PAUSE_MIN_SEC := 0.30
const PAUSE_MAX_SEC := 1.15
const LOOK_CHANCE := 0.45
const LOOK_MIN_SEC := 0.45
const LOOK_MAX_SEC := 1.25
const LOOK_SWEEP_RAD := 0.62
const LOOK_SWEEP_SPEED := 2.8

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
	_rng.randomize()


func configure(p_nav_system: Node, p_home_room_id: int) -> void:
	nav_system = p_nav_system
	home_room_id = p_home_room_id
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
		_patrol_cfg_float("pause_min_sec", PAUSE_MIN_SEC) * 0.65,
		_patrol_cfg_float("pause_max_sec", PAUSE_MAX_SEC) * 0.75
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
	_route.append(fallback)

	if nav_system and nav_system.has_method("random_point_in_room") and home_room_id >= 0:
		var point_count := _rng.randi_range(
			_patrol_cfg_int("route_points_min", ROUTE_POINTS_MIN),
			_patrol_cfg_int("route_points_max", ROUTE_POINTS_MAX)
		)
		for i in range(point_count):
			var margin := _rng.randf_range(18.0, 34.0)
			_route.append(nav_system.random_point_in_room(home_room_id, margin))

	# Deduplicate near points to avoid jitter loops.
	var compact: Array[Vector2] = []
	for p in _route:
		var keep := true
		for q in compact:
			if p.distance_to(q) < _patrol_cfg_float("route_dedup_min_dist_px", 42.0):
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
