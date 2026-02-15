## door_physics_v3.gd
## Stable swing-door controller with anti-jitter sign lock, deterministic closer,
## reverse impulse on bodies, and anti-pinch logic.
class_name DoorPhysicsV3
extends Node2D

const DOOR_COLOR := Color(0.92, 0.18, 0.18, 1.0)
const DOOR_Z_INDEX := 25

# --- Push response ---
const PUSH_TORQUE_CLAMP := 48.0
const MIN_PUSH_SPEED_PX := 30.0
const MIN_PUSH_TORQUE_ABS := 0.25
const FAST_PUSH_SPEED_PX := 220.0
const FAST_PUSH_OPEN_KICK := 12.0
const OPEN_BREAK_ANGLE_RAD := deg_to_rad(6.0)
const OPEN_BREAK_SPEED_RAD := 1.0
const OPEN_BREAK_BOOST := 5.0
const CONTACT_CLOSE_ASSIST_MULT := 1.28
const CONTACT_OPEN_RESIST_MULT := 0.95
const APPROACH_BOOST_MULT := 0.6
const MAX_PERP_DISTANCE_PX := 28.0

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
const HOLD_AFTER_PUSH_SEC := 0.10

# --- Anti-jitter ---
const SIGN_LOCK_SEC := 0.08
const SIGN_SWITCH_NEAR_CLOSED_RAD := deg_to_rad(42.0)

# --- Shot reaction ---
const SHOT_REACTION_RADIUS_PX := 240.0
const SHOT_REACTION_MIN_IMPULSE := 0.18
const SHOT_REACTION_MAX_IMPULSE := 1.2

# --- Sensor ---
const SENSOR_PADDING := 20.0
const SENSOR_THICKNESS := 40.0

# --- Anti-pinch ---
const PINCH_REOPEN_TORQUE := 6.0
const PINCH_CHECK_DISTANCE_PX := 6.0

# --- Reverse impulse ---
const REVERSE_IMPULSE_MIN_ANGULAR_SPEED := 2.0
const REVERSE_IMPULSE_MAX_PUSH := 280.0

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
var _preferred_open_sign: int = 0
var _sign_lock_timer: float = 0.0
var _hold_open_timer: float = 0.0
var _state: DoorState = DoorState.CLOSED
var _rng := RandomNumberGenerator.new()
var _pinch_active: bool = false

var _debug_sign_flips: int = 0
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

func _cfg_push_torque_min() -> float:
	if GameConfig: return GameConfig.door_push_torque_min
	return 2.5

func _cfg_push_torque_max() -> float:
	if GameConfig: return GameConfig.door_push_torque_max
	return 22.0

func _cfg_push_speed_ref() -> float:
	if GameConfig: return GameConfig.door_push_speed_ref
	return 380.0

func _cfg_reverse_impulse_mult() -> float:
	if GameConfig: return GameConfig.door_reverse_impulse_mult
	return 0.8

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

	_sign_lock_timer = maxf(0.0, _sign_lock_timer - delta)
	_hold_open_timer = maxf(0.0, _hold_open_timer - delta)

	# --- Anti-pinch: detect body in doorway while closing ---
	var bodies_in_doorway := _get_bodies_in_leaf_path()
	_pinch_active = not bodies_in_doorway.is_empty() and _state == DoorState.CLOSING

	var push := _collect_push_input()
	var is_pushed := bool(push.get("active", false))
	var push_torque := 0.0
	var max_speed := 0.0
	var max_angular := _cfg_max_angular_speed()

	if is_pushed:
		_hold_open_timer = HOLD_AFTER_PUSH_SEC
		max_speed = float(push.get("max_speed", 0.0))
		var sign := _resolve_push_sign(int(push.get("sign", 0)))
		var torque_abs := float(push.get("torque_abs", 0.0))
		push_torque = sign * torque_abs
		if max_speed >= FAST_PUSH_SPEED_PX and sign != 0:
			_angular_velocity = sign * maxf(absf(_angular_velocity), FAST_PUSH_OPEN_KICK)
		_state = DoorState.OPENING

	var angle_sign := signf(_angle_offset)
	var torque_sign := signf(push_torque)
	if absf(_angle_offset) > deg_to_rad(2.0) and torque_sign != 0.0 and angle_sign != 0.0:
		var is_closing_torque := torque_sign != angle_sign
		if is_closing_torque:
			push_torque *= CONTACT_CLOSE_ASSIST_MULT
		else:
			push_torque *= CONTACT_OPEN_RESIST_MULT

	var stiffness := _cfg_stiffness_idle()
	if is_pushed or _hold_open_timer > 0.0:
		stiffness = _cfg_stiffness_pushed()
		if not is_pushed:
			_state = DoorState.HOLD
	else:
		_state = DoorState.CLOSING if absf(_angle_offset) > SNAP_TO_ZERO_RAD else DoorState.CLOSED

	# Anti-pinch: suppress closing spring when body is in the way
	if _pinch_active:
		stiffness = 0.0
		push_torque = signf(_angle_offset) * PINCH_REOPEN_TORQUE

	if is_pushed and absf(_angle_offset) < OPEN_BREAK_ANGLE_RAD and absf(_angular_velocity) < OPEN_BREAK_SPEED_RAD and absf(push_torque) > 0.0001:
		_angular_velocity += signf(push_torque) * OPEN_BREAK_BOOST * delta

	var damping_val := _cfg_damping()
	var friction_val := _cfg_dry_friction()
	var spring := -_angle_offset * stiffness
	var damping := -_angular_velocity * damping_val
	var dry_friction := 0.0
	if absf(_angular_velocity) > 0.0001:
		dry_friction = -signf(_angular_velocity) * friction_val
	elif not is_pushed and absf(_angle_offset) > 0.0001:
		dry_friction = -signf(_angle_offset) * friction_val * 0.45

	var total_torque := spring + damping + dry_friction + push_torque
	total_torque = clampf(total_torque, -PUSH_TORQUE_CLAMP, PUSH_TORQUE_CLAMP)

	var prev_angular_velocity := _angular_velocity
	_angular_velocity += total_torque * delta
	_angular_velocity = clampf(_angular_velocity, -max_angular, max_angular)

	_angle_offset += _angular_velocity * delta
	_enforce_open_limits()

	if not is_pushed and _hold_open_timer <= 0.0 and absf(_angle_offset) <= SNAP_TO_ZERO_RAD and absf(_angular_velocity) <= SNAP_VEL_RAD:
		_angle_offset = 0.0
		_angular_velocity = 0.0
		_preferred_open_sign = 0
		_state = DoorState.CLOSED

	if not is_pushed and absf(_angular_velocity) < _cfg_dry_friction() * 0.05 and absf(_angle_offset) < deg_to_rad(1.8):
		_angular_velocity = 0.0

	_apply_pose()

	# Reverse impulse disabled: only entities push doors, not vice versa.

	# --- Debug draw ---
	if _cfg_debug_draw():
		queue_redraw()


func reset_to_closed() -> void:
	_angle_offset = 0.0
	_angular_velocity = 0.0
	_preferred_open_sign = 0
	_sign_lock_timer = 0.0
	_hold_open_timer = 0.0
	_state = DoorState.CLOSED
	_pinch_active = false
	_debug_sign_flips = 0
	_debug_limit_hits = 0
	_apply_pose()


func apply_shot_impulse(shot_pos: Vector2, strength: float = 1.0) -> void:
	var to_shot := shot_pos - global_position
	var dist := to_shot.length()
	if dist > SHOT_REACTION_RADIUS_PX:
		return
	var ratio := 1.0 - clampf(dist / SHOT_REACTION_RADIUS_PX, 0.0, 1.0)
	var falloff := pow(ratio, 1.35)
	var impulse := lerpf(SHOT_REACTION_MIN_IMPULSE, SHOT_REACTION_MAX_IMPULSE, falloff) * clampf(strength, 0.0, 2.0)
	if impulse <= 0.0:
		return
	var normal := _leaf_axis.orthogonal().normalized()
	var sign := signf(normal.dot(to_shot))
	if sign == 0.0:
		sign = float(_preferred_open_sign)
	if sign == 0.0:
		sign = 1.0
	_angular_velocity += sign * impulse
	_angular_velocity = clampf(_angular_velocity, -_cfg_max_angular_speed(), _cfg_max_angular_speed())


func get_debug_metrics() -> Dictionary:
	return {
		"angle_deg": rad_to_deg(_angle_offset),
		"angular_velocity": _angular_velocity,
		"sign_flips": _debug_sign_flips,
		"limit_hits": _debug_limit_hits,
		"state": int(_state),
		"hold_timer": _hold_open_timer,
		"pinch_active": _pinch_active,
	}


# ==========================================================================
# REVERSE IMPULSE — door pushes bodies on contact
# ==========================================================================

func _apply_reverse_impulse(_delta: float) -> void:
	if not _trigger_area:
		return
	var mult := _cfg_reverse_impulse_mult()
	if mult <= 0.0:
		return

	var tip_world := global_position + _leaf_axis.rotated(_angle_offset) * door_length
	var hinge_world := global_position
	var leaf_dir := (tip_world - hinge_world).normalized()
	var push_normal := leaf_dir.orthogonal() * signf(_angular_velocity)

	for body_variant in _trigger_area.get_overlapping_bodies():
		var body := body_variant as CharacterBody2D
		if not body:
			continue
		var rel := body.global_position - hinge_world
		var along := leaf_dir.dot(rel)
		if along < 0.0 or along > door_length + 8.0:
			continue
		var perp := absf(push_normal.dot(rel))
		if perp > door_thickness + 12.0:
			continue
		# Lever arm: tip moves faster than hinge
		var lever := clampf(along / maxf(door_length, 1.0), 0.1, 1.0)
		var tip_speed := absf(_angular_velocity) * door_length * lever
		var push_strength := clampf(tip_speed * mult, 0.0, REVERSE_IMPULSE_MAX_PUSH)
		if push_strength < 1.0:
			continue
		var impulse_vec := push_normal * push_strength
		# Apply as velocity delta (CharacterBody2D doesn't have apply_impulse)
		body.velocity += impulse_vec * _delta


# ==========================================================================
# ANTI-PINCH — detect bodies in leaf sweep path
# ==========================================================================

func _get_bodies_in_leaf_path() -> Array:
	if not _trigger_area:
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


# ==========================================================================
# PUSH INPUT
# ==========================================================================

func _resolve_push_sign(candidate_sign: int) -> int:
	if candidate_sign == 0:
		return _preferred_open_sign
	if _preferred_open_sign == 0:
		_preferred_open_sign = candidate_sign
		_sign_lock_timer = SIGN_LOCK_SEC
		return _preferred_open_sign
	if candidate_sign == _preferred_open_sign:
		_sign_lock_timer = SIGN_LOCK_SEC
		return _preferred_open_sign
	if _sign_lock_timer > 0.0 and absf(_angle_offset) > SIGN_SWITCH_NEAR_CLOSED_RAD and _state != DoorState.CLOSED:
		return _preferred_open_sign
	_preferred_open_sign = candidate_sign
	_sign_lock_timer = SIGN_LOCK_SEC
	_debug_sign_flips += 1
	return _preferred_open_sign


func _enforce_open_limits() -> void:
	var bounce := _cfg_limit_bounce()
	if _angle_offset > _max_open_positive:
		_angle_offset = _max_open_positive
		_debug_limit_hits += 1
		if _angular_velocity > 0.0:
			_angular_velocity = -maxf(_angular_velocity * bounce, 0.18)
	elif _angle_offset < -_max_open_negative:
		_angle_offset = -_max_open_negative
		_debug_limit_hits += 1
		if _angular_velocity < 0.0:
			_angular_velocity = maxf(absf(_angular_velocity) * bounce, 0.18)


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


func _collect_push_input() -> Dictionary:
	if not _trigger_area:
		return {"active": false}
	var bodies := _trigger_area.get_overlapping_bodies()
	if bodies.is_empty():
		return {"active": false}

	var positive := 0.0
	var negative := 0.0
	var max_speed := 0.0
	var leaf := Vector2.RIGHT.rotated(_closed_rotation + _angle_offset).normalized()
	var normal := leaf.orthogonal().normalized()
	var door_len := maxf(door_length, 1.0)
	var speed_ref := _cfg_push_speed_ref()
	var torque_min := _cfg_push_torque_min()
	var torque_max := _cfg_push_torque_max()

	for body_variant in bodies:
		var body := body_variant as Node2D
		if not body:
			continue
		var velocity := _extract_body_velocity(body)
		var speed := velocity.length()
		if speed <= MIN_PUSH_SPEED_PX:
			continue

		var rel := body.global_position - global_position
		# Perpendicular distance to door leaf — skip bodies too far from the actual leaf
		var perp_dist := absf(normal.dot(rel))
		if perp_dist > MAX_PERP_DISTANCE_PX:
			continue
		max_speed = maxf(max_speed, speed)

		var lever_ratio := clampf(absf(leaf.dot(rel)) / door_len, 0.08, 1.0)
		var sign := _push_sign_for_body(body, velocity, normal)

		var cross := rel.x * velocity.y - rel.y * velocity.x
		if absf(cross) > 0.001:
			sign = signf(cross)

		var speed_ratio := clampf(speed / speed_ref, 0.0, 1.0)
		speed_ratio *= speed_ratio
		var base_torque := lerpf(torque_min, torque_max, speed_ratio)
		var cross_drive := base_torque * lever_ratio
		var approach_speed := absf(velocity.dot(normal))
		var approach_ratio := clampf((approach_speed - MIN_PUSH_SPEED_PX) / maxf(FAST_PUSH_SPEED_PX - MIN_PUSH_SPEED_PX, 1.0), 0.0, 1.0)
		var approach_boost := torque_max * APPROACH_BOOST_MULT * approach_ratio * approach_ratio
		var contribution := cross_drive + approach_boost
		if sign >= 0.0:
			positive += contribution
		else:
			negative += contribution

	if max_speed <= MIN_PUSH_SPEED_PX:
		return {"active": false}

	var sign_out := 0
	if positive > negative:
		sign_out = 1
	elif negative > positive:
		sign_out = -1
	elif positive > 0.0:
		sign_out = _preferred_open_sign

	var torque_abs := absf(positive - negative)
	if torque_abs < MIN_PUSH_TORQUE_ABS:
		return {"active": false}

	return {
		"active": sign_out != 0,
		"sign": sign_out,
		"torque_abs": clampf(torque_abs, 0.0, PUSH_TORQUE_CLAMP),
		"max_speed": max_speed,
	}


func _extract_body_velocity(body: Node2D) -> Vector2:
	if body.has_meta("door_push_velocity"):
		var push_v: Variant = body.get_meta("door_push_velocity")
		if push_v is Vector2:
			return push_v
	if "velocity" in body:
		return body.velocity
	var rb := body as RigidBody2D
	if rb:
		return rb.linear_velocity
	return Vector2.ZERO


func _push_sign_for_body(body: Node2D, velocity: Vector2, normal: Vector2) -> float:
	var to_body := body.global_position - global_position
	var side := normal.dot(to_body)
	var sign := signf(side)
	if sign == 0.0 and velocity.length_squared() > 0.001:
		sign = signf(normal.dot(velocity.normalized()))
	if sign == 0.0 and _preferred_open_sign != 0:
		sign = float(_preferred_open_sign)
	return sign


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
