## vfx_system.gd
## VFXSystem - handles blood decals, corpses, corpse baking, and footprints.
## CANON: Blood stays forever.
## CANON: Corpses limit 200; when reached, bake into texture layer.
## CANON: Footprints only spawn when player walks over blood/corpses.
class_name VFXSystem
extends Node

## Container for decals (blood, footprints)
var decals_container: Node2D = null

## Container for corpses
var corpses_container: Node2D = null

## Container for baked corpse textures
var baked_container: Node2D = null

## Corpse limit before baking
const CORPSE_LIMIT := 200

## Active corpse entities
var _corpses: Array[Node2D] = []

## Baked corpse viewport (for rendering corpses to texture)
var _bake_viewport: SubViewport = null
var _bake_sprite: Sprite2D = null

## Blood decal scene (simple colored sprite)
var _blood_decal_scene: PackedScene = null

## Corpse visual settings
const BLOOD_COLORS := [
	Color(0.6, 0.0, 0.0, 0.8),
	Color(0.5, 0.0, 0.0, 0.7),
	Color(0.7, 0.1, 0.1, 0.75),
]


func _ready() -> void:
	# Subscribe to events
	if EventBus:
		EventBus.enemy_killed.connect(_on_enemy_killed)


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

	print("[VFXSystem] Initialized")


## Spawn blood decal at position
func spawn_blood(pos: Vector3, size: float = 1.0) -> void:
	if not decals_container:
		return

	var blood := _create_blood_sprite(size)
	blood.position = Vector2(pos.x, pos.y)
	blood.rotation = randf() * TAU
	decals_container.add_child(blood)

	# Emit event
	if EventBus:
		EventBus.emit_blood_spawned(pos, size)


## Spawn corpse at position
func spawn_corpse(pos: Vector3, enemy_type: String, rotation: float = 0.0) -> void:
	if not corpses_container:
		return

	# Check corpse limit
	if _corpses.size() >= CORPSE_LIMIT:
		_bake_corpses()

	var corpse := _create_corpse_sprite(enemy_type)
	corpse.position = Vector2(pos.x, pos.y)
	corpse.rotation = rotation if rotation != 0.0 else randf() * TAU
	corpses_container.add_child(corpse)
	_corpses.append(corpse)

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

	# Simple bake: just move corpses to baked container and make them static
	# For a real implementation, we'd render to a viewport texture
	# MVP: Keep corpses but move to baked layer (reduces processing since they don't need updates)

	for corpse in _corpses:
		if is_instance_valid(corpse):
			# Reparent to baked container
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
	# Check decals (blood)
	if decals_container:
		for child in decals_container.get_children():
			if child is Sprite2D:
				if child.position.distance_to(pos) < radius:
					return true

	# Check corpses
	if corpses_container:
		for child in corpses_container.get_children():
			if child is Sprite2D or child is Node2D:
				if child.position.distance_to(pos) < radius:
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


## Get corpse count
func get_corpse_count() -> int:
	return _corpses.size()


## Get total corpses including baked
func get_total_corpse_count() -> int:
	var total := _corpses.size()
	if baked_container:
		total += baked_container.get_child_count()
	return total
