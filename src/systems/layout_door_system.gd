## layout_door_system.gd
## Builds physical doors for ProceduralLayoutV2 openings.
class_name LayoutDoorSystem
extends Node

const DOOR_PHYSICS_V3_SCRIPT := preload("res://src/systems/door_physics_v3.gd")

var doors_parent: Node2D = null

func initialize(p_doors_parent: Node2D) -> void:
	doors_parent = p_doors_parent


func rebuild_for_layout(layout) -> void:
	clear_doors()
	if not doors_parent:
		return
	if not layout or not bool(layout.valid):
		return

	var wall_thickness := 16.0
	if layout and layout.has_method("_door_wall_thickness"):
		wall_thickness = float(layout._door_wall_thickness())

	for door_variant in (layout.doors as Array):
		var opening := door_variant as Rect2
		_spawn_door(opening, wall_thickness)

	if "_entry_gate" in layout:
		var gate := layout._entry_gate as Rect2
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
