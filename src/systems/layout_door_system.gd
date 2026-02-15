## layout_door_system.gd
## Builds physical doors for ProceduralLayoutV2 openings.
class_name LayoutDoorSystem
extends Node

const DOOR_PHYSICS_V3_SCRIPT := preload("res://src/systems/door_physics_v3.gd")
const SHOTGUN_WEAPON := "shotgun"

var doors_parent: Node2D = null


func _ready() -> void:
	if EventBus:
		if not EventBus.player_shot.is_connected(_on_player_shot):
			EventBus.player_shot.connect(_on_player_shot)
		if not EventBus.enemy_shot.is_connected(_on_enemy_shot):
			EventBus.enemy_shot.connect(_on_enemy_shot)


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


func _on_player_shot(weapon_type: String, position: Vector3, _direction: Vector3) -> void:
	if weapon_type != SHOTGUN_WEAPON:
		return
	_apply_shot_reaction(Vector2(position.x, position.y))


func _on_enemy_shot(_enemy_id: int, weapon_type: String, position: Vector3, _direction: Vector3) -> void:
	if weapon_type != SHOTGUN_WEAPON:
		return
	_apply_shot_reaction(Vector2(position.x, position.y))


func _apply_shot_reaction(shot_pos: Vector2) -> void:
	if not doors_parent:
		return
	for child in doors_parent.get_children():
		if child and child.has_method("apply_shot_impulse"):
			child.apply_shot_impulse(shot_pos, 1.0)
