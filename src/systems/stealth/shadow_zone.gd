## shadow_zone.gd
## Stealth visibility modifier zone. Does not affect LOS/occlusion.
class_name ShadowZone
extends Area2D

@export_range(0.1, 1.0) var shadow_multiplier: float = 0.35

var _players_inside: Dictionary = {}


func _ready() -> void:
	if not is_in_group("shadow_zones"):
		add_to_group("shadow_zones")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	monitoring = true
	monitorable = true
	set_physics_process(true)
	call_deferred("_sync_overlap_state")


func _exit_tree() -> void:
	_players_inside.clear()
	_recompute_global_player_visibility()


func _physics_process(_delta: float) -> void:
	if not monitoring:
		return
	if not _has_active_collision_shape():
		return
	var had_player := not _players_inside.is_empty()
	var has_player := _refresh_players_inside_from_overlaps()
	if had_player != has_player:
		_recompute_global_player_visibility()


func _on_body_entered(body: Node) -> void:
	if not _is_player(body):
		return
	_players_inside[body.get_instance_id()] = true
	_recompute_global_player_visibility()


func _on_body_exited(body: Node) -> void:
	if not _is_player(body):
		return
	_players_inside.erase(body.get_instance_id())
	_recompute_global_player_visibility()


func _is_player(body: Node) -> bool:
	if body == null:
		return false
	return body.is_in_group("player")


func _shadow_is_binary_canon() -> bool:
	if GameConfig and GameConfig.stealth_canon is Dictionary:
		return bool(GameConfig.stealth_canon.get("shadow_is_binary", true))
	return true


func _sync_overlap_state() -> void:
	if not is_inside_tree():
		return
	if _has_active_collision_shape():
		_refresh_players_inside_from_overlaps()
	_recompute_global_player_visibility()


func _refresh_players_inside_from_overlaps() -> bool:
	var next_inside: Dictionary = {}
	for body_variant in get_overlapping_bodies():
		var body := body_variant as Node
		if not _is_player(body):
			continue
		next_inside[body.get_instance_id()] = true
	_players_inside = next_inside
	return not _players_inside.is_empty()


func _has_active_collision_shape() -> bool:
	for child_variant in get_children():
		var shape_node := child_variant as CollisionShape2D
		if shape_node == null:
			continue
		if shape_node.disabled:
			continue
		if shape_node.shape == null:
			continue
		return true
	return false


func _recompute_global_player_visibility() -> void:
	if not RuntimeState:
		return
	var tree := get_tree()
	if tree == null:
		return

	var binary_shadow := _shadow_is_binary_canon()
	var has_shadow_overlap := false
	var multiplier := 1.0
	for zone_variant in tree.get_nodes_in_group("shadow_zones"):
		var zone := zone_variant as ShadowZone
		if zone == null:
			continue
		if zone._players_inside.is_empty():
			continue
		has_shadow_overlap = true
		if binary_shadow:
			RuntimeState.player_visibility_mul = 0.0
			return
		multiplier = minf(multiplier, clampf(zone.shadow_multiplier, 0.0, 1.0))

	RuntimeState.player_visibility_mul = multiplier if has_shadow_overlap else 1.0


func contains_point(world_point: Vector2) -> bool:
	for child_variant in get_children():
		var shape_node := child_variant as CollisionShape2D
		if shape_node == null or shape_node.disabled:
			continue
		var shape := shape_node.shape
		if shape == null:
			continue
		var local_point := shape_node.global_transform.affine_inverse() * world_point
		if shape is RectangleShape2D:
			var rect := shape as RectangleShape2D
			var half := rect.size * 0.5
			if absf(local_point.x) <= half.x and absf(local_point.y) <= half.y:
				return true
		elif shape is CircleShape2D:
			var circle := shape as CircleShape2D
			if local_point.length_squared() <= circle.radius * circle.radius:
				return true
	return false
