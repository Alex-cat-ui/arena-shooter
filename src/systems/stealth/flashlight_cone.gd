## flashlight_cone.gd
## Flashlight cone helper for test-profile stealth detection.
class_name FlashlightCone
extends Node2D

@export_range(10.0, 120.0, 1.0) var cone_angle_deg: float = 55.0:
	set(value):
		cone_angle_deg = clampf(value, 1.0, 179.0)
		queue_redraw()

@export_range(64.0, 2000.0, 1.0) var cone_distance: float = 1000.0:
	set(value):
		cone_distance = maxf(value, 1.0)
		queue_redraw()

@export_range(1.0, 10.0, 0.1) var flashlight_visibility_bonus: float = 2.5
@export var debug_draw_enabled: bool = true

var _runtime_active: bool = false
var _runtime_hit: bool = false
var _runtime_facing: Vector2 = Vector2.RIGHT
var _runtime_inactive_reason: String = ""


func set_flashlight_visibility_bonus(value: float) -> void:
	flashlight_visibility_bonus = maxf(value, 1.0)


func get_flashlight_visibility_bonus() -> float:
	return flashlight_visibility_bonus


func is_point_in_cone(origin: Vector2, forward: Vector2, point: Vector2) -> bool:
	var n_forward := _safe_forward(forward)
	var to_point := point - origin
	var distance_to_point := to_point.length()
	if distance_to_point > cone_distance:
		return false
	if distance_to_point <= 0.001:
		return true
	var dir_to_point := to_point / distance_to_point
	var min_dot := cos(deg_to_rad(cone_angle_deg) * 0.5)
	return n_forward.dot(dir_to_point) >= min_dot


func is_player_hit(origin: Vector2, forward: Vector2, player_position: Vector2, has_los: bool, active: bool) -> bool:
	var evaluation := evaluate_hit(origin, forward, player_position, has_los, active)
	return bool(evaluation.get("hit", false))


func evaluate_hit(origin: Vector2, forward: Vector2, player_position: Vector2, has_los: bool, active: bool) -> Dictionary:
	var in_cone := is_point_in_cone(origin, forward, player_position)
	if not active:
		return {"hit": false, "in_cone": in_cone, "inactive_reason": "state_blocked"}
	if not has_los:
		return {"hit": false, "in_cone": in_cone, "inactive_reason": "los_blocked"}
	if not in_cone:
		return {"hit": false, "in_cone": false, "inactive_reason": "cone_miss"}
	return {"hit": true, "in_cone": true, "inactive_reason": ""}


func update_runtime_debug(forward: Vector2, active: bool, hit: bool, inactive_reason: String = "") -> void:
	_runtime_facing = _safe_forward(forward)
	_runtime_active = active
	_runtime_hit = hit and active
	_runtime_inactive_reason = inactive_reason
	queue_redraw()


func _draw() -> void:
	if not debug_draw_enabled:
		return
	if not _runtime_active:
		return

	var half_angle := deg_to_rad(cone_angle_deg) * 0.5
	var left := _runtime_facing.rotated(-half_angle) * cone_distance
	var right := _runtime_facing.rotated(half_angle) * cone_distance
	var fill_color := Color(1.0, 0.93, 0.60, 0.18)
	var edge_color := Color(1.0, 0.93, 0.60, 0.70)
	if _runtime_hit:
		fill_color = Color(1.0, 0.80, 0.42, 0.24)
		edge_color = Color(1.0, 0.80, 0.42, 0.95)

	draw_colored_polygon(PackedVector2Array([Vector2.ZERO, left, right]), fill_color)
	draw_polyline(PackedVector2Array([Vector2.ZERO, left, right, Vector2.ZERO]), edge_color, 2.0, true)


func _safe_forward(forward: Vector2) -> Vector2:
	if forward.length_squared() <= 0.0001:
		return Vector2.RIGHT
	return forward.normalized()
