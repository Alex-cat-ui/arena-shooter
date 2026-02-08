## atmosphere_system.gd
## AtmosphereSystem - ambient dust particles and floor decal spawning.
## CANON: Pure visual, never obscures combat readability.
## CANON: Lightweight, pooled nodes, headless safe.
class_name AtmosphereSystem
extends Node

## Particle pool
var _particle_pool: Array[Sprite2D] = []

## Active particles
var _active_particles: Array[Dictionary] = []

## Floor decals (static, spawned once on init)
var _decals_spawned: bool = false

## Containers
var _particle_container: Node2D = null
var _decal_container: Node2D = null

## Arena bounds
var _arena_min: Vector2 = Vector2(-500, -500)
var _arena_max: Vector2 = Vector2(500, 500)

## Spawn timer for particles
var _spawn_timer: float = 0.0

const PARTICLE_POOL_SIZE := 30
const FLOOR_DECAL_COUNT := 12
const PARTICLE_SPAWN_INTERVAL := 0.5


func _ready() -> void:
	pass


## Initialize
func initialize(particle_container: Node2D, decal_container: Node2D, arena_min: Vector2, arena_max: Vector2) -> void:
	_particle_container = particle_container
	_decal_container = decal_container
	_arena_min = arena_min
	_arena_max = arena_max

	# Create particle pool
	for i in range(PARTICLE_POOL_SIZE):
		var sprite := Sprite2D.new()
		sprite.visible = false
		sprite.z_index = 20  # Above everything (but very faint)
		# Create tiny dot texture
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		for x in range(4):
			for y in range(4):
				var dist := Vector2(x, y).distance_to(Vector2(2, 2))
				if dist < 2.0:
					img.set_pixel(x, y, Color(0.8, 0.75, 0.65, 0.5))
		sprite.texture = ImageTexture.create_from_image(img)
		particle_container.add_child(sprite)
		_particle_pool.append(sprite)

	# Spawn floor decals (once)
	if not _decals_spawned:
		_spawn_floor_decals()
		_decals_spawned = true

	print("[AtmosphereSystem] Initialized")


## Update called each frame
func update(delta: float) -> void:
	if not _particle_container:
		return

	# Spawn new particles periodically
	_spawn_timer -= delta
	if _spawn_timer <= 0:
		_spawn_timer = PARTICLE_SPAWN_INTERVAL
		_try_spawn_particle()

	# Update active particles
	var alpha_min := GameConfig.atmosphere_particle_alpha_min if GameConfig else 0.05
	var alpha_max := GameConfig.atmosphere_particle_alpha_max if GameConfig else 0.15
	var i := 0
	while i < _active_particles.size():
		var entry: Dictionary = _active_particles[i]
		entry["time_left"] -= delta
		if entry["time_left"] <= 0:
			var spr: Sprite2D = entry["sprite"]
			spr.visible = false
			_active_particles.remove_at(i)
			continue

		var spr: Sprite2D = entry["sprite"]
		# Slow drift
		spr.position += Vector2(entry["drift"]) * delta

		# Fade based on lifetime (bell curve: fade in then out)
		var lifetime: float = float(entry["lifetime"])
		var progress: float = 1.0 - (float(entry["time_left"]) / lifetime)
		var fade: float
		if progress < 0.2:
			fade = progress / 0.2  # Fade in
		elif progress > 0.8:
			fade = (1.0 - progress) / 0.2  # Fade out
		else:
			fade = 1.0
		spr.modulate.a = float(entry["base_alpha"]) * fade
		i += 1


func _try_spawn_particle() -> void:
	# Find free sprite
	var sprite: Sprite2D = null
	for s in _particle_pool:
		if not s.visible:
			sprite = s
			break
	if not sprite:
		return

	# Random position near camera (player)
	var player_pos := Vector2.ZERO
	if RuntimeState:
		player_pos = Vector2(RuntimeState.player_pos.x, RuntimeState.player_pos.y)

	var offset := Vector2(randf_range(-200, 200), randf_range(-150, 150))
	sprite.position = player_pos + offset

	var alpha_min := GameConfig.atmosphere_particle_alpha_min if GameConfig else 0.05
	var alpha_max := GameConfig.atmosphere_particle_alpha_max if GameConfig else 0.15
	var life_min := GameConfig.atmosphere_particle_lifetime_min if GameConfig else 3.0
	var life_max := GameConfig.atmosphere_particle_lifetime_max if GameConfig else 6.0

	var lifetime := randf_range(life_min, life_max)
	var base_alpha := randf_range(alpha_min, alpha_max)
	var drift := Vector2(randf_range(-5, 5), randf_range(-3, 3))

	sprite.modulate = Color(1, 1, 1, 0)
	sprite.visible = true

	_active_particles.append({
		"sprite": sprite,
		"time_left": lifetime,
		"lifetime": lifetime,
		"base_alpha": base_alpha,
		"drift": drift,
	})


## Spawn sparse floor decals (dirt/cracks)
func _spawn_floor_decals() -> void:
	if not _decal_container:
		return

	for i in range(FLOOR_DECAL_COUNT):
		var pos := Vector2(
			randf_range(_arena_min.x + 50, _arena_max.x - 50),
			randf_range(_arena_min.y + 50, _arena_max.y - 50),
		)

		var decal := _create_floor_decal()
		decal.position = pos
		decal.rotation = randf() * TAU
		_decal_container.add_child(decal)


func _create_floor_decal() -> Sprite2D:
	var sprite := Sprite2D.new()
	# z_index inherited from container (FloorDecals at -9), no per-sprite offset
	# Effective z = -9, above floor at -20, below footprints at -5

	# Create procedural crack/dirt mark
	var size := randi_range(8, 18)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var color := Color(0.08, 0.05, 0.03, 0.35)

	# Draw random scratches/cracks
	var points := randi_range(3, 6)
	for p in range(points):
		var x := randi_range(1, size - 2)
		var y := randi_range(1, size - 2)
		# Draw small cluster
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var px := x + dx
				var py := y + dy
				if px >= 0 and px < size and py >= 0 and py < size:
					var alpha_var := 0.5 + randf() * 0.5
					img.set_pixel(px, py, Color(color.r, color.g, color.b, color.a * alpha_var))

	sprite.texture = ImageTexture.create_from_image(img)
	sprite.modulate = Color(1, 1, 1, 0.5)
	return sprite


## Get active particle count (for debug overlay)
func get_particle_count() -> int:
	return _active_particles.size()


## Get floor decal count (for debug overlay)
func get_decal_count() -> int:
	if _decal_container:
		return _decal_container.get_child_count()
	return 0
