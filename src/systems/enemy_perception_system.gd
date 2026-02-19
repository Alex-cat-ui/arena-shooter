## enemy_perception_system.gd
## Perception helper for enemy LOS/FOV checks and player lookup.
class_name EnemyPerceptionSystem
extends RefCounted

var owner: Node2D = null
var _player_node: Node2D = null
var _navigation_service: Node = null


func _init(p_owner: Node2D) -> void:
	owner = p_owner


func set_navigation_service(nav_service: Node) -> void:
	_navigation_service = nav_service


func has_player() -> bool:
	return _refresh_player_ref()


func get_player_position() -> Vector2:
	if _refresh_player_ref():
		return _player_node.global_position
	return Vector2.ZERO


func get_player_visibility_factor(origin: Vector2, max_distance: float) -> float:
	var snapshot := get_player_visibility_snapshot(origin, max_distance)
	return float(snapshot.get("visibility_factor", 0.0))


func get_player_visibility_snapshot(origin: Vector2, max_distance: float) -> Dictionary:
	return _compute_visibility_snapshot(origin, max_distance)


func can_see_player(origin: Vector2, facing_dir: Vector2, fov_deg: float, max_distance: float, exclude: Array[RID]) -> bool:
	if not _refresh_player_ref():
		return false
	if RuntimeState and RuntimeState.player_hp <= 0:
		return false

	var to_player := _player_node.global_position - origin
	var dist := to_player.length()
	if dist <= 0.001:
		return true
	if dist > max_distance:
		return false

	var dir_to_player := to_player / dist
	var facing := facing_dir.normalized()
	if facing.length_squared() <= 0.0001:
		facing = dir_to_player
	var min_dot := cos(deg_to_rad(fov_deg) * 0.5)
	if facing.dot(dir_to_player) < min_dot:
		return false

	return _has_clear_los_to(origin, _player_node.global_position, exclude)


func ray_hits_player(origin: Vector2, direction: Vector2, max_range: float, exclude: Array[RID]) -> bool:
	if not _refresh_player_ref():
		return false
	if direction.length_squared() <= 0.0001:
		return false

	var query := PhysicsRayQueryParameters2D.create(origin, origin + direction.normalized() * max_range)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = exclude

	var result := owner.get_world_2d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return false
	return _is_player_collider(result.get("collider", null))


func _has_clear_los_to(origin: Vector2, target_pos: Vector2, exclude: Array[RID]) -> bool:
	var query := PhysicsRayQueryParameters2D.create(origin, target_pos)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = exclude

	var result := owner.get_world_2d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return true
	return _is_player_collider(result.get("collider", null))


func _is_player_collider(collider: Variant) -> bool:
	if collider == null:
		return false
	if not _refresh_player_ref():
		return false
	var node := collider as Node
	if not node:
		return false
	if node == _player_node:
		return true
	if node.get_parent() == _player_node:
		return true
	return node.is_in_group("player")


func _refresh_player_ref() -> bool:
	if _player_node and is_instance_valid(_player_node):
		return true
	if not owner:
		_player_node = null
		return false
	var players := owner.get_tree().get_nodes_in_group("player")
	if players.is_empty():
		_player_node = null
		return false
	_player_node = players[0] as Node2D
	return _player_node != null


func _compute_visibility_snapshot(origin: Vector2, max_distance: float) -> Dictionary:
	var out := {
		"distance_to_player": INF,
		"distance_factor": 0.0,
		"shadow_mul": 1.0,
		"visibility_factor": 0.0,
	}
	if not _refresh_player_ref():
		return out
	if RuntimeState and RuntimeState.player_hp <= 0:
		return out
	if max_distance <= 0.001:
		return out

	var to_player := _player_node.global_position - origin
	var distance_to_player := to_player.length()
	var distance_factor := 0.0
	if distance_to_player <= 0.001:
		distance_factor = 1.0
	elif distance_to_player >= max_distance:
		distance_factor = 0.0
	else:
		distance_factor = 1.0 - (distance_to_player / max_distance)

	var shadow_mul := 1.0
	var nav_service := _resolve_navigation_service()
	if nav_service and nav_service.has_method("is_point_in_shadow"):
		var in_shadow_variant: Variant = nav_service.call("is_point_in_shadow", _player_node.global_position)
		shadow_mul = 0.0 if bool(in_shadow_variant) else 1.0
	elif RuntimeState:
		shadow_mul = clampf(float(RuntimeState.player_visibility_mul), 0.0, 1.0)

	out["distance_to_player"] = distance_to_player
	out["distance_factor"] = clampf(distance_factor, 0.0, 1.0)
	out["shadow_mul"] = shadow_mul
	out["visibility_factor"] = clampf(distance_factor * shadow_mul, 0.0, 1.0)
	return out


func _resolve_navigation_service() -> Node:
	if _navigation_service and is_instance_valid(_navigation_service):
		return _navigation_service
	if owner == null:
		return null
	if "nav_system" in owner:
		var nav_variant: Variant = owner.get("nav_system")
		var nav_node := nav_variant as Node
		if nav_node and is_instance_valid(nav_node):
			_navigation_service = nav_node
			return _navigation_service
	return null
