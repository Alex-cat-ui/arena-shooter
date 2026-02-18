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


func _exit_tree() -> void:
	_players_inside.clear()
	if RuntimeState:
		RuntimeState.player_visibility_mul = 1.0


func _on_body_entered(body: Node) -> void:
	if not _is_player(body):
		return
	_players_inside[body.get_instance_id()] = true
	if RuntimeState:
		if _shadow_is_binary_canon():
			RuntimeState.player_visibility_mul = 0.0
		else:
			RuntimeState.player_visibility_mul = shadow_multiplier


func _on_body_exited(body: Node) -> void:
	if not _is_player(body):
		return
	_players_inside.erase(body.get_instance_id())
	if not RuntimeState:
		return
	if _players_inside.is_empty():
		RuntimeState.player_visibility_mul = 1.0
	elif _shadow_is_binary_canon():
		RuntimeState.player_visibility_mul = 0.0
	else:
		RuntimeState.player_visibility_mul = shadow_multiplier


func _is_player(body: Node) -> bool:
	if body == null:
		return false
	return body.is_in_group("player")


func _shadow_is_binary_canon() -> bool:
	if GameConfig and GameConfig.stealth_canon is Dictionary:
		return bool(GameConfig.stealth_canon.get("shadow_is_binary", true))
	return true


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
