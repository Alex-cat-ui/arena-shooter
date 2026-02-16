## suspicion_ring_presenter.gd
## World-space ring UI that fills clockwise based on enemy suspicion.
class_name SuspicionRingPresenter
extends Node2D

const START_ANGLE := -PI * 0.5

@export_range(4.0, 48.0, 1.0) var ring_radius: float = 12.0:
	set(value):
		ring_radius = maxf(value, 1.0)
		queue_redraw()

@export_range(1.0, 16.0, 0.5) var ring_width: float = 4.0:
	set(value):
		ring_width = maxf(value, 1.0)
		queue_redraw()

@export var head_offset: Vector2 = Vector2(0.0, -44.0):
	set(value):
		head_offset = value
		position = head_offset
		queue_redraw()

@export var fill_color: Color = Color(1.0, 1.0, 1.0, 0.95)
@export var track_color: Color = Color(1.0, 1.0, 1.0, 0.20)
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.95)

var _progress: float = 0.0
var _enabled: bool = false


func _ready() -> void:
	print("RING_POLICY_ACTIVE_v20260216")
	position = head_offset
	z_as_relative = false
	z_index = 240
	_refresh_visibility()
	queue_redraw()


func set_enabled(enabled: bool) -> void:
	if _enabled == enabled:
		return
	_enabled = enabled
	_refresh_visibility()
	queue_redraw()


func set_progress(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if is_equal_approx(_progress, clamped):
		return
	_progress = clamped
	if _enabled:
		queue_redraw()


func get_progress() -> float:
	return _progress


func _process(_delta: float) -> void:
	_refresh_visibility()


func _draw() -> void:
	if not _enabled:
		return
	var radius := maxf(ring_radius, 1.0)
	var width := maxf(ring_width, 1.0)
	var base_points := maxi(int(radius * 3.0), 24)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, base_points, outline_color, width + 2.0, true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, base_points, track_color, width, true)
	if _progress <= 0.0001:
		return
	var end_angle := START_ANGLE + TAU * _progress
	var fill_points := maxi(8, int(base_points * _progress) + 2)
	draw_arc(Vector2.ZERO, radius, START_ANGLE, end_angle, fill_points, fill_color, width, true)


func _refresh_visibility() -> void:
	visible = _enabled and _is_ring_state_visible()


func _is_ring_state_visible() -> bool:
	var owner := get_parent()
	if owner == null:
		return false
	var state_name := String(owner.get_meta("awareness_state", "CALM")).to_upper()
	if state_name == "ALERT" or state_name == "COMBAT":
		return true
	if state_name == "CALM" or state_name == "IDLE":
		return false
	return false
