## physics_world.gd
## Wrapper interface for physics operations.
## CANON: Must accept/return Vector3 in public API.
## CANON: Physics may use Vector2 internally but must convert.
## Phase 0: Stub implementation.
class_name PhysicsWorld
extends Node

## Reference to the physics space (set by level)
var _space_rid: RID


func _ready() -> void:
	print("[PhysicsWorld] Initialized (Phase 0 stub)")


## Initialize with physics space
func initialize(space: RID) -> void:
	_space_rid = space


## ============================================================================
## PUBLIC API (Vector3)
## ============================================================================

## Raycast from origin in direction, returns hit info or null
## All positions are Vector3 (CANON)
func raycast(origin: Vector3, direction: Vector3, distance: float, collision_mask: int = 0xFFFFFFFF) -> Dictionary:
	# Phase 0 stub - no actual raycasting
	# Future implementation will use Physics2DDirectSpaceState
	return {}


## Check for overlapping bodies at position with radius
## Returns array of body info dictionaries
func overlap_circle(center: Vector3, radius: float, collision_mask: int = 0xFFFFFFFF) -> Array[Dictionary]:
	# Phase 0 stub
	return []


## Move a body and return collision info
## Returns Dictionary with: position (Vector3), collided (bool), collision_normal (Vector3)
func move_and_collide(body_rid: RID, motion: Vector3) -> Dictionary:
	# Phase 0 stub
	return {
		"position": Vector3.ZERO,
		"collided": false,
		"collision_normal": Vector3.ZERO
	}


## ============================================================================
## INTERNAL HELPERS
## ============================================================================

## Convert Vector3 to Vector2 (internal use only)
func _to_vec2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.y)


## Convert Vector2 to Vector3 (internal use only)
func _to_vec3(v: Vector2) -> Vector3:
	return Vector3(v.x, v.y, 0)
