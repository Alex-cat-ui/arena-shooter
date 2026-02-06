## arena_boundary.gd
## Visual arena boundary - darkened border beyond play area.
## CANON: Purely cosmetic, no collision or gameplay impact.
## CANON: Communicates map limits to the player.
class_name ArenaBoundary
extends Node2D

## Thickness of boundary strips (pixels)
const BOUNDARY_THICKNESS := 2000.0

## Boundary darkness color
const BOUNDARY_COLOR := Color(0.0, 0.0, 0.0, 0.6)

## Arena bounds
var arena_min: Vector2 = Vector2(-500, -500)
var arena_max: Vector2 = Vector2(500, 500)

## Whether visuals have been created
var _initialized: bool = false


## Initialize with arena bounds
func initialize(a_min: Vector2, a_max: Vector2) -> void:
	arena_min = a_min
	arena_max = a_max
	_initialized = true
	queue_redraw()


func _draw() -> void:
	if not _initialized:
		return

	var w := arena_max.x - arena_min.x
	var h := arena_max.y - arena_min.y

	# Top boundary
	draw_rect(Rect2(
		arena_min.x - BOUNDARY_THICKNESS,
		arena_min.y - BOUNDARY_THICKNESS,
		w + 2 * BOUNDARY_THICKNESS,
		BOUNDARY_THICKNESS
	), BOUNDARY_COLOR)

	# Bottom boundary
	draw_rect(Rect2(
		arena_min.x - BOUNDARY_THICKNESS,
		arena_max.y,
		w + 2 * BOUNDARY_THICKNESS,
		BOUNDARY_THICKNESS
	), BOUNDARY_COLOR)

	# Left boundary
	draw_rect(Rect2(
		arena_min.x - BOUNDARY_THICKNESS,
		arena_min.y,
		BOUNDARY_THICKNESS,
		h
	), BOUNDARY_COLOR)

	# Right boundary
	draw_rect(Rect2(
		arena_max.x,
		arena_min.y,
		BOUNDARY_THICKNESS,
		h
	), BOUNDARY_COLOR)
