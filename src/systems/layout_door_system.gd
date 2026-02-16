## layout_door_system.gd
## Builds physical doors for ProceduralLayoutV2 openings.
class_name LayoutDoorSystem
extends Node

const DOOR_PHYSICS_V3_SCRIPT := preload("res://src/systems/door_physics_v3.gd")
const DEFAULT_INTERACT_RADIUS_PX := 20.0
const DEFAULT_KICK_RADIUS_PX := 40.0
const INTERACT_OPEN_THRESHOLD_DEG := 10.0

var doors_parent: Node2D = null

func initialize(p_doors_parent: Node2D) -> void:
	doors_parent = p_doors_parent


func find_nearest_door(source_pos: Vector2, max_distance_px: float = INF):
	if not doors_parent:
		return null
	if max_distance_px < 0.0:
		return null

	var best_dist_sq = INF
	if is_finite(max_distance_px):
		best_dist_sq = max_distance_px * max_distance_px

	var nearest = null
	for child_variant in doors_parent.get_children():
		var door = child_variant as Node2D
		if not door:
			continue
		var dist_sq = _door_distance_sq_to_source(door, source_pos)
		if dist_sq <= best_dist_sq:
			best_dist_sq = dist_sq
			nearest = door
	return nearest


func interact_toggle(source_pos: Vector2, max_distance_px: float = DEFAULT_INTERACT_RADIUS_PX) -> bool:
	var door = find_nearest_door(source_pos, max_distance_px)
	if not door:
		return false
	if _should_open_on_interact(door):
		door.command_open_action(source_pos)
	else:
		door.command_close()
	return true


func kick(source_pos: Vector2, max_distance_px: float = DEFAULT_KICK_RADIUS_PX) -> bool:
	var door = find_nearest_door(source_pos, max_distance_px)
	if not door:
		return false
	door.command_open_kick(source_pos)
	return true


func rebuild_for_layout(layout) -> void:
	clear_doors()
	if not doors_parent:
		return
	if not layout or not bool(layout.valid):
		return

	var wall_thickness = 16.0
	if layout and layout.has_method("_door_wall_thickness"):
		wall_thickness = float(layout._door_wall_thickness())

	for door_variant in (layout.doors as Array):
		var opening = door_variant as Rect2
		_spawn_door(opening, wall_thickness)

	if "_entry_gate" in layout:
		var gate = layout._entry_gate as Rect2
		if gate != Rect2():
			_spawn_door(gate, wall_thickness)


func clear_doors() -> void:
	if not doors_parent:
		return
	for child in doors_parent.get_children():
		doors_parent.remove_child(child)
		child.queue_free()


func _spawn_door(opening: Rect2, wall_thickness: float) -> void:
	if opening.size.x <= 1.0 or opening.size.y <= 1.0:
		return
	var door: Node2D = DOOR_PHYSICS_V3_SCRIPT.new()
	door.name = "PhysicalDoor_%d" % doors_parent.get_child_count()
	doors_parent.add_child(door)
	door.configure_from_opening(opening, wall_thickness)
	door.reset_to_closed()


func _should_open_on_interact(door) -> bool:
	if not door:
		return false
	if door.has_method("is_closed_or_nearly_closed"):
		return bool(door.is_closed_or_nearly_closed(INTERACT_OPEN_THRESHOLD_DEG))
	if not door.has_method("get_debug_metrics"):
		return true
	var metrics = door.get_debug_metrics() as Dictionary
	var angle_deg = absf(float(metrics.get("angle_deg", 0.0)))
	return angle_deg <= INTERACT_OPEN_THRESHOLD_DEG


func _door_distance_sq_to_source(door: Node2D, source_pos: Vector2) -> float:
	if door and door.has_method("get_opening_distance_px"):
		var opening_distance = float(door.call("get_opening_distance_px", source_pos))
		return opening_distance * opening_distance
	return door.global_position.distance_squared_to(source_pos)
