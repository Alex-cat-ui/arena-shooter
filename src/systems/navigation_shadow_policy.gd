## navigation_shadow_policy.gd
## Shadow and traverse policy helpers for NavigationService.
class_name NavigationShadowPolicy
extends RefCounted

var _service: Node = null


func _init(service: Node) -> void:
	_service = service


func can_enemy_traverse_point(enemy: Node, point: Vector2) -> bool:
	if enemy == null:
		return true
	var point_in_shadow := is_point_in_shadow(point)
	if not point_in_shadow:
		return true
	if is_enemy_flashlight_active(enemy):
		return true
	return _enemy_is_currently_inside_shadow(enemy)


func is_point_in_shadow(point: Vector2) -> bool:
	var tree := _service.get_tree()
	if tree == null:
		return false
	for zone_variant in tree.get_nodes_in_group("shadow_zones"):
		var zone := zone_variant as ShadowZone
		if zone == null:
			continue
		if zone.contains_point(point):
			return true
	return false


func is_enemy_flashlight_active(enemy: Node) -> bool:
	if enemy == null:
		return false
	if enemy.has_method("is_flashlight_active_for_navigation"):
		var active_variant: Variant = enemy.call("is_flashlight_active_for_navigation")
		return bool(active_variant)
	return false


func validate_enemy_path_policy(
	enemy: Node,
	from_pos: Vector2,
	path_points: Array,
	sample_step_px: float
) -> Dictionary:
	if path_points.is_empty():
		return {"valid": false, "segment_index": -1}
	if enemy == null:
		return {"valid": true, "segment_index": -1}
	var sample_step := maxf(sample_step_px, 0.001)
	var prev := from_pos
	var segment_index := 0
	for point_variant in path_points:
		var point := point_variant as Vector2
		var segment_len := prev.distance_to(point)
		var steps := maxi(int(ceil(segment_len / sample_step)), 1)
		for step in range(1, steps + 1):
			var t := float(step) / float(steps)
			var sample := prev.lerp(point, t)
			if not can_enemy_traverse_point(enemy, sample):
				return {
					"valid": false,
					"segment_index": segment_index,
					"blocked_point": sample,
				}
		prev = point
		segment_index += 1
	return {"valid": true, "segment_index": -1}


func _enemy_is_currently_inside_shadow(enemy: Node) -> bool:
	var enemy_node := enemy as Node2D
	if enemy_node == null:
		return false
	return is_point_in_shadow(enemy_node.global_position)
