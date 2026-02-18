## stealth_test_layout.gd
## Minimal one-room layout stub compatible with NavigationService/EnemyAlertSystem consumers.
class_name StealthTestLayout
extends RefCounted

var valid: bool = true
var rooms: Array = []
var doors: Array = []
var _door_adj: Dictionary = {0: []}
var player_room_id: int = 0
var _void_ids: Array = []

var _room_rect: Rect2 = Rect2(-560.0, -320.0, 1120.0, 640.0)


func _init(room_rect: Rect2 = Rect2(-560.0, -320.0, 1120.0, 640.0)) -> void:
	_room_rect = room_rect
	rooms = [{
		"id": 0,
		"rects": [_room_rect],
		"center": _room_rect.get_center(),
		"is_corridor": false,
	}]
	doors = []
	_door_adj = {0: []}
	player_room_id = 0
	_void_ids = []


func _room_id_at_point(point: Vector2) -> int:
	return 0 if _room_rect.has_point(point) else -1


func _door_adjacent_room_ids(_door: Rect2) -> Array:
	return []
