## door_physics_v3.gd
## Deterministic door controller with two animations: open and close.
## Public API stays backward-compatible with existing DoorPhysicsV3 call sites.
class_name DoorPhysicsV3
extends Node2D

const DOOR_COLOR := Color(0.92, 0.18, 0.18, 1.0)
const DOOR_Z_INDEX := 25
const DEFAULT_OPEN_ANGLE_DEG := 90.0
const DEFAULT_OPEN_DURATION_SEC := 0.16
const DEFAULT_CLOSE_DURATION_SEC := 0.16
const DEFAULT_CLOSE_CLEAR_CONFIRM_SEC := 0.45
const HINGE_INSET_PX := 2.0
const LEAF_END_CLEARANCE_PX := 4.0
const SENSOR_PADDING := 20.0
const SENSOR_THICKNESS := 40.0
const BLOCKED_REOPEN_MIN_RATIO := 0.25
const BLOCKED_REOPEN_NUDGE_RATIO := 0.10

enum DoorState {
	CLOSED,
	OPENING,
	HOLD,
	CLOSING,
}

static var _cached_white_tex: ImageTexture = null

var door_length: float = 50.0
var door_thickness: float = 11.0
var is_vertical: bool = false

var _leaf_axis: Vector2 = Vector2.RIGHT
var _closed_rotation: float = 0.0
var _open_sign: float = 1.0
var _open_ratio: float = 0.0
var _angle_offset: float = 0.0
var _angular_velocity: float = 0.0
var _state: DoorState = DoorState.CLOSED
var _pinch_active: bool = false
var close_intent: bool = false
var _prev_angle_offset: float = 0.0
var _anim_tween: Tween = null
var _clear_open_elapsed: float = 0.0

var _opening_rect_world: Rect2 = Rect2()
var _opening_center_world: Vector2 = Vector2.ZERO

var _pivot: Node2D = null
var _door_body: StaticBody2D = null
var _door_collision: CollisionShape2D = null
var _door_shape: RectangleShape2D = null
var _door_visual: Sprite2D = null
var _trigger_area: Area2D = null
var _trigger_collision: CollisionShape2D = null
var _trigger_shape: RectangleShape2D = null


func _ready() -> void:
	_ensure_nodes()
	reset_to_closed()


func _physics_process(delta: float) -> void:
	if delta > 0.0:
		_angular_velocity = (_angle_offset - _prev_angle_offset) / delta
	else:
		_angular_velocity = 0.0
	_prev_angle_offset = _angle_offset

	if close_intent and _state == DoorState.CLOSING:
		if _is_opening_occupied():
			_cancel_animation()
			_state = DoorState.HOLD
			_pinch_active = true
			_clear_open_elapsed = 0.0
			_set_open_ratio(minf(1.0, maxf(_open_ratio, 0.25) + 0.10))
			_set_collision_enabled(false)
		elif _open_ratio <= 0.001:
			_set_open_ratio(0.0)
			_set_collision_enabled(true)
			_state = DoorState.CLOSED
			close_intent = false
			_pinch_active = false
			_clear_open_elapsed = 0.0
		return

	if close_intent and (_state == DoorState.OPENING or _state == DoorState.HOLD):
		if _is_opening_occupied():
			_pinch_active = true
			_state = DoorState.HOLD
			_clear_open_elapsed = 0.0
		else:
			_clear_open_elapsed += delta
			if _clear_open_elapsed >= _close_clear_confirm_sec():
				_play_close_animation()


func configure_from_opening(opening: Rect2, wall_thickness: float) -> void:
	_ensure_nodes()
	_opening_rect_world = opening
	_opening_center_world = opening.get_center()
	is_vertical = opening.size.y > opening.size.x
	var opening_span := maxf(opening.size.x, opening.size.y)
	door_length = maxf(opening_span - LEAF_END_CLEARANCE_PX, 12.0)
	door_thickness = maxf(wall_thickness - 5.0, 4.0)

	if is_vertical:
		position = Vector2(opening.get_center().x, opening.position.y + HINGE_INSET_PX)
		_leaf_axis = Vector2.DOWN
		_closed_rotation = PI * 0.5
	else:
		position = Vector2(opening.position.x + HINGE_INSET_PX, opening.get_center().y)
		_leaf_axis = Vector2.RIGHT
		_closed_rotation = 0.0

	_configure_leaf_geometry()
	_configure_trigger_geometry()
	reset_to_closed()


func reset_to_closed() -> void:
	_cancel_animation()
	_open_sign = 1.0
	_set_open_ratio(0.0)
	_state = DoorState.CLOSED
	close_intent = false
	_pinch_active = false
	_angular_velocity = 0.0
	_clear_open_elapsed = 0.0
	_prev_angle_offset = _angle_offset


func command_open_action(source_pos: Vector2 = Vector2.ZERO) -> void:
	_open_sign = _resolve_open_sign(source_pos)
	if _open_sign == 0.0:
		_open_sign = 1.0
	close_intent = false
	_pinch_active = false
	_clear_open_elapsed = 0.0
	_play_open_animation()


func command_open_enemy(source_pos: Vector2) -> void:
	command_open_action(source_pos)


func command_open_kick(source_pos: Vector2 = Vector2.ZERO) -> void:
	command_open_action(source_pos)


func apply_action_impulse(source_pos: Vector2 = Vector2.ZERO) -> void:
	command_open_action(source_pos)


func apply_kick_impulse(source_pos: Vector2 = Vector2.ZERO) -> void:
	command_open_kick(source_pos)


func command_close() -> void:
	close_intent = true
	_clear_open_elapsed = 0.0
	if _is_opening_occupied():
		_pinch_active = true
		_state = DoorState.HOLD
		return
	_play_close_animation()


func is_closed_or_nearly_closed(threshold_deg: float = 10.0) -> bool:
	return absf(rad_to_deg(_angle_offset)) <= maxf(0.0, threshold_deg)


func get_opening_center_world() -> Vector2:
	if _opening_rect_world != Rect2():
		return _opening_center_world
	return global_position


func get_opening_distance_px(point: Vector2) -> float:
	if _opening_rect_world == Rect2():
		return point.distance_to(global_position)
	var rect := _opening_rect_world
	var nearest_x := clampf(point.x, rect.position.x, rect.end.x)
	var nearest_y := clampf(point.y, rect.position.y, rect.end.y)
	return point.distance_to(Vector2(nearest_x, nearest_y))


func get_debug_metrics() -> Dictionary:
	return {
		"angle_deg": rad_to_deg(_angle_offset),
		"angular_velocity": _angular_velocity,
		"limit_hits": 0,
		"state": int(_state),
		"hold_timer": 0.0,
		"pinch_active": _pinch_active,
		"close_intent": close_intent,
	}


func _play_open_animation() -> void:
	_cancel_animation()
	_state = DoorState.OPENING
	_clear_open_elapsed = 0.0
	_set_collision_enabled(false)
	_anim_tween = create_tween()
	_anim_tween.tween_method(_set_open_ratio, _open_ratio, 1.0, _open_duration_sec())
	_anim_tween.finished.connect(func() -> void:
		if not is_inside_tree():
			return
		_set_open_ratio(1.0)
		_state = DoorState.HOLD
		_pinch_active = false
	)


func _play_close_animation() -> void:
	_cancel_animation()
	_state = DoorState.CLOSING
	_clear_open_elapsed = 0.0
	_anim_tween = create_tween()
	_anim_tween.tween_method(_set_open_ratio, _open_ratio, 0.0, _close_duration_sec())
	_anim_tween.finished.connect(func() -> void:
		if not is_inside_tree():
			return
		if _is_opening_occupied():
			_pinch_active = true
			_state = DoorState.HOLD
			close_intent = true
			_clear_open_elapsed = 0.0
			_set_open_ratio(minf(1.0, maxf(_open_ratio, BLOCKED_REOPEN_MIN_RATIO) + BLOCKED_REOPEN_NUDGE_RATIO))
			_set_collision_enabled(false)
			return
		_set_open_ratio(0.0)
		_set_collision_enabled(true)
		_state = DoorState.CLOSED
		close_intent = false
		_pinch_active = false
		_clear_open_elapsed = 0.0
		)


func _cancel_animation() -> void:
	if _anim_tween and is_instance_valid(_anim_tween):
		_anim_tween.kill()
	_anim_tween = null


func _set_open_ratio(value: float) -> void:
	_open_ratio = clampf(value, 0.0, 1.0)
	_angle_offset = deg_to_rad(_open_angle_deg()) * _open_sign * _open_ratio
	_apply_pose()
	if _open_ratio <= 0.001:
		_set_collision_enabled(true)
	else:
		_set_collision_enabled(false)


func _is_opening_occupied() -> bool:
	if _trigger_area == null or not _trigger_area.monitoring:
		return false
	for body_variant in _trigger_area.get_overlapping_bodies():
		var body := body_variant as Node
		if body == null:
			continue
		if body == _door_body:
			continue
		if body.is_in_group("player") or body.is_in_group("enemies"):
			return true
		if body is CharacterBody2D or body is RigidBody2D:
			return true
	return false


func _resolve_open_sign(source_pos: Vector2) -> float:
	if source_pos == Vector2.ZERO:
		if absf(_angle_offset) > 0.001:
			return signf(_angle_offset)
		return 1.0
	var leaf_normal := _leaf_axis.rotated(_angle_offset).orthogonal().normalized()
	var side := leaf_normal.dot(source_pos - global_position)
	var sign := signf(side)
	if sign != 0.0:
		return sign
	if absf(_angle_offset) > 0.001:
		return signf(_angle_offset)
	return 1.0


func _ensure_nodes() -> void:
	if _pivot:
		return

	_pivot = Node2D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)

	_door_body = StaticBody2D.new()
	_door_body.name = "DoorBody"
	_door_body.collision_layer = 1
	_door_body.collision_mask = 1
	add_child(_door_body)

	_door_collision = CollisionShape2D.new()
	_door_collision.name = "DoorCollision"
	_door_shape = RectangleShape2D.new()
	_door_collision.shape = _door_shape
	_door_body.add_child(_door_collision)

	_door_visual = Sprite2D.new()
	_door_visual.name = "DoorVisual"
	_door_visual.texture = _white_pixel()
	_door_visual.modulate = DOOR_COLOR
	_door_visual.z_as_relative = false
	_door_visual.z_index = DOOR_Z_INDEX
	add_child(_door_visual)

	_trigger_area = Area2D.new()
	_trigger_area.name = "TriggerArea"
	_trigger_area.collision_layer = 0
	_trigger_area.collision_mask = 3
	_trigger_area.monitoring = true
	_trigger_area.monitorable = false
	add_child(_trigger_area)

	_trigger_collision = CollisionShape2D.new()
	_trigger_collision.name = "TriggerCollision"
	_trigger_shape = RectangleShape2D.new()
	_trigger_collision.shape = _trigger_shape
	_trigger_area.add_child(_trigger_collision)

	_configure_leaf_geometry()
	_configure_trigger_geometry()


func _configure_leaf_geometry() -> void:
	if not _door_shape or not _door_collision or not _door_visual:
		return
	var visual_size := Vector2(door_length, door_thickness)
	_door_shape.size = visual_size
	var center := Vector2(door_length * 0.5, 0.0)
	_door_collision.position = center
	_door_visual.position = center
	_door_visual.scale = visual_size


func _configure_trigger_geometry() -> void:
	if not _trigger_shape or not _trigger_collision:
		return
	var size := Vector2(door_length + SENSOR_PADDING, SENSOR_THICKNESS)
	if is_vertical:
		size = Vector2(SENSOR_THICKNESS, door_length + SENSOR_PADDING)
	_trigger_shape.size = size
	_trigger_collision.position = _leaf_axis.normalized() * (door_length * 0.5)


func _set_collision_enabled(enabled: bool) -> void:
	if _door_collision:
		_door_collision.set_deferred("disabled", not enabled)


func _apply_pose() -> void:
	var target_rotation := _closed_rotation + _angle_offset
	if _pivot:
		_pivot.rotation = target_rotation
	if _door_body:
		_door_body.position = Vector2.ZERO
		_door_body.rotation = target_rotation
		_door_body.force_update_transform()
	if _door_visual:
		var center := Vector2(door_length * 0.5, 0.0)
		_door_visual.position = center.rotated(target_rotation)
		_door_visual.rotation = target_rotation


func _white_pixel() -> ImageTexture:
	if _cached_white_tex and is_instance_valid(_cached_white_tex):
		return _cached_white_tex
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.WHITE)
	_cached_white_tex = ImageTexture.create_from_image(img)
	return _cached_white_tex


func _open_angle_deg() -> float:
	if GameConfig and ("door_open_angle_deg" in GameConfig):
		var value := float(GameConfig.door_open_angle_deg)
		return clampf(value, 1.0, 179.0)
	return DEFAULT_OPEN_ANGLE_DEG


func _open_duration_sec() -> float:
	if GameConfig and ("door_open_duration_sec" in GameConfig):
		var value := float(GameConfig.door_open_duration_sec)
		return maxf(value, 0.01)
	return DEFAULT_OPEN_DURATION_SEC


func _close_duration_sec() -> float:
	if GameConfig and ("door_close_duration_sec" in GameConfig):
		var value := float(GameConfig.door_close_duration_sec)
		return maxf(value, 0.01)
	return DEFAULT_CLOSE_DURATION_SEC


func _close_clear_confirm_sec() -> float:
	if GameConfig and ("door_close_clear_confirm_sec" in GameConfig):
		var value := float(GameConfig.door_close_clear_confirm_sec)
		return maxf(value, 0.0)
	return DEFAULT_CLOSE_CLEAR_CONFIRM_SEC
