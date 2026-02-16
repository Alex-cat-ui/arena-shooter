## shadow_zone.gd
## Stealth visibility modifier zone. Does not affect LOS/occlusion.
class_name ShadowZone
extends Area2D

@export_range(0.1, 1.0) var shadow_multiplier: float = 0.35

var _players_inside: Dictionary = {}


func _ready() -> void:
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
		RuntimeState.player_visibility_mul = shadow_multiplier


func _on_body_exited(body: Node) -> void:
	if not _is_player(body):
		return
	_players_inside.erase(body.get_instance_id())
	if _players_inside.is_empty() and RuntimeState:
		RuntimeState.player_visibility_mul = 1.0


func _is_player(body: Node) -> bool:
	if body == null:
		return false
	return body.is_in_group("player")
