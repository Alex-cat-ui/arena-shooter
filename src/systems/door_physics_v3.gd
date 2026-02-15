## door_physics_v3.gd
## Stable swing-door controller with command-driven opening,
## deterministic safer close, and anti-pinch logic.
class_name DoorPhysicsV3
extends Node2D

const DOOR_COLOR := Color(0.92, 0.18, 0.18, 1.0)
const DOOR_Z_INDEX := 25

# --- Command open impulses ---
const TORQUE_CLAMP := 48.0
const COMMAND_ACTION_IMPULSE := 9.0
const COMMAND_KICK_IMPULSE := 13.0
const OPEN_BREAK_ANGLE_RAD := deg_to_rad(6.0)
const OPEN_BREAK_SPEED_RAD := 1.0
const OPEN_BREAK_BOOST := 5.0

# --- Geometry ---
const MAX_SWING_ANGLE_RAD := deg_to_rad(170.0)
const SWING_STEP_RAD := deg_to_rad(2.0)
const TIP_CLEARANCE_PX := 4.0
const COLLISION_EXTRA_THICKNESS_PX := 0.0
const HINGE_INSET_PX := 2.0
const LEAF_END_CLEARANCE_PX := 4.0

# --- Snap / hold ---
const SNAP_TO_ZERO_RAD := deg_to_rad(1.2)
const SNAP_VEL_RAD := 0.08
const HOLD_AFTER_ACTION_SEC := 0.10
const HOLD_AFTER_KICK_SEC := 0.18

# --- Sensor ---
const SENSOR_PADDING := 20.0
const SENSOR_THICKNESS := 40.0

# --- Anti-pinch ---
const PINCH_REOPEN_TORQUE := 6.0
const PINCH_CHECK_DISTANCE_PX := 6.0

# --- Debug ---
const DEBUG_HINGE_RADIUS := 4.0
const DEBUG_LIMIT_COLOR := Color(0.2, 0.8, 0.2, 0.4)
const DEBUG_LEAF_COLOR := Color(1.0, 0.3, 0.3, 0.8)
const DEBUG_HINGE_COLOR := Color(1.0, 1.0, 0.0, 0.9)

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
var _angle_offset: float = 0.0
var _angular_velocity: float = 0.0
var _max_open_positive: float = deg_to_rad(90.0)
var _max_open_negative: float = deg_to_rad(90.0)
var _hold_open_timer: float = 0.0
var _state: DoorState = DoorState.CLOSED
var _rng := RandomNumberGenerator.new()
var _pinch_active: bool = false
var close_intent: bool = false
var _queued_open_impulse: float = 0.0
var _queued_open_sign: float = 0.0

var _debug_limit_hits: int = 0

var _pivot: Node2D = null
var _door_body: StaticBody2D = null
var _door_collision: CollisionShape2D = null
var _door_shape: RectangleShape2D = null
var _door_visual: Sprite2D = null
var _trigger_area: Area2D = null
var _trigger_collision: CollisionShape2D = null
var _trigger_shape: RectangleShape2D = null


# --- Config helpers (read from GameConfig singleton if available) ---

func _cfg_stiffness_idle() -> float:
	if GameConfig: return GameConfig.door_close_stiffness_idle
	return 5.5

func _cfg_stiffness_pushed() -> float:
	if GameConfig: return GameConfig.door_close_stiffness_pushed
	return 0.9

func _cfg_damping() -> float:
	if GameConfig: return GameConfig.door_angular_damping
	return 3.2

func _cfg_dry_friction() -> float:
	if GameConfig: return GameConfig.door_dry_friction
	return 1.8

func _cfg_max_angular_speed() -> float:
	if GameConfig: return GameConfig.door_max_angular_speed
	return 18.0

func _cfg_limit_bounce() -> float:
	if GameConfig: return GameConfig.door_limit_bounce
	return 0.25

func _cfg_debug_draw() -> bool:
	if GameConfig: return GameConfig.door_debug_draw
	return false


func _ready() -> void:
	_rng.randomize()
	_ensure_nodes()
	reset_to_closed()
	call_deferred("_refresh_swing_limits")


func configure_from_opening(opening: Rect2, wall_thickness: float) -> void:
	_ensure_nodes()
	_rng.randomize()
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

	reset_to_closed()
	_configure_leaf_geometry()
	_configure_trigger_geometry()
	call_deferred("_refresh_swing_limits")


func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return

	_hold_open_timer = maxf(0.0, _hold_open_timer - delta)

	# --- Anti-pinch: detect body in doorway and resist motion toward body ---
	var bodies_in_doorway := _get_bodies_in_leaf_path()
	_pinch_active = false

	var command_torque := _consume_queued_open_torque()
	var command_active := absf(command_torque) > 0.0001
	var max_angular := _cfg_max_angular_speed()

	if command_active:
		_hold_open_timer = maxf(_hold_open_timer, HOLD_AFTER_ACTION_SEC)
		_state = DoorState.OPENING

	if not close_intent and not command_active and _hold_open_timer <= 0.0 and absf(_angle_offset) > SNAP_TO_ZERO_RAD:
		close_intent = true

	var should_close := close_intent and not command_active and _hold_open_timer <= 0.0

	var stiffness := _cfg_stiffness_idle()
	if command_active or _hold_open_timer > 0.0:
		stiffness = _cfg_stiffness_pushed()
		if not command_active:
			_state = DoorState.HOLD
	elif should_close:
		_state = DoorState.CLOSING if absf(_angle_offset) > SNAP_TO_ZERO_RAD else DoorState.CLOSED
	else:
		stiffness = _cfg_stiffness_pushed()
		_state = DoorState.CLOSED if absf(_angle_offset) <= SNAP_TO_ZERO_RAD else DoorState.HOLD

	var leaf_normal := _leaf_axis.rotated(_angle_offset).normalized().orthogonal()
	var pinch_sweeping_toward := _is_sweeping_toward_bodies(bodies_in_doorway, leaf_normal)
	var pinch_blocking := not bodies_in_doorway.is_empty() and (should_close or pinch_sweeping_toward)
	_pinch_active = pinch_blocking

	# Anti-pinch: heavily reduce closer + softly bleed speed if leaf is moving into body
	if pinch_blocking:
		stiffness *= 0.15
		var reopen_sign := _pinch_reopen_sign(bodies_in_doorway, leaf_normal)
		if reopen_sign != 0.0:
			command_torque += reopen_sign * PINCH_REOPEN_TORQUE * 0.75
		if pinch_sweeping_toward and absf(_angular_velocity) > 0.0001:
			_angular_velocity *= 0.82

	if command_active and absf(_angle_offset) < OPEN_BREAK_ANGLE_RAD and absf(_angular_velocity) < OPEN_BREAK_SPEED_RAD:
		_angular_velocity += signf(command_torque) * OPEN_BREAK_BOOST * delta

	var damping_val := _cfg_damping()
	if absf(_angle_offset) < deg_to_rad(15.0) and not command_active:
		damping_val *= 2.0
	var friction_val := _cfg_dry_friction()
	var spring := -_angle_offset * stiffness
	var damping := -_angular_velocity * damping_val
	var dry_friction := 0.0
	if absf(_angular_velocity) > 0.0001:
		dry_friction = -signf(_angular_velocity) * friction_val
	elif not command_active and absf(_angle_offset) > 0.0001:
		dry_friction = -signf(_angle_offset) * friction_val * 0.45

	var total_torque := spring + damping + dry_friction + command_torque
	total_torque = clampf(total_torque, -TORQUE_CLAMP, TORQUE_CLAMP)

	_angular_velocity += total_torque * delta
	_angular_velocity = clampf(_angular_velocity, -max_angular, max_angular)

	_angle_offset += _angular_velocity * delta
	_enforce_open_limits()

	if should_close and absf(_angle_offset) <= SNAP_TO_ZERO_RAD and absf(_angular_velocity) <= SNAP_VEL_RAD:
		_angle_offset = 0.0
		_angular_velocity = 0.0
		close_intent = false
		_state = DoorState.CLOSED
	elif should_close and not pinch_blocking and absf(_angle_offset) <= deg_to_rad(2.2) and absf(_angular_velocity) <= 0.15:
		# Finalize close cleanly when the doorway is free and we are already near closed.
		_angle_offset = 0.0
		_angular_velocity = 0.0
		close_intent = false
		_state = DoorState.CLOSED

	if not command_active and absf(_angular_velocity) < _cfg_dry_friction() * 0.05 and absf(_angle_offset) < deg_to_rad(1.8):
		_angular_velocity = 0.0

	_apply_pose()

	# --- Debug draw ---
	if _cfg_debug_draw():
		queue_redraw()


func reset_to_closed() -> void:
	_angle_offset = 0.0
	_angular_velocity = 0.0
	_hold_open_timer = 0.0
	_state = DoorState.CLOSED
	_pinch_active = false
	close_intent = false
	_queued_open_impulse = 0.0
	_queued_open_sign = 0.0
	_debug_limit_hits = 0
	_apply_pose()


func command_open_action(source_pos: Vector2 = Vector2.ZERO) -> void:
	_queue_open_impulse(source_pos, COMMAND_ACTION_IMPULSE, HOLD_AFTER_ACTION_SEC)


func command_open_kick(source_pos: Vector2 = Vector2.ZERO) -> void:
	_queue_open_impulse(source_pos, COMMAND_KICK_IMPULSE, HOLD_AFTER_KICK_SEC)


func apply_action_impulse(source_pos: Vector2 = Vector2.ZERO) -> void:
	command_open_action(source_pos)


func apply_kick_impulse(source_pos: Vector2 = Vector2.ZERO) -> void:
	command_open_kick(source_pos)


func command_close() -> void:
	close_intent = true
	_hold_open_timer = 0.0


func _queue_open_impulse(source_pos: Vector2, impulse: float, hold_sec: float) -> void:
	var open_sign := _resolve_open_sign(source_pos)
	if open_sign == 0.0:
		open_sign = 1.0
	_queued_open_sign = open_sign
	_queued_open_impulse = maxf(_queued_open_impulse, impulse)
	_hold_open_timer = maxf(_hold_open_timer, hold_sec)
	close_intent = false


func _consume_queued_open_torque() -> float:
	if _queued_open_impulse <= 0.0 or _queued_open_sign == 0.0:
		return 0.0
	var kick := _queued_open_sign * _queued_open_impulse
	# Command input is an intentional action/kick, so apply an immediate angular kick.
	_angular_velocity = clampf(_angular_velocity + kick, -_cfg_max_angular_speed(), _cfg_max_angular_speed())
	_queued_open_impulse = 0.0
	return kick * 0.45


func _resolve_open_sign(source_pos: Vector2) -> float:
	if source_pos == Vector2.ZERO:
		if absf(_angle_offset) > SNAP_TO_ZERO_RAD:
			return signf(_angle_offset)
		return 1.0
	var leaf_normal := _leaf_axis.rotated(_angle_offset).orthogonal().normalized()
	var side := leaf_normal.dot(source_pos - global_position)
	var sign := signf(side)
	if sign != 0.0:
		return sign
	if absf(_angle_offset) > SNAP_TO_ZERO_RAD:
		return signf(_angle_offset)
	return 0.0


func get_debug_metrics() -> Dictionary:
	return {
		"angle_deg": rad_to_deg(_angle_offset),
		"angular_velocity": _angular_velocity,
		"limit_hits": _debug_limit_hits,
		"state": int(_state),
		"hold_timer": _hold_open_timer,
		"pinch_active": _pinch_active,
		"close_intent": close_intent,
	}


# ==========================================================================
# ANTI-PINCH — detect bodies in leaf sweep path
# ==========================================================================

func _get_bodies_in_leaf_path() -> Array:
	if not _trigger_area:
		return []
	if not _trigger_area.monitoring:
		return []
	var result: Array = []
	var tip_world := global_position + _leaf_axis.rotated(_angle_offset) * door_length
	var leaf_dir := (tip_world - global_position).normalized()
	var leaf_normal := leaf_dir.orthogonal()

	for body_variant in _trigger_area.get_overlapping_bodies():
		var body := body_variant as Node2D
		if not body:
			continue
		var rel := body.global_position - global_position
		var along := leaf_dir.dot(rel)
		if along < -4.0 or along > door_length + 8.0:
			continue
		var perp := absf(leaf_normal.dot(rel))
		if perp < PINCH_CHECK_DISTANCE_PX + door_thickness:
			result.append(body)
	return result


func _enforce_open_limits() -> void:
	var bounce := _cfg_limit_bounce()
	if _angle_offset > _max_open_positive:
		_angle_offset = _max_open_positive
		_debug_limit_hits += 1
		if _angular_velocity > 0.0:
			var speed_ratio := clampf(_angular_velocity / maxf(_cfg_max_angular_speed(), 0.001), 0.0, 1.0)
			var rebound_floor := lerpf(0.03, 0.12, speed_ratio)
			_angular_velocity = -maxf(_angular_velocity * bounce, rebound_floor)
	elif _angle_offset < -_max_open_negative:
		_angle_offset = -_max_open_negative
		_debug_limit_hits += 1
		if _angular_velocity < 0.0:
			var speed_ratio_neg := clampf(absf(_angular_velocity) / maxf(_cfg_max_angular_speed(), 0.001), 0.0, 1.0)
			var rebound_floor_neg := lerpf(0.03, 0.12, speed_ratio_neg)
			_angular_velocity = maxf(absf(_angular_velocity) * bounce, rebound_floor_neg)


func _is_sweeping_toward_bodies(bodies: Array, leaf_normal: Vector2) -> bool:
	if absf(_angular_velocity) <= 0.01:
		return false
	var motion_sign := signf(_angular_velocity)
	for body_variant in bodies:
		var body := body_variant as Node2D
		if not body:
			continue
		var side := leaf_normal.dot(body.global_position - global_position)
		if absf(side) <= PINCH_CHECK_DISTANCE_PX:
			return true
		if side * motion_sign > 0.0:
			return true
	return false


func _pinch_reopen_sign(bodies: Array, leaf_normal: Vector2) -> float:
	var side_sum := 0.0
	for body_variant in bodies:
		var body := body_variant as Node2D
		if not body:
			continue
		side_sum += leaf_normal.dot(body.global_position - global_position)
	if absf(side_sum) > 0.01:
		return -signf(side_sum)
	if absf(_angular_velocity) > 0.01:
		return -signf(_angular_velocity)
	if absf(_angle_offset) > 0.01:
		return signf(_angle_offset)
	return 0.0


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
	var collision_size := visual_size
	collision_size.y += COLLISION_EXTRA_THICKNESS_PX
	_door_shape.size = collision_size

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


func _refresh_swing_limits() -> void:
	if not is_inside_tree():
		return
	var pos_limit := _compute_open_limit(1.0)
	var neg_limit := _compute_open_limit(-1.0)
	_max_open_positive = pos_limit if pos_limit > 0.05 else deg_to_rad(160.0)
	_max_open_negative = neg_limit if neg_limit > 0.05 else deg_to_rad(160.0)


func _compute_open_limit(direction_sign: float) -> float:
	var limit := 0.0
	var excludes := _limit_query_excludes()
	var test_angle := SWING_STEP_RAD
	while test_angle <= MAX_SWING_ANGLE_RAD + 0.0001:
		var tip := global_position + _leaf_axis.rotated(direction_sign * test_angle) * door_length
		var query := PhysicsRayQueryParameters2D.create(global_position, tip)
		query.collision_mask = 1
		query.collide_with_bodies = true
		query.collide_with_areas = false
		query.exclude = excludes
		var hit := get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			limit = test_angle
			test_angle += SWING_STEP_RAD
			continue
		var hit_pos := hit.get("position", tip) as Vector2
		var hit_dist := global_position.distance_to(hit_pos)
		if hit_dist >= door_length - TIP_CLEARANCE_PX:
			limit = test_angle
			test_angle += SWING_STEP_RAD
			continue
		break
	return limit


func _limit_query_excludes() -> Array[RID]:
	var excludes: Array[RID] = []
	if _door_body:
		excludes.append(_door_body.get_rid())
	var tree := get_tree()
	if not tree:
		return excludes
	for node_variant in tree.get_nodes_in_group("player"):
		var node := node_variant as CollisionObject2D
		if node:
			excludes.append(node.get_rid())
	for node_variant in tree.get_nodes_in_group("enemies"):
		var node := node_variant as CollisionObject2D
		if node:
			excludes.append(node.get_rid())
	return excludes


# ==========================================================================
# DEBUG DRAW
# ==========================================================================

func _draw() -> void:
	if not _cfg_debug_draw():
		return

	# Hinge point
	draw_circle(Vector2.ZERO, DEBUG_HINGE_RADIUS, DEBUG_HINGE_COLOR)

	# Current leaf
	var tip_local := _leaf_axis.rotated(_angle_offset) * door_length
	draw_line(Vector2.ZERO, tip_local, DEBUG_LEAF_COLOR, 2.0)

	# Positive limit arc
	var pos_tip := _leaf_axis.rotated(_max_open_positive) * door_length
	draw_line(Vector2.ZERO, pos_tip, DEBUG_LIMIT_COLOR, 1.0)

	# Negative limit arc
	var neg_tip := _leaf_axis.rotated(-_max_open_negative) * door_length
	draw_line(Vector2.ZERO, neg_tip, DEBUG_LIMIT_COLOR, 1.0)

	# Closed position
	var closed_tip := _leaf_axis * door_length
	draw_line(Vector2.ZERO, closed_tip, Color(0.5, 0.5, 0.5, 0.3), 1.0)

	# State label
	var state_names := ["CLOSED", "OPENING", "HOLD", "CLOSING"]
	var label := "%s %.1f° %.1frad/s" % [state_names[int(_state)], rad_to_deg(_angle_offset), _angular_velocity]
	if _pinch_active:
		label += " PINCH"
	draw_string(ThemeDB.fallback_font, Vector2(-40.0, -16.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)


func _white_pixel() -> ImageTexture:
	if _cached_white_tex and is_instance_valid(_cached_white_tex):
		return _cached_white_tex
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.WHITE)
	_cached_white_tex = ImageTexture.create_from_image(img)
	return _cached_white_tex
