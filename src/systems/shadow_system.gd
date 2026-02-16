## shadow_system.gd
## ShadowSystem - renders entity shadows and player highlight ring.
## CANON: Pure visual, no gameplay impact.
## CANON: Shadows render below entities, must not obscure sprites.
class_name ShadowSystem
extends Node2D

## References
var player_node: CharacterBody2D = null
var entities_container: Node2D = null

## Player radius for shadow/highlight calculations
var _player_radius: float = 16.0
var _enemy_radius: float = 12.0


## Initialize with references
func initialize(player: CharacterBody2D, entities: Node2D) -> void:
	player_node = player
	entities_container = entities

	# Determine player radius from collision shape
	if player_node:
		var col := player_node.get_node_or_null("CollisionShape2D")
		if col and col is CollisionShape2D and col.shape is CircleShape2D:
			_player_radius = (col.shape as CircleShape2D).radius

	print("[ShadowSystem] Initialized (player_radius=%.0f)" % _player_radius)


func _draw() -> void:
	if not GameConfig:
		return

	# Draw player shadow
	if player_node and is_instance_valid(player_node):
		var shadow_radius := _player_radius * GameConfig.shadow_player_radius_mult
		var shadow_alpha := GameConfig.shadow_player_alpha
		var shadow_color := Color(0, 0, 0, shadow_alpha)
		var pos := player_node.position
		# Shadow slightly offset down-right for depth illusion
		draw_circle(pos + Vector2(1, 2), shadow_radius, shadow_color)

		# Player highlight ring
		var ring_radius := _player_radius + GameConfig.highlight_player_radius_offset
		var ring_thickness := GameConfig.highlight_player_thickness
		var ring_alpha := GameConfig.highlight_player_alpha
		var ring_color := Color(0.4, 0.7, 1.0, ring_alpha)
		_draw_ring(pos, ring_radius, ring_thickness, ring_color)

	# Draw enemy shadows
	if entities_container:
		var shadow_mult := GameConfig.shadow_enemy_radius_mult
		var shadow_alpha := GameConfig.shadow_enemy_alpha
		var shadow_color := Color(0, 0, 0, shadow_alpha)

		for child in entities_container.get_children():
			if child == player_node:
				continue
			if not child is CharacterBody2D or not is_instance_valid(child):
				continue
			if "is_dead" in child and child.is_dead:
				continue

			var radius := _enemy_radius * shadow_mult

			draw_circle(child.position + Vector2(1, 2), radius, shadow_color)


## Draw a ring (circle outline) using arc segments
func _draw_ring(center: Vector2, radius: float, thickness: float, color: Color) -> void:
	var segments := 24
	var points := PackedVector2Array()
	for i in range(segments + 1):
		var angle := float(i) / float(segments) * TAU
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], color, thickness, true)


## Must be called each frame to update visual positions
func update(_delta: float) -> void:
	queue_redraw()
