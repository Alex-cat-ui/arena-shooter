## vfx_system.gd
## VFXSystem - handles blood decals, corpses, corpse baking, and chain lightning VFX.
## CANON: Blood stays persistent but ages (darkens/desaturates).
## CANON: Corpses limit 200; when reached, bake into texture layer.
## CANON: Blood decal count clamped (oldest removed first).
class_name VFXSystem
extends Node

## Container for decals (blood)
var decals_container: Node2D = null

## Container for corpses
var corpses_container: Node2D = null

## Container for baked corpse textures
var baked_container: Node2D = null

## Corpse limit before baking
const CORPSE_LIMIT := 200

## Active corpse entities
var _corpses: Array[Node2D] = []

## Blood decal tracking for aging
var _blood_decals: Array[Dictionary] = []  # {sprite, age}

## Corpse visual settings
const BLOOD_COLORS := [
	Color(0.6, 0.0, 0.0, 0.8),
	Color(0.5, 0.0, 0.0, 0.7),
	Color(0.7, 0.1, 0.1, 0.75),
]

## Container for chain lightning VFX arcs
var _lightning_container: Node2D = null


func _ready() -> void:
	# Subscribe to events
	if EventBus:
		EventBus.enemy_killed.connect(_on_enemy_killed)
		EventBus.chain_lightning_hit.connect(_on_chain_lightning_hit)


## Initialize VFX system with containers
func initialize(decals: Node2D, corpses: Node2D) -> void:
	decals_container = decals
	corpses_container = corpses

	# Create baked container if not exists
	if corpses_container and not baked_container:
		baked_container = Node2D.new()
		baked_container.name = "BakedCorpses"
		corpses_container.add_child(baked_container)
		# Baked layer should be below active corpses
		corpses_container.move_child(baked_container, 0)

	# Create lightning VFX container
	if not _lightning_container:
		_lightning_container = Node2D.new()
		_lightning_container.name = "LightningArcs"
		if decals_container and decals_container.get_parent():
			decals_container.get_parent().add_child(_lightning_container)

	print("[VFXSystem] Initialized")


## Update blood aging each frame
func update_aging(delta: float) -> void:
	if _blood_decals.is_empty():
		return

	var darken_rate := GameConfig.blood_darken_rate if GameConfig else 0.01
	var desat_rate := GameConfig.blood_desaturate_rate if GameConfig else 0.005

	for entry in _blood_decals:
		entry["age"] += delta
		var spr: Sprite2D = entry["sprite"]
		if not is_instance_valid(spr):
			continue

		# Gradually darken and desaturate
		var age: float = entry["age"]
		var darken := minf(age * darken_rate, 0.5)  # Cap darkening
		var desat := minf(age * desat_rate, 0.3)     # Cap desaturation

		var base_color: Color = entry["base_modulate"]
		var r := lerpf(base_color.r, base_color.r * 0.3, darken)
		var g := lerpf(base_color.g, base_color.g * 0.3, darken)
		var b := lerpf(base_color.b, base_color.b * 0.3, darken)
		# Desaturate: shift toward grey
		var grey := (r + g + b) / 3.0
		r = lerpf(r, grey, desat)
		g = lerpf(g, grey, desat)
		b = lerpf(b, grey, desat)
		spr.modulate = Color(r, g, b, base_color.a)


## Spawn blood decal at position
func spawn_blood(pos: Vector3, size: float = 1.0) -> void:
	if not decals_container:
		return

	# Clamp blood decals
	var max_decals := GameConfig.blood_max_decals if GameConfig else 500
	while _blood_decals.size() >= max_decals:
		var oldest: Dictionary = _blood_decals.pop_front()
		var spr: Sprite2D = oldest["sprite"]
		if is_instance_valid(spr):
			spr.queue_free()

	var blood := _create_blood_sprite(size)
	blood.position = Vector2(pos.x, pos.y)
	blood.rotation = randf() * TAU
	decals_container.add_child(blood)

	# Track for aging
	_blood_decals.append({
		"sprite": blood,
		"age": 0.0,
		"base_modulate": blood.modulate,
	})

	# Emit event
	if EventBus:
		EventBus.emit_blood_spawned(pos, size)


## Spawn corpse at position with settle animation
func spawn_corpse(pos: Vector3, enemy_type: String, rotation: float = 0.0) -> void:
	if not corpses_container:
		return

	# Check corpse limit
	if _corpses.size() >= CORPSE_LIMIT:
		_bake_corpses()

	var corpse := _create_corpse_sprite(enemy_type)
	var final_rot := rotation if rotation != 0.0 else randf() * TAU
	corpse.position = Vector2(pos.x, pos.y)
	corpse.rotation = final_rot
	corpses_container.add_child(corpse)
	_corpses.append(corpse)

	# Corpse settle animation: small rotation + slide
	var settle_rot := final_rot + randf_range(-0.15, 0.15)
	var settle_slide := Vector2(randf_range(-3, 3), randf_range(-3, 3))
	var tween := corpse.create_tween()
	tween.set_parallel(true)
	tween.tween_property(corpse, "rotation", settle_rot, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(corpse, "position", corpse.position + settle_slide, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Also spawn blood at corpse location
	spawn_blood(pos, 1.5)

	# Emit event
	if EventBus:
		EventBus.emit_corpse_spawned(pos, enemy_type, corpse.rotation)


func _create_blood_sprite(size: float) -> Sprite2D:
	var sprite := Sprite2D.new()

	# Create simple blood texture (circle)
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var color: Color = BLOOD_COLORS[randi() % BLOOD_COLORS.size()]

	# Draw filled circle
	var center := Vector2(16, 16)
	for x in range(32):
		for y in range(32):
			var dist := Vector2(x, y).distance_to(center)
			if dist < 14:
				# Vary alpha based on distance for softer edge
				var alpha := color.a * (1.0 - (dist / 14.0) * 0.3)
				img.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))

	var tex := ImageTexture.create_from_image(img)
	sprite.texture = tex
	sprite.scale = Vector2(size, size)
	sprite.modulate.a = 0.7 + randf() * 0.3

	return sprite


func _create_corpse_sprite(enemy_type: String) -> Sprite2D:
	var sprite := Sprite2D.new()

	# Create simple corpse texture (darker body shape)
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var color := Color(0.2, 0.15, 0.15, 0.85)

	# Draw filled ellipse for body
	var center := Vector2(16, 16)
	for x in range(32):
		for y in range(32):
			var dx := (x - center.x) / 12.0
			var dy := (y - center.y) / 8.0
			if dx * dx + dy * dy < 1.0:
				img.set_pixel(x, y, color)

	var tex := ImageTexture.create_from_image(img)
	sprite.texture = tex
	sprite.modulate = Color(0.3, 0.2, 0.2, 0.9)

	return sprite


## Bake all corpses into a texture layer
func _bake_corpses() -> void:
	if _corpses.is_empty():
		return

	print("[VFXSystem] Baking %d corpses..." % _corpses.size())

	for corpse in _corpses:
		if is_instance_valid(corpse):
			var old_pos := corpse.global_position
			var old_rot := corpse.rotation
			corpse.get_parent().remove_child(corpse)
			baked_container.add_child(corpse)
			corpse.global_position = old_pos
			corpse.rotation = old_rot

	var baked_count := _corpses.size()
	_corpses.clear()

	# Emit bake event
	if EventBus:
		EventBus.emit_corpses_baked(baked_count)

	print("[VFXSystem] Baked %d corpses" % baked_count)


## Check if position has blood/corpse (for footprint spawning)
func has_blood_or_corpse_at(pos: Vector2, radius: float = 20.0) -> bool:
	return has_blood_at(pos, radius) or has_corpse_at(pos, radius)


## Check if position is near a blood decal only
func has_blood_at(pos: Vector2, radius: float = 20.0) -> bool:
	if decals_container:
		for child in decals_container.get_children():
			if child is Sprite2D:
				if child.global_position.distance_to(pos) < radius:
					return true
	return false


## Check if position is near a corpse only (active + baked Sprite2D, not containers)
func has_corpse_at(pos: Vector2, radius: float = 20.0) -> bool:
	# Check active corpses
	for corpse in _corpses:
		if is_instance_valid(corpse):
			if corpse.global_position.distance_to(pos) < radius:
				return true
	# Check baked corpses (only Sprite2D children, skip Node2D containers)
	if baked_container:
		for child in baked_container.get_children():
			if child is Sprite2D:
				if child.global_position.distance_to(pos) < radius:
					return true
	return false


## Event handler for enemy death
func _on_enemy_killed(enemy_id: int, enemy_type: String, wave_id: int) -> void:
	# Find the enemy to get its position
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if "entity_id" in enemy and enemy.entity_id == enemy_id:
			var pos := Vector3(enemy.position.x, enemy.position.y, 0)
			spawn_corpse(pos, enemy_type, enemy.rotation if "rotation" in enemy else 0.0)
			break


## ============================================================================
## CHAIN LIGHTNING VFX (Phase 3)
## ============================================================================

## Event handler for chain lightning arc
func _on_chain_lightning_hit(origin: Vector3, target: Vector3) -> void:
	if not _lightning_container:
		return

	var line := Line2D.new()
	line.width = 2.0
	line.default_color = Color(0.4, 0.7, 1.0, 0.9)
	line.add_point(Vector2(origin.x, origin.y))

	# Add a jagged midpoint for electric look
	var mid := Vector2(
		(origin.x + target.x) / 2.0 + randf_range(-8, 8),
		(origin.y + target.y) / 2.0 + randf_range(-8, 8)
	)
	line.add_point(mid)
	line.add_point(Vector2(target.x, target.y))

	_lightning_container.add_child(line)

	# Fade out and remove
	var tween := line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.15)
	tween.tween_callback(line.queue_free)


## Get corpse count
func get_corpse_count() -> int:
	return _corpses.size()


## Get total corpses including baked
func get_total_corpse_count() -> int:
	var total := _corpses.size()
	if baked_container:
		total += baked_container.get_child_count()
	return total
