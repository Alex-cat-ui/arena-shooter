## CANON: Must accept/return Vector3 in public API.
## CANON: Physics may use Vector2 internally but must convert.
class_name PhysicsWorld
extends Node

var _space_rid: RID


func initialize(space: RID) -> void:
	_space_rid = space


func raycast(origin: Vector3, direction: Vector3, distance: float, collision_mask: int = 0xFFFFFFFF) -> Dictionary:
	if distance <= 0.0:
		return {}
	var ray_dir := _to_vec2(direction)
	if ray_dir.length_squared() <= 0.0:
		return {}
	var space_state := _get_space_state()
	if space_state == null:
		return {}
	var start := _to_vec2(origin)
	var end := start + ray_dir.normalized() * distance
	var query := PhysicsRayQueryParameters2D.create(start, end)
	query.collision_mask = collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = true
	return _normalize_2d_hit(space_state.intersect_ray(query))


func overlap_circle(center: Vector3, radius: float, collision_mask: int = 0xFFFFFFFF) -> Array[Dictionary]:
	if radius <= 0.0:
		return []
	var space_state := _get_space_state()
	if space_state == null:
		return []
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	query.shape = circle
	query.transform = Transform2D(0.0, _to_vec2(center))
	query.collision_mask = collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = true
	var raw_results := space_state.intersect_shape(query, 64)
	var results: Array[Dictionary] = []
	for raw_variant in raw_results:
		var raw := raw_variant as Dictionary
		results.append(_normalize_2d_hit(raw))
	return results


func move_and_collide(body_rid: RID, motion: Vector3) -> Dictionary:
	var motion_2d := _to_vec2(motion)
	var start_variant: Variant = _body_position(body_rid)
	if not (start_variant is Vector2):
		return {
			"position": Vector3.ZERO,
			"collided": false,
			"collision_normal": Vector3.ZERO,
		}
	var start := start_variant as Vector2
	var target := start + motion_2d
	var hit := _segment_hit(start, target, body_rid)
	if hit.is_empty():
		return {
			"position": _to_vec3(target),
			"collided": false,
			"collision_normal": Vector3.ZERO,
		}
	var hit_position := target
	var hit_normal := Vector2.ZERO
	var hit_position_variant: Variant = hit.get("position", target)
	if hit_position_variant is Vector2:
		hit_position = hit_position_variant
	var hit_normal_variant: Variant = hit.get("normal", Vector2.ZERO)
	if hit_normal_variant is Vector2:
		hit_normal = hit_normal_variant
	return {
		"position": _to_vec3(hit_position),
		"collided": true,
		"collision_normal": _to_vec3(hit_normal),
	}


func _segment_hit(from: Vector2, to: Vector2, body_rid: RID) -> Dictionary:
	if from == to:
		return {}
	var space_state := _get_space_state()
	if space_state == null:
		return {}
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	if body_rid.is_valid():
		query.exclude = [body_rid]
	return space_state.intersect_ray(query)


func _body_position(body_rid: RID) -> Variant:
	if not body_rid.is_valid():
		return null
	var transform_variant: Variant = PhysicsServer2D.body_get_state(body_rid, PhysicsServer2D.BODY_STATE_TRANSFORM)
	if transform_variant is Transform2D:
		return (transform_variant as Transform2D).origin
	return null


func _get_space_state() -> PhysicsDirectSpaceState2D:
	var space := _resolved_space_rid()
	if not space.is_valid():
		return null
	return PhysicsServer2D.space_get_direct_state(space)


func _resolved_space_rid() -> RID:
	if _space_rid.is_valid():
		return _space_rid
	var viewport := get_viewport()
	if viewport == null:
		return RID()
	var world := viewport.get_world_2d()
	if world == null:
		return RID()
	return world.space


func _normalize_2d_hit(hit_2d: Dictionary) -> Dictionary:
	if hit_2d.is_empty():
		return {}
	var normalized := hit_2d.duplicate()
	if normalized.has("position"):
		var position_value: Variant = normalized.get("position")
		if position_value is Vector2:
			normalized["position"] = _to_vec3(position_value)
	if normalized.has("normal"):
		var normal_value: Variant = normalized.get("normal")
		if normal_value is Vector2:
			normalized["normal"] = _to_vec3(normal_value)
	if normalized.has("point"):
		var point_value: Variant = normalized.get("point")
		if point_value is Vector2:
			normalized["point"] = _to_vec3(point_value)
	return normalized

func _to_vec2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.y)


func _to_vec3(v: Vector2) -> Vector3:
	return Vector3(v.x, v.y, 0)
