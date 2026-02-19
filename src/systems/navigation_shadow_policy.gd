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
	if enemy.has_meta("flashlight_active"):
		return bool(enemy.get_meta("flashlight_active"))
	if enemy.has_method("get_debug_detection_snapshot"):
		var snapshot_variant: Variant = enemy.call("get_debug_detection_snapshot")
		if snapshot_variant is Dictionary:
			var snapshot := snapshot_variant as Dictionary
			return bool(snapshot.get("flashlight_active", false))
	return false


func _enemy_is_currently_inside_shadow(enemy: Node) -> bool:
	var enemy_node := enemy as Node2D
	if enemy_node == null:
		return false
	return is_point_in_shadow(enemy_node.global_position)
