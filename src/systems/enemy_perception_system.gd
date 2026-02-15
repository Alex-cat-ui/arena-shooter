## enemy_perception_system.gd
## Perception helper for enemy LOS/FOV checks and player lookup.
class_name EnemyPerceptionSystem
extends RefCounted

var owner: Node2D = null
var _player_node: Node2D = null


func _init(p_owner: Node2D) -> void:
	owner = p_owner


func has_player() -> bool:
	return _refresh_player_ref()


func get_player_position() -> Vector2:
	if _refresh_player_ref():
		return _player_node.global_position
	return Vector2.ZERO


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
