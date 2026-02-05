## aim_system.gd
## Computes aimPoint and aimDir based on mouse + player pos.
## CANON: Other systems do not access camera/mouse directly.
## CANON: aimDir is Vector3 (z=0).
class_name AimSystem
extends Node

## Current aim point in world coordinates (Vector3)
var aim_point: Vector3 = Vector3.ZERO

## Current aim direction (normalized Vector3)
var aim_dir: Vector3 = Vector3(1, 0, 0)

## Reference to camera for screen-to-world conversion
var _camera: Camera2D = null


func _ready() -> void:
	print("[AimSystem] Initialized")


## Set camera reference (called by level)
func set_camera(camera: Camera2D) -> void:
	_camera = camera


## Update aim based on mouse position
## Called each frame by level
func update_aim(player_pos: Vector3) -> void:
	if not _camera:
		return

	# Get mouse position in screen space
	var mouse_screen := _camera.get_viewport().get_mouse_position()

	# Convert to world space
	var mouse_world := _camera.get_global_mouse_position()

	# Store aim point as Vector3 (CANON: z=0)
	aim_point = Vector3(mouse_world.x, mouse_world.y, 0)

	# Calculate direction from player to aim point
	var direction := aim_point - player_pos

	# Normalize if not zero
	if direction.length_squared() > 0.0001:
		aim_dir = direction.normalized()
	else:
		aim_dir = Vector3(1, 0, 0)  # Default right

	# Update RuntimeState
	if RuntimeState:
		RuntimeState.player_aim_dir = aim_dir
