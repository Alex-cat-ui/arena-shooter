## footprint_system.gd
## FootprintSystem - PNG paired-step boot tread footprints aligned to movement.
## CANON: Footprints spawn based on player movement distance (accumulator).
## CANON: Single paired-step PNG stamp per spawn (no left/right alternation).
## CANON: Pooled nodes, fade before lifetime end, count-clamped.
## CANON: Bloody boots decay over 8 prints after stepping on blood.
class_name FootprintSystem
extends Node

## Legacy constant kept for test backward-compatibility
const MAX_FOOTPRINTS := 20

## Boot print PNG texture (paired-step stamp)
const BOOT_TEX := preload("res://assets/sprites/footprints/boot_print_cc0.png")

## Shader for tinting footprints by alpha channel only
const FOOTPRINT_SHADER := preload("res://shaders/footprint_tint.gdshader")

## Container for footprints
var footprints_container: Node2D = null

## VFX system reference (for blood/corpse proximity checks)
var vfx_system: Node = null

## Pool of footprint sprites (pre-allocated)
var _pool: Array[Sprite2D] = []

## Active footprints (ordered oldest-first)
var _active: Array[Dictionary] = []  # {sprite, time_left, max_time, base_alpha}

## Previous player position for velocity/direction calculation
var _prev_player_pos: Vector2 = Vector2.ZERO

## Distance accumulator for stable step spacing
var _distance_accum: float = 0.0

## Whether system has been initialized with a position
var _initialized: bool = false

## Blood charges remaining (decremented each off-blood step)
var _blood_charges: int = 0

## Debug counter
var _spawned_total: int = 0

## Debug: last frame detection results
var last_on_blood: bool = false
var last_on_corpse: bool = false


func _ready() -> void:
	pass


## Initialize footprint system
func initialize(container: Node2D, vfx: Node = null) -> void:
	footprints_container = container
	vfx_system = vfx
	_active.clear()
	_initialized = false
	_distance_accum = 0.0
	_blood_charges = 0
	_spawned_total = 0
	last_on_blood = false
	last_on_corpse = false

	# Pre-allocate pool
	var max_count := GameConfig.footprint_max_count if GameConfig else 100
	_pool.clear()
	for i in range(max_count):
		var sprite := Sprite2D.new()
		sprite.visible = false
		sprite.z_index = -5  # Below blood/corpses, above floor
		sprite.texture = BOOT_TEX
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var mat := ShaderMaterial.new()
		mat.shader = FOOTPRINT_SHADER
		sprite.material = mat
		container.add_child(sprite)
		_pool.append(sprite)

	print("[FootprintSystem] Initialized (pool: %d, vfx_wired: %s)" % [max_count, str(vfx != null)])


## Update called each frame by LevelMVP
func update(delta: float) -> void:
	if not footprints_container or not RuntimeState:
		return
	if GameConfig and not GameConfig.footprints_enabled:
		return

	var player_pos := Vector2(RuntimeState.player_pos.x, RuntimeState.player_pos.y)

	if not _initialized:
		_prev_player_pos = player_pos
		_initialized = true
		return

	# Calculate movement delta
	var delta_pos := player_pos - _prev_player_pos
	_prev_player_pos = player_pos

	# No movement = no spawn (prevents spawning when aiming/rotating in place)
	if delta_pos.length() < 0.001:
		_age_footprints(delta)
		return

	var speed := delta_pos.length() / maxf(delta, 0.001)
	var vel_threshold := GameConfig.footprint_velocity_threshold if GameConfig else 35.0

	if speed < vel_threshold:
		_age_footprints(delta)
		return

	var move_dir := delta_pos.normalized()

	# Distance accumulator for stable spacing
	_distance_accum += delta_pos.length()
	var step_dist := GameConfig.footprint_step_distance_px if GameConfig else 40.0

	if _distance_accum >= step_dist:
		_distance_accum = 0.0

		# Compute stamp position (where the footprint actually lands)
		var rear_offset := GameConfig.footprint_rear_offset_px if GameConfig else 12.0
		var stamp_pos := player_pos - move_dir * rear_offset

		# Check blood/corpse at stamp contact point (not player center)
		var r := GameConfig.footprint_blood_detect_radius if GameConfig else 25.0
		var on_blood := false
		var on_corpse := false
		if vfx_system:
			if vfx_system.has_method("has_blood_at"):
				on_blood = vfx_system.has_blood_at(stamp_pos, r)
			if vfx_system.has_method("has_corpse_at"):
				on_corpse = vfx_system.has_corpse_at(stamp_pos, r)

		# Update debug flags
		last_on_blood = on_blood
		last_on_corpse = on_corpse

		# Stepping on blood reloads charges (corpse alone does not)
		if on_blood:
			_blood_charges = GameConfig.boots_blood_max_prints if GameConfig else 8

		# Only spawn if on blood/corpse or have blood charges (no prints on clean grass)
		if on_blood or on_corpse or _blood_charges > 0:
			_spawn_footprint(stamp_pos, move_dir, on_blood, on_corpse)

	# Age active footprints
	_age_footprints(delta)


func _age_footprints(delta: float) -> void:
	var fade_start := 2.0  # Fade last 2 seconds
	var i := 0
	while i < _active.size():
		var entry: Dictionary = _active[i]
		entry["time_left"] -= delta
		if entry["time_left"] <= 0:
			# Return to pool
			var spr: Sprite2D = entry["sprite"]
			spr.visible = false
			_active.remove_at(i)
			continue
		elif entry["time_left"] < fade_start:
			# Fade out via shader tint_color.a
			var fade_ratio: float = float(entry["time_left"]) / fade_start
			var spr: Sprite2D = entry["sprite"]
			var mat := spr.material as ShaderMaterial
			var c: Color = mat.get_shader_parameter("tint_color")
			c.a = float(entry["base_alpha"]) * fade_ratio
			mat.set_shader_parameter("tint_color", c)
		i += 1


func _spawn_footprint(stamp_pos: Vector2, move_dir: Vector2, on_blood: bool, on_corpse: bool) -> void:
	# Clamp active count
	var max_count := GameConfig.footprint_max_count if GameConfig else 100
	while _active.size() >= max_count:
		var oldest: Dictionary = _active.pop_front()
		var spr: Sprite2D = oldest["sprite"]
		spr.visible = false

	# Get a sprite from pool (find first invisible)
	var sprite: Sprite2D = null
	for s in _pool:
		if not s.visible:
			sprite = s
			break

	if not sprite:
		# Pool exhausted, recycle oldest
		if _active.size() > 0:
			var oldest: Dictionary = _active.pop_front()
			sprite = oldest["sprite"]
			sprite.visible = false
		else:
			return

	var jitter_deg := GameConfig.footprint_rotation_jitter_deg if GameConfig else 1.0
	var fp_scale := GameConfig.footprint_scale if GameConfig else 0.65
	var lifetime := GameConfig.footprint_lifetime_sec if GameConfig else 20.0

	# Set texture (paired-step stamp, no flip)
	sprite.texture = BOOT_TEX
	sprite.flip_h = false

	# Rotation: toe faces movement direction
	var jitter_rad := deg_to_rad(randf_range(-jitter_deg, jitter_deg))
	var rot_offset := deg_to_rad(GameConfig.footprint_rotation_offset_deg if GameConfig else 90.0)
	sprite.rotation = move_dir.angle() + rot_offset + jitter_rad

	sprite.position = stamp_pos
	sprite.scale = Vector2(fp_scale, fp_scale)

	# Determine footprint alpha (always red via shader)
	var base_alpha := GameConfig.footprint_alpha if GameConfig else 0.35
	var alpha := base_alpha

	if on_blood or on_corpse:
		alpha = base_alpha
		_blood_charges = GameConfig.boots_blood_max_prints if GameConfig else 8
	elif _blood_charges > 0:
		var maxp := GameConfig.boots_blood_max_prints if GameConfig else 8
		var fade := float(_blood_charges) / float(maxp)
		alpha = base_alpha * fade
		_blood_charges -= 1
	else:
		return

	var mat := sprite.material as ShaderMaterial
	mat.set_shader_parameter("tint_color", Color(0.70, 0.10, 0.10, alpha))
	sprite.visible = true

	_active.append({
		"sprite": sprite,
		"time_left": lifetime,
		"max_time": lifetime,
		"base_alpha": alpha,
	})

	_spawned_total += 1

	# Emit event
	if EventBus:
		EventBus.emit_footprint_spawned(Vector3(stamp_pos.x, stamp_pos.y, 0), sprite.rotation)


## Get footprint count
func get_footprint_count() -> int:
	return _active.size()


## Debug: total footprints spawned this session
func get_spawned_total() -> int:
	return _spawned_total


## Debug: current blood charges remaining
func get_blood_charges() -> int:
	return _blood_charges


## Clear all footprints
func clear() -> void:
	for entry in _active:
		var spr: Sprite2D = entry["sprite"]
		if is_instance_valid(spr):
			spr.visible = false
	_active.clear()
	_initialized = false
	_distance_accum = 0.0
	_blood_charges = 0
	_spawned_total = 0
	last_on_blood = false
	last_on_corpse = false
