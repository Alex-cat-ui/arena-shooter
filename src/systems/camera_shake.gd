## camera_shake.gd
## Simple camera shake utility for juice effects.
## CANON: Triggered only via EventBus events (rocket_exploded, etc.)
## CANON: Purely visual - no gameplay physics changes.
class_name CameraShake
extends Node

## Camera reference
var _camera: Camera2D = null

## Current shake intensity
var _shake_amount: float = 0.0

## Remaining shake time
var _shake_timer: float = 0.0


## Initialize with camera reference
func initialize(camera: Camera2D) -> void:
	_camera = camera


## Trigger a shake effect
func shake(amount: float, duration: float) -> void:
	# Use max to allow overlapping shakes without canceling
	_shake_amount = maxf(_shake_amount, amount)
	_shake_timer = maxf(_shake_timer, duration)


## Update called each frame from level
func update(delta: float) -> void:
	if not _camera or _shake_timer <= 0:
		return

	_shake_timer -= delta

	if _shake_timer <= 0:
		_shake_amount = 0.0
		_camera.offset = Vector2.ZERO
		return

	# Apply random offset within shake amount
	_camera.offset = Vector2(
		randf_range(-_shake_amount, _shake_amount),
		randf_range(-_shake_amount, _shake_amount)
	)
