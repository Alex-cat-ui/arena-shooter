## footprint_system.gd
## FootprintSystem - handles player footprints on blood/corpses.
## CANON: Footprints spawn ONLY when player moves over BLOOD or CORPSES.
## CANON: Footprint is a transparent boot-print mask that visually "removes" top layer.
## CANON: Footprints do not appear on clean floor.
## CANON: Maximum 20 footprints, LIFO (oldest removed when adding 21st).
class_name FootprintSystem
extends Node

## Maximum footprints
const MAX_FOOTPRINTS := 20

## Distance between footprint spawns (in pixels)
const FOOTPRINT_INTERVAL := 40.0

## Container for footprints
var footprints_container: Node2D = null

## Reference to VFXSystem (for checking blood/corpse presence)
var vfx_system: VFXSystem = null

## Active footprint sprites (LIFO queue)
var _footprints: Array[Sprite2D] = []

## Last position where footprint was spawned
var _last_footprint_pos: Vector2 = Vector2.ZERO

## Has the first footprint been placed? (to initialize _last_footprint_pos)
var _initialized: bool = false


func _ready() -> void:
	pass


## Initialize footprint system
func initialize(container: Node2D, vfx: VFXSystem) -> void:
	footprints_container = container
	vfx_system = vfx
	_footprints.clear()
	_initialized = false
	print("[FootprintSystem] Initialized")


## Update called each frame
func update(_delta: float) -> void:
	if not footprints_container or not vfx_system:
		return

	# Get player position
	if not RuntimeState:
		return

	var player_pos := Vector2(RuntimeState.player_pos.x, RuntimeState.player_pos.y)

	# Check if player has moved enough since last footprint
	if not _initialized:
		_last_footprint_pos = player_pos
		_initialized = true
		return

	var distance := player_pos.distance_to(_last_footprint_pos)
	if distance < FOOTPRINT_INTERVAL:
		return

	# Check if standing on blood or corpse
	if not vfx_system.has_blood_or_corpse_at(player_pos, 30.0):
		# Update position but don't spawn footprint
		_last_footprint_pos = player_pos
		return

	# Spawn footprint
	_spawn_footprint(player_pos)
	_last_footprint_pos = player_pos


func _spawn_footprint(pos: Vector2) -> void:
	# Check limit - remove oldest if at max
	if _footprints.size() >= MAX_FOOTPRINTS:
		var oldest: Sprite2D = _footprints.pop_front() as Sprite2D
		if is_instance_valid(oldest):
			oldest.queue_free()

	# Create footprint sprite
	var footprint := _create_footprint_sprite()
	footprint.position = pos

	# Calculate rotation based on player movement direction
	var direction := Vector2.ZERO
	if RuntimeState:
		direction = Vector2(RuntimeState.player_aim_dir.x, RuntimeState.player_aim_dir.y)
	if direction.length_squared() > 0:
		footprint.rotation = direction.angle()
	else:
		footprint.rotation = randf() * TAU

	footprints_container.add_child(footprint)
	_footprints.append(footprint)

	# Emit event
	if EventBus:
		EventBus.emit_footprint_spawned(Vector3(pos.x, pos.y, 0), footprint.rotation)


func _create_footprint_sprite() -> Sprite2D:
	var sprite := Sprite2D.new()

	# Create footprint texture (boot-shaped mask)
	# MVP: Simple dark ellipse that looks like pressed blood
	var img := Image.create(24, 32, false, Image.FORMAT_RGBA8)

	# Draw two boot-print shapes (left and right foot alternating)
	var is_left := (_footprints.size() % 2 == 0)

	# Boot print color - dark, semi-transparent to "subtract" from blood layer
	# This creates the effect of pressing out/removing blood
	var color := Color(0.1, 0.05, 0.05, 0.6)

	# Draw simplified boot shape
	var offset_x := 2 if is_left else 14
	for x in range(10):
		for y in range(28):
			# Boot shape: wider at top (heel area), narrower at bottom (toe)
			var rel_y := float(y) / 28.0
			var width := 8.0 - rel_y * 3.0  # Narrower toward toe
			var center_x := 5.0

			var dx: float = absf(float(x) - center_x)
			if dx < width / 2.0:
				# Add some texture variation
				var alpha := color.a * (0.8 + randf() * 0.4)
				img.set_pixel(offset_x + x, y + 2, Color(color.r, color.g, color.b, alpha))

	var tex := ImageTexture.create_from_image(img)
	sprite.texture = tex

	# Use blend mode to create "subtraction" effect
	# In Godot, we can use modulate with low alpha or use a shader
	# MVP: Use dark color with blend
	sprite.modulate = Color(0.2, 0.1, 0.1, 0.7)

	return sprite


## Get footprint count
func get_footprint_count() -> int:
	return _footprints.size()


## Clear all footprints
func clear() -> void:
	for footprint in _footprints:
		if is_instance_valid(footprint):
			footprint.queue_free()
	_footprints.clear()
	_initialized = false
