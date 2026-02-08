## melee_arc_system.gd
## MeleeArcSystem - visual arc effects for katana slashes.
## CANON: Pure visual, no collision or gameplay impact.
## CANON: Spawns only during ACTIVE window, auto-cleanup after duration.
## CANON: Pooled Line2D nodes.
class_name MeleeArcSystem
extends Node

## Arc pool
var _arc_pool: Array[Line2D] = []

## Dash trail pool
var _trail_pool: Array[Line2D] = []

## Active arcs with remaining time
var _active_arcs: Array[Dictionary] = []  # {node, time_left, max_time}

## Container for arc visuals
var _container: Node2D = null

## Reference to player for position
var player_node: CharacterBody2D = null

const ARC_POOL_SIZE := 8
const TRAIL_POOL_SIZE := 6
const ARC_SEGMENTS := 16


func _ready() -> void:
	if EventBus:
		EventBus.melee_hit.connect(_on_melee_hit)


## Initialize with a container node
func initialize(container: Node2D, player: CharacterBody2D) -> void:
	_container = container
	player_node = player

	# Pre-allocate arc pool
	for i in range(ARC_POOL_SIZE):
		var line := Line2D.new()
		line.visible = false
		line.z_index = 10  # Above entities
		container.add_child(line)
		_arc_pool.append(line)

	# Pre-allocate trail pool
	for i in range(TRAIL_POOL_SIZE):
		var line := Line2D.new()
		line.visible = false
		line.z_index = 10
		container.add_child(line)
		_trail_pool.append(line)

	print("[MeleeArcSystem] Initialized")


## Called each frame by LevelMVP
func update(delta: float) -> void:
	# Age and fade active arcs
	var i := 0
	while i < _active_arcs.size():
		var entry: Dictionary = _active_arcs[i]
		entry["time_left"] -= delta
		if entry["time_left"] <= 0:
			var node: Line2D = entry["node"]
			node.visible = false
			_active_arcs.remove_at(i)
			continue
		else:
			# Fade out
			var ratio: float = float(entry["time_left"]) / float(entry["max_time"])
			var node: Line2D = entry["node"]
			node.modulate.a = ratio * float(entry["base_alpha"])
		i += 1


## Spawn a slash arc visual
func spawn_arc(move_type: String) -> void:
	if not player_node or not _container:
		return

	match move_type:
		"katana_light":
			_spawn_slash_arc(
				GameConfig.melee_arc_light_radius if GameConfig else 26.0,
				GameConfig.melee_arc_light_arc_deg if GameConfig else 80.0,
				GameConfig.melee_arc_light_thickness if GameConfig else 2.0,
				GameConfig.melee_arc_light_duration if GameConfig else 0.08,
				GameConfig.melee_arc_light_alpha if GameConfig else 0.6,
				Color(0.9, 0.95, 1.0)
			)
		"katana_heavy":
			_spawn_slash_arc(
				GameConfig.melee_arc_heavy_radius if GameConfig else 30.0,
				GameConfig.melee_arc_heavy_arc_deg if GameConfig else 110.0,
				GameConfig.melee_arc_heavy_thickness if GameConfig else 3.0,
				GameConfig.melee_arc_heavy_duration if GameConfig else 0.12,
				GameConfig.melee_arc_heavy_alpha if GameConfig else 0.8,
				Color(1.0, 0.85, 0.7)
			)
		"katana_dash":
			_spawn_dash_trail()


func _spawn_slash_arc(radius: float, arc_deg: float, thickness: float, duration: float, alpha: float, color: Color) -> void:
	var line := _get_pooled_arc()
	if not line:
		return

	# Build arc points around player aim direction
	var aim_dir := Vector2.RIGHT
	if RuntimeState:
		aim_dir = Vector2(RuntimeState.player_aim_dir.x, RuntimeState.player_aim_dir.y).normalized()
	if aim_dir.length_squared() < 0.01:
		aim_dir = Vector2.RIGHT

	var center_angle := aim_dir.angle()
	var half_arc := deg_to_rad(arc_deg / 2.0)
	var start_angle := center_angle - half_arc
	var player_pos := player_node.position

	line.clear_points()
	line.width = thickness
	line.default_color = color

	for seg in range(ARC_SEGMENTS + 1):
		var t := float(seg) / float(ARC_SEGMENTS)
		var angle := start_angle + t * 2.0 * half_arc
		var point := player_pos + Vector2(cos(angle), sin(angle)) * radius
		line.add_point(point)

	line.modulate = Color(1, 1, 1, alpha)
	line.visible = true

	_active_arcs.append({
		"node": line,
		"time_left": duration,
		"max_time": duration,
		"base_alpha": alpha,
	})


func _spawn_dash_trail() -> void:
	if not player_node:
		return

	var aim_dir := Vector2.RIGHT
	if RuntimeState:
		aim_dir = Vector2(RuntimeState.player_aim_dir.x, RuntimeState.player_aim_dir.y).normalized()
	if aim_dir.length_squared() < 0.01:
		aim_dir = Vector2.RIGHT

	var afterimages := GameConfig.melee_arc_dash_afterimages if GameConfig else 3
	var length_min := GameConfig.melee_arc_dash_length_min if GameConfig else 20.0
	var length_max := GameConfig.melee_arc_dash_length_max if GameConfig else 28.0
	var base_alpha := GameConfig.melee_arc_dash_alpha if GameConfig else 0.6
	var player_pos := player_node.position

	for i in range(afterimages):
		var line := _get_pooled_trail()
		if not line:
			break

		var offset := aim_dir * (-float(i) * 8.0)  # Trail behind
		var length := randf_range(length_min, length_max)
		var perp := Vector2(-aim_dir.y, aim_dir.x)

		line.clear_points()
		line.width = 2.0
		line.default_color = Color(0.7, 0.85, 1.0)

		var start := player_pos + offset - aim_dir * (length * 0.5)
		var end := player_pos + offset + aim_dir * (length * 0.5)
		# Add slight perpendicular spread
		start += perp * randf_range(-3, 3)
		end += perp * randf_range(-3, 3)

		line.add_point(start)
		line.add_point(end)

		var alpha := base_alpha * (1.0 - float(i) / float(afterimages))
		line.modulate = Color(1, 1, 1, alpha)
		line.visible = true

		_active_arcs.append({
			"node": line,
			"time_left": 0.12,
			"max_time": 0.12,
			"base_alpha": alpha,
		})


func _get_pooled_arc() -> Line2D:
	for line in _arc_pool:
		if not line.visible:
			return line
	return null


func _get_pooled_trail() -> Line2D:
	for line in _trail_pool:
		if not line.visible:
			return line
	return null


func _on_melee_hit(_pos: Vector3, _move_type: String) -> void:
	# Handled by MeleeSystem triggering spawn_arc directly
	pass
